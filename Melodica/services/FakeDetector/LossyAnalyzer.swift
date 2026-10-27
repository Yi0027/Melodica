import Foundation

nonisolated enum LossyAnalyzer {

    struct Analysis: Sendable {
        let declaredKbps: Int
        let spectralKbps: Int
        let spectralSource: String       // "cutoff" | "energyRatio" | "r16" | "none"
        let cutoffHz: Double
        let r16Holes: Double
        let r16Offset: Int
        let ratio: Double
        let steps: Int                    // legacy, для UI; в score не участвует
        let score: Int
        let verdict: VerdictResult
        let confidence: String
        let reasons: [String]
    }

    // MARK: - Bitrate estimators

    /// Оценка битрейта по r16. Откалибровано на Musopen (5394 файла,
    /// honest + fake) 2026-10. Пороги — середины между медианами
    /// honest MP3 по каждой ступени (см. digest per-variant medians).
    ///
    /// Диапазоны медиан honest:
    ///   96: 5.44   128: 4.99   160: 3.91   192: 2.38
    ///   224: 1.66  256: 1.33   320: 1.26
    ///
    /// ⚠️ 256 и 320 практически неразличимы по r16 (медианы 1.33 vs 1.26).
    /// Таблица возвращает корректное значение для fake до 224 включительно,
    /// но для fake 256→320 даёт 256, что при ratio=1.25 — только warning.
    /// Это архитектурный предел R16, не ошибка таблицы.
    /// Оценка битрейта по r16. Откалибровано на Musopen (5828 файлов,
    /// honest + fake) 2026-10. Пороги — середины между медианами honest
    /// по каждой ступени. Таблицы отдельные для 44.1k и 48k: granule=576
    /// сэмплов при 48k короче в миллисекундах, MDCT-дыры шире, r16
    /// систематически выше в 1.5–2 раза.
    ///
    /// Медианы honest (r16):
    ///   44100:  96=4.07  128=3.38  160=2.64  192=1.87  224=1.45  256=1.33  320=1.27
    ///   48000:  96=6.34  128=5.96  160=4.38  192=2.81  224=1.83  256=1.37  320=1.27
    ///
    /// Прочие SR (88.2k, 96k) не калиброваны — возвращаем nil.
    nonisolated static func ceilingFromR16(_ holes: Double, sampleRate: Int) -> Int? {
        if holes.isNaN { return nil }
        switch sampleRate {
        case 44100:
            if holes >= 3.72 { return 96 }
            if holes >= 3.01 { return 128 }
            if holes >= 2.25 { return 160 }
            if holes >= 1.66 { return 192 }
            if holes >= 1.39 { return 224 }
            if holes >= 1.30 { return 256 }
            return 320
        case 48000:
            if holes >= 6.15 { return 96 }
            if holes >= 5.17 { return 128 }
            if holes >= 3.59 { return 160 }
            if holes >= 2.32 { return 192 }
            if holes >= 1.60 { return 224 }
            if holes >= 1.32 { return 256 }
            return 320
        default:
            return nil
        }
    }

    /// Оценка по cutoff. Работает, только когда cutoff заметно ниже Nyquist.
    /// Signature-таблица покрывает диапазон до 21500 Гц для 320 kbps.
    nonisolated static func spectralFromCutoff(
        cutoffHz: Double,
        sampleRate: Int,
        declaredKbps: Int,
        codec: LossyCodec
    ) -> Int? {
        guard cutoffHz > 0 else { return nil }
        let nyquist = Double(sampleRate) / 2.0
        guard cutoffHz < nyquist - 500 else { return nil }
        let table = FLACDetectiveConstants.signatures(for: codec, sampleRate: sampleRate)
        for sig in table {
            if cutoffHz >= sig.lo && cutoffHz < sig.hi {
                return sig.kbps
            }
        }
        return nil
    }

    /// ⚠️ DEPRECATED / НЕ ИСПОЛЬЗУЕТСЯ (calibration 2026-10).
    ///
    /// Раньше: оценка по доле энергии выше 15 кГц. Отключено, потому что
    /// на Musopen-калибровке сигнал давал 53.4% FP на honest — er отражает
    /// наличие HF в исходном мастере (жанрозависимо), а не битрейт
    /// кодирования. Распределения er для honest_X и fake_X→320 совпадают.
    ///
    /// Оставлена для будущей перекалибровки в режиме «сравнение с honest
    /// того же трека» (см. секцию identity_ref в digest_v3.1).
    nonisolated static func spectralFromEnergyRatio(_ er: Double) -> Int? {
        if er.isNaN { return nil }
        if er < 0.0005 { return nil }
        if er < 0.0020 { return 96 }
        if er < 0.0050 { return 128 }
        if er < 0.0085 { return 160 }
        if er < 0.0105 { return 192 }
        if er < 0.0115 { return 224 }
        if er < 0.0130 { return 256 }
        return 320
    }

    // MARK: - Public entry

    nonisolated static func analyze(
        declaredKbps: Int,
        cutoffHz: Double,
        sampleRate: Int,
        energyRatio: Double,
        r16Holes: Double,
        r16Offset: Int,
        isVBR: Bool,
        codec: LossyCodec
    ) -> Analysis {

        var reasons: [String] = []

        // AAC-детекция менее надёжна, чем MP3: границы окон AAC
        // сдвигаются с энкодером и sample rate, окна перекрываются.
        // На 48k у aac_256 разброс cut_iqr до 4600 Гц — вердикт может
        // уехать на одну ступень. Помечаем для UI.
        switch codec {
        case .aac:
            reasons.append(NSLocalizedString("reason_aac_not_verifiable", comment: ""))
        case .opus:
            reasons.append(NSLocalizedString("reason_opus_not_verifiable", comment: ""))
        case .vorbis:
            reasons.append(NSLocalizedString("reason_vorbis_approximate", comment: ""))
        default:
            break
        }

        guard declaredKbps > 0 else {
            return Analysis(
                declaredKbps: 0, spectralKbps: 0, spectralSource: "none",
                cutoffHz: cutoffHz, r16Holes: r16Holes, r16Offset: r16Offset,
                ratio: 0, steps: 0, score: 0, verdict: .authentic,
                confidence: NSLocalizedString("verdict_authentic", comment: ""),
                reasons: ["Declared bitrate unknown"]
            )
        }

        let nyquist = Double(sampleRate) / 2.0
        let cutoffNearNyquist = cutoffHz >= nyquist - 500

        // 1. Cutoff — первичный сигнал, если он заметно ниже Nyquist.
        let cutoffSpectral = spectralFromCutoff(
            cutoffHz: cutoffHz,
            sampleRate: sampleRate,
            declaredKbps: declaredKbps,
            codec: codec
        )

        // 2. energyRatio — ОТКЛЮЧЁН как первичный сигнал (calibration 2026-10).
        //    На 5394 файлах Musopen давал 53.4% ошибок в honest:
        //    классика не содержит HF в самом мастере, поэтому er ≈ 0
        //    независимо от битрейта кодирования. Распределения er для
        //    honest_X и fake_X→320 идентичны — сигнал не различает их.
        //    Файлы, которые раньше шли сюда, теперь идут в r16-fallback
        //    (для CBR) или в notAssessed (для VBR с cutoff у Nyquist).
        //    Функция spectralFromEnergyRatio оставлена для будущей
        //    перекалибровки, когда мы сможем сравнивать fake с honest
        //    одного и того же трека.
        let energySpectral: Int? = nil

        // 3. r16 — последний fallback, только для CBR без других сигналов.
        let r16Spectral: Int? = {
            guard cutoffSpectral == nil, energySpectral == nil, !isVBR else { return nil }
            return ceilingFromR16(r16Holes, sampleRate: sampleRate)
        }()

        let spectral: Int
        let source: String
        if let c = cutoffSpectral {
            spectral = c
            source = "cutoff"
            reasons.append("Cutoff: declared \(declaredKbps) kbps, spectral cutoff \(Int(cutoffHz)) Hz → ~\(c) kbps")
        } else if let e = energySpectral {
            spectral = e
            source = "energyRatio"
            reasons.append("Cutoff at Nyquist; energy above 15 kHz (\(String(format: "%.4f", energyRatio))) → ~\(e) kbps")
        } else if let r = r16Spectral {
            spectral = r
            source = "r16"
            reasons.append("R16: declared \(declaredKbps) kbps, holes ratio \(String(format: "%.2f", r16Holes)) → ceiling ~\(r) kbps (corroboration only)")
        } else if cutoffNearNyquist && isVBR {
            // VBR + cutoff у Nyquist: спектральные признаки ненадёжны.
            // Никакого вердикта — честно «не знаем».
            return Analysis(
                declaredKbps: declaredKbps, spectralKbps: 0, spectralSource: "none",
                cutoffHz: cutoffHz, r16Holes: r16Holes, r16Offset: r16Offset,
                ratio: 0, steps: 0, score: 0, verdict: .notAssessed,
                confidence: NSLocalizedString("verdict_not_assessed", comment: ""),
                reasons: ["VBR with cutoff at Nyquist — no reliable spectral signature"]
            )
        } else {
            return Analysis(
                declaredKbps: declaredKbps, spectralKbps: 0, spectralSource: "none",
                cutoffHz: cutoffHz, r16Holes: r16Holes, r16Offset: r16Offset,
                ratio: 0, steps: 0, score: 0, verdict: .notAssessed,
                confidence: NSLocalizedString("verdict_not_assessed", comment: ""),
                reasons: reasons + ["Neither cutoff nor energyRatio measurable"]
            )
        }

        let ratio = Double(declaredKbps) / Double(spectral)

        // steps оставлен для совместимости с UI (BitrateAnalyzer и Card-View
        // могут его показывать). В расчёте score НЕ участвует — работает ratio.
        let ladder = [96, 128, 160, 192, 224, 256, 320]
        let declaredIdx = nearestIdx(declaredKbps, ladder: ladder)
        let spectralIdx = nearestIdx(spectral, ladder: ladder)
        let steps = max(0, declaredIdx - spectralIdx)

        // Score по ratio. Для VBR мягче (declared — усреднённое, а не ступень).
        let score: Int
        if isVBR {
            if ratio < 1.30 {
                score = 0
                reasons.append("VBR: declared≈\(declaredKbps), spectral≈\(spectral) — within tolerance")
            } else if ratio < 1.55 {
                score = 31
                reasons.append("VBR: declared≈\(declaredKbps), spectral≈\(spectral) — mild mismatch")
            } else if ratio < 1.90 {
                score = 55
                reasons.append("VBR: declared≈\(declaredKbps), spectral≈\(spectral) — 2× mismatch")
            } else {
                score = 86
                reasons.append("VBR: declared≈\(declaredKbps), spectral≈\(spectral) — severe mismatch")
            }
        } else {
            if ratio < 1.15 {
                score = 0
                reasons.append("CBR: declared \(declaredKbps), spectral \(spectral) — agree")
            } else if ratio < 1.35 {
                score = 31
                reasons.append("CBR: declared \(declaredKbps), spectral \(spectral) — borderline")
            } else if ratio < 1.55 {
                score = 55
                reasons.append("CBR: declared \(declaredKbps), spectral \(spectral) — suspicious")
            } else {
                score = 86
                reasons.append("CBR: declared \(declaredKbps), spectral \(spectral) — fake certain")
            }
        }

        // Suspected double-encode MP3: declared 320, но spectral
        // измерил 224/256. Акустически fake 224→320 и honest 224
        // идентичны (см. differential spectrum: разница 0–2 дБ),
        // поэтому поймать по аудио нельзя. Единственный сигнал —
        // declared=320 в заголовке при несоответствии spectral.
        //
        // Узкий критерий:
        //   - codec == .mp3 (для AAC другое поведение)
        //   - declaredKbps == 320
        //   - spectral 224 или 256 (не трогаем 96/128/160/192 —
        //     там ratio > 1.55 и они и так fakeCertain)
        //   - score в сером коридоре [31, 86)
        let isSuspectedDoubleEncode = codec == .mp3
            && declaredKbps == 320
            && (spectral == 224 || spectral == 256)
            && score >= 31 && score < 86

        let verdict: VerdictResult
        let confidence: String
        if isSuspectedDoubleEncode {
            verdict = .suspectedDoubleEncode
            confidence = NSLocalizedString("verdict_suspected_double", comment: "")
            reasons.append(NSLocalizedString("reason_suspected_double_encode", comment: ""))
        } else {
            // Vorbis: не даём fakeCertain, даже если score высокий.
            // Окна Vorbis слишком широкие, чтобы отличить «фейк 320»
            // от «честного q6», — держим максимум warning/suspicious.
            let cappedScore: Int = (codec == .vorbis && score >= 86) ? 55 : score
            switch cappedScore {
            case 86...:
                verdict = .fakeCertain
                confidence = NSLocalizedString("verdict_fake_certain", comment: "")
            case 55...:
                verdict = .suspicious
                confidence = NSLocalizedString("verdict_suspicious_single_family", comment: "")
            case 31...:
                verdict = .warning
                confidence = NSLocalizedString("verdict_warning", comment: "")
            default:
                verdict = .authentic
                confidence = NSLocalizedString("verdict_authentic", comment: "")
            }
        }

        return Analysis(
            declaredKbps: declaredKbps,
            spectralKbps: spectral,
            spectralSource: source,
            cutoffHz: cutoffHz,
            r16Holes: r16Holes,
            r16Offset: r16Offset,
            ratio: ratio,
            steps: steps,
            score: score,
            verdict: verdict,
            confidence: confidence,
            reasons: reasons
        )
    }

    nonisolated private static func nearestIdx(_ kbps: Int, ladder: [Int]) -> Int {
        var best = 0
        var bestDiff = Int.max
        for (i, v) in ladder.enumerated() {
            let d = abs(v - kbps)
            if d < bestDiff { bestDiff = d; best = i }
        }
        return best
    }
}
