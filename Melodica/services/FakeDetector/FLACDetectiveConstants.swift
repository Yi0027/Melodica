import Foundation

nonisolated enum FLACDetectiveConstants {

    // MARK: - Rule 1 low wall
    nonisolated static let lowWallMinStepDb: Double = 15.0
    nonisolated static let lowWallMinSilenceDb: Double = 30.0
    nonisolated static let lowWallMaxHz: Double = 16000.0

    // MARK: - MP3 signatures
    nonisolated static let mp3Signatures: [(kbps: Int, lo: Double, hi: Double)] = [
        (320, 19500, 21500),
        (256, 18500, 19500),
        (224, 17500, 18500),
        (192, 16500, 17500),
        (160, 15500, 16500),
        (128, 10000, 15500),
    ]

    nonisolated static let mp3StandardBitrates: [Int] = [96, 128, 160, 192, 224, 256, 320]
    
    // MARK: - Per-codec cutoff signatures
    //
    // MP3-окна не работают для AAC: кодек на том же битрейте режет HF
    // агрессивнее и с другими границами. Vorbis вообще не двигает cutoff
    // при росте q — все q2..q8 в районе 16-17 кГц. Opus всегда ~20 кГц
    // независимо от битрейта.
    //
    // Данные: calibration Musopen 2026-10.

    /// AAC-LC окна в Hz. Стена кодека фиксированная по частоте и
    /// не зависит от sample rate выхода — проверено на 44100/48000:
    /// медианы honest совпадают с точностью до ~30 Hz.
    /// Нормализация к 44.1 kHz НЕ применяется (см. spectralFromCutoff).
    /// AAC-LC окна в Hz. Стена кодека на 44.1k и 48k сдвигается по-разному
    /// и распределения 192/256 пересекаются в районе 18500–19500:
    ///   aac_192 44100  med=19352  IQR=19315..19358  (узко)
    ///   aac_192 48000  med=19242  IQR=16957..19564  (широко)
    ///   aac_256 44100  med=21956  IQR=21016..22039
    ///   aac_256 48000  med=18647  IQR=17176..21808  (широко, пересекается с 192)
    /// Разделить их нельзя — слиты в одно окно 256.
    nonisolated static let aacSignatures: [(kbps: Int, lo: Double, hi: Double)] = [
        (256, 18500, 22500),
        (160, 17600, 18500),
        (128, 16600, 17600),
        (96,  15000, 16600),
    ]

    /// Vorbis-окна. Очень грубые: q4 пересекается с q2 (IQR
    /// 14458..18913 при медиане 15845), q6 почти не отличается от q8
    /// (17390 vs 17770, IQR пересекаются). Реально различимы только
    /// две группы: "низкое качество" (q2/q4) и "высокое" (q6/q8).
    /// Используется только как приблизительный сигнал, никогда не
    /// даёт fakeCertain.
    nonisolated static let vorbisSignatures: [(kbps: Int, lo: Double, hi: Double)] = [
        (192, 17000, 24000),   // q6/q8
        (96,  12000, 17000),   // q2/q4
    ]

    /// Opus: cutoff ~20.1 кГц для 48..192 kbps. Тоже пустая —
    /// bitrate измеряется из OpusHead, а не из спектра.
    nonisolated static let opusSignatures: [(kbps: Int, lo: Double, hi: Double)] = []

    nonisolated static func signatures(for codec: LossyCodec, sampleRate: Int) -> [(kbps: Int, lo: Double, hi: Double)] {
        switch codec {
        case .mp3:
            return mp3Signatures

        case .vorbis:
            // Грубая детекция, только 44.1k. На 48k IQR q2 = 14238..23908,
            // окно шириной 10 кГц перекрывает всё остальное.
            return sampleRate == 44100 ? vorbisSignatures : []

        case .aac:
            // Отключено. Cutoff AAC зависит от энкодера (ffmpeg / iTunes /
            // Fraunhofer дают разные стены). Внутри одного ffmpeg 44.1k и
            // 48k ведут себя по-разному — IQR honest aac_256 на 48k =
            // 17998..21931. Никакое окно не покроет такой разброс.
            return []

        case .opus:
            // Отключено. У Opus нет фиксированной cutoff-стены: начиная
            // с 48 kbps CELT работает в fullband (20 кГц) для всех
            // битрейтов. Cutoff не коррелирует с битрейтом by design.
            return []

        case .alac, .unknown:
            return []
        }
    }

    // MARK: - Cutoff thresholds
    nonisolated static let cutoffThresholds: [Int: Double] = [
        44100: 20000,
        48000: 22000,
        88200: 40000,
        96000: 44000,
        176400: 80000,
        192000: 88000,
    ]
    nonisolated static let nyquistPercentage: Double = 0.45

    // MARK: - Score thresholds
    nonisolated static let scoreFakeCertain: Int = 86
    nonisolated static let scoreSuspicious: Int = 55
    nonisolated static let scoreWarning: Int = 31
    nonisolated static let scoreAuthentic: Int = 30

    // MARK: - Conviction / corroboration
    nonisolated static let convictionMinFamilies: Int = 2
    nonisolated static let convictionMinScore: Int = 55
    nonisolated static let minFamilyContribution: Int = 20
    nonisolated static let familyIndependenceMinCutoffHz: Double = 16000.0
    nonisolated static let mergedFamilySeparator: String = "&"

    // MARK: - Rule 1 gates
    nonisolated static let cutoffVarianceThreshold: Double = 130.0
    nonisolated static let wallMinStepDb: Double = 12.0
    nonisolated static let wallGateMaxHz: Double = 19500.0
    nonisolated static let deepFloorDb: Double = -58.0
    nonisolated static let nearnyqFloorDb: Double = -55.0
    nonisolated static let highQualityCutoffThreshold: Double = 21500.0

    // MARK: - Rule 5/6
    nonisolated static let varianceThreshold: Double = 100.0
    nonisolated static let highBitrateThreshold: Double = 1000.0
    nonisolated static let coherentBitrateThreshold: Double = 800.0

    // MARK: - Rule 7 silence
    nonisolated static let silenceMinCutoffHz: Double = 19000.0
    nonisolated static let silenceMaxCutoffHz: Double = 21500.0
    nonisolated static let ditherTranscodeRatio: Double = 0.3
    nonisolated static let ditherAuthenticRatio: Double = 0.15

    // MARK: - Rule 8 Nyquist
    nonisolated static let nyquistStrongRatio: Double = 0.98
    nonisolated static let nyquistModerateRatio: Double = 0.95
    nonisolated static let nyquistStrongBonus: Int = -50
    nonisolated static let nyquistModerateBonus: Int = -30

    // MARK: - Rule 11 cassette
    nonisolated static let cassetteThreshold: Int = 25
    nonisolated static let cassetteMinCutoffHz: Double = 19000.0

    // MARK: - Rule 13 MDCT
    nonisolated static let mdctWindowLen: Int = 2048
    nonisolated static let mdctHop: Int = 1024
    nonisolated static let mdctBandLoHz: Double = 2000.0
    nonisolated static let mdctBandHiHz: Double = 16000.0
    nonisolated static let mdctHoleDepthDb: Double = 40.0
    nonisolated static let mdctMinBaselineHoleFraction: Double = 0.001
    nonisolated static let mdctRatioHard: Double = 3.0
    nonisolated static let mdctRatioReview: Double = 2.0
    nonisolated static let mdctScoreHard: Int = 55
    nonisolated static let mdctScoreReview: Int = 25
    nonisolated static let mdctMinCutoffHz: Double = 0.0

    // MARK: - Rule 14 temporal seam
    nonisolated static let temporalFftSize: Int = 4096
    nonisolated static let temporalBandLoHz: Double = 10000.0
    nonisolated static let temporalBandHiHz: Double = 22050.0
    nonisolated static let temporalSearchFromHz: Double = 12000.0
    nonisolated static let temporalHalfWidth: Int = 4
    nonisolated static let temporalMinFrames: Int = 32
    nonisolated static let temporalSeamBar: Double = 0.60
    nonisolated static let temporalMinCutoffHz: Double = 15000.0

    // MARK: - Rule 15 stereo seam
    nonisolated static let stereoFftSize: Int = 2048
    nonisolated static let stereoBandLoHz: Double = 10000.0
    nonisolated static let stereoUnionDead: Double = 3e-4
    nonisolated static let stereoMonoGate: Double = 1e-5
    nonisolated static let stereoMaxFrames: Int = 200
    nonisolated static let stereoMinFrames: Int = 16
    nonisolated static let stereoRunBar: Double = 2.0
    nonisolated static let stereoMinCutoffHz: Double = 17000.0

    // MARK: - Helpers

    nonisolated static func cutoffThreshold(forSampleRate sr: Int) -> Double {
        if let exact = cutoffThresholds[sr] { return exact }
        return Double(sr) * nyquistPercentage
    }

    nonisolated static func estimateMp3Bitrate(cutoffHz: Double) -> Int? {
        for sig in mp3Signatures {
            if cutoffHz >= sig.lo && cutoffHz < sig.hi {
                return sig.kbps
            }
        }
        return nil
    }

    nonisolated static func isLossyFormat(_ ext: String) -> Bool {
        ["mp3", "mp2", "aac", "m4a", "ogg", "oga", "opus", "wma", "ac3"]
            .contains(ext.lowercased())
    }

    nonisolated static func isLosslessFormat(_ ext: String) -> Bool {
        ["flac", "alac", "wav", "wave", "aiff", "aif", "ape", "wv"]
            .contains(ext.lowercased())
    }

    nonisolated static func isCompressedLosslessFormat(_ ext: String) -> Bool {
        ["flac", "alac", "ape", "wv"].contains(ext.lowercased())
    }

    nonisolated static func isUncompressedLosslessFormat(_ ext: String) -> Bool {
        ["wav", "wave", "aiff", "aif"].contains(ext.lowercased())
    }

    // Python: LOW_WALL_FROM_HZ = 2000, CUTOFF_SCAN_START = 14000.
    // Старое `> 0 && < 14000` пропускало 500/1000 Hz, которые не могут
    // прийти из low_wall_hz (тот сканирует от 2 kHz).
    nonisolated static func isLowWallReading(_ cutoffHz: Double) -> Bool {
        cutoffHz >= 2000 && cutoffHz < 14000
    }
    // MARK: - Rule 13 codec grids (vorbis-switch, CELT)
    // Python mdct_alignment.py: свои бары для каждой гипотезы, калиброваны
    // на genuine p99.9 отдельно.
    nonisolated static let vorbisSwitchReview: Double = 1.7
    nonisolated static let vorbisSwitchHard: Double = 2.4
    nonisolated static let celtReview: Double = 2.2
    nonisolated static let celtHard: Double = 3.2
}
