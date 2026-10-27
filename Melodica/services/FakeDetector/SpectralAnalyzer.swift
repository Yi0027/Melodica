import Foundation
import AVFoundation
import Accelerate

nonisolated struct SpectralReading {
    let cutoffHz: Double           // финальный (после fallback)
    let cutoffSliceHz: Double      // что дал slice-based
    let cutoffEnergyHz: Double     // что дал energy-based
    let cutoffStdHz: Double
    let edgeStepDb: Double
    let floorAboveDb: Double
    let residualFloorDb: Double
    let energyRatio: Double
    let isLowWall: Bool
    let lowWallHz: Double
    let dropCutoffHz: Double
    let dropDb: Double
    let dropConfidence: Double
    let spectrumSummary: String
    let hfSlopeDbPerKhz: Double
    let energyAbove18k: Double
}

nonisolated enum SpectralAnalysis {

    static let windowSeconds: Double = 30.0

    nonisolated static func analyze(
        url: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> SpectralReading? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = Int(format.sampleRate)
        let totalFrames = file.length
        let duration = Double(totalFrames) / format.sampleRate

        let windowsCount = duration > 90 ? 3 : 1
        let windowFrames = Int(windowSeconds * format.sampleRate)
        let usableFrames = min(windowFrames, Int(totalFrames))
        guard usableFrames > 4096 else { return nil }

        let fftSize = 8192
        let binWidth = Double(sampleRate) / Double(fftSize)
        let nyquist = Double(sampleRate) / 2.0

        // Per-window метрики. cutoff уже с учётом low wall (как в Python
        // `_analyze_window`: если detect_cutoff вернул "no edge", low_wall_hz
        // перезаписывает cutoff).
        struct WindowReading {
            let cutoff: Double
            let lowWall: Double
            let edgeStep: Double
            let floorAbove: Double
            let energyRatio: Double
            let powerDb: [Float]
        }
        var readings: [WindowReading] = []
        var middlePower: [Float]? = nil

        for w in 0..<windowsCount {
            // Python `_window_bounds`: центрируем окно вокруг (w+1)/(n+1) duration.
            let fraction = Double(w + 1) / Double(windowsCount + 1)
            let centerFrame = Double(totalFrames) * fraction
            var startFrame = AVAudioFramePosition(centerFrame - Double(usableFrames) / 2.0)
            if startFrame < 0 { startFrame = 0 }
            guard startFrame + AVAudioFramePosition(usableFrames) <= totalFrames else { continue }

            file.framePosition = startFrame
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(usableFrames)
            ) else { continue }
            do { try file.read(into: buffer) } catch { continue }
            guard let ch = buffer.floatChannelData else { continue }
            let frameLen = Int(buffer.frameLength)
            guard frameLen >= fftSize else { continue }

            var mono = [Float](repeating: 0, count: frameLen)
            let chCount = Int(buffer.format.channelCount)
            let scale = 1.0 / Float(chCount)
            for c in 0..<chCount {
                let src = ch[c]
                for i in 0..<frameLen { mono[i] += src[i] * scale }
            }

            guard let power = computePowerSpectrum(mono, fftSize: fftSize) else { continue }
            let (sliceCut, _, lowWall) = detectCutoffFromPower(
                power, binWidth: binWidth, sampleRate: sampleRate
            )

            // Python `_analyze_window`: если detect_cutoff вернул "no edge" —
            // пробуем low_wall_hz. Если он что-то нашёл, cutoff = low wall.
            let noEdge = isNoEdgeReading(
                sliceCut, sampleRate: sampleRate, binWidth: binWidth,
                nBins: power.count
            )
            let effectiveCutoff: Double
            if noEdge, lowWall.isFinite {
                effectiveCutoff = lowWall
            } else if sliceCut > 0 {
                effectiveCutoff = sliceCut
            } else {
                continue
            }

            // Per-window step / floor / energy — считаются от этого окна,
            // для этого cutoff. Раньше делалось один раз для middle.
            let (es, fa, er) = computeWindowMetrics(
                mono: mono, sampleRate: sampleRate, cutoffHz: effectiveCutoff
            )

            readings.append(WindowReading(
                cutoff: effectiveCutoff,
                lowWall: lowWall,
                edgeStep: es,
                floorAbove: fa,
                energyRatio: er,
                powerDb: power
            ))

            if windowsCount == 1 || w == windowsCount / 2 {
                middlePower = power
            }

            onProgress?(Double(w + 1) / Double(windowsCount))
        }

        guard !readings.isEmpty else { return nil }

        // Python `analyze_spectrum`: final_cutoff = min(cutoff_freqs).
        // Почему min: transcode режет HF во всех окнах; достаточно одного
        // окна с низким cutoff, чтобы это заметить.
        let minIdx = readings.indices.min(by: {
            readings[$0].cutoff < readings[$1].cutoff
        })!
        let finalCutoff = readings[minIdx].cutoff
        // Step и floor берутся из того же окна — «край, который Rule 1
        // будет читать, это тот, который описан».
        let edgeStep = readings[minIdx].edgeStep
        let floorAbove = readings[minIdx].floorAbove
        // Python: final_energy = min(energy_ratios).
        let energyRatio = readings.map { $0.energyRatio }.min() ?? 0
        // low wall — из окна с min cutoff, или первое валидное.
        let lowWallHz: Double = {
            if readings[minIdx].lowWall.isFinite { return readings[minIdx].lowWall }
            return readings.compactMap { $0.lowWall.isFinite ? $0.lowWall : nil }.first ?? .nan
        }()

        // Cutoff wander (std) — по всем окнам. NaN при одном окне.
        let cutoffs = readings.map { $0.cutoff }
        let std: Double = cutoffs.count > 1 ? standardDeviation(cutoffs) : .nan

        // Residual — Welch по всему файлу, читается только для near-Nyquist
        // 320 kbps gate. Оставлен как отдельная функция.
        var residual: Double = .nan
        if 0.85 * nyquist <= finalCutoff && finalCutoff < 0.94 * nyquist {
            residual = computeResidualFloorDb(
                url: url, sampleRate: sampleRate,
                totalFrames: totalFrames, format: format
            ) ?? .nan
        }

        // Shape — из middle-окна (не влияет на вердикт, только для UI).
        let shape: SpectralShapeAnalyzer.ShapeReading
        if let power = middlePower {
            shape = SpectralShapeAnalyzer.analyze(
                powerDb: power, binWidth: binWidth, sampleRate: sampleRate
            )
        } else {
            shape = SpectralShapeAnalyzer.ShapeReading(
                dropCutoffHz: .nan, dropDb: 0, dropConfidence: 0,
                spectrumSummary: "", hfSlopeDbPerKhz: .nan, energyAbove18k: .nan
            )
        }

        // isLowWall: final cutoff в [2000, 14000) — как Python
        // `is_low_wall_reading` (detect_cutoff никогда не возвращает
        // значение < 14000; если оно там, это точно low wall).
        let isLowWall = FLACDetectiveConstants.isLowWallReading(finalCutoff)

        return SpectralReading(
            cutoffHz: finalCutoff,
            cutoffSliceHz: finalCutoff,
            cutoffEnergyHz: .nan,
            cutoffStdHz: std,
            edgeStepDb: edgeStep,
            floorAboveDb: floorAbove,
            residualFloorDb: residual,
            energyRatio: energyRatio,
            isLowWall: isLowWall,
            lowWallHz: lowWallHz,
            dropCutoffHz: shape.dropCutoffHz,
            dropDb: shape.dropDb,
            dropConfidence: shape.dropConfidence,
            spectrumSummary: shape.spectrumSummary,
            hfSlopeDbPerKhz: shape.hfSlopeDbPerKhz,
            energyAbove18k: shape.energyAbove18k
        )
    }

    /// Welch-усреднённый power spectrum по всему окну.
    /// Python `_magnitude_spectrum` делает один огромный FFT на весь 30 s;
    /// мы эмулируем то же самое усреднением по кадрам — 250 Hz cell profile
    /// получается таким же, а память и кэш ведут себя гораздо лучше.
    nonisolated private static func computePowerSpectrum(
        _ audio: [Float], fftSize: Int
    ) -> [Float]? {
        guard audio.count >= fftSize else { return nil }
        let hop = fftSize / 2
        let half = fftSize / 2

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        // Накопитель магнитуд (не мощности — как Python: |X|, потом 20*log10).
        var accMag = [Float](repeating: 0, count: half)
        var count = 0
        var start = 0

        while start + fftSize <= audio.count {
            var block = Array(audio[start..<(start + fftSize)])
            vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(fftSize))

            var real = [Float](repeating: 0, count: half)
            var imag = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    block.withUnsafeMutableBufferPointer { bp in
                        bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // vDSP pack: DC в real[0], Nyquist в imag[0], бины 1..half-1 обычные.
            // DC не используем (как и раньше).
            for j in 1..<half {
                accMag[j] += (real[j] * real[j] + imag[j] * imag[j]).squareRoot()
            }
            // Nyquist (j = half) не представлен — выходит за пределы массива.
            // Не критично: границы 250 Hz ячеек далеко от Nyquist.

            count += 1
            start += hop
        }

        guard count > 0 else { return nil }

        var powerDb = [Float](repeating: -160, count: half)
        let inv = 1.0 / Float(count)
        for j in 1..<half {
            let m = accMag[j] * inv
            powerDb[j] = m > 1e-10 ? 20 * log10(m) : -160
        }
        return powerDb
    }
    /// Python `_no_edge`: cutoff близко к Nyquist или к верхнему бину —
    /// значит detect_cutoff сказал "ничего не нашёл".
    nonisolated private static func isNoEdgeReading(
        _ cutoffHz: Double, sampleRate: Int, binWidth: Double, nBins: Int
    ) -> Bool {
        let nyq = Double(sampleRate) / 2.0
        let lastBinHz = Double(nBins - 1) * binWidth
        return cutoffHz >= 0.999 * nyq || cutoffHz >= lastBinHz - 1e-6
    }

    /// Один FFT-блок mono → edge step, floor above edge, HF energy ratio.
    /// Работает на переданном mono (уже загружен из окна), не читает файл.
    /// Заменяет часть `computeEdgeMetrics`, но per-window и без residual.
    nonisolated private static func computeWindowMetrics(
        mono: [Float], sampleRate: Int, cutoffHz: Double
    ) -> (edgeStep: Double, floorAbove: Double, energyRatio: Double) {
        let fftSize = 8192
        let half = fftSize / 2
        guard mono.count >= fftSize else { return (.nan, .nan, 0) }

        let start = max(0, (mono.count - fftSize) / 2)
        var block = Array(mono[start..<(start + fftSize)])

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(fftSize))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (.nan, .nan, 0)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                block.withUnsafeMutableBufferPointer { bp in
                    bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        var powerDb = [Float](repeating: -160, count: half)
        for j in 1..<half {
            let p = real[j] * real[j] + imag[j] * imag[j]
            powerDb[j] = p > 1e-20 ? 10 * log10(p) : -160
        }

        let binWidth = Double(sampleRate) / Double(fftSize)
        let refLo = Int(10000.0 / binWidth)
        let refHi = min(half - 1, Int(14000.0 / binWidth))
        guard refLo < refHi else { return (.nan, .nan, 0) }
        var refSum: Float = 0
        for j in refLo...refHi { refSum += powerDb[j] }
        let refLvl = refSum / Float(refHi - refLo + 1)

        let cutoffBin = Int(cutoffHz / binWidth)
        guard cutoffBin >= refHi else { return (.nan, .nan, 0) }

        // Edge step — максимальный обрыв на 2×250 Hz cells вокруг cutoff.
        let cellBins = max(1, Int(250.0 / binWidth))
        var maxStep: Float = 0
        let searchLo = max(refHi, cutoffBin - 4 * cellBins)
        let searchHi = min(half - 1 - cellBins, cutoffBin + 4 * cellBins)
        if searchLo < searchHi {
            var j = searchLo
            while j < searchHi {
                let jn = min(half - 1, j + cellBins)
                var sumA: Float = 0, sumB: Float = 0
                var countA = 0, countB = 0
                for k in j..<jn { sumA += powerDb[k]; countA += 1 }
                for k in jn..<min(half, jn + cellBins) { sumB += powerDb[k]; countB += 1 }
                if countA > 0 && countB > 0 {
                    let step = (sumA / Float(countA)) - (sumB / Float(countB))
                    if step > maxStep { maxStep = step }
                }
                j += cellBins
            }
        }

        // Floor above edge.
        let floorStart = min(half - 1, cutoffBin + Int(1000.0 / binWidth))
        let floorEnd = min(half - 1, Int(0.993 * Double(sampleRate) / 2.0 / binWidth))
        var floor: Float = .nan
        if floorEnd > floorStart + 4 {
            var vals: [Float] = []
            for j in floorStart...floorEnd { vals.append(powerDb[j] - refLvl) }
            vals.sort()
            floor = vals[vals.count / 2]
        }

        // HF energy ratio.
        let loBin = max(1, Int(1000.0 / binWidth))
        let hiBin = Int(15000.0 / binWidth)
        var totalE: Double = 0
        var hiE: Double = 0
        for j in loBin..<half {
            let e = pow(10.0, Double(powerDb[j]) / 10.0)
            totalE += e
            if j >= hiBin { hiE += e }
        }
        let ratio = totalE > 0 ? hiE / totalE : 0

        return (
            Double(maxStep),
            floor.isNaN ? .nan : Double(floor),
            ratio
        )
    }

    /// Residual floor — Welch-спектр по всему файлу, median band выше wall.
    /// Вызывается только когда cutoff в [0.85, 0.94] * Nyquist (для 320 gate).
    /// Существующий `computeEdgeMetrics` возвращал это же значение, но был
    /// привязан к чтению middle-окна. Теперь читается отдельно — один раз,
    /// только когда нужно.
    nonisolated private static func computeResidualFloorDb(
        url: URL, sampleRate: Int,
        totalFrames: AVAudioFramePosition, format: AVAudioFormat
    ) -> Double? {
        let fftSize = 8192
        let half = fftSize / 2
        let start = max(0, Int(totalFrames) / 2 - fftSize / 2)
        guard start + fftSize <= totalFrames else { return nil }

        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        file.framePosition = AVAudioFramePosition(start)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(fftSize)
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData else { return nil }
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: fftSize)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<fftSize { mono[i] += src[i] * scale }
        }

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(mono, 1, hann, 1, &mono, 1, vDSP_Length(fftSize))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                mono.withUnsafeMutableBufferPointer { mp in
                    mp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        var powerDb = [Float](repeating: -160, count: half)
        for j in 1..<half {
            let p = real[j] * real[j] + imag[j] * imag[j]
            powerDb[j] = p > 1e-20 ? 10 * log10(p) : -160
        }

        let binWidth = Double(sampleRate) / Double(fftSize)
        let refLo = Int(10000.0 / binWidth)
        let refHi = min(half - 1, Int(14000.0 / binWidth))
        guard refLo < refHi else { return nil }
        var refSum: Float = 0
        for j in refLo...refHi { refSum += powerDb[j] }
        let refLvl = refSum / Float(refHi - refLo + 1)

        let resStart = Int(0.85 * Double(sampleRate) / 2.0 / binWidth)
        let resEnd = min(half - 1, Int(0.94 * Double(sampleRate) / 2.0 / binWidth))
        guard resEnd > resStart + 4 else { return nil }
        var vals: [Float] = []
        for j in resStart...resEnd { vals.append(powerDb[j] - refLvl) }
        vals.sort()
        return Double(vals[vals.count / 2])
    }

    /// Возвращает (sliceHz, energyHz=NaN, lowWallHz).
    nonisolated private static func detectCutoffFromPower(
        _ powerDb: [Float], binWidth: Double, sampleRate: Int
    ) -> (sliceHz: Double, energyHz: Double, lowWallHz: Double) {
        let half = powerDb.count
        let refLo = Int(10000.0 / binWidth)
        let refHi = min(half - 1, Int(14000.0 / binWidth))
        guard refLo < refHi else { return (0, .nan, .nan) }

        var refSum: Float = 0
        for j in refLo...refHi { refSum += powerDb[j] }
        let refLvl = refSum / Float(refHi - refLo + 1)

        let noiseLo = min(half - 1, Int(21000.0 / binWidth))
        let noiseHi = min(half - 1, Int(23000.0 / binWidth))
        var noiseLvl: Float = -160
        if noiseHi > noiseLo {
            var s: Float = 0
            var n = 0
            for j in noiseLo...noiseHi { s += powerDb[j]; n += 1 }
            if n > 0 { noiseLvl = s / Float(n) }
        }

        let threshold = max(refLvl - 30.0, noiseLvl + 5.0)
        var cutoffBin = half - 1
        for j in stride(from: half - 2, through: 1, by: -1) {
            if powerDb[j] > threshold {
                cutoffBin = min(half - 1, j + 2)
                break
            }
        }
        let sliceHz = Double(cutoffBin) * binWidth

        var lowWallHz: Double = .nan
        if sliceHz >= Double(sampleRate) / 2.0 - 500 {
            if let lw = detectLowWall(powerDb, binWidth: binWidth) {
                lowWallHz = lw
            }
        }
        return (sliceHz, .nan, lowWallHz)
    }

    nonisolated private static func detectLowWall(
        _ powerDb: [Float], binWidth: Double
    ) -> Double? {
        let maxBin = min(powerDb.count - 1, Int(FLACDetectiveConstants.lowWallMaxHz / binWidth))
        let cellBins = max(1, Int(500.0 / binWidth))
        guard maxBin > 3 * cellBins else { return nil }

        for j in stride(from: maxBin - 2 * cellBins, through: 4, by: -cellBins) {
            guard j - cellBins >= 1 else { continue }
            var sumA: Float = 0, sumB: Float = 0
            for k in (j - cellBins)..<j { sumA += powerDb[k] }
            for k in j..<min(powerDb.count, j + cellBins) { sumB += powerDb[k] }
            let avgA = sumA / Float(cellBins)
            let avgB = sumB / Float(cellBins)
            let step = avgA - avgB
            if step < Float(FLACDetectiveConstants.lowWallMinStepDb) { continue }

            var maxAbove: Float = -200
            for k in min(powerDb.count - 1, j + cellBins)..<maxBin {
                if powerDb[k] > maxAbove { maxAbove = powerDb[k] }
            }
            if maxAbove < avgB + Float(FLACDetectiveConstants.lowWallMinSilenceDb) {
                return Double(j) * binWidth
            }
        }
        return nil
    }

    nonisolated static func median(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return .nan }
        let s = arr.sorted()
        // np.median для чётного count — среднее двух центральных.
        // Старый `s[s.count / 2]` давал upper-median, систематически выше.
        if s.count % 2 == 0 {
            return (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
        }
        return s[s.count / 2]
    }

    nonisolated static func standardDeviation(_ arr: [Double]) -> Double {
        guard arr.count > 1 else { return 0 }
        let m = arr.reduce(0, +) / Double(arr.count)
        let v = arr.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(arr.count)
        return v.squareRoot()
    }
}
