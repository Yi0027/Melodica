import Foundation
import AVFoundation
import Accelerate

nonisolated enum SilenceRule {

    // MARK: - Public entry

    nonisolated static func apply(_ ctx: ScoringContext) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []

        // Python: cutoff-гейт 19000..21500 ДО любой работы. Swift это делает
        // в runPipeline, но оставим и здесь — на всякий случай.
        guard ctx.cutoffHz >= 19000, ctx.cutoffHz <= 21500 else { return (0, []) }

        guard let audio = ctx.loadedAudio ?? loadMono(ctx.fileURL),
              let sr = ctx.loadedAudioSampleRate ?? Optional(ctx.sampleRate) else {
            return (0, [])
        }

        // ============ PHASE 1 ============
        let silences = detectSilences(audio, sampleRate: sr)
        let totalSilenceSamples = silences.reduce(0) { $0 + ($1.1 - $1.0) }
        let totalSilenceSec = Double(totalSilenceSamples) / Double(sr)
        guard totalSilenceSec >= 2.0 else {
            return (0, ["R7: insufficient silence"])
        }

        guard let musicRange = musicSegment(audio, sampleRate: sr) else { return (0, []) }
        var silenceChunks: [Float] = []
        for (s, e) in silences {
            silenceChunks.append(contentsOf: audio[s..<e])
        }

        let eMusic = spectralEnergy(musicRange, sampleRate: sr, lo: 16000, hi: 22000)
        let eSilence = spectralEnergy(silenceChunks, sampleRate: sr, lo: 16000, hi: 22000)
        let ratio = eSilence / (eMusic + 1e-10)
        ctx.silenceRatio = ratio

        if ratio > 0.3 {
            return (50, ["R7-P1: Artificial dither detected in silences (ratio \(String(format: "%.2f", ratio)) > 0.3) (+50pts)"])
        }
        if ratio < 0.15 {
            return (-50, ["R7-P1: Clean natural silence (ratio \(String(format: "%.2f", ratio)) < 0.15) (-50pts)"])
        }
        // else — uncertain zone, идём в Phase 2.

        // ============ PHASE 2: vinyl noise ============
        let (isVinyl, vinylDetails) = detectVinylNoise(
            audio: audio, sampleRate: sr, cutoffHz: ctx.cutoffHz
        )
        if isVinyl {
            score -= 40
            reasons.append(String(
                format: "R7-P2: Vinyl noise detected (energy=%.1fdB, autocorr=%.2f) (-40pts)",
                vinylDetails.energyDb, vinylDetails.autocorr
            ))
            // ============ PHASE 3: clicks & pops ============
            let (_, clicksPerMin) = detectClicksAndPops(audio, sampleRate: sr)
            if clicksPerMin >= 5 && clicksPerMin <= 50 {
                score -= 10
                reasons.append(String(
                    format: "R7-P3: Vinyl clicks detected (%.1f clicks/min) (-10pts)",
                    clicksPerMin
                ))
            }
        } else if vinylDetails.energyDb < -70 {
            score += 20
            reasons.append(String(
                format: "R7-P2: No noise above cutoff (energy=%.1fdB) → Digital upsampling suspect (+20pts)",
                vinylDetails.energyDb
            ))
        } else {
            reasons.append(String(
                format: "R7-P2: Noise with pattern detected (autocorr=%.2f) → Uncertain (0pts)",
                vinylDetails.autocorr
            ))
        }
        return (score, reasons)
    }

    // MARK: - Phase 2: vinyl noise

    struct VinylDetails {
        let energyDb: Double
        let autocorr: Double
        let temporalVariance: Double
        let isVinyl: Bool
    }

    /// Python: scipy.signal.butter(4, [lo, hi], 'bandpass') + sosfilt.
    /// Swift-эквивалент — FFT-фильтр (проще, чем реализовывать SOS).
    /// Работает на коротком срезе (≈ несколько секунд silenceChunks).
    nonisolated static func detectVinylNoise(
        audio: [Float], sampleRate: Int, cutoffHz: Double
    ) -> (Bool, VinylDetails) {
        let fail = VinylDetails(energyDb: -100, autocorr: 0, temporalVariance: 0, isVinyl: false)
        let nyquist = Double(sampleRate) / 2.0
        if cutoffHz >= nyquist - 1000 { return (false, fail) }

        let upper = nyquist - 100
        guard let noiseBand = filterBand(
            audio, sampleRate: sampleRate, low: cutoffHz, high: upper
        ), !noiseBand.isEmpty else { return (false, fail) }

        let energyDb = calculateEnergyDb(noiseBand)
        if energyDb < -70 {
            return (false, VinylDetails(energyDb: energyDb, autocorr: 0, temporalVariance: 0, isVinyl: false))
        }
        let autocorr = calculateAutocorrelation(noiseBand, sampleRate: sampleRate, lag: 50)
        let temporalVariance = calculateTemporalVariance(noiseBand, sampleRate: sampleRate)

        let isVinyl = energyDb > -70 && autocorr < 0.3 && temporalVariance < 5.0
        return (isVinyl, VinylDetails(
            energyDb: energyDb, autocorr: autocorr,
            temporalVariance: temporalVariance, isVinyl: isVinyl
        ))
    }

    // MARK: - Phase 2 helpers

    /// FFT-полосовой фильтр [low, high]. Заменяет scipy butter+sosfilt.
    /// FFT-полосовой фильтр [low, high]. Заменяет scipy butter+sosfilt.
    /// Комплексный FFT на вещественном сигнале с эрмитовой симметрией:
    /// фильтрация по положительным и отрицательным бинам согласованно.
    nonisolated static func filterBand(
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

        // Forward FFT. Указатели живут внутри замыкания — DSPSplitComplex их
        // не сохраняет за пределы вызова, но компилятор этого не знает и
        // требует явного lifetime через withUnsafeMutableBufferPointer.
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Bandpass: обнуляем бины вне [loBin, hiBin] в ОБЕИХ половинах
        // (эрмитова симметрия для вещественного результата).
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

        // Inverse FFT.
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

    nonisolated static func calculateEnergyDb(_ audio: [Float]) -> Double {
        guard !audio.isEmpty else { return -100 }
        var sum: Double = 0
        for v in audio { sum += Double(v) * Double(v) }
        let rms = (sum / Double(audio.count)).squareRoot()
        return 20 * log10(rms + 1e-10)
    }

    nonisolated static func calculateAutocorrelation(
        _ audio: [Float], sampleRate: Int, lag: Int = 50
    ) -> Double {
        let segLen = min(audio.count, sampleRate)  // 1 секунда
        guard segLen > lag * 2 else { return 0 }
        var segment = Array(audio[0..<segLen])
        var mean: Double = 0
        for v in segment { mean += Double(v) }
        mean /= Double(segment.count)
        var ss: Double = 0
        for v in segment { ss += (Double(v) - mean) * (Double(v) - mean) }
        let std = (ss / Double(segment.count)).squareRoot() + 1e-10
        for i in 0..<segment.count { segment[i] = Float((Double(segment[i]) - mean) / std) }

        var num: Double = 0
        for i in 0..<(segLen - lag) { num += Double(segment[i]) * Double(segment[i + lag]) }
        let autocorr = num / Double(segLen - lag)
        return abs(autocorr)
    }

    nonisolated static func calculateTemporalVariance(_ audio: [Float], sampleRate: Int) -> Double {
        let segLen = sampleRate  // 1 секунда
        let nSegs = min(5, audio.count / segLen)
        guard nSegs >= 2 else { return 0 }
        var energies: [Double] = []
        for i in 0..<nSegs {
            let s = i * segLen
            let e = s + segLen
            let seg = Array(audio[s..<e])
            energies.append(calculateEnergyDb(seg))
        }
        let m = energies.reduce(0, +) / Double(nSegs)
        let v = energies.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(nSegs)
        return v.squareRoot()
    }

    // MARK: - Phase 3: clicks and pops

    /// Python: 4th-order highpass 1 kHz → hilbert envelope → medfilt(0.5 ms)
    /// → find_peaks(3 * median, distance=10 ms). Swift: highpass через FFT,
    /// envelope = |analytic signal| через FFT.
    nonisolated static func detectClicksAndPops(
        _ audio: [Float], sampleRate: Int
    ) -> (numClicks: Int, clicksPerMin: Double) {
        let duration = Double(audio.count) / Double(sampleRate)
        guard duration >= 10 else { return (0, 0) }

        guard let hp = highpass(audio, sampleRate: sampleRate, cutoff: 1000) else {
            return (0, 0)
        }
        guard let envelope = analyticEnvelope(hp, sampleRate: sampleRate) else {
            return (0, 0)
        }

        // Медианный фильтр ~0.5 ms
        var winSize = Int(0.0005 * Double(sampleRate))
        if winSize % 2 == 0 { winSize += 1 }
        let smoothed = winSize >= 3 ? medianFilter(envelope, size: winSize) : envelope

        // Порог 3 × медианы
        var sorted = smoothed
        sorted.sort()
        let med = sorted[sorted.count / 2]
        let threshold = med * 3

        // find_peaks: локальные максимумы выше порога с расстоянием 10 ms
        let minDistance = Int(0.01 * Double(sampleRate))
        var peaks = 0
        var lastPeak = -minDistance
        var i = 1
        while i < smoothed.count - 1 {
            if smoothed[i] > threshold,
               smoothed[i] > smoothed[i - 1],
               smoothed[i] >= smoothed[i + 1],
               i - lastPeak >= minDistance {
                peaks += 1
                lastPeak = i
            }
            i += 1
        }
        let perMin = Double(peaks) / duration * 60.0
        return (peaks, perMin)
    }

    /// FFT-based highpass; обнуляет бины ниже cutoff.
    nonisolated static func highpass(_ audio: [Float], sampleRate: Int, cutoff: Double) -> [Float]? {
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
        let cutBin = Int(cutoff / binWidth)
        for k in 0..<fftSize {
            let freqIdx = k <= half ? k : fftSize - k
            if freqIdx < cutBin {
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

    /// |analytic signal| через комплексный FFT: положительные частоты ×2,
    /// отрицательные → 0, обратное преобразование даёт re + i·Hilbert(re).
    nonisolated static func analyticEnvelope(_ audio: [Float], sampleRate: Int) -> [Float]? {
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

        // Forward complex FFT: real[i] + i·imag[i].
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Hilbert: DC (k=0) и Nyquist (k=half) не трогаем;
        // k=1..half-1 (положительные) ×2; k=half+1..fftSize-1 (отрицательные) → 0.
        for k in 1..<half {
            real[k] *= 2
            imag[k] *= 2
        }
        for k in (half + 1)..<fftSize {
            real[k] = 0
            imag[k] = 0
        }

        // Inverse complex FFT: получим аналитический сигнал.
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
            }
        }

        let scale = 1.0 / Float(fftSize)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let re = real[i] * scale
            let im = imag[i] * scale
            out[i] = (re * re + im * im).squareRoot()
        }
        return out
    }

    nonisolated static func medianFilter(_ x: [Float], size: Int) -> [Float] {
        guard size > 1, !x.isEmpty else { return x }
        let half = size / 2
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            var vals = Array(x[lo...hi])
            vals.sort()
            out[i] = vals[vals.count / 2]
        }
        return out
    }

    // MARK: - Phase 1 helpers (unchanged)

    nonisolated static func detectSilences(_ audio: [Float], sampleRate: Int,
                                            thresholdDb: Double = -40.0,
                                            minDuration: Double = 0.5) -> [(Int, Int)] {
        let thrLinear = Float(pow(10.0, thresholdDb / 20.0))
        let minSamples = Int(minDuration * Double(sampleRate))
        var segments: [(Int, Int)] = []
        var start: Int? = nil
        for i in 0..<audio.count {
            if abs(audio[i]) < thrLinear {
                if start == nil { start = i }
            } else {
                if let s = start, i - s >= minSamples { segments.append((s, i)) }
                start = nil
            }
        }
        if let s = start, audio.count - s >= minSamples { segments.append((s, audio.count)) }
        return segments
    }

    nonisolated static func musicSegment(_ audio: [Float], sampleRate: Int) -> [Float]? {
        let start = min(audio.count, 10 * sampleRate)
        let end = min(audio.count, 40 * sampleRate)
        guard start < end else { return nil }
        return Array(audio[start..<end])
    }

    nonisolated static func spectralEnergy(_ audio: [Float], sampleRate: Int, lo: Double, hi: Double) -> Double {
        guard audio.count >= 4096 else { return 0 }
        let fftSize = 4096
        let half = fftSize / 2
        var block = Array(audio.prefix(fftSize))
        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(fftSize))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
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
        let binWidth = Double(sampleRate) / Double(fftSize)
        let loBin = Int(lo / binWidth)
        let hiBin = min(half - 1, Int(hi / binWidth))
        guard loBin < hiBin else { return 0 }
        var energy: Double = 0
        for j in loBin...hiBin {
            energy += Double(real[j] * real[j] + imag[j] * imag[j])
        }
        return energy / Double(audio.count)
    }

    nonisolated static func rms(_ audio: [Float]) -> Double {
        guard !audio.isEmpty else { return 0 }
        var sum: Double = 0
        for v in audio { sum += Double(v) * Double(v) }
        return (sum / Double(audio.count)).squareRoot()
    }

    nonisolated static func loadMono(_ url: URL) -> [Float]? {
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
        return mono
    }
}
