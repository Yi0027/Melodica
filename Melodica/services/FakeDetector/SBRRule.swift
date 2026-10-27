import Foundation
import Accelerate

/// Rule 17: spectral band replication — high band is a phase-locked copy of a lower one.
///
/// HE-AAC (v1/v2), mp3PRO и родственники: декодер строит верх из нижних
/// QMF-субполос. Копия выдаёт себя — её фаза эволюционирует как у источника.
/// Естественная музыка так себя не ведёт.
///
/// Порт `sbr.py`. Зависит от `stationarity.py` (abstain на неподвижном спектре).
nonisolated enum SBRRule {

    // MARK: - Constants

    static let qmfBands = 64
    static let stftSize = 128
    static let stftHop = 64
    static let segmentFrames = 256
    static let nSegments = 32
    static let shiftLo = 6
    static let shiftHi = 41          // exclusive
    static let highBandLoHz = 5500.0
    static let highBandHiHz = 20000.0
    static let minEnergy = 1e-6
    static let liveFloorDb = -50.0

    // Thresholds
    static let coherenceReview = 0.40
    static let coherenceHard = 0.55
    static let scoreHard = 55
    static let scoreReview = 25

    // MARK: - Stationarity (stationarity.py)

    static let statFftSize = 2048
    static let statNSegments = 8
    static let statSegmentS = 2.0
    static let statBandLoHz = 1000.0
    static let statBandHiHz = 16000.0
    static let stationaryBelowDb = 2.0

    /// Python `is_stationary`. True — спектр не движется, Rule 17 абстенится.
    static func isStationary(_ mono: [Float], sampleRate: Int) -> Bool {
        let m = spectralMotionDb(mono, sampleRate: sampleRate)
        return m.isFinite && m < stationaryBelowDb
    }

    /// Python `spectral_motion_db`.
    static func spectralMotionDb(_ mono: [Float], sampleRate: Int) -> Double {
        let seg = Int(statSegmentS * Double(sampleRate))
        let n = mono.count
        guard n >= seg else { return .nan }

        let fftSize = statFftSize
        let hop = fftSize / 2
        let nFramesPerSeg = (seg - fftSize) / hop
        guard nFramesPerSeg > 0 else { return .nan }

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let half = fftSize / 2
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return .nan }
        defer { vDSP_destroy_fftsetup(setup) }

        let binWidth = Double(sampleRate) / Double(fftSize)
        let loBin = Int(statBandLoHz / binWidth)
        let hiBin = min(half - 1, Int(min(statBandHiHz, Double(sampleRate) / 2.0) / binWidth))
        let bandSize = hiBin - loBin + 1
        guard bandSize > 0 else { return .nan }

        var allFrames: [[Double]] = []

        let segStarts: [Int] = (0..<statNSegments).map { i in
            let v = Double(n - seg) * Double(i) / Double(statNSegments - 1)
            return Int(v)
        }

        for segStart in segStarts {
            var energy: Double = 0
            for i in 0..<seg {
                let v = Double(mono[segStart + i])
                energy += v * v
            }
            if energy <= 1e-8 * Double(seg) { continue }

            for frame in 0..<nFramesPerSeg {
                let start = segStart + frame * hop
                var windowed = [Float](repeating: 0, count: fftSize)
                for i in 0..<fftSize { windowed[i] = mono[start + i] * hann[i] }

                var re = [Float](repeating: 0, count: half)
                var im = [Float](repeating: 0, count: half)
                re.withUnsafeMutableBufferPointer { rp in
                    im.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        windowed.withUnsafeBufferPointer { wp in
                            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                                vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    }
                }
                var mags = [Double](repeating: 0, count: bandSize)
                for (bi, k) in (loBin...hiBin).enumerated() {
                    let mag = Double((re[k] * re[k] + im[k] * im[k]).squareRoot())
                    mags[bi] = 20 * log10(mag + 1e-9)
                }
                allFrames.append(mags)
            }
        }
        guard !allFrames.isEmpty else { return .nan }

        let nFrames = allFrames.count
        var stds = [Double](repeating: 0, count: bandSize)
        for bi in 0..<bandSize {
            var sum: Double = 0
            for f in 0..<nFrames { sum += allFrames[f][bi] }
            let mean = sum / Double(nFrames)
            var ss: Double = 0
            for f in 0..<nFrames {
                let d = allFrames[f][bi] - mean
                ss += d * d
            }
            stds[bi] = (ss / Double(nFrames)).squareRoot()
        }
        // Python: np.median — для чётного count среднее двух центральных.
        stds.sort()
        if stds.count % 2 == 0 {
            return (stds[stds.count / 2 - 1] + stds[stds.count / 2]) / 2.0
        }
        return stds[stds.count / 2]
    }

    // MARK: - Replication coherence

    struct CoherenceResult {
        let coherence: Double
        let shift: Int
    }

    /// Python `replication_coherence`. Возвращает (coherence, shift).
    static func replicationCoherence(mono: [Float], sampleRate: Int) -> CoherenceResult {
        let n = mono.count
        let total = (n - stftSize) / stftHop
        guard total >= segmentFrames * 4 else {
            return CoherenceResult(coherence: .nan, shift: -1)
        }

        let nSegs = min(nSegments, total / segmentFrames)
        var starts = [Int]()
        if nSegs == 1 {
            starts = [0]
        } else {
            for i in 0..<nSegs {
                let v = Double(total - segmentFrames) * Double(i) / Double(nSegs - 1)
                starts.append(Int(v))
            }
        }

        let totalFrames = starts.count * segmentFrames
        var frameStarts = [Int]()
        frameStarts.reserveCapacity(totalFrames)
        for s in starts {
            for j in 0..<segmentFrames {
                frameStarts.append((s + j) * stftHop)
            }
        }

        var hann = [Float](repeating: 0, count: stftSize)
        vDSP_hann_window(&hann, vDSP_Length(stftSize), Int32(vDSP_HANN_NORM))

        let half = stftSize / 2
        let log2n = vDSP_Length(log2(Float(stftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return CoherenceResult(coherence: .nan, shift: -1)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        // Спектр: [totalFrames][qmfBands=64]. vDSP_fft_zrip упаковывает
        // DC в re[0], Nyquist в im[0]; бины 1..63 — обычные комплексные.
        // Nyquist теряем — он не участвует (ks >= 6).
        var specRe = [Float](repeating: 0, count: totalFrames * qmfBands)
        var specIm = [Float](repeating: 0, count: totalFrames * qmfBands)

        var windowed = [Float](repeating: 0, count: stftSize)
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)

        for (fi, start) in frameStarts.enumerated() {
            for i in 0..<stftSize { windowed[i] = mono[start + i] * hann[i] }
            for i in 0..<half { re[i] = 0; im[i] = 0 }

            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            let base = fi * qmfBands
            specRe[base] = re[0]
            specIm[base] = 0
            for k in 1..<qmfBands {
                specRe[base + k] = re[k]
                specIm[base + k] = im[k]
            }
        }

        let width = Double(sampleRate) / Double(stftSize)
        let kLo = Int(highBandLoHz / width)
        let kHi = Int(min(highBandHiHz, Double(sampleRate) / 2.0 - 1000) / width)
        guard kHi > kLo else {
            return CoherenceResult(coherence: .nan, shift: -1)
        }

        // Проверка: хотя бы одна (segment, k) клетка в high band живая.
        let liveThr = pow(10.0, liveFloorDb / 10.0)
        var hasLive = false
        outer: for segIdx in 0..<starts.count {
            var strongest: Float = 0
            for k in 0..<qmfBands {
                var e: Float = 0
                for j in 0..<segmentFrames {
                    let idx = (segIdx * segmentFrames + j) * qmfBands + k
                    e += specRe[idx] * specRe[idx] + specIm[idx] * specIm[idx]
                }
                if e > strongest { strongest = e }
            }
            for k in kLo..<kHi {
                var e: Float = 0
                for j in 0..<segmentFrames {
                    let idx = (segIdx * segmentFrames + j) * qmfBands + k
                    e += specRe[idx] * specRe[idx] + specIm[idx] * specIm[idx]
                }
                if e > strongest * Float(liveThr) {
                    hasLive = true
                    break outer
                }
            }
        }
        guard hasLive else {
            return CoherenceResult(coherence: .nan, shift: -1)
        }

        var bestValue: Double = .nan
        var bestShift: Int = -1

        for shift in shiftLo..<shiftHi {
            let ksLo = max(kLo, shift + 2)
            guard ksLo < kHi else { continue }

            var cohVals = [Double]()
            cohVals.reserveCapacity(starts.count * (kHi - ksLo))

            for segIdx in 0..<starts.count {
                for k in ksLo..<kHi {
                    var eH: Float = 0
                    var eL: Float = 0
                    var sumRe: Float = 0
                    var sumIm: Float = 0
                    for j in 0..<segmentFrames {
                        let hiIdx = (segIdx * segmentFrames + j) * qmfBands + k
                        let loIdx = (segIdx * segmentFrames + j) * qmfBands + (k - shift)
                        let hRe = specRe[hiIdx]
                        let hIm = specIm[hiIdx]
                        var lRe = specRe[loIdx]
                        var lIm = specIm[loIdx]
                        // alternate: (-1)^(shift*t) для нечётного shift
                        if shift % 2 == 1 && j % 2 == 1 {
                            lRe = -lRe
                            lIm = -lIm
                        }
                        eH += hRe * hRe + hIm * hIm
                        eL += lRe * lRe + lIm * lIm
                        // high * conj(low) = (hRe*lRe + hIm*lIm) + i(hIm*lRe - hRe*lIm)
                        sumRe += hRe * lRe + hIm * lIm
                        sumIm += hIm * lRe - hRe * lIm
                    }
                    if eH > Float(minEnergy) {
                        let num = (sumRe * sumRe + sumIm * sumIm).squareRoot()
                        let denom = (eH * eL).squareRoot() + 1e-20
                        cohVals.append(Double(num / denom))
                    }
                }
            }

            guard !cohVals.isEmpty else { continue }
            cohVals.sort()
            let value: Double
            if cohVals.count % 2 == 0 {
                value = (cohVals[cohVals.count / 2 - 1] + cohVals[cohVals.count / 2]) / 2.0
            } else {
                value = cohVals[cohVals.count / 2]
            }
            if !bestValue.isFinite || value > bestValue {
                bestValue = value
                bestShift = shift
            }
        }

        return CoherenceResult(coherence: bestValue, shift: bestShift)
    }

    // MARK: - Rule entry

    /// Возвращает (score, reasons, witness). Скорит в двух тирах (25/55).
    static func apply(
        _ ctx: ScoringContext,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (score: Int, reasons: [String], witness: Bool) {
        onProgress?(0.0)
        guard let audio = ctx.loadedAudio, let sr = ctx.loadedAudioSampleRate else {
            onProgress?(1.0)
            return (0, [], false)
        }
        if isStationary(audio, sampleRate: sr) {
            onProgress?(1.0)
            return (0, [], false)
        }
        onProgress?(0.20)
        let r = replicationCoherence(mono: audio, sampleRate: sr)
        onProgress?(1.0)
        ctx.sbrCoherence = r.coherence

        guard r.coherence.isFinite else { return (0, [], false) }

        if r.coherence >= coherenceHard {
            return (scoreHard, [
                String(
                    format: "R17: the high band is a copy of a lower one (SBR, as in HE-AAC) — phase coherence %.2f across a %d-subband shift (+%dpts)",
                    r.coherence, r.shift, scoreHard
                )
            ], true)
        }
        if r.coherence >= coherenceReview {
            return (scoreReview, [
                String(
                    format: "R17: possible band replication (coherence %.2f across a %d-subband shift) (+%dpts)",
                    r.coherence, r.shift, scoreReview
                )
            ], true)
        }
        return (0, [], false)
    }
}
