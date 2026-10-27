import Foundation
import AVFoundation
import Accelerate

nonisolated enum HiresAnalyzer {

    static let standardSourceRates: [Int] = [44100, 48000, 88200, 96000]
    static let nyquistTolerance = 0.06
    static let silentFloorDb = -70.0
    static let welchNfft = 16384

    enum Verdict: String {
        case genuineHires = "GENUINE_HIRES"
        case upsampled = "UPSAMPLED"
        case paddedDepth = "PADDED_DEPTH"
        case upsampledAndPadded = "UPSAMPLED_AND_PADDED"
        case notHires = "NOT_HIRES"
        case unknown = "UNKNOWN"
    }

    struct UpsamplingResult {
        let isUpsampled: Bool
        let suspectedOriginalRate: Int
        let contentEdgeHz: Double
        let floorAboveDb: Double
    }

    /// Порт `detect_upsampling`. Не применяется при sampleRate <= 48000.
    static func detectUpsampling(
        _ audio: [Float], sampleRate: Int
    ) -> UpsamplingResult {
        let fallback = UpsamplingResult(
            isUpsampled: false, suspectedOriginalRate: sampleRate,
            contentEdgeHz: .nan, floorAboveDb: .nan
        )
        guard sampleRate > 48000 else { return fallback }

        guard let (freqs, magsDb) = welchMagnitudeDb(
            audio, sampleRate: sampleRate, nfft: welchNfft
        ) else { return fallback }

        let nyq = Double(sampleRate) / 2.0
        let inLo = 0.05 * nyq
        let inHi = 0.45 * nyq
        guard let ref = medianBetween(freqs, magsDb, lo: inLo, hi: inHi) else {
            return fallback
        }

        guard freqs.count >= 2 else { return fallback }
        let binHz = freqs[1] - freqs[0]
        let smoothBins = max(3, Int((500.0 / max(binHz, 1e-6)).rounded()))
        let smoothed = movingAverage(magsDb, window: smoothBins)
        let threshold = ref - 40.0
        var contentEdge: Double = .nan
        for i in stride(from: smoothed.count - 1, through: 0, by: -1) {
            if smoothed[i] >= threshold {
                contentEdge = freqs[i]
                break
            }
        }
        guard contentEdge.isFinite else { return fallback }

        // Genuine hi-res: content идёт к самому Nyquist.
        if contentEdge >= 0.92 * nyq { return fallback }

        // Snap edge к ближайшему стандартному Nyquist.
        var bestRate: Int? = nil
        for r0 in standardSourceRates {
            if r0 >= sampleRate { continue }
            let n0 = Double(r0) / 2.0
            if abs(contentEdge - n0) <= nyquistTolerance * n0 {
                if let cur = bestRate {
                    if Double(cur) / 2.0 < n0 { bestRate = r0 }
                } else {
                    bestRate = r0
                }
            }
        }
        guard let snapped = bestRate else { return fallback }

        // Floor above edge — должен быть digital silence.
        let aboveLo = contentEdge * 1.03
        let aboveHi = 0.98 * nyq
        guard let floor = medianBetween(freqs, magsDb, lo: aboveLo, hi: aboveHi) else {
            return fallback
        }
        let relFloor = floor - ref
        if relFloor >= silentFloorDb { return fallback }

        return UpsamplingResult(
            isUpsampled: true,
            suspectedOriginalRate: snapped,
            contentEdgeHz: contentEdge,
            floorAboveDb: relFloor
        )
    }

    /// Порт `classify_hires`.
    static func classifyHires(
        sampleRate: Int?,
        bitDepth: Int?,
        isUpsampled: Bool,
        suspectedOriginalRate: Int,
        isFakeHighRes: Bool,
        estimatedDepth: Int,
        floorAboveDb: Double
    ) -> (verdict: Verdict, reasons: [String]) {
        guard let sr = sampleRate, let bd = bitDepth else {
            let unknown = sampleRate == nil ? "sample rate" : "bit depth"
            return (.unknown, [
                "Hi-res axis not evaluated: \(unknown) unknown (header unreadable)"
            ])
        }
        let isHighRate = sr > 48000
        let isHighDepth = bd > 16
        if !isHighRate && !isHighDepth { return (.notHires, []) }

        var reasons: [String] = []
        let upsampled = isUpsampled && isHighRate
        let padded = isFakeHighRes && isHighDepth

        if upsampled {
            var edge = ""
            if floorAboveDb.isFinite {
                edge = String(format: ", %.0f dB void above the cliff", floorAboveDb)
            }
            reasons.append(String(
                format: "Upsampled: spectral cliff at ~%.1f kHz (original rate ~%d Hz) with digital silence above%@ — sold as %d Hz hi-res",
                Double(suspectedOriginalRate) / 2.0 / 1000.0,
                suspectedOriginalRate,
                edge,
                sr
            ))
        }
        if padded {
            reasons.append(
                "Padded depth: \(bd)-bit container holds only \(estimatedDepth)-bit data "
                + "(the low \(bd - estimatedDepth) bits are silent)"
            )
        }

        if upsampled && padded { return (.upsampledAndPadded, reasons) }
        if upsampled { return (.upsampled, reasons) }
        if padded { return (.paddedDepth, reasons) }
        return (.genuineHires, ["Genuine high-resolution: real content above the CD band"])
    }

    // MARK: - Welch spectrum + helpers

    static func welchMagnitudeDb(
        _ audio: [Float], sampleRate: Int, nfft: Int = welchNfft
    ) -> (freqs: [Double], magsDb: [Double])? {
        guard audio.count >= nfft else { return nil }
        var hann = [Float](repeating: 0, count: nfft)
        vDSP_hann_window(&hann, vDSP_Length(nfft), Int32(vDSP_HANN_NORM))
        let half = nfft / 2
        let step = nfft / 2
        let log2n = vDSP_Length(log2(Float(nfft)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var acc = [Double](repeating: 0, count: half + 1)
        var count = 0
        var start = 0
        while start + nfft <= audio.count {
            var block = Array(audio[start..<(start + nfft)])
            vDSP_vmul(block, 1, hann, 1, &block, 1, vDSP_Length(nfft))
            var re = [Float](repeating: 0, count: half)
            var im = [Float](repeating: 0, count: half)
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    block.withUnsafeMutableBufferPointer { bp in
                        bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            // vDSP: DC в re[0], Nyquist в im[0], бины 1..half-1 обычные.
            acc[0] += Double(abs(re[0]))
            acc[half] += Double(abs(im[0]))
            for j in 1..<half {
                let m = Double((re[j] * re[j] + im[j] * im[j]).squareRoot())
                acc[j] += m
            }
            count += 1
            start += step
        }
        guard count > 0 else { return nil }
        var freqs = [Double](repeating: 0, count: half + 1)
        var magsDb = [Double](repeating: -160, count: half + 1)
        for j in 0...half {
            freqs[j] = Double(j) * Double(sampleRate) / Double(nfft)
            let m = acc[j] / Double(count)
            magsDb[j] = 20 * log10(m + 1e-10)
        }
        return (freqs, magsDb)
    }

    private static func medianBetween(
        _ freqs: [Double], _ vals: [Double], lo: Double, hi: Double
    ) -> Double? {
        var selected: [Double] = []
        for i in 0..<freqs.count where freqs[i] >= lo && freqs[i] <= hi {
            selected.append(vals[i])
        }
        guard !selected.isEmpty else { return nil }
        selected.sort()
        if selected.count % 2 == 0 {
            return (selected[selected.count / 2 - 1] + selected[selected.count / 2]) / 2.0
        }
        return selected[selected.count / 2]
    }

    private static func movingAverage(_ x: [Double], window: Int) -> [Double] {
        guard window > 1, !x.isEmpty else { return x }
        let half = window / 2
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            var s: Double = 0
            for j in lo...hi { s += x[j] }
            out[i] = s / Double(hi - lo + 1)
        }
        return out
    }
}
