import Foundation

nonisolated enum CalibrationDump {

    /// Рекурсивно обходит папку, анализирует каждый lossy-файл и пишет CSV на Desktop.
    @MainActor
    static func run(folder: URL) async {
        let urls: [URL] = collectLossyFiles(in: folder)

        print("=== Calibration started ===")
        print("Found: \(urls.count) files")
        print("Processing...")

        let concurrency = min(8, ProcessInfo.processInfo.activeProcessorCount)
        let batchSize = concurrency
        var index = 0
        var lines: [String] = []
        lines.reserveCapacity(urls.count + 1)
        // 17 полей → 16 запятых. codec — 4-я колонка.
        lines.append("filename,track_folder,group,codec,declared_kbps,spectral_kbps,sample_rate,cutoff_final_hz,cutoff_slice_hz,cutoff_energy_hz,edge_step_db,energy_ratio,r16_holes,r16_offset,ratio,spectral_source,is_vbr,score,verdict,drop_cutoff_hz,drop_db,drop_conf,hf_slope,energy_above_18k,spectrum")

        var processed = 0
        let startTime = Date()

        while index < urls.count {
            let batch = Array(urls[index..<min(index + batchSize, urls.count)])
            index += batchSize

            await withTaskGroup(of: (Int, String).self) { group in
                for (i, url) in batch.enumerated() {
                    group.addTask {
                        let line = await analyzeOne(url: url)
                        return (i, line)
                    }
                }
                var batchLines: [(Int, String)] = []
                for await pair in group {
                    batchLines.append(pair)
                }
                batchLines.sort { $0.0 < $1.0 }
                for (_, line) in batchLines {
                    lines.append(line)
                }
            }

            processed += batch.count
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(processed) / elapsed
            let remaining = Double(urls.count - processed) / max(rate, 0.1)
            print(String(format: "  %d/%d (%.0f%%), %.1f files/sec, ~%.0f min remaining",
                         processed, urls.count,
                         Double(processed) * 100.0 / Double(urls.count),
                         rate, remaining / 60.0))
        }

        let outURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("calibration_full.csv")

        let output = lines.joined(separator: "\n")
        do {
            try output.write(to: outURL, atomically: true, encoding: .utf8)
            print("=== Done ===")
            print("Written to: \(outURL.path)")
            print("Total: \(urls.count) rows")
        } catch {
            print("!!! Failed to write: \(error)")
        }
    }

    /// Анализ одного файла. Возвращает готовую CSV-строку.
    /// 18 полей → 17 запятых между ними.
    nonisolated private static func analyzeOne(url: URL) async -> String {
        guard let r = await BitrateAnalyzer.analyzeURL(url) else {
            // ERROR-строка: filename + 17 пустых полей.
            // Считаем: filename(1) + 17 полей = 18 полей → 17 запятых.
            return "\(url.lastPathComponent),ERROR,,,,,,,,,,,,,,,,,,,,,,,"
        }
        let group = url.path.contains("/honest/") ? "honest"
                   : url.path.contains("/fake/") ? "fake"
                   : "unknown"
        let trackFolder = url.deletingLastPathComponent().lastPathComponent
        let declared = r.declaredKbps ?? 0
        let spectral = r.effectiveKbps
        let ratio: String = (declared > 0 && spectral > 0)
            ? String(format: "%.2f", Double(declared) / Double(spectral))
            : ""

        let codecStr = r.codec.rawValue
        let sliceStr = r.cutoffSliceHz.isFinite ? "\(Int(r.cutoffSliceHz))" : ""
        let energyStr = r.cutoffEnergyHz.isFinite ? "\(Int(r.cutoffEnergyHz))" : ""
        let edgeStr = r.edgeStepDb.isFinite ? String(format: "%.1f", r.edgeStepDb) : ""
        let erStr = String(format: "%.4f", r.energyRatio)
        let r16Str = r.r16Holes.isFinite ? String(format: "%.2f", r.r16Holes) : ""
        let r16OffStr = r.r16Offset >= 0 ? "\(r.r16Offset)" : ""
        let srcStr = r.spectralSource.isEmpty ? "none" : r.spectralSource
        let vbrStr = r.isVBR ? "1" : "0"

        let dropCutStr = r.dropCutoffHz.isFinite ? String(format: "%.0f", r.dropCutoffHz) : ""
        let dropDbStr = String(format: "%.1f", r.dropDb)
        let dropConfStr = String(format: "%.2f", r.dropConfidence)
        let slopeStr = r.hfSlopeDbPerKhz.isFinite ? String(format: "%.2f", r.hfSlopeDbPerKhz) : ""
        let above18kStr = r.energyAbove18k.isFinite ? String(format: "%.1f", r.energyAbove18k) : ""
        let spectrumStr = r.spectrumSummary

        return "\(url.lastPathComponent),\(trackFolder),\(group),\(codecStr),\(declared),\(spectral),\(r.sampleRate),\(Int(r.cutoffHz)),\(sliceStr),\(energyStr),\(edgeStr),\(erStr),\(r16Str),\(r16OffStr),\(ratio),\(srcStr),\(vbrStr),\(r.score),\(r.verdict.rawValue),\(dropCutStr),\(dropDbStr),\(dropConfStr),\(slopeStr),\(above18kStr),\(spectrumStr)"
    }

    /// Собирает lossy-файлы. На время калибровки оставлены только MP3:
    /// AAC/OGG/Opus детектируются приблизительно (см. per-variant rates),
    /// их окна энкодер-зависимы, и в дайджест они только шумят.
    /// В боевом сканировании файлы этих форматов обрабатываются как
    /// notAssessed + предупреждение в UI.
    nonisolated private static func collectLossyFiles(in folder: URL) -> [URL] {
        let supported: Set<String> = ["mp3"]
        var result: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("Cannot enumerate: \(folder.path)")
            return []
        }
        for case let url as URL in enumerator {
            if supported.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        result.sort { $0.path < $1.path }
        return result
    }
}
