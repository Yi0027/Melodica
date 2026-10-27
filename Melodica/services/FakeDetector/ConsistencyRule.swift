import Foundation
import AVFoundation
import Accelerate

nonisolated enum ConsistencyRule {

    private static let segmentSeconds: Double = 10.0
    private static let coherentStdHz: Double = 500
    private static let dynamicStdHz: Double = 1000

    nonisolated static func apply(_ ctx: ScoringContext) -> (score: Int, reasons: [String]) {
        guard ctx.currentScore > 30 else { return (0, []) }

        var score = 0
        var reasons: [String] = []

        // Прогрессивно: сначала 2 сегмента (5%, 95%).
        var cutoffs: [Double] = []
        for ratio in [0.05, 0.95] {
            if let c = readSegmentCutoff(ctx.fileURL, sampleRate: ctx.sampleRate,
                                          duration: ctx.duration, centerRatio: ratio) {
                cutoffs.append(c)
            } else {
                cutoffs.append(0)
            }
        }
        let valid = cutoffs.filter { $0 > 0 }
        guard valid.count >= 2 else { return (0, []) }

        var variance = standardDeviation(valid)
        if variance >= coherentStdHz && variance <= dynamicStdHz {
            // Серая зона — дочитываем 25%, 50%, 75%.
            for ratio in [0.25, 0.50, 0.75] {
                if let c = readSegmentCutoff(ctx.fileURL, sampleRate: ctx.sampleRate,
                                              duration: ctx.duration, centerRatio: ratio) {
                    cutoffs.append(c)
                } else {
                    cutoffs.append(0)
                }
            }
            let valid2 = cutoffs.filter { $0 > 0 }
            variance = valid2.count > 1 ? standardDeviation(valid2) : 0
        }

        // Пересчёт problematic сегментов.
        var problematic = 0
        for cut in cutoffs where cut > 0 {
            let segCtx = ScoringContext(
                fileURL: ctx.fileURL, sampleRate: ctx.sampleRate,
                bitDepth: ctx.bitDepth, channels: ctx.channels,
                duration: segmentSeconds, realBitrate: ctx.realBitrate,
                apparentBitrate: ctx.apparentBitrate,
                variance: nil, ratioMeasured: false,
                cutoffHz: cut,
                cutoffStdHz: 0.0,          // Python передаёт 0.0
                energyRatio: 0.0,          // Python default
                residualFloorDb: .nan,     // Python default
                edgeStepDb: .nan,
                floorAboveDb: .nan,
                isLowWall: FLACDetectiveConstants.isLowWallReading(cut),
                lowWallHz: .nan
            )
            let (r1, _) = SpectralRules.applyRule1(segCtx)
            let (r2, _) = SpectralRules.applyRule2(segCtx)
            if r1.score + r2 > 50 { problematic += 1 }
        }

        // Python-логика (без лишних гейтов).
        if variance > 1000 {
            score -= 20
            reasons.append("R10: High cutoff variance (\(Int(variance)) Hz) → Likely dynamic mastering (-20pts)")
        } else if problematic == 1 {
            score -= 30
            reasons.append("R10: Local anomaly detected (single problematic segment) → Likely artifact (-30pts)")
        } else if variance < 500 && problematic >= 3 {
            reasons.append("R10: Consistent anomaly across the whole file (variance \(Int(variance)) Hz)")
        }
        return (score, reasons)
    }

    /// Cutoff одного 10-секундного сегмента. Swift-эквивалент `_segment_cutoff`.
    nonisolated private static func readSegmentCutoff(
        _ url: URL, sampleRate: Int, duration: Double, centerRatio: Double
    ) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let centerTime = duration * centerRatio
        var startTime = max(0, centerTime - segmentSeconds / 2)
        if startTime + segmentSeconds > duration {
            startTime = max(0, duration - segmentSeconds)
        }
        let startFrame = AVAudioFramePosition(startTime * Double(sampleRate))
        let frames = AVAudioFrameCount(segmentSeconds * Double(sampleRate))

        file.framePosition = startFrame
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: frames
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        guard n >= 4096 else { return nil }
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n { mono[i] += src[i] * scale }
        }
        return detectCutoff(mono, sampleRate: sampleRate)
    }

    /// Одна и та же `detectCutoff`, что в SpectralAnalysis, но параметризована
    /// sampleRate — для чистоты R10 не тянем весь SpectralAnalysis.
    nonisolated private static func detectCutoff(_ audio: [Float], sampleRate: Int) -> Double? {
        let n = min(audio.count, 1 << 14)  // 16384
        guard n >= 4096 else { return nil }
        var block = Array(audio.prefix(n))
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(n))

        let half = n / 2
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
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
        let binWidth = Double(sampleRate) / Double(n)
        let refLo = Int(10000.0 / binWidth)
        let refHi = min(half - 1, Int(14000.0 / binWidth))
        guard refLo < refHi else { return nil }
        var refSum: Float = 0
        for j in refLo...refHi { refSum += powerDb[j] }
        let refLvl = refSum / Float(refHi - refLo + 1)
        let thr = refLvl - 30
        var cutoffBin = half - 1
        for j in stride(from: half - 2, through: 1, by: -1) {
            if powerDb[j] > thr { cutoffBin = min(half - 1, j + 2); break }
        }
        return Double(cutoffBin) * binWidth
    }

    nonisolated private static func standardDeviation(_ arr: [Double]) -> Double {
        guard arr.count > 1 else { return 0 }
        let m = arr.reduce(0, +) / Double(arr.count)
        return (arr.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(arr.count)).squareRoot()
    }
}
