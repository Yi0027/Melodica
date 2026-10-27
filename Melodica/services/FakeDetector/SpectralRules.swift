import Foundation

/// Rule 1, 2, 8 — точный порт из `rules/spectral.py`.

nonisolated enum SpectralRules {

    // MARK: - Rule 8: Nyquist exception

    static func applyRule8(_ ctx: ScoringContext) -> (score: Int, reasons: [String]) {
        var reasons: [String] = []
        let nyquist = Double(ctx.sampleRate) / 2.0
        guard nyquist > 0 else { return (0, reasons) }
        let ratio = ctx.cutoffHz / nyquist

        let baseBonus: Int
        let description: String
        if ratio >= FLACDetectiveConstants.nyquistStrongRatio {
            baseBonus = FLACDetectiveConstants.nyquistStrongBonus
            description = "Very close to limit"
        } else if ratio >= FLACDetectiveConstants.nyquistModerateRatio {
            baseBonus = FLACDetectiveConstants.nyquistModerateBonus
            description = "Probably authentic"
        } else {
            return (0, reasons)
        }

        var finalBonus = baseBonus
        if let mp3 = ctx.mp3BitrateDetected {
            if let sr = ctx.silenceRatio, sr > 0.2 {
                finalBonus = 0
                reasons.append("R8: Nyquist bonus cancelled (MP3 signature \(mp3) kbps + suspect dither \(String(format: "%.2f", sr)) > 0.2)")
            } else if let sr = ctx.silenceRatio, sr > 0.15 {
                finalBonus = -15
                reasons.append("R8: Cutoff at \(String(format: "%.1f", ratio * 100))% of Nyquist (\(Int(ctx.cutoffHz))/\(Int(nyquist)) Hz) → Reduced bonus (MP3 signature + grey zone) (-15pts)")
            } else {
                reasons.append("R8: Cutoff at \(String(format: "%.1f", ratio * 100))% of Nyquist (\(Int(ctx.cutoffHz))/\(Int(nyquist)) Hz) → \(description) (\(baseBonus)pts, MP3 signature but authentic silence)")
            }
        } else {
            reasons.append("R8: Cutoff at \(String(format: "%.1f", ratio * 100))% of Nyquist (\(Int(ctx.cutoffHz))/\(Int(nyquist)) Hz) → \(description) (\(baseBonus)pts)")
        }

        return (finalBonus, reasons)
    }

    // MARK: - Rule 1: MP3 bitrate signature

    static func applyRule1(_ ctx: ScoringContext) -> (result: (score: Int, reasons: [String]), estimated: Int?) {
        var score = 0
        var reasons: [String] = []

        // Safety 0: low wall
        if ctx.isLowWall {
            return ((score, reasons), nil)
        }

        let nyquist = Double(ctx.sampleRate) / 2.0
        let nyquistThreshold = 0.95 * nyquist

        // Safety 1: Nyquist
        if ctx.cutoffHz >= nyquistThreshold {
            return ((score, reasons), nil)
        }

        // Safety B: cutoff exactly 20000
        if ctx.cutoffHz == 20000.0 {
            let wallIsReal = !ctx.residualFloorDb.isNaN
                && ctx.residualFloorDb <= FLACDetectiveConstants.nearnyqFloorDb
            if !wallIsReal {
                if ctx.energyRatio > 0.000001 {
                    return ((0, []), nil)
                }
                if ctx.cutoffStdHz == 0.0 || ctx.cutoffStdHz.isNaN {
                    return ((0, []), nil)
                }
            }
        }

        // Safety 2: high-quality cutoff threshold
        if ctx.cutoffHz > FLACDetectiveConstants.highQualityCutoffThreshold {
            return ((score, reasons), nil)
        }

        // Gate A: variance
        if ctx.cutoffStdHz.isFinite
            && ctx.cutoffStdHz > FLACDetectiveConstants.cutoffVarianceThreshold
            && !floorIsDigitalSilence(ctx.floorAboveDb, cutoffHz: ctx.cutoffHz) {
            return ((score, reasons), nil)
        }

        // Gate D: slope is not a wall
        if edgeIsASlope(ctx.edgeStepDb, cutoffHz: ctx.cutoffHz, floorAboveDb: ctx.floorAboveDb) {
            reasons.append("R1: edge at \(Int(ctx.cutoffHz)) Hz falls only \(Int(ctx.edgeStepDb)) dB over 500 Hz — a roll-off, not a codec wall; no MP3 signature read")
            return ((score, reasons), nil)
        }
        // soft edge over silence — не блокирует, только логируем
        _ = softEdgeOverSilence(ctx.edgeStepDb, cutoffHz: ctx.cutoffHz, floorAboveDb: ctx.floorAboveDb)

        // MP3-низкочастотный фильтр фиксирован в Hz и не зависит от sample
        // rate контейнера: файл 320 kbps с 48 kHz режет ~20.5 kHz так же,
        // как и с 44.1 kHz. Нормализация сдвигала оценку на 8.8% вверх и
        // была багом. Python читает сырой cutoff.
        guard let estimated = FLACDetectiveConstants.estimateMp3Bitrate(cutoffHz: ctx.cutoffHz) else {
            return ((score, reasons), nil)
        }

        // Container windows (from flac-detective)
        let mp3Ranges: [Int: (Double, Double)] = [
            128: (400, 550),
            160: (450, 650),
            192: (500, 750),
            224: (550, 800),
            256: (600, 850),
            320: (700, 1050),
        ]
        guard let (minBr, maxBr) = mp3Ranges[estimated] else {
            return ((score, reasons), nil)
        }

        // Exception 320: cutoff >= 94% Nyquist
        if estimated == 320 {
            let limit = 0.94 * nyquist
            if ctx.cutoffHz >= limit {
                return ((score, reasons), nil)
            }
        }

        let pcmLevel = 0.90 * (Double(ctx.sampleRate) * 32.0 / 1000.0)
        let wallProvedDepth = !ctx.residualFloorDb.isNaN
            && ctx.residualFloorDb <= FLACDetectiveConstants.nearnyqFloorDb
        let containerUninformative = ctx.realBitrate >= pcmLevel && wallProvedDepth
        let depthProven = floorIsDigitalSilence(ctx.floorAboveDb, cutoffHz: ctx.cutoffHz)

        let inWindow = ctx.realBitrate >= minBr && ctx.realBitrate <= maxBr
        guard containerUninformative || depthProven || inWindow else {
            return ((score, reasons), nil)
        }

        // Near-Nyquist 320 kbps wall hardness gate
        if estimated == 320
            && !ctx.residualFloorDb.isNaN
            && ctx.residualFloorDb > FLACDetectiveConstants.nearnyqFloorDb {
            reasons.append("R1: 320 kbps cutoff near Nyquist but high residual floor (\(Int(ctx.residualFloorDb)) dB) → authentic band-limited, signature dropped")
            return ((score, reasons), nil)
        }

        score += 50
        reasons.append("Constant MP3 bitrate detected (Spectral): \(estimated) kbps")
        if depthProven {
            reasons.append("R1: the band above \(Int(ctx.cutoffHz)) Hz sits at \(Int(ctx.floorAboveDb)) dB — digital silence, the mark of a codec low-pass")
        }
        return ((score, reasons), estimated)
    }

    // MARK: - Rule 2: cutoff vs Nyquist

    static func applyRule2(_ ctx: ScoringContext) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []
        let threshold = FLACDetectiveConstants.cutoffThreshold(forSampleRate: ctx.sampleRate)

        if ctx.isLowWall {
            let s = Int(min((threshold - ctx.cutoffHz) / 200, 30))
            reasons.append("R2: the audio stops at \(Int(ctx.cutoffHz)) Hz behind a wall, nothing above it (+\(s)pts)")
            return (s, reasons)
        }

        if ctx.cutoffHz < threshold {
            let deficit = threshold - ctx.cutoffHz
            let penalty = min(deficit / 200, 30)
            let s = Int(penalty)
            score += s
            reasons.append("R2: Cutoff \(Int(ctx.cutoffHz)) Hz < \(Int(threshold)) Hz (+\(Int(penalty))pts)")
        }
        return (score, reasons)
    }

    // MARK: - Gate helpers

    static func floorIsDigitalSilence(_ floorAboveDb: Double, cutoffHz: Double) -> Bool {
        if cutoffHz >= FLACDetectiveConstants.wallGateMaxHz { return false }
        guard !floorAboveDb.isNaN else { return false }
        return floorAboveDb <= FLACDetectiveConstants.deepFloorDb
    }

    static func edgeIsASlope(_ edgeStepDb: Double, cutoffHz: Double, floorAboveDb: Double) -> Bool {
        if cutoffHz >= FLACDetectiveConstants.wallGateMaxHz { return false }
        if floorIsDigitalSilence(floorAboveDb, cutoffHz: cutoffHz) { return false }
        guard !edgeStepDb.isNaN else { return false }
        return edgeStepDb < FLACDetectiveConstants.wallMinStepDb
    }

    static func softEdgeOverSilence(_ edgeStepDb: Double, cutoffHz: Double, floorAboveDb: Double) -> Bool {
        guard cutoffHz < FLACDetectiveConstants.wallGateMaxHz else { return false }
        guard !edgeStepDb.isNaN else { return false }
        guard edgeStepDb < FLACDetectiveConstants.wallMinStepDb else { return false }
        return floorIsDigitalSilence(floorAboveDb, cutoffHz: cutoffHz)
    }

    /// Соответствует `rule1_may_consult_container`.
    static func rule1MayConsultContainer(_ ctx: ScoringContext) -> Bool {
        if ctx.isLowWall { return false }
        let nyquist = Double(ctx.sampleRate) / 2.0
        if ctx.cutoffHz >= 0.95 * nyquist { return false }
        if ctx.cutoffHz > FLACDetectiveConstants.highQualityCutoffThreshold { return false }
        if ctx.cutoffStdHz.isFinite
            && ctx.cutoffStdHz > FLACDetectiveConstants.cutoffVarianceThreshold
            && !floorIsDigitalSilence(ctx.floorAboveDb, cutoffHz: ctx.cutoffHz) { return false }
        if edgeIsASlope(ctx.edgeStepDb, cutoffHz: ctx.cutoffHz, floorAboveDb: ctx.floorAboveDb) { return false }
        // Сырой cutoff, без нормализации к 44.1 kHz — см. applyRule1.
        return FLACDetectiveConstants.estimateMp3Bitrate(cutoffHz: ctx.cutoffHz) != nil
    }
}
