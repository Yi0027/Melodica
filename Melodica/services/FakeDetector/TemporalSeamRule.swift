import Foundation
import Accelerate

/// Rule 14: temporal seam — witness без очков.

nonisolated enum TemporalSeamRule {

    /// Возвращает (seam_score, seam_hz) или (.nan, .nan).
    static func temporalSeam(_ x: [Float], sampleRate: Int) -> (Double, Double) {
        let fftSize = FLACDetectiveConstants.temporalFftSize
        let hop = fftSize / 2
        guard x.count > fftSize else { return (.nan, .nan) }

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return (.nan, .nan) }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = fftSize / 2
        var frames: [[Float]] = []
        var start = 0
        // Python: range(0, len(x) - FFT_SIZE, hop) — последний фрейм НЕ включается.
        // Swift был <=, из-за чего захватывал лишний фрейм.
        while start + fftSize < x.count {
            var block = Array(x[start..<(start + fftSize)])
            // Python проверяет energetic ПОСЛЕ умножения на окно.
            vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(fftSize))

            var mean: Float = 0
            for v in block { mean += abs(v) }
            mean /= Float(fftSize)
            if mean < 1e-6 {
                start += hop
                continue
            }

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
            var mag = [Float](repeating: 0, count: half)
            for j in 0..<half {
                mag[j] = (real[j] * real[j] + imag[j] * imag[j]).squareRoot()
            }
            frames.append(mag)
            start += hop
        }

        guard frames.count >= FLACDetectiveConstants.temporalMinFrames else { return (.nan, .nan) }

        let binWidth = Double(sampleRate) / Double(fftSize)
        // Python: freqs <= min(Nyquist, BAND_HI_HZ). Recompute hiBin по частоте.
        let hiBin = min(half - 1, Int(FLACDetectiveConstants.temporalBandHiHz / binWidth))
        let loBin = Int(FLACDetectiveConstants.temporalBandLoHz / binWidth)
        let bandSize = hiBin - loBin + 1
        guard bandSize >= 4 * FLACDetectiveConstants.temporalHalfWidth + 2 else { return (.nan, .nan) }

        var variability = [Double](repeating: 0, count: bandSize)
        for i in 0..<bandSize {
            let bin = loBin + i
            var vals = [Double](repeating: 0, count: frames.count)
            for (fi, frame) in frames.enumerated() {
                vals[fi] = log1p(Double(frame[bin]))
            }
            let m = vals.reduce(0, +) / Double(vals.count)
            let v = vals.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(vals.count)
            variability[i] = v.squareRoot()
        }

        // Python: candidates = np.where(band_freqs >= SEARCH_FROM_HZ)[0] → ceil.
        // Старый Int() truncation давал off-by-one (1114 vs 1115 при 12000/10.77).
        let searchBin = Int(ceil(FLACDetectiveConstants.temporalSearchFromHz / binWidth)) - loBin
        let hw = FLACDetectiveConstants.temporalHalfWidth
        var bestDrop: Double = -Double.infinity
        var bestHz: Double = .nan

        for i in 0..<bandSize {
            guard i >= searchBin else { continue }
            guard i >= hw, i + hw <= variability.count else { continue }
            let before = variability[(i - hw)..<i].reduce(0, +) / Double(hw)
            let after = variability[i..<(i + hw)].reduce(0, +) / Double(hw)
            if before <= 0 { continue }
            let drop = (before - after) / before
            if drop > bestDrop {
                bestDrop = drop
                bestHz = Double(loBin + i) * binWidth
            }
        }

        guard bestDrop.isFinite else { return (.nan, .nan) }
        return (max(0, bestDrop), bestHz)
    }

    static func apply(
        _ ctx: ScoringContext,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (score: Int, reasons: [String], witness: Bool) {
        onProgress?(0.0)
        guard let audio = ctx.loadedAudio, let sr = ctx.loadedAudioSampleRate else {
            onProgress?(1.0)
            return (0, [], false)
        }
        guard ctx.cutoffHz >= FLACDetectiveConstants.temporalMinCutoffHz else {
            onProgress?(1.0)
            return (0, [], false)
        }
        onProgress?(0.15)
        let (score, hz) = temporalSeam(audio, sampleRate: sr)
        onProgress?(1.0)
        ctx.temporalSeam = score

        guard score.isFinite && score >= FLACDetectiveConstants.temporalSeamBar else {
            return (0, [], false)
        }
        return (
            0,
            ["R14: high-frequency variation collapses at \(Int(hz)) Hz (\(String(format: "%.2f", score))) — independent witness, no points"],
            true
        )
    }
}
