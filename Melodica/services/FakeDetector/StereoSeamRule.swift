import Foundation
import AVFoundation
import Accelerate

nonisolated enum StereoSeamRule {

    nonisolated static func restore(_ signal: [Float]) -> [Float] {
        var peak: Float = 0
        for v in signal { if abs(v) > peak { peak = abs(v) } }
        guard peak > 0, peak < 1.0 else { return signal }
        return signal.map { $0 / peak }
    }

    nonisolated static func interiorRuns(_ mask: [Bool]) -> [Int] {
        guard mask.contains(true) else { return [] }
        var padded = mask
        padded.insert(false, at: 0)
        padded.append(false)
        var runs: [Int] = []
        var start: Int? = nil
        for i in 1..<padded.count {
            if !padded[i-1] && padded[i] { start = i - 1 }
            if padded[i-1] && !padded[i], let s = start {
                let e = i - 1
                if e < mask.count && s > 0 {
                    runs.append(e - s)
                }
                start = nil
            }
        }
        return runs
    }

    nonisolated static func spectra(_ signal: [Float], sampleRate: Int) -> [[Float]] {
        let fftSize = FLACDetectiveConstants.stereoFftSize
        let hop = fftSize / 2
        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = fftSize / 2
        let binWidth = Double(sampleRate) / Double(fftSize)
        let loBin = Int(FLACDetectiveConstants.stereoBandLoHz / binWidth)
        guard loBin < half else { return [] }
        let bandSize = half - loBin

        let usable = signal.count - fftSize
        guard usable > 0 else { return [] }
        let maxFrames = FLACDetectiveConstants.stereoMaxFrames
        let stride = max(hop, (usable / maxFrames) / hop * hop)

        var frames: [[Float]] = []
        var start = 0
        while start + fftSize <= signal.count && frames.count < maxFrames {
            var block = Array(signal[start..<(start + fftSize)])
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
            var mag = [Float](repeating: 0, count: bandSize)
            for j in 0..<bandSize {
                let k = loBin + j
                mag[j] = (real[k] * real[k] + imag[k] * imag[k]).squareRoot()
            }
            frames.append(mag)
            start += stride
        }
        return frames
    }

    nonisolated static func sideDeadRun(left: [Float], right: [Float], sampleRate: Int) -> (Double, Double) {
        guard left.count == right.count, !left.isEmpty else { return (.nan, 0) }
        var mid = [Float](repeating: 0, count: left.count)
        var side = [Float](repeating: 0, count: left.count)
        for i in 0..<left.count {
            mid[i] = (left[i] + right[i]) / 2.0
            side[i] = left[i] - right[i]
        }

        var midEnergy: Double = 0
        var sideEnergy: Double = 0
        for i in 0..<mid.count {
            midEnergy += Double(mid[i]) * Double(mid[i])
            sideEnergy += Double(side[i]) * Double(side[i])
        }
        midEnergy /= Double(mid.count)
        sideEnergy /= Double(side.count)
        let ratio = midEnergy > 0 ? sideEnergy / midEnergy : 0
        if ratio < FLACDetectiveConstants.stereoMonoGate {
            return (.nan, ratio)
        }

        let sideSpec = spectra(restore(side), sampleRate: sampleRate)
        let midSpec = spectra(restore(mid), sampleRate: sampleRate)
        guard sideSpec.count == midSpec.count,
              sideSpec.count >= FLACDetectiveConstants.stereoMinFrames,
              !sideSpec.isEmpty else {
            return (.nan, ratio)
        }

        let dead = FLACDetectiveConstants.stereoUnionDead
        var perFrame: [Double] = []
        for f in 0..<sideSpec.count {
            var mask = [Bool](repeating: false, count: sideSpec[f].count)
            for j in 0..<mask.count {
                mask[j] = midSpec[f][j] < Float(dead) || sideSpec[f][j] < Float(dead)
            }
            let runs = interiorRuns(mask)
            if runs.isEmpty {
                perFrame.append(0)
            } else {
                perFrame.append(Double(runs.reduce(0, +)) / Double(runs.count))
            }
        }
        return (SpectralAnalysis.median(perFrame), ratio)
    }

    nonisolated static func apply(
        _ ctx: ScoringContext,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (score: Int, reasons: [String], witness: Bool) {
        onProgress?(0.0)
        guard let sr = ctx.loadedAudioSampleRate else {
            onProgress?(1.0)
            return (0, [], false)
        }
        guard ctx.cutoffHz >= FLACDetectiveConstants.stereoMinCutoffHz else {
            onProgress?(1.0)
            return (0, [], false)
        }
        onProgress?(0.10)
        guard let st = try? loadStereoSamples(ctx.fileURL, sampleRate: sr),
              st.left.count == st.right.count, !st.left.isEmpty else {
            onProgress?(1.0)
            return (0, [], false)
        }
        onProgress?(0.20)
        let (run, _) = sideDeadRun(left: st.left, right: st.right, sampleRate: sr)
        onProgress?(1.0)
        ctx.stereoDeadRun = run

        guard run.isFinite && run >= FLACDetectiveConstants.stereoRunBar else {
            return (0, [], false)
        }
        return (
            0,
            ["R15: the stereo side channel dies in runs of \(Int(run)) bins above 10 kHz — independent witness, no points"],
            true
        )
    }

    nonisolated private static func loadStereoSamples(_ url: URL, sampleRate: Int) throws -> (left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let total = file.length
        guard total > 0, total <= Int64(UInt32.max - 1) else { return ([], []) }
        // Cap the maximum frames read into memory to ~25 million frames (~9.5 minutes of 44.1kHz audio, ~200MB)
        // to prevent multi-gigabyte OOM terminations on long mixes or extreme sample rates.
        let maxAllowedFrames: Int64 = 25_000_000
        let framesToRead = min(total, maxAllowedFrames)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(framesToRead)
        ) else { return ([], []) }
        file.framePosition = 0
        try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
        guard let data = buffer.floatChannelData, Int(buffer.format.channelCount) >= 2 else {
            return ([], [])
        }
        let n = Int(buffer.frameLength)
        let left: [Float] = Array(UnsafeBufferPointer(start: data[0], count: n))
        let right: [Float] = Array(UnsafeBufferPointer(start: data[1], count: n))
        return (left, right)
    }
}
