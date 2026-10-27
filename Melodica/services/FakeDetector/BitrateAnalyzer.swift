import Foundation
import AVFoundation
import AudioToolbox

nonisolated enum BitrateAnalyzer {
    
    // MARK: - Scan progress

    enum ScanStage: Sendable {
        case opened
        case spectral
        case flacEquivalent
        case lossyAnalysis
        case rules
        case witnesses
        case done

        var label: String {
            switch self {
            case .opened:         return NSLocalizedString("scan_stage_opened", comment: "")
            case .spectral:       return NSLocalizedString("scan_stage_spectral", comment: "")
            case .flacEquivalent: return NSLocalizedString("scan_stage_flac_equivalent", comment: "")
            case .lossyAnalysis:  return NSLocalizedString("scan_stage_lossy", comment: "")
            case .rules:          return NSLocalizedString("scan_stage_rules", comment: "")
            case .witnesses:      return NSLocalizedString("scan_stage_witnesses", comment: "")
            case .done:           return NSLocalizedString("scan_stage_done", comment: "")
            }
        }

        /// Шкала откалибрована **по времени**, а не по числу стадий.
        /// Быстрые шаги (opened, spectral, fast rules) — доли процента.
        /// Медленные (flacEquivalent, R13, R16) — десятки процентов.
        ///
        /// Lossless: opened 0–1, spectral 1–3, FEQ 3–15, rules 15–95.
        /// Lossy:    opened 0–1, spectral 1–3, lossyAnalysis 3–10,
        ///           witnesses 10–95.
        var base: Double {
            switch self {
            case .opened:         return 0.00
            case .spectral:       return 0.01
            case .flacEquivalent: return 0.03
            case .lossyAnalysis:  return 0.03
            case .rules:          return 0.15
            case .witnesses:      return 0.10
            case .done:           return 0.95
            }
        }

        var end: Double {
            switch self {
            case .opened:         return 0.01
            case .spectral:       return 0.03
            case .flacEquivalent: return 0.15
            case .lossyAnalysis:  return 0.10
            case .rules:          return 0.95
            case .witnesses:      return 0.95
            case .done:           return 1.00
            }
        }

        func fullProgress(sub: Double) -> Double {
            let s = max(0.0, min(1.0, sub))
            return base + (end - base) * s
        }

        var fraction: Double { base }
    }

    enum ScanEvent: Sendable {
        case trackStarted(index: Int, track: Track)
        case stage(index: Int, stage: ScanStage)
        case stageProgress(index: Int, stage: ScanStage, sub: Double)
        case trackFinished(index: Int, result: Result)
        case trackFailed(index: Int)
        case finished
    }

    struct Result: Sendable {
        let sampleRate: Int
        let dropCutoffHz: Double
        let dropDb: Double
        let dropConfidence: Double
        let hfSlopeDbPerKhz: Double
        let energyAbove18k: Double
        let spectrumSummary: String
        let codec: LossyCodec
        let spectralSource: String
        let isVBR: Bool
        let track: Track
        let fileSize: UInt64
        let containerFormat: String
        let isCueTrack: Bool

        let declaredKbps: Int?
        let declaredSource: String
        let effectiveKbps: Int

        let cutoffHz: Double
        let cutoffStdHz: Double
        let edgeStepDb: Double
        let floorAboveDb: Double
        let residualFloorDb: Double
        let energyRatio: Double
        let cutoffSliceHz: Double
        let cutoffEnergyHz: Double
        let r16Holes: Double
        let r16Offset: Int
        let isLowWall: Bool
        let lowWallHz: Double

        let isSilent: Bool
        let isBrickwall: Bool
        let isUpsampled: Bool
        let upsampledFrom: Int?

        let ruleScores: [String: Int]
        let witnessFamilies: Set<String>
        let evidenceFamilies: Set<String>
        let score: Int

        let verdict: VerdictResult
        let confidence: String
        let reasons: [String]
    }

    struct DeclaredBitrate: Sendable {
        let kbps: Int
        let source: String
    }

    // MARK: - Public

    nonisolated static func analyzeURL(_ url: URL) async -> Result? {
        let placeholder = Track.placeholder(url: url)
        return await analyze(placeholder)
    }

    nonisolated static func analyze(
        _ track: Track,
        onStage: (@Sendable (ScanStage) -> Void)? = nil,
        onStageProgress: (@Sendable (ScanStage, Double) -> Void)? = nil
    ) async -> Result? {
        onStage?(.opened)
        onStageProgress?(.opened, 0.0)
        let realURL: URL = {
            if track.url.fragment?.hasPrefix("cue_") == true {
                var c = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                c?.fragment = nil
                return c?.url ?? track.url
            }
            return track.url
        }()

        let isCue = track.url.fragment?.hasPrefix("cue_") == true

        let attrs = try? FileManager.default.attributesOfItem(atPath: realURL.path)
        guard let size = attrs?[.size] as? UInt64, size > 0 else { return nil }

        let ext = realURL.pathExtension.lowercased()

        let codec: LossyCodec = LossyCodecDetector.detect(url: realURL)

        guard let avFile = try? AVAudioFile(forReading: realURL) else { return nil }
        let sampleRate = Int(avFile.processingFormat.sampleRate)
        let channels = Int(avFile.processingFormat.channelCount)
        let duration = Double(avFile.length) / avFile.processingFormat.sampleRate
        let bitDepth = Int(avFile.processingFormat.streamDescription.pointee.mBitsPerChannel)

        let declaredInfo = await resolveDeclaredKbps(url: realURL)
        let declaredKbps = declaredInfo?.kbps ?? 0
        let declaredSource = declaredInfo?.source ?? "—"

        let apparent = Int(Double(sampleRate * bitDepth * channels) / 1000.0)

        onStage?(.spectral)
        let spectralProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onStageProgress else { return nil }
            return { sub in cb(.spectral, sub) }
        }()
        guard let spectral = SpectralAnalysis.analyze(
            url: realURL, onProgress: spectralProgress
        ) else { return nil }

        let tempCtxForGate = ScoringContext(
            fileURL: realURL, sampleRate: sampleRate, bitDepth: bitDepth,
            channels: channels, duration: duration,
            realBitrate: 0, apparentBitrate: apparent,
            variance: nil, ratioMeasured: false,
            cutoffHz: spectral.cutoffHz, cutoffStdHz: spectral.cutoffStdHz,
            energyRatio: spectral.energyRatio,
            residualFloorDb: spectral.residualFloorDb,
            edgeStepDb: spectral.edgeStepDb, floorAboveDb: spectral.floorAboveDb,
            isLowWall: spectral.isLowWall, lowWallHz: spectral.lowWallHz
        )
        let isLossyCodec: Bool = {
            switch codec {
            case .mp3, .aac, .vorbis, .opus: return true
            case .alac, .unknown:            return false
            }
        }()
        let measureEquivalent = !isLossyCodec
            && SpectralRules.rule1MayConsultContainer(tempCtxForGate)
        if measureEquivalent {
            onStage?(.flacEquivalent)
        }
        let feqProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onStageProgress else { return nil }
            return { sub in cb(.flacEquivalent, sub) }
        }()
        let flacEquivalentSize: Int? = measureEquivalent
            ? FlacEquivalentSize.measure(realURL, onProgress: feqProgress) : nil

        let realBitrate: Double = {
            if let feq = flacEquivalentSize, duration > 0 {
                return Double(feq) * 8.0 / duration / 1000.0
            }
            if declaredKbps > 0 { return Double(declaredKbps) }
            if duration > 0 { return Double(size) * 8.0 / duration / 1000.0 }
            return 0
        }()

        if isLossyCodec {
            onStage?(.lossyAnalysis)
            onStageProgress?(.lossyAnalysis, 1.0)
            var r16Holes: Double = .nan
            var r16Offset: Int = -1
            if ext == "mp3" {
                let nyquist = Double(sampleRate) / 2.0
                let cutoffUsable = spectral.cutoffHz > 0
                    && spectral.cutoffHz < nyquist - 500
                if !cutoffUsable {
                    let r16EarlyProgress: (@Sendable (Double) -> Void)? = {
                        guard let cb = onStageProgress else { return nil }
                        return { sub in cb(.lossyAnalysis, sub) }
                    }()
                    if let grid = runMP3GridRule(
                        url: realURL, sampleRate: sampleRate,
                        onProgress: r16EarlyProgress
                    ) {
                        r16Holes = grid.ratio
                        r16Offset = grid.offset
                    }
                }
            }

            let isVBR: Bool
            switch ext {
            case "mp3":
                isVBR = Self.isVBR(url: realURL)
            case "m4a", "aac":
                isVBR = await Self.isAACVBR(url: realURL)
            default:
                isVBR = false
            }

            let lossy = LossyAnalyzer.analyze(
                declaredKbps: declaredKbps,
                cutoffHz: spectral.cutoffHz,
                sampleRate: sampleRate,
                energyRatio: spectral.energyRatio,
                r16Holes: r16Holes,
                r16Offset: r16Offset,
                isVBR: isVBR,
                codec: codec
            )

            var witnessFamilies: Set<String> = []
            var extraReasons: [String] = []

            let mdctEligible: Bool = {
                switch codec {
                case .aac, .vorbis, .opus: return true
                case .mp3:                 return false
                case .alac, .unknown:      return false
                }
            }()

            var extraScore = 0
            if mdctEligible, lossy.score >= 31, lossy.score < 86 {
                if let mdct = runFullMDCTForLossy(url: realURL, sampleRate: sampleRate),
                   mdct.isWitness {
                    witnessFamilies.insert("mdct")
                    extraReasons.append(mdct.reason)
                    extraScore += mdct.score
                }
            }

            let lossyCtx = ScoringContext(
                fileURL: realURL, sampleRate: sampleRate, bitDepth: bitDepth,
                channels: channels, duration: duration,
                realBitrate: realBitrate, apparentBitrate: apparent,
                variance: nil, ratioMeasured: false,
                cutoffHz: spectral.cutoffHz,
                cutoffStdHz: spectral.cutoffStdHz,
                energyRatio: spectral.energyRatio,
                residualFloorDb: spectral.residualFloorDb,
                edgeStepDb: spectral.edgeStepDb,
                floorAboveDb: spectral.floorAboveDb,
                isLowWall: spectral.isLowWall,
                lowWallHz: spectral.lowWallHz
            )
            onStage?(.witnesses)
            let witnessProgress: (@Sendable (Double) -> Void)? = {
                guard let cb = onStageProgress else { return nil }
                return { sub in cb(.witnesses, sub) }
            }()
            runLossyWitnesses(lossyCtx, codec: codec, onProgress: witnessProgress)

            let witnessFamilies2 = lossyCtx.witnessFamilies
            let allFamilies = witnessFamilies.union(witnessFamilies2)
            let totalScore = lossy.score + extraScore

            var finalVerdict: VerdictResult
            var finalConfidence: String

            let r18Fires = lossyCtx.sideStepDb.isFinite
                && lossyCtx.sideStepDb >= SideStepRule.stepBarDb
            let r18Strong = lossyCtx.sideStepDb.isFinite
                && lossyCtx.sideStepDb >= 15.0
            let isHighDeclaredMp3 = codec == .mp3 && declaredKbps >= 256

            if lossy.verdict == .notAssessed && extraScore == 0 {
                finalVerdict = .notAssessed
                finalConfidence = NSLocalizedString("verdict_not_assessed", comment: "")
            } else if lossy.verdict == .suspectedDoubleEncode && extraScore == 0 {
                finalVerdict = .suspectedDoubleEncode
                finalConfidence = NSLocalizedString("verdict_suspected_double", comment: "")
            } else if isHighDeclaredMp3 && r18Strong {
                finalVerdict = .fakeCertain
                finalConfidence = NSLocalizedString("verdict_fake_certain", comment: "")
            } else if isHighDeclaredMp3 && r18Fires {
                finalVerdict = .suspicious
                finalConfidence = NSLocalizedString("verdict_suspicious", comment: "")
            } else if totalScore >= 86 {
                finalVerdict = .fakeCertain
                finalConfidence = NSLocalizedString("verdict_fake_certain", comment: "")
            } else if totalScore >= 55 {
                finalVerdict = .suspicious
                finalConfidence = NSLocalizedString("verdict_suspicious_single_family", comment: "")
            } else if totalScore >= 31 {
                finalVerdict = .warning
                finalConfidence = NSLocalizedString("verdict_warning", comment: "")
            } else {
                finalVerdict = .authentic
                finalConfidence = NSLocalizedString("verdict_authentic", comment: "")
            }

            let brickwall = !spectral.edgeStepDb.isNaN
                && spectral.edgeStepDb >= FLACDetectiveConstants.wallMinStepDb

            var finalRuleScores: [String: Int] = ["Rule1MP3Bitrate": lossy.score]
            if extraScore > 0 {
                finalRuleScores["Rule13MDCTAlignment"] = extraScore
            }
            for (rule, score) in lossyCtx.ruleScores where score != 0 {
                finalRuleScores[rule, default: 0] += score
            }

            onStage?(.done)
            onStageProgress?(.done, 1.0)
            return Result(
                sampleRate: sampleRate,
                dropCutoffHz: spectral.dropCutoffHz,
                dropDb: spectral.dropDb,
                dropConfidence: spectral.dropConfidence,
                hfSlopeDbPerKhz: spectral.hfSlopeDbPerKhz,
                energyAbove18k: spectral.energyAbove18k,
                spectrumSummary: spectral.spectrumSummary,
                codec: codec,
                spectralSource: lossy.spectralSource,
                isVBR: isVBR,
                track: track,
                fileSize: size,
                containerFormat: ext.uppercased(),
                isCueTrack: isCue,
                declaredKbps: declaredInfo?.kbps,
                declaredSource: declaredSource,
                effectiveKbps: lossy.spectralKbps,
                cutoffHz: spectral.cutoffHz,
                cutoffStdHz: spectral.cutoffStdHz,
                edgeStepDb: spectral.edgeStepDb,
                floorAboveDb: spectral.floorAboveDb,
                residualFloorDb: spectral.residualFloorDb,
                energyRatio: spectral.energyRatio,
                cutoffSliceHz: spectral.cutoffSliceHz,
                cutoffEnergyHz: spectral.cutoffEnergyHz,
                r16Holes: r16Holes,
                r16Offset: r16Offset,
                isLowWall: spectral.isLowWall,
                lowWallHz: spectral.lowWallHz,
                isSilent: spectral.cutoffHz <= 0,
                isBrickwall: brickwall,
                isUpsampled: false,
                upsampledFrom: nil,
                ruleScores: finalRuleScores,
                witnessFamilies: allFamilies,
                evidenceFamilies: Evidence.evidenceFamilies(
                    finalRuleScores, witnesses: allFamilies
                ),
                score: max(0, totalScore),
                verdict: finalVerdict,
                confidence: finalConfidence,
                reasons: lossy.reasons + extraReasons + lossyCtx.reasons
            )
        }

        let ctx = ScoringContext(
            fileURL: realURL,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channels: channels,
            duration: duration,
            realBitrate: realBitrate,
            apparentBitrate: apparent,
            variance: nil,
            ratioMeasured: false,
            cutoffHz: spectral.cutoffHz,
            cutoffStdHz: spectral.cutoffStdHz,
            energyRatio: spectral.energyRatio,
            residualFloorDb: spectral.residualFloorDb,
            edgeStepDb: spectral.edgeStepDb,
            floorAboveDb: spectral.floorAboveDb,
            isLowWall: spectral.isLowWall,
            lowWallHz: spectral.lowWallHz
        )

        onStage?(.rules)
        let rulesProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onStageProgress else { return nil }
            return { sub in cb(.rules, sub) }
        }()
        _ = runPipeline(ctx, onProgress: rulesProgress)

        if ctx.currentScore < FLACDetectiveConstants.scoreWarning {
            let rms = Assessability.sampledRms(realURL, sampleRate: sampleRate)
            if let reason = Assessability.unassessableReason(
                sampleRate: sampleRate,
                durationS: duration,
                cutoffFreq: spectral.cutoffHz,
                rms: rms
            ) {
                ctx.currentScore = 0
                ctx.reasons.append("Not assessed: \(reason)")
                ctx.forceNotAssessed = true
            }
        }

        let evidence = Evidence.evidenceFamilies(
            ctx.ruleScores, witnesses: ctx.witnessFamilies
        )
        let collapsed = Evidence.collapseDependentFamilies(evidence, cutoffHz: ctx.cutoffHz)

        let (v, conf): (VerdictResult, String)
        if ctx.forceNotAssessed {
            v = .notAssessed
            conf = NSLocalizedString("verdict_not_assessed", comment: "")
        } else {
            (v, conf) = Verdict.determine(score: max(0, ctx.currentScore), families: collapsed)
        }

        let brickwall = !spectral.edgeStepDb.isNaN
            && spectral.edgeStepDb >= FLACDetectiveConstants.wallMinStepDb

        onStage?(.done)
        onStageProgress?(.done, 1.0)
        return Result(
            sampleRate: sampleRate,
            dropCutoffHz: spectral.dropCutoffHz,
            dropDb: spectral.dropDb,
            dropConfidence: spectral.dropConfidence,
            hfSlopeDbPerKhz: spectral.hfSlopeDbPerKhz,
            energyAbove18k: spectral.energyAbove18k,
            spectrumSummary: spectral.spectrumSummary,
            codec: codec,
            spectralSource: "none",
            isVBR: false,
            track: track,
            fileSize: size,
            containerFormat: ext.uppercased(),
            isCueTrack: isCue,
            declaredKbps: declaredInfo?.kbps,
            declaredSource: declaredSource,
            effectiveKbps: FLACDetectiveConstants.estimateMp3Bitrate(cutoffHz: spectral.cutoffHz) ?? 0,
            cutoffHz: spectral.cutoffHz,
            cutoffStdHz: spectral.cutoffStdHz,
            edgeStepDb: spectral.edgeStepDb,
            floorAboveDb: spectral.floorAboveDb,
            residualFloorDb: spectral.residualFloorDb,
            energyRatio: spectral.energyRatio,
            cutoffSliceHz: spectral.cutoffSliceHz,
            cutoffEnergyHz: spectral.cutoffEnergyHz,
            r16Holes: .nan,
            r16Offset: -1,
            isLowWall: spectral.isLowWall,
            lowWallHz: spectral.lowWallHz,
            isSilent: spectral.cutoffHz <= 0,
            isBrickwall: brickwall,
            isUpsampled: false,
            upsampledFrom: nil,
            ruleScores: ctx.ruleScores,
            witnessFamilies: ctx.witnessFamilies,
            evidenceFamilies: collapsed,
            score: max(0, ctx.currentScore),
            verdict: v,
            confidence: conf,
            reasons: ctx.reasons
        )
    }

    /// Запускает witness-набор для lossy-файла.
    ///
    /// Шкала (sub от `.witnesses`, span 0.10..0.95 = 0.85 total):
    ///   0.00 — вход
    ///   0.05 — loadAudio (0.5 s)
    ///   0.10 — R14 skip/R14 (0.5 s)
    ///   0.25 — R15 (2 s, самый долгий после R16)
    ///   0.35 — R18 (0.5 s)
    ///   0.35..1.00 — R16 (10 s — самый долгий)
    nonisolated private static func runLossyWitnesses(
        _ ctx: ScoringContext,
        codec: LossyCodec,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        onProgress?(0.00)
        _ = loadAudioIfNeeded(ctx)
        onProgress?(0.05)

        if codec != .mp3 && ctx.cutoffHz >= 15000 {
            ctx.activeRule = "Rule14TemporalSeam"
            let (r14, r14Reasons, witness) = TemporalSeamRule.apply(ctx)
            ctx.addScore(r14, r14Reasons)
            if witness { ctx.witnessFamilies.insert("temporal") }
            ctx.activeRule = nil
        }
        onProgress?(0.10)

        ctx.activeRule = "Rule15StereoSeam"
        let (r15, r15Reasons, witness15) = StereoSeamRule.apply(ctx)
        ctx.addScore(r15, r15Reasons)
        if witness15 { ctx.witnessFamilies.insert("stereo") }
        ctx.activeRule = nil

        onProgress?(0.25)

        if let st = loadStereoSamples(
            ctx.fileURL,
            sampleRate: ctx.loadedAudioSampleRate ?? ctx.sampleRate
        ) {
            ctx.activeRule = "Rule18SideStep"
            let (r18, r18Reasons, witness18) = SideStepRule.apply(
                ctx, left: st.left, right: st.right
            )
            ctx.addScore(r18, r18Reasons)
            if witness18 { ctx.witnessFamilies.insert("stereo") }
            ctx.activeRule = nil
        }

        onProgress?(0.35)

        if codec == .mp3 {
            let r16Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(0.35 + sub * 0.65) }
            }()
            let (ratio, offset) = MP3GridRule.gridPeakRatio(
                ctx.loadedAudio ?? [],
                sampleRate: ctx.loadedAudioSampleRate ?? ctx.sampleRate,
                onProgress: r16Progress
            )
            ctx.mp3GridRatio = ratio
            if ratio.isFinite {
                ctx.reasons.append("R16: MP3 granule grid (alignment \(offset), holes \(String(format: "%.2f", ratio))x)")
            }
        } else {
            onProgress?(1.00)
        }
    }

    nonisolated private static func runFullMDCTForLossy(
        url: URL, sampleRate: Int
    ) -> (reason: String, score: Int, ratio: Double, isWitness: Bool)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let total = file.length
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(total)
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)

        var mono = [Float](repeating: 0, count: n)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n { mono[i] += src[i] * scale }
        }

        let left:  [Float] = chCount >= 1
            ? Array(UnsafeBufferPointer(start: ch[0], count: n)) : []
        let right: [Float] = chCount >= 2
            ? Array(UnsafeBufferPointer(start: ch[1], count: n)) : left

        let ctx = ScoringContext(
            fileURL: url, sampleRate: sampleRate,
            bitDepth: 16, channels: chCount, duration: Double(n) / Double(sampleRate),
            realBitrate: 0, apparentBitrate: 0,
            variance: nil, ratioMeasured: false,
            cutoffHz: 0, cutoffStdHz: .nan, energyRatio: 0,
            residualFloorDb: .nan, edgeStepDb: .nan, floorAboveDb: .nan,
            isLowWall: false, lowWallHz: .nan
        )
        ctx.loadedAudio = mono
        ctx.loadedAudioSampleRate = sampleRate

        let (score, reasons) = MDCTAlignmentRule.applyFull(ctx, left: left, right: right)
        guard score > 0, let reason = reasons.first else { return nil }
        return (reason, score, ctx.mdctPeakRatio, true)
    }

    nonisolated private static func runMP3GridRule(
           url: URL, sampleRate: Int,
           onProgress: (@Sendable (Double) -> Void)? = nil
       ) -> (reason: String, ratio: Double, offset: Int)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let take = min(file.length, AVAudioFramePosition(sampleRate * 31))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(take)
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n { mono[i] += src[i] * scale }
        }

        let (ratio, offset) = MP3GridRule.gridPeakRatio(
            mono, sampleRate: sampleRate, onProgress: onProgress
        )
        guard ratio.isFinite else { return nil }

        let reason = "R16: MP3 granule grid (alignment \(offset), holes \(String(format: "%.2f", ratio))x)"
        return (reason, ratio, offset)
    }

    // MARK: - Pipeline

    /// Шкала (sub от `.rules`, span 0.15..0.95 = 0.80 total):
    ///   0.00 — вход
    ///   0.02 — после R8
    ///   0.04 — после R11
    ///   0.06 — после R1/R2/R4 (short-circuit 2 → silentHeuristicsPath)
    ///   0.06..0.85 — R13 (10 s)
    ///   0.86 — после R17
    ///   0.88 — после R14
    ///   0.90 — после R15
    ///   0.94 — после R18
    ///   0.96 — после R10
    ///   1.00 — конец
    nonisolated private static func runPipeline(
        _ ctx: ScoringContext,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> VerdictResult {
        onProgress?(0.00)

        ctx.activeRule = "Rule8NyquistException"
        let (r8, r8Reasons) = SpectralRules.applyRule8(ctx)
        ctx.addScore(r8, r8Reasons)
        ctx.activeRule = nil

        onProgress?(0.02)
        let initialR8Score = ctx.currentScore
        let initialR8Reasons = ctx.reasons

        if ctx.cutoffHz < CassetteRule.minCutoffHz {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule11CassetteDetection"
            let (r11, r11Reasons) = CassetteRule.apply(ctx)
            ctx.addScore(r11, r11Reasons)
            ctx.cassetteScore = r11
            ctx.activeRule = nil
        }

        let cassetteDetected = ctx.cassetteScore >= FLACDetectiveConstants.cassetteThreshold
        if cassetteDetected {
            ctx.activeRule = "Rule11CassetteDetection"
            ctx.addScore(-40, ["R11: Authentic cassette audio source (bonus -40pts)"])
            ctx.activeRule = nil
        }

        onProgress?(0.04)

        if !cassetteDetected {
            ctx.activeRule = "Rule1MP3Bitrate"
            let (r1, estimated) = SpectralRules.applyRule1(ctx)
            ctx.addScore(r1.score, r1.reasons)
            ctx.mp3BitrateDetected = estimated
            ctx.activeRule = nil
        }

        ctx.activeRule = "Rule2Cutoff"
        let (r2, r2Reasons) = SpectralRules.applyRule2(ctx)
        ctx.addScore(r2, r2Reasons)
        ctx.activeRule = nil

        ctx.activeRule = "Rule424BitSuspect"
        let (r4, r4Reasons) = applyRule4(ctx)
        ctx.addScore(r4, r4Reasons)
        ctx.activeRule = nil

        onProgress?(0.06)

        if ctx.currentScore >= FLACDetectiveConstants.scoreFakeCertain && checkCorroborated(ctx) {
            return .fakeCertain
        }

        if ctx.currentScore < 10 && ctx.mp3BitrateDetected == nil {
            return silentHeuristicsPath(ctx, deep: false, onProgress: onProgress)
        }

        if ctx.cutoffHz >= 19000 && ctx.cutoffHz <= 21500 {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule7SilenceAnalysis"
            let (r7, r7Reasons) = SilenceRule.apply(ctx)
            ctx.addScore(r7, r7Reasons)
            ctx.activeRule = nil
        }

        onProgress?(0.08)

        if ctx.mp3BitrateDetected != nil {
            refineRule8(ctx, initialScore: initialR8Score, initialReasons: initialR8Reasons)
        }

        if MDCTAlignmentRule.shouldRun(cutoffHz: ctx.cutoffHz, currentScore: ctx.currentScore) {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule13MDCTAlignment"
            let r13Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                // R13 — 10 s из 15. span 0.08..0.80 в rules.
                return { sub in cb(0.08 + sub * 0.72) }
            }()
            let (r13, r13Reasons) = MDCTAlignmentRule.apply(ctx, onProgress: r13Progress)
            ctx.addScore(r13, r13Reasons)
            ctx.activeRule = nil
            withdrawR8ProtectionIfNeeded(ctx)
            onProgress?(0.82)
        } else {
            onProgress?(0.82)
        }

        if MDCTAlignmentRule.shouldRun(cutoffHz: ctx.cutoffHz, currentScore: ctx.currentScore) {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule17SBRReplication"
            let (r17, r17Reasons, _) = SBRRule.apply(ctx)
            ctx.addScore(r17, r17Reasons)
            ctx.activeRule = nil
            withdrawR8ProtectionIfNeededFor17(ctx)
        }
        onProgress?(0.84)

        if ctx.cutoffHz >= 15000 {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule14TemporalSeam"
            let (r14, r14Reasons, witness) = TemporalSeamRule.apply(ctx)
            ctx.addScore(r14, r14Reasons)
            if witness { ctx.witnessFamilies.insert("temporal") }
            ctx.activeRule = nil
        }
        onProgress?(0.88)

        _ = loadAudioIfNeeded(ctx)
        ctx.activeRule = "Rule15StereoSeam"
        let (r15, r15Reasons, witness15) = StereoSeamRule.apply(ctx)
        ctx.addScore(r15, r15Reasons)
        if witness15 { ctx.witnessFamilies.insert("stereo") }
        ctx.activeRule = nil

        onProgress?(0.92)

        if let stereo = loadStereoSamples(ctx.fileURL, sampleRate: ctx.loadedAudioSampleRate ?? ctx.sampleRate) {
            ctx.activeRule = "Rule18SideStep"
            let (r18, r18Reasons, witness18) = SideStepRule.apply(
                ctx, left: stereo.left, right: stereo.right
            )
            ctx.addScore(r18, r18Reasons)
            if witness18 { ctx.witnessFamilies.insert("stereo") }
            ctx.activeRule = nil
        }
        onProgress?(0.94)

        if ctx.currentScore >= FLACDetectiveConstants.scoreFakeCertain && checkCorroborated(ctx) {
            return .fakeCertain
        }

        if ctx.currentScore > 30 {
            ctx.activeRule = "Rule10Consistency"
            let (r10, r10Reasons) = ConsistencyRule.apply(ctx)
            ctx.addScore(r10, r10Reasons)
            ctx.activeRule = nil
        }

        onProgress?(0.96)

        if ctx.currentScore >= FLACDetectiveConstants.convictionMinScore
            && !checkCorroborated(ctx) {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule16MP3Grid"
            let (_, r16Reasons, witness16) = MP3GridRule.apply(ctx)
            ctx.addScore(0, r16Reasons)
            if witness16 { ctx.witnessFamilies.insert("mp3grid") }
            ctx.activeRule = nil
        }

        onProgress?(1.00)
        return .authentic
    }

    /// Тот же span, что и у runPipeline. Особенность: та же функция `onProgress`
    /// приходит с уже эмитнутым `0.06` (после R1/R2/R4), поэтому R13 стартует
    /// с `0.06`, а не с 0.
    nonisolated private static func silentHeuristicsPath(
        _ ctx: ScoringContext,
        deep: Bool,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> VerdictResult {

        // R13 — самая долгая (10 s). Отдаём ей span 0.06..0.56.
        // Дальше R17 (1s), R14 (1.5s), R15 (2s), R18 (0.5s) — 0.56..0.95.
        // Никаких early return — они давали прыжок 77→100.

        if !deep {
            let asked = MDCTAlignmentRule.shouldRun(
                cutoffHz: ctx.cutoffHz, currentScore: ctx.currentScore
            )
            if asked {
                _ = loadAudioIfNeeded(ctx)
                ctx.activeRule = "Rule13MDCTAlignment"
                let r13Progress: (@Sendable (Double) -> Void)? = {
                    guard let cb = onProgress else { return nil }
                    return { sub in cb(0.06 + sub * 0.50) }
                }()
                let (r13, r13Reasons) = MDCTAlignmentRule.apply(ctx, onProgress: r13Progress)
                ctx.addScore(r13, r13Reasons)
                ctx.activeRule = nil
                withdrawR8ProtectionIfNeeded(ctx)
                onProgress?(0.58)
            } else {
                onProgress?(0.58)
            }
        } else {
            _ = loadAudioIfNeeded(ctx)
            ctx.activeRule = "Rule13MDCTAlignment"
            let r13Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(0.06 + sub * 0.50) }
            }()
            let (r13, r13Reasons) = MDCTAlignmentRule.apply(ctx, onProgress: r13Progress)
            ctx.addScore(r13, r13Reasons)
            ctx.activeRule = nil
            withdrawR8ProtectionIfNeeded(ctx)
            onProgress?(0.58)
        }

        // R17 — 1 s. span 0.58..0.66.
        if ctx.currentScore < FLACDetectiveConstants.scoreFakeCertain {
            ctx.activeRule = "Rule17SBRReplication"
            let r17Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(0.58 + sub * 0.08) }
            }()
            let (r17, r17Reasons, _) = SBRRule.apply(ctx, onProgress: r17Progress)
            ctx.addScore(r17, r17Reasons)
            ctx.activeRule = nil
            withdrawR8ProtectionIfNeededFor17(ctx)
        }
        onProgress?(0.66)

        // R14 — 1.5 s. span 0.66..0.76.
        if ctx.cutoffHz >= 15000 {
            ctx.activeRule = "Rule14TemporalSeam"
            let r14Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(0.66 + sub * 0.10) }
            }()
            let (r14, r14Reasons, witness) = TemporalSeamRule.apply(ctx, onProgress: r14Progress)
            ctx.addScore(r14, r14Reasons)
            if witness { ctx.witnessFamilies.insert("temporal") }
            ctx.activeRule = nil
        }
        onProgress?(0.76)

        // R15 — 2 s, самое долгое после R13. span 0.76..0.90.
        _ = loadAudioIfNeeded(ctx)
        ctx.activeRule = "Rule15StereoSeam"
        let r15Progress: (@Sendable (Double) -> Void)? = {
            guard let cb = onProgress else { return nil }
            return { sub in cb(0.76 + sub * 0.14) }
        }()
        let (r15, r15Reasons, witness15) = StereoSeamRule.apply(ctx, onProgress: r15Progress)
        ctx.addScore(r15, r15Reasons)
        if witness15 { ctx.witnessFamilies.insert("stereo") }
        ctx.activeRule = nil
        onProgress?(0.90)

        // R18 — 0.5 s. span 0.90..0.95.
        if let stereo = loadStereoSamples(
            ctx.fileURL,
            sampleRate: ctx.loadedAudioSampleRate ?? ctx.sampleRate
        ) {
            ctx.activeRule = "Rule18SideStep"
            let r18Progress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(0.90 + sub * 0.05) }
            }()
            let (r18, r18Reasons, witness18) = SideStepRule.apply(
                ctx, left: stereo.left, right: stereo.right,
                onProgress: r18Progress
            )
            ctx.addScore(r18, r18Reasons)
            if witness18 { ctx.witnessFamilies.insert("stereo") }
            ctx.activeRule = nil
        }
        onProgress?(0.96)

        // R16 — обычно не запускается на authentic (score < 55). Если
        // всё же сработает, диапазон у него будет 0.96..1.00.
        if ctx.currentScore >= FLACDetectiveConstants.convictionMinScore
            && !checkCorroborated(ctx) {
            ctx.activeRule = "Rule16MP3Grid"
            let (_, r16Reasons, witness16) = MP3GridRule.apply(ctx)
            ctx.addScore(0, r16Reasons)
            if witness16 { ctx.witnessFamilies.insert("mp3grid") }
            ctx.activeRule = nil
        }

        onProgress?(1.00)
        return .authentic
    }

    nonisolated private static func refineRule8(
        _ ctx: ScoringContext, initialScore: Int, initialReasons: [String]
    ) {
        ctx.currentScore -= initialScore
        ctx.ruleScores["Rule8NyquistException"] =
            (ctx.ruleScores["Rule8NyquistException"] ?? 0) - initialScore
        for reason in initialReasons {
            if let idx = ctx.reasons.firstIndex(of: reason) {
                ctx.reasons.remove(at: idx)
            }
        }
        ctx.activeRule = "Rule8NyquistException"
        let (r8, r8Reasons) = SpectralRules.applyRule8(ctx)
        ctx.addScore(r8, r8Reasons)
        ctx.activeRule = nil
    }

    nonisolated private static func withdrawR8ProtectionIfNeededFor17(_ ctx: ScoringContext) {
        let r17Score = ctx.ruleScores["Rule17SBRReplication"] ?? 0
        guard r17Score > 0 else { return }
        let r8Score = ctx.ruleScores["Rule8NyquistException"] ?? 0
        if r8Score < 0 {
            ctx.addScore(-r8Score, [
                "R8 protection withdrawn: R17 found the high band to be a copy of a lower one (band replication)"
            ])
        }
    }

    nonisolated private static func withdrawR8ProtectionIfNeeded(_ ctx: ScoringContext) {
        let r13Score = ctx.ruleScores["Rule13MDCTAlignment"] ?? 0
        guard r13Score > 0 else { return }
        let r8Score = ctx.ruleScores["Rule8NyquistException"] ?? 0
        if r8Score < 0 {
            ctx.addScore(-r8Score, [
                "R8 protection withdrawn: R13 found a positive MDCT quantisation signature"
            ])
        }
    }

    nonisolated private static func codecRulePoints(_ ctx: ScoringContext) -> Int {
        return (ctx.ruleScores["Rule13MDCTAlignment"] ?? 0)
             + (ctx.ruleScores["Rule17SBRReplication"] ?? 0)
    }

    nonisolated private static func applyRule4(_ ctx: ScoringContext) -> (Int, [String]) {
        guard ctx.bitDepth == 24,
              let mp3 = ctx.mp3BitrateDetected, mp3 < 500,
              ctx.cutoffHz < 19000 else {
            return (0, [])
        }
        if let sr = ctx.silenceRatio, sr < 0.15 { return (0, []) }
        return (30, ["R4: 24-bit with MP3 source \(mp3) kbps and cutoff \(Int(ctx.cutoffHz)) Hz (upscale suspect)"])
    }

    nonisolated private static func checkCorroborated(_ ctx: ScoringContext) -> Bool {
        let evidence = Evidence.evidenceFamilies(ctx.ruleScores, witnesses: ctx.witnessFamilies)
        let collapsed = Evidence.collapseDependentFamilies(evidence, cutoffHz: ctx.cutoffHz)
        return collapsed.count >= FLACDetectiveConstants.convictionMinFamilies
    }

    nonisolated private static func loadStereoSamples(
        _ url: URL, sampleRate: Int
    ) -> (left: [Float], right: [Float])? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let total = file.length
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(total)
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let data = buffer.floatChannelData,
              Int(buffer.format.channelCount) >= 2 else { return nil }
        let n = Int(buffer.frameLength)
        let left = Array(UnsafeBufferPointer(start: data[0], count: n))
        let right = Array(UnsafeBufferPointer(start: data[1], count: n))
        return (left, right)
    }

    @discardableResult
    nonisolated private static func loadAudioIfNeeded(_ ctx: ScoringContext) -> Bool {
        if ctx.loadedAudio != nil { return true }
        guard let file = try? AVAudioFile(forReading: ctx.fileURL) else { return false }
        let total = file.length
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(total)
        ) else { return false }
        do { try file.read(into: buffer) } catch { return false }
        guard let ch = buffer.floatChannelData else { return false }
        let n = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n { mono[i] += src[i] * scale }
        }
        ctx.loadedAudio = mono
        ctx.loadedAudioSampleRate = Int(file.processingFormat.sampleRate)
        return true
    }

    // MARK: - Declared bitrate

    nonisolated private static func resolveDeclaredKbps(url: URL) async -> DeclaredBitrate? {
        if let tb = audioToolboxBitrate(url: url) { return tb }
        if let av = await bitrateFromAVAsset(url: url), av > 0 {
            return DeclaredBitrate(kbps: av, source: "AVAsset")
        }
        if let bytes = await totalSampleDataLength(url: url) {
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration).seconds, d.isFinite, d > 0 {
                let kbps = Int((Double(bytes) * 8.0 / d / 1000.0).rounded())
                if kbps > 0 { return DeclaredBitrate(kbps: kbps, source: "audio data") }
            }
        }
        return nil
    }

    nonisolated private static func audioToolboxBitrate(url: URL) -> DeclaredBitrate? {
        var fileID: AudioFileID?
        let st = AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID)
        guard st == noErr, let fid = fileID else { return nil }
        defer { AudioFileClose(fid) }

        var bitrate: UInt32 = 0
        var sz = UInt32(MemoryLayout<UInt32>.size)
        if AudioFileGetProperty(fid, kAudioFilePropertyBitRate, &sz, &bitrate) == noErr, bitrate > 0 {
            return DeclaredBitrate(kbps: Int((Double(bitrate) / 1000.0).rounded()), source: "AudioToolbox")
        }

        var bytes: UInt64 = 0
        var bsz = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(fid, kAudioFilePropertyAudioDataByteCount, &bsz, &bytes) == noErr,
              bytes > 0 else { return nil }

        var duration: Double = 0
        var dsz = UInt32(MemoryLayout<Double>.size)
        guard AudioFileGetProperty(fid, kAudioFilePropertyEstimatedDuration, &dsz, &duration) == noErr,
              duration > 0 else { return nil }
        let kbps = Int((Double(bytes) * 8.0 / duration / 1000.0).rounded())
        return kbps > 0 ? DeclaredBitrate(kbps: kbps, source: "audio data") : nil
    }

    nonisolated private static func bitrateFromAVAsset(url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        guard let rate = try? await track.load(.estimatedDataRate) else { return nil }
        let kbps = Int((rate / 1000).rounded())
        return kbps > 0 ? kbps : nil
    }

    nonisolated private static func totalSampleDataLength(url: URL) async -> UInt64? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        guard let bytes = try? await track.load(.totalSampleDataLength), bytes > 0 else { return nil }
        return UInt64(bytes)
    }

    nonisolated static func isAACVBR(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let rate = try? await track.load(.estimatedDataRate),
              let bytes = try? await track.load(.totalSampleDataLength),
              let duration = try? await asset.load(.duration).seconds,
              duration > 0, rate > 0
        else { return false }
        let audioDataKbps = Double(bytes) * 8.0 / duration / 1000.0
        let rateKbps = Double(rate) / 1000.0
        let ratio = rateKbps / max(audioDataKbps, 1)
        return ratio < 0.85 || ratio > 1.15
    }

    nonisolated static func isVBR(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "mp3" else { return false }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }

        var audioStart: UInt64 = 0
        if let header = try? fh.read(upToCount: 10), header.count == 10 {
            if header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 {
                let size = (UInt64(header[6] & 0x7F) << 21)
                         | (UInt64(header[7] & 0x7F) << 14)
                         | (UInt64(header[8] & 0x7F) << 7)
                         |  UInt64(header[9] & 0x7F)
                let flags = header[5]
                let footerExtra: UInt64 = (flags & 0x10) != 0 ? 10 : 0
                audioStart = 10 + size + footerExtra
            } else {
                audioStart = 0
            }
        }

        do {
            try fh.seek(toOffset: audioStart)
        } catch {
            return false
        }

        guard let data = try? fh.read(upToCount: 512), data.count >= 8 else {
            return false
        }

        var i = 0
        let searchLimit = min(data.count - 4, 128)
        while i < searchLimit {
            if data[i] == 0xFF, (data[i + 1] & 0xE0) == 0xE0 {
                break
            }
            i += 1
        }
        guard i < searchLimit else { return false }

        let searchStart = i + 4
        let searchEnd = min(data.count - 4, i + 200)
        guard searchStart < searchEnd else { return false }

        for j in searchStart..<searchEnd {
            let tag = String(bytes: data[j..<(j + 4)], encoding: .ascii)
            if tag == "Xing" { return true }
            if tag == "Info" { return false }
        }

        return false
    }

    // MARK: - Batch

    @discardableResult
    nonisolated static func analyze(
        tracks: [Track],
        onEvent: (@Sendable (ScanEvent) -> Void)? = nil
    ) async -> [Result] {
        var seen: Set<String> = []
        var unique: [Track] = []
        for track in tracks {
            let path: String = {
                if track.url.fragment?.hasPrefix("cue_") == true {
                    var c = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                    c?.fragment = nil
                    return (c?.url ?? track.url).path
                }
                return track.url.path
            }()
            if seen.contains(path) { continue }
            seen.insert(path)
            unique.append(track)
        }

        var results: [Result] = []
        for (i, track) in unique.enumerated() {
            if Task.isCancelled { return results }
            onEvent?(.trackStarted(index: i, track: track))

            let stageHandler: (@Sendable (ScanStage) -> Void)? = {
                guard let ev = onEvent else { return nil }
                return { stage in ev(.stage(index: i, stage: stage)) }
            }()

            let stageProgressHandler: (@Sendable (ScanStage, Double) -> Void)? = {
                guard let ev = onEvent else { return nil }
                return { stage, sub in
                    ev(.stageProgress(index: i, stage: stage, sub: sub))
                }
            }()

            if let r = await analyze(
                track,
                onStage: stageHandler,
                onStageProgress: stageProgressHandler
            ) {
                results.append(r)
                if Task.isCancelled { return results }
                onEvent?(.trackFinished(index: i, result: r))
            } else {
                if Task.isCancelled { return results }
                onEvent?(.trackFailed(index: i))
            }
            await Task.yield()
        }
        if Task.isCancelled { return results }
        onEvent?(.finished)
        return results
    }
}

// MARK: - UI helpers

extension BitrateAnalyzer.Result {

    var displayBitrateKbps: Int? {
        switch verdict {
        case .authentic, .warning:
            return declaredKbps
        case .suspectedDoubleEncode, .suspicious, .fakeCertain:
            return effectiveKbps > 0 ? effectiveKbps : declaredKbps
        case .notAssessed:
            return nil
        }
    }

    var showsEffectiveBitrate: Bool {
        switch verdict {
        case .authentic, .notAssessed:
            return false
        default:
            return effectiveKbps > 0
        }
    }
}
