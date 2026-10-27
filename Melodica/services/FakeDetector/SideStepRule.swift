import Foundation
import Accelerate

/// Rule 18: side-channel step — witness, 0 очков.
///
/// Joint-stereo кодеры (Vorbis point stereo, CELT intensity stereo) перестают
/// кодировать разницу выше некоторой частоты: side падает на ~20 dB относительно
/// mid. Rule 15 читает side как *мёртвый* (абсолютный бар + cutoff ≥ 17 kHz),
/// а этот witness читает сам шаг, ниже cutoff файла.
///
/// Порт `joint_stereo.py`. Всегда 0 очков, всегда семейство `stereo`.
nonisolated enum SideStepRule {

    static let fftSize = 2048
    static let nFrames = 600
    static let bandHz = 1000.0
    static let lowHz = 1000.0
    static let topHz = 20000.0
    static let span = 3
    static let cutoffMarginHz = 500.0
    static let loudPercentile = 25.0
    static let minLoudFrames = 16
    static let monoGateDb = -40.0

    static let stepBarDb = 7.5

    struct Result {
        let stepDb: Double
        let splitHz: Double
        let sideToMidDb: Double
    }

    static func sideStep(
        left: [Float], right: [Float], sampleRate: Int, cutoffHz: Double
    ) -> Result {
        let nanResult = Result(stepDb: .nan, splitHz: .nan, sideToMidDb: .nan)
        let n = left.count
        guard n == right.count, n > fftSize else { return nanResult }

        let hop = fftSize / 2
        let total = (n - fftSize) / hop
        guard total >= 64 else { return nanResult }

        let nTake = min(nFrames, total)
        var starts = [Int]()
        starts.reserveCapacity(nTake)
        for i in 0..<nTake {
            let v: Double = (nTake == 1)
                ? 0
                : Double(n - fftSize - 1) * Double(i) / Double(nTake - 1)
            starts.append(Int(v))
        }

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let half = fftSize / 2
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nanResult
        }
        defer { vDSP_destroy_fftsetup(setup) }

        let binWidth = Double(sampleRate) / Double(fftSize)

        var eMid = [[Float]](repeating: [Float](repeating: 0, count: half), count: nTake)
        var eSide = [[Float]](repeating: [Float](repeating: 0, count: half), count: nTake)

        for (fi, start) in starts.enumerated() {
            var wMid = [Float](repeating: 0, count: fftSize)
            var wSide = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize {
                let l = left[start + i]
                let r = right[start + i]
                wMid[i] = ((l + r) / 2.0) * hann[i]
                wSide[i] = ((l - r) / 2.0) * hann[i]
            }

            // mid FFT
            var reM = [Float](repeating: 0, count: half)
            var imM = [Float](repeating: 0, count: half)
            reM.withUnsafeMutableBufferPointer { rp in
                imM.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    wMid.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            for k in 0..<half { eMid[fi][k] = reM[k] * reM[k] + imM[k] * imM[k] }

            // side FFT
            var reS = [Float](repeating: 0, count: half)
            var imS = [Float](repeating: 0, count: half)
            reS.withUnsafeMutableBufferPointer { rp in
                imS.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    wSide.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            for k in 0..<half { eSide[fi][k] = reS[k] * reS[k] + imS[k] * imS[k] }
        }

        var sumMid: Double = 0
        var sumSide: Double = 0
        for fi in 0..<nTake {
            for k in 0..<half {
                sumMid += Double(eMid[fi][k])
                sumSide += Double(eSide[fi][k])
            }
        }
        let sideToMid = 10 * log10(sumSide / max(sumMid, 1e-30) + 1e-30)
        guard sideToMid >= monoGateDb else {
            return Result(stepDb: .nan, splitHz: .nan, sideToMidDb: sideToMid)
        }

        // Верхняя граница бэндов: min(Nyquist-1000, 20000, cutoff-500).
        var top = min(Double(sampleRate) / 2.0 - 1000, topHz)
        if cutoffHz.isFinite {
            top = min(top, cutoffHz - cutoffMarginHz)
        }
        var edges: [Double] = []
        var f = lowHz
        while f <= top + 1 {
            edges.append(f)
            f += bandHz
        }
        guard edges.count >= 2 else {
            return Result(stepDb: .nan, splitHz: .nan, sideToMidDb: sideToMid)
        }

        var ratios = [Double](repeating: .nan, count: edges.count - 1)
        for bi in 0..<(edges.count - 1) {
            let lo = edges[bi]
            let hi = edges[bi + 1]
            let kLo = max(0, Int(lo / binWidth))
            let kHi = min(half, Int(hi / binWidth))
            guard kHi > kLo else { continue }

            var bandMid = [Float](repeating: 0, count: nTake)
            var bandSide = [Float](repeating: 0, count: nTake)
            for fi in 0..<nTake {
                var sm: Float = 0
                var ss: Float = 0
                for k in kLo..<kHi {
                    sm += eMid[fi][k]
                    ss += eSide[fi][k]
                }
                bandMid[fi] = sm
                bandSide[fi] = ss
            }

            // Порог = 25-й перцентиль: только громкие фреймы участвуют.
            var sortedMid = bandMid
            sortedMid.sort()
            let thrIdx = Int(Double(sortedMid.count) * loudPercentile / 100.0)
            let thr = sortedMid[min(thrIdx, sortedMid.count - 1)]

            var loudRatios: [Double] = []
            for fi in 0..<nTake where bandMid[fi] > thr {
                let r = 10 * log10(Double(bandSide[fi] + 1e-30) / Double(bandMid[fi] + 1e-30))
                loudRatios.append(r)
            }
            guard loudRatios.count >= minLoudFrames else { continue }
            loudRatios.sort()
            if loudRatios.count % 2 == 0 {
                ratios[bi] = (loudRatios[loudRatios.count / 2 - 1] + loudRatios[loudRatios.count / 2]) / 2.0
            } else {
                ratios[bi] = loudRatios[loudRatios.count / 2]
            }
        }

        // step = max_s [median(r[s-3..s-1]) - median(r[s..s+2])]
        var bestStep: Double = -.infinity
        var bestHz: Double = .nan
        if ratios.count >= 2 * span {
            for i in span..<(ratios.count - span + 1) {
                let below = Array(ratios[(i - span)..<i])
                let above = Array(ratios[i..<(i + span)])
                if below.contains(where: { $0.isNaN }) || above.contains(where: { $0.isNaN }) {
                    continue
                }
                let b = median(below)
                let a = median(above)
                let step = b - a
                if step > bestStep {
                    bestStep = step
                    bestHz = edges[i]
                }
            }
        }
        if !bestStep.isFinite {
            return Result(stepDb: .nan, splitHz: .nan, sideToMidDb: sideToMid)
        }
        return Result(stepDb: bestStep, splitHz: bestHz, sideToMidDb: sideToMid)
    }

    // MARK: - Rule entry

    static func apply(
        _ ctx: ScoringContext, left: [Float], right: [Float],
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (score: Int, reasons: [String], witness: Bool) {
        onProgress?(0.0)
        guard let sr = ctx.loadedAudioSampleRate else {
            onProgress?(1.0)
            return (0, [], false)
        }
        onProgress?(0.15)
        let r = sideStep(left: left, right: right, sampleRate: sr, cutoffHz: ctx.cutoffHz)
        onProgress?(1.0)
        ctx.sideStepDb = r.stepDb

        // Joint-stereo coupling happens above ~7 kHz for MP3, ~10 kHz for
        // Vorbis. A side-channel step below 10 kHz is a musical feature
        // (mono bass, stereo upper range), not coder behaviour.
        let minStepHz: Double = 10_000
        guard r.stepDb.isFinite && r.stepDb >= stepBarDb,
              r.splitHz.isFinite && r.splitHz >= minStepHz else {
            return (0, [], false)
        }
        return (0, [
            String(
                format: "R18: the stereo side channel steps down %.0f dB at %.0f Hz (joint-stereo coding) — independent witness, no points",
                r.stepDb, r.splitHz
            )
        ], true)
    }

    private static func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        if s.count % 2 == 0 {
            return (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
        }
        return s[s.count / 2]
    }
}
