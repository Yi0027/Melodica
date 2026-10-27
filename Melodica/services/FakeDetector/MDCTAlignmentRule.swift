import Foundation
import AVFoundation
import Accelerate

/// Rule 13: MDCT frame alignment — точный порт из `mdct.py`.

nonisolated enum MDCTAlignmentRule {

    // KBD window (alpha=4)
    static let windowLen = FLACDetectiveConstants.mdctWindowLen
    static let hop = FLACDetectiveConstants.mdctHop

    static func kbdWindow(length: Int = 2048, alpha: Double = 4.0) -> [Float] {
        let half = length / 2
        // Kaiser window: I0(pi*alpha*sqrt(1-((n-half)/half)^2)) / I0(pi*alpha)
        // у numpy.kaiser(hald+1, beta): beta = pi*alpha
        var kaiser = [Double](repeating: 0, count: half + 1)
        let beta = Double.pi * alpha
        for i in 0...half {
            let x = 2.0 * Double(i) / Double(half) - 1.0
            let arg = beta * (1.0 - x * x).squareRoot()
            kaiser[i] = besselI0(arg) / besselI0(beta)
        }
        // cumulative
        var cum = [Double](repeating: 0, count: half + 1)
        var s = 0.0
        for i in 0...half { s += kaiser[i]; cum[i] = s }
        let total = cum[half]
        var rising = [Float](repeating: 0, count: half)
        for i in 0..<half {
            rising[i] = Float((cum[i] / total).squareRoot())
        }
        var w = rising
        w.append(contentsOf: rising.reversed())
        return w
    }

    static func vorbisWindow(length: Int = 2048) -> [Float] {
        let n = length
        var w = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let inner = Double.pi / Double(n) * (Double(i) + 0.5)
            let s = sin(inner)
            let v = sin(Double.pi / 2.0 * s * s)
            w[i] = Float(v)
        }
        return w
    }

    static func besselI0(_ x: Double) -> Double {
        // Аппроксимация I0 (стандартная из Numerical Recipes / A&S)
        let ax = abs(x)
        if ax < 3.75 {
            let t = (ax / 3.75) * (ax / 3.75)
            return 1.0 + t * (3.5156229 + t * (3.0899424 + t * (1.2067492
                + t * (0.2659732 + t * (0.360768e-1 + t * 0.45813e-2)))))
        }
        let y = 3.75 / ax
        return (exp(ax) / ax.squareRoot()) * (0.39894228 + y * (0.1328592e-1
            + y * (0.225319e-2 + y * (-0.157565e-2 + y * (0.916281e-2
            + y * (-0.2057706e-1 + y * (0.2635537e-1 + y * (-0.1647633e-1
            + y * 0.392377e-2))))))))
    }

    /// Прямой MDCT через наивное мат-умножение (медленно, но точно как в Python).
    /// Возвращает магнитуды |X_k| для k в lo..<hi.
    static func mdctMagnitudes(
        _ block: [Float], window: [Float], bandLoHz: Double, bandHiHz: Double,
        sampleRate: Int
    ) -> [Float] {
        let half = windowLen / 2
        let nyquist = Double(sampleRate) / 2.0
        let lo = max(1, Int(bandLoHz / nyquist * Double(half)))
        let hi = min(half, Int(bandHiHz / nyquist * Double(half)))
        guard hi > lo else { return [] }

        // windowed block
        var x = [Float](repeating: 0, count: windowLen)
        for i in 0..<windowLen { x[i] = block[i] * window[i] }

        var mags = [Float](repeating: 0, count: hi - lo)
        // X[k] = sum_{n=0}^{2N-1} x[n] * cos(pi/N * (n + 0.5 + N/2) * (k + 0.5))
        let piOverN = Double.pi / Double(half)
        for k in lo..<hi {
            let kk = Double(k) + 0.5
            var sum: Double = 0
            for n in 0..<windowLen {
                let ang = piOverN * (Double(n) + 0.5 + Double(half) / 2.0) * kk
                sum += Double(x[n]) * cos(ang)
            }
            mags[k - lo] = Float(abs(sum))
        }
        return mags
    }

    /// Hole fraction at specific offsets.
    /// Возвращает массив [Float] — hole fraction для каждого offset (или NaN).
    static func alignmentCurve(
        _ audio: [Float], sampleRate: Int,
        window: [Float], nFrames: Int,
        offsets: [Int], refSize: Int = 33,
        depthDb: Double = 40.0,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> [Float] {
        let usable = audio.count - windowLen
        guard usable > 0 else { return offsets.map { _ in .nan } }

        let stride: Int = max(hop, (usable / max(1, nFrames)) / hop * hop)
        let thr = Float(pow(10.0, -depthDb / 20.0))
        var holeCount = [Float](repeating: 0, count: offsets.count)
        var used = [Float](repeating: 0, count: offsets.count)

        // numpy-версия проверяет max(starts) + WINDOW_LEN > len(x) → break всего frame.
        // Если хоть один offset не влезает, фрейм не обрабатывается вовсе.
        let maxOffset = offsets.max() ?? 0

        for frame in 0..<nFrames {
            onProgress?(Double(frame) / Double(nFrames))
            let maxStart = maxOffset + frame * stride
            if maxStart + windowLen > audio.count { break }

            for (oi, off) in offsets.enumerated() {
                let start = off + frame * stride
                let block = Array(audio[start..<(start + windowLen)])
                let mags = mdctMagnitudes(
                    block, window: window,
                    bandLoHz: FLACDetectiveConstants.mdctBandLoHz,
                    bandHiHz: FLACDetectiveConstants.mdctBandHiHz,
                    sampleRate: sampleRate
                )
                guard mags.count >= refSize else { continue }

                // Локальная медиана — референс и для energetic-проверки, и для hole-теста.
                let half = refSize / 2
                var ref = [Float](repeating: 0, count: mags.count)
                for j in 0..<mags.count {
                    let lo = max(0, j - half)
                    let hi = min(mags.count - 1, j + half)
                    var vals = Array(mags[lo...hi])
                    vals.sort()
                    ref[j] = vals[vals.count / 2]
                }
                var refMean: Float = 0
                for v in ref { refMean += v }
                refMean /= Float(ref.count)
                // numpy: ref.mean(axis=1) > 1e-7 — проверка по МЕДИАНЕ, не по mags.
                if refMean < 1e-7 { continue }

                var holes = 0
                for j in 0..<mags.count where mags[j] < ref[j] * thr {
                    holes += 1
                }
                holeCount[oi] += Float(holes) / Float(mags.count)
                used[oi] += 1
            }
        }

        onProgress?(1.0)
        return offsets.indices.map { i in
            used[i] > 0 ? holeCount[i] / used[i] : .nan
        }
    }

    /// Возвращает (peak_ratio, best_offset) для одного окна.
    static func alignmentStat(
        _ audio: [Float], sampleRate: Int,
        windowKind: String,
        coarseFrames: Int = 3,
        fineFrames: Int = 24,
        nCandidates: Int = 24,
        nBaseline: Int = 64,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (Double, Int) {
        let window: [Float]
        switch windowKind {
        case "kbd": window = kbdWindow()
        case "vorbis": window = vorbisWindow()
        default: window = kbdWindow()
        }

        let allOffsets = Array(0..<hop)
        // Coarse — быстрая (nFrames: 3), но эмитим 0..0.05 в общем прогрессе R13.
        let coarseProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onProgress else { return nil }
            return { sub in cb(sub * 0.05) }
        }()
        let coarse = alignmentCurve(
            audio, sampleRate: sampleRate, window: window,
            nFrames: coarseFrames, offsets: allOffsets, refSize: 9,
            onProgress: coarseProgress
        )

        // Ранжируем
        var ranked = allOffsets
        ranked.sort { a, b in
            let va = coarse[a].isFinite ? coarse[a] : -1
            let vb = coarse[b].isFinite ? coarse[b] : -1
            return va > vb
        }
        let candidates = Array(ranked.prefix(nCandidates)).sorted()

        // Baseline offsets
        var spread: [Int] = []
        let n = nBaseline * 2
        if n > 1 {
            for i in 0..<n {
                let v = Int(Double(hop - 1) * Double(i) / Double(n - 1))
                spread.append(v)
            }
        }
        var baseline: [Int] = []
        for o in spread {
            let minDist = candidates.map { abs(o - $0) }.min() ?? 1000
            if minDist > 4 { baseline.append(o) }
        }
        baseline = Array(Set(baseline)).sorted().prefix(nBaseline).map { $0 }
        guard !baseline.isEmpty else { return (.nan, -1) }

        let offsets = candidates + baseline
        // Fine — самая долгая часть. 0.05..1.00 в общем прогрессе R13.
        let fineProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onProgress else { return nil }
            return { sub in cb(0.05 + sub * 0.95) }
        }()
        let fine = alignmentCurve(
            audio, sampleRate: sampleRate, window: window,
            nFrames: fineFrames, offsets: offsets, refSize: 33,
            onProgress: fineProgress
        )

        let candVals = Array(fine.prefix(candidates.count))
        let baseVals = Array(fine.dropFirst(candidates.count)).filter { $0.isFinite }
        guard !baseVals.isEmpty else { return (.nan, -1) }

        let bestIdx = candVals.enumerated()
            .filter { $0.element.isFinite }
            .max(by: { $0.element < $1.element })?.offset
        guard let bi = bestIdx else { return (.nan, -1) }
        let peak = Double(candVals[bi])
        let medianBase = Double(SpectralAnalysis.median(baseVals.map { Double($0) }))

        if medianBase < FLACDetectiveConstants.mdctMinBaselineHoleFraction {
            return (.nan, -1)
        }
        return (peak / medianBase, candidates[bi])
    }

    static func bestAlignmentStat(
        _ audio: [Float],
        sampleRate: Int,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (Double, Int, String) {
        var best: (Double, Int, String) = (.nan, -1, "none")
        let hypotheses = ["kbd", "vorbis"]
        for (i, kind) in hypotheses.enumerated() {
            // Каждая гипотеза получает свой под-диапазон: kbd → [0, 0.5],
            // vorbis → [0.5, 1.0]. Если первая гипотеза даёт ratio >= 3.0,
            // break — сразу эмитим 1.0.
            let base = Double(i) / Double(hypotheses.count)
            let span = 1.0 / Double(hypotheses.count)
            let subProgress: (@Sendable (Double) -> Void)? = {
                guard let cb = onProgress else { return nil }
                return { sub in cb(base + sub * span) }
            }()
            let (r, o) = alignmentStat(
                audio, sampleRate: sampleRate, windowKind: kind,
                onProgress: subProgress
            )
            if r.isFinite && (!best.0.isFinite || r > best.0) {
                best = (r, o, kind)
            }
            if r.isFinite && r >= 3.0 { break }
        }
        onProgress?(1.0)
        return best
    }

    static func shouldRun(cutoffHz: Double, currentScore: Int) -> Bool {
        return cutoffHz >= FLACDetectiveConstants.mdctMinCutoffHz
            && currentScore < FLACDetectiveConstants.scoreFakeCertain
    }

    static func apply(
        _ ctx: ScoringContext,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (score: Int, reasons: [String]) {
        onProgress?(0.00)
        guard let audio = ctx.loadedAudio, let sr = ctx.loadedAudioSampleRate else {
            return (0, [])
        }
        // bestAlignmentStat (две гипотезы) — самая долгая часть R13,
        // занимает 0.00 → 0.70 в шкале R13.
        let bestProgress: (@Sendable (Double) -> Void)? = {
            guard let cb = onProgress else { return nil }
            return { sub in cb(sub * 0.70) }
        }()
        let (ratio, offset, hypothesis) = bestAlignmentStat(
            audio, sampleRate: sr, onProgress: bestProgress
        )
        ctx.mdctPeakRatio = ratio
        onProgress?(0.70)

        // Исходный тир (KBD/Vorbis).
        var points = 0
        var reason = ""
        if ratio.isFinite {
            if ratio >= FLACDetectiveConstants.mdctRatioHard {
                points = FLACDetectiveConstants.mdctScoreHard
                reason = "R13: MDCT quantisation grid detected (\(hypothesis) window) — hole density \(String(format: "%.1f", ratio))x higher at frame alignment \(offset) than at any other (+\(FLACDetectiveConstants.mdctScoreHard)pts)"
            } else if ratio >= FLACDetectiveConstants.mdctRatioReview {
                points = FLACDetectiveConstants.mdctScoreReview
                reason = "R13: possible MDCT alignment structure (\(String(format: "%.1f", ratio))x at offset \(offset), \(hypothesis) window) (+\(FLACDetectiveConstants.mdctScoreReview)pts)"
            }
        }

        // Codec grids (vorbis-switch, CELT) — если исходный тир < hard
        // и спектр не стационарен (a tone fakes alignment).
        let stationary = points < FLACDetectiveConstants.mdctScoreHard
            && SBRRule.isStationary(audio, sampleRate: sr)
        if !stationary && points < FLACDetectiveConstants.mdctScoreHard {
            // Vorbis block-switch (left/right каналы). Требует стерео.
            if let st = loadStereo(ctx.fileURL, sampleRate: sr),
               st.left.count == st.right.count {
                let (vRatio, _) = CodecGrids.vorbisSwitchRatio(
                    left: st.left, right: st.right, sampleRate: sr
                )
                ctx.vorbisSwitchRatio = vRatio
                let vPoints = pointsFor(
                    vRatio,
                    review: FLACDetectiveConstants.vorbisSwitchReview,
                    hard: FLACDetectiveConstants.vorbisSwitchHard
                )
                if vPoints > points {
                    points = vPoints
                    reason = "R13: Vorbis block grid detected on the left/right channels — hole density \(String(format: "%.1f", vRatio))x higher on one grid, moving in 128-sample steps, than on any other (+\(vPoints)pts)"
                }
            }
            // Эмит вынесен за пределы `if let st` — он должен сработать
            // даже когда стерео не загрузилось или точек не нашлось.
            onProgress?(0.90)

            // CELT (Opus) — только если ещё не hard.
            if points < FLACDetectiveConstants.mdctScoreHard {
                let (cRatio, _) = CodecGrids.celtRatio(mono: audio, sampleRate: sr)
                ctx.celtRatio = cRatio
                let cPoints = pointsFor(
                    cRatio,
                    review: FLACDetectiveConstants.celtReview,
                    hard: FLACDetectiveConstants.celtHard
                )
                if cPoints > points {
                    points = cPoints
                    reason = "R13: Opus (CELT) frame grid detected — hole density \(String(format: "%.1f", cRatio))x higher at one 20 ms alignment, read at 48 kHz with the decoder's de-emphasis undone (+\(cPoints)pts)"
                }
            }
        }

        // Гарантированный финальный эмит. Сработает и при stationary,
        // и когда hard-tier уже был достигнут на первом чтении.
        onProgress?(1.00)

        if points == 0 { return (0, []) }
        return (points, [reason])
    }
    /// Полная версия apply с явным стерео. Вызывается из lossy-ветки
    /// BitrateAnalyzer, где каналы уже загружены и повторный I/O не нужен.
    /// Идентична apply(_:), но использует переданные left/right вместо
    /// повторного чтения из файла.
    static func applyFull(
        _ ctx: ScoringContext, left: [Float], right: [Float]
    ) -> (score: Int, reasons: [String]) {
        guard let audio = ctx.loadedAudio, let sr = ctx.loadedAudioSampleRate else {
            return (0, [])
        }
        let (ratio, offset, hypothesis) = bestAlignmentStat(audio, sampleRate: sr)
        ctx.mdctPeakRatio = ratio

        var points = 0
        var reason = ""
        if ratio.isFinite {
            if ratio >= FLACDetectiveConstants.mdctRatioHard {
                points = FLACDetectiveConstants.mdctScoreHard
                reason = "R13: MDCT quantisation grid detected (\(hypothesis) window) — hole density \(String(format: "%.1f", ratio))x higher at frame alignment \(offset) than at any other (+\(FLACDetectiveConstants.mdctScoreHard)pts)"
            } else if ratio >= FLACDetectiveConstants.mdctRatioReview {
                points = FLACDetectiveConstants.mdctScoreReview
                reason = "R13: possible MDCT alignment structure (\(String(format: "%.1f", ratio))x at offset \(offset), \(hypothesis) window) (+\(FLACDetectiveConstants.mdctScoreReview)pts)"
            }
        }

        // Codec grids (vorbis-switch, CELT) — только если исходный тир < hard
        // и спектр не стационарен (a tone fakes alignment).
        let stationary = points < FLACDetectiveConstants.mdctScoreHard
            && SBRRule.isStationary(audio, sampleRate: sr)

        if !stationary && points < FLACDetectiveConstants.mdctScoreHard {
            // Vorbis block-switch — используем переданные каналы.
            if left.count == right.count && !left.isEmpty {
                let (vRatio, _) = CodecGrids.vorbisSwitchRatio(
                    left: left, right: right, sampleRate: sr
                )
                ctx.vorbisSwitchRatio = vRatio
                let vPoints = pointsFor(
                    vRatio,
                    review: FLACDetectiveConstants.vorbisSwitchReview,
                    hard: FLACDetectiveConstants.vorbisSwitchHard
                )
                if vPoints > points {
                    points = vPoints
                    reason = "R13: Vorbis block grid detected on the left/right channels — hole density \(String(format: "%.1f", vRatio))x higher on one grid, moving in 128-sample steps, than on any other (+\(vPoints)pts)"
                }
            }

            // CELT (Opus) — только если ещё не hard.
            if points < FLACDetectiveConstants.mdctScoreHard {
                let (cRatio, _) = CodecGrids.celtRatio(mono: audio, sampleRate: sr)
                ctx.celtRatio = cRatio
                let cPoints = pointsFor(
                    cRatio,
                    review: FLACDetectiveConstants.celtReview,
                    hard: FLACDetectiveConstants.celtHard
                )
                if cPoints > points {
                    points = cPoints
                    reason = "R13: Opus (CELT) frame grid detected — hole density \(String(format: "%.1f", cRatio))x higher at one 20 ms alignment, read at 48 kHz with the decoder's de-emphasis undone (+\(cPoints)pts)"
                }
            }
        }

        if points == 0 { return (0, []) }
        return (points, [reason])
    }

    private static func pointsFor(_ ratio: Double, review: Double, hard: Double) -> Int {
        guard ratio.isFinite else { return 0 }
        if ratio >= hard { return FLACDetectiveConstants.mdctScoreHard }
        if ratio >= review { return FLACDetectiveConstants.mdctScoreReview }
        return 0
    }

    private static func loadStereo(_ url: URL, sampleRate: Int)
        -> (left: [Float], right: [Float])? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let total = file.length
        guard total > 0, total <= Int64(UInt32.max - 1) else { return nil }
        let maxAllowedFrames: Int64 = 25_000_000
        let framesToRead = min(total, maxAllowedFrames)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(framesToRead)
        ) else { return nil }
        do { try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead)) } catch { return nil }
        guard let data = buffer.floatChannelData,
              Int(buffer.format.channelCount) >= 2 else { return nil }
        let n = Int(buffer.frameLength)
        return (
            Array(UnsafeBufferPointer(start: data[0], count: n)),
            Array(UnsafeBufferPointer(start: data[1], count: n))
        )
    }
}
