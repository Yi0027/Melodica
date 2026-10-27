import Foundation
import AVFoundation
import Accelerate

/// Rule 11: cassette audio source detection.
///
/// Возвращает EVIDENCE OF BEING A CASSETTE, а не fake. Пайплайн решает:
/// если score >= cassetteThreshold (25), дать −40 и отключить Rule 1.
///
/// Порт `rules/cassette.py` v1.19.1:
/// - TEST 11A (constant tape hiss) — bandpass + autocorr
/// - TEST 11B (progressive roll-off) — наклон 12-18 kHz
/// - TEST 11C, 11D — удалены в Python (v1.8, v1.13.14), не портируем
nonisolated enum CassetteRule {

    // MARK: - Constants

    static let cassetteThreshold: Int = 25
    static let minCutoffHz: Double = 19000.0
    static let segmentSeconds: Double = 30.0

    // MARK: - Public entry

    /// Возвращает (cassette_score 0..70, reasons). НЕ добавляет очки в ctx сам —
    /// это делает runPipeline, применяя −40 bonus отдельно, как в Python.
    nonisolated static func apply(_ ctx: ScoringContext) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []

        // Python: `if cutoff_freq >= 19000: return 0, reasons`
        guard ctx.cutoffHz < minCutoffHz else { return (0, []) }

        // 30-секундный сегмент из середины файла, моно.
        guard let seg = loadMiddleSegment(
            ctx.fileURL, sampleRate: ctx.sampleRate, duration: ctx.duration
        ), !seg.isEmpty else {
            return (0, [])
        }

        // ===== TEST 11A: constant tape hiss =====
        // Python: если floor_is_digital_silence → пропустить 11A (нет шума
        // над цифровой тишиной). Иначе — bandpass + autocorr.
        if SpectralRules.floorIsDigitalSilence(ctx.floorAboveDb, cutoffHz: ctx.cutoffHz) {
            reasons.append(String(
                format: "R11A: no tape hiss — the band above %.0f Hz is digital silence (%.0f dB), which a cassette cannot leave",
                ctx.cutoffHz, ctx.floorAboveDb
            ))
        } else {
            // Python: если cutoff < 16000 → (cutoff+1000, 18000)
            //         иначе → (cutoff+500, min(20000, sr/2-100))
            let noiseLow: Double
            let noiseHigh: Double
            if ctx.cutoffHz < 16000 {
                noiseLow = ctx.cutoffHz + 1000
                noiseHigh = 18000
            } else {
                noiseLow = ctx.cutoffHz + 500
                noiseHigh = min(20000, Double(ctx.sampleRate) / 2.0 - 100)
            }
            if noiseHigh > noiseLow,
               let noiseBand = bandpass(seg, sampleRate: ctx.sampleRate,
                                         low: noiseLow, high: noiseHigh),
               noiseBand.count > 200 {
                let noiseEnergyDb = 20 * log10(std(noiseBand) + 1e-10)
                if noiseEnergyDb > -55 {
                    // Python: corrcoef(noise_signal[:-100], noise_signal[100:])[0,1]
                    // с проверкой std < 1e-6 → 0.0
                    var autocorr = 0.0
                    let stdCheck = std(noiseBand)
                    if stdCheck >= 1e-6 {
                        autocorr = self.autocorrelation(noiseBand, lag: 100)
                        if autocorr.isNaN { autocorr = 0 }
                    }
                    if abs(autocorr) < 0.2 {
                        score += 30
                        reasons.append(String(
                            format: "R11A: Tape hiss detected (%.1f dB, random) (likely cassette)",
                            noiseEnergyDb
                        ))
                    }
                }
            }
        }

        // ===== TEST 11B: progressive roll-off =====
        // Python: freqs = linspace(12000, 18000, 20);
        // for freq: bandpass(freq-250, freq+250), std → response[i] = 20*log10(std + 1e-10)
        let response = bandResponse(
            seg, sampleRate: ctx.sampleRate, from: 12000, to: 18000, steps: 20
        )
        if response.count > 1 {
            let slope = (response[response.count - 1] - response[0]) / 6.0  // dB/kHz
            if slope > -6 && slope < -3 {
                score += 20
                reasons.append(String(
                    format: "R11B: Natural cassette roll-off (%.1f dB/kHz) (likely cassette)",
                    slope
                ))
            } else if slope < -10 {
                score -= 20
                reasons.append(String(
                    format: "R11B: Sharp digital cut (%.1f dB/kHz) (likely digital)",
                    slope
                ))
            }
        }

        // TEST 11C — удалён в Python v1.8 (был константный +15).
        // TEST 11D — удалён в Python v1.13.14 (250 Hz grid не читает wow/flutter).

        return (max(0, score), reasons)
    }

    // MARK: - Segment loading

    nonisolated private static func loadMiddleSegment(
        _ url: URL, sampleRate: Int, duration: Double
    ) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let startSec = max(0, (duration - segmentSeconds) / 2)
        let actualDuration = min(segmentSeconds, duration)
        guard actualDuration > 0 else { return nil }

        let startFrame = AVAudioFramePosition(startSec * Double(sampleRate))
        let frames = AVAudioFrameCount(actualDuration * Double(sampleRate))
        guard frames > 0 else { return nil }

        file.framePosition = startFrame
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: frames
        ) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let ch = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return nil }
        let chCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        let scale = 1.0 / Float(chCount)
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n { mono[i] += src[i] * scale }
        }
        return mono
    }

    // MARK: - DSP helpers

    /// FFT-полосовой фильтр. Заменяет scipy.signal.butter(5, [lo, hi], 'bandpass')
    /// + sosfilt. Возвращает сигнал той же длины, что вход.
    nonisolated private static func bandpass(
        _ audio: [Float], sampleRate: Int, low: Double, high: Double
    ) -> [Float]? {
        let n = audio.count
        guard n >= 4096 else { return nil }
        let fftSize = 1 << Int(ceil(log2(Double(n))))
        let half = fftSize / 2

        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        for i in 0..<n { real[i] = audio[i] }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        let binWidth = Double(sampleRate) / Double(fftSize)
        let loBin = max(0, Int(low / binWidth))
        let hiBin = min(half - 1, Int(high / binWidth))
        for k in 0..<fftSize {
            let freqIdx = k <= half ? k : fftSize - k
            if freqIdx < loBin || freqIdx > hiBin {
                real[k] = 0
                imag[k] = 0
            }
        }

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
            }
        }

        let scale = 1.0 / Float(fftSize)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n { out[i] = real[i] * scale }
        return out
    }

    nonisolated private static func std(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        var m: Double = 0
        for v in x { m += Double(v) }
        m /= Double(x.count)
        var ss: Double = 0
        for v in x {
            let d = Double(v) - m
            ss += d * d
        }
        return (ss / Double(x.count)).squareRoot()
    }

    /// Python: np.corrcoef(a[:-lag], a[lag:])[0, 1] — Pearson r.
    nonisolated private static func autocorrelation(_ x: [Float], lag: Int) -> Double {
        guard x.count > lag * 2 else { return 0 }
        let n = x.count - lag
        var meanA: Double = 0
        var meanB: Double = 0
        for i in 0..<n {
            meanA += Double(x[i])
            meanB += Double(x[i + lag])
        }
        meanA /= Double(n)
        meanB /= Double(n)
        var cov: Double = 0
        var varA: Double = 0
        var varB: Double = 0
        for i in 0..<n {
            let a = Double(x[i]) - meanA
            let b = Double(x[i + lag]) - meanB
            cov += a * b
            varA += a * a
            varB += b * b
        }
        let denom = (varA * varB).squareRoot()
        return denom > 0 ? cov / denom : 0
    }

    /// Python: for freq in linspace(12000, 18000, 20):
    ///            bandpass(freq-250, freq+250), std → response
    /// Если freq + 250 >= Nyquist → response.append(-100).
    nonisolated private static func bandResponse(
        _ audio: [Float], sampleRate: Int, from: Double, to: Double, steps: Int
    ) -> [Double] {
        var response: [Double] = []
        response.reserveCapacity(steps)
        let nyquist = Double(sampleRate) / 2.0
        for i in 0..<steps {
            let freq = from + (to - from) * Double(i) / Double(steps - 1)
            if freq + 250 < nyquist {
                if let band = bandpass(audio, sampleRate: sampleRate,
                                       low: freq - 250, high: freq + 250) {
                    response.append(20 * log10(std(band) + 1e-10))
                } else {
                    response.append(-100)
                }
            } else {
                response.append(-100)
            }
        }
        return response
    }
}
