import Foundation
import AVFoundation
import Accelerate

/// Codec grids, которые fixed 2048-sample reading не видит:
/// Vorbis block switching и CELT (Opus).
///
/// Порт `codec_grids.py`. Оба чтения сертифицированы отдельно от Rule 13
/// (KBD/Vorbis): Vorbis-switch bars 1.7/2.4, CELT bars 2.2/3.2.
nonisolated enum CodecGrids {

    // MARK: - Constants

    static let holeDepthDb = 40.0
    static let bandLoHz = 2000.0
    static let bandHiHz = 16000.0

    static let nTriage = 4
    static let nFine = 16
    static let nCandidates = 8
    static let nBaseline = 12
    static let guardDistance = 4
    static let triageRef = 9
    static let fineRef = 33
    static let minBaselineHoleFraction = 0.001

    static let vorbisBlock = 2048
    static let vorbisSwitchStep = 128

    static let celtRate = 48000
    static let celtFrame = 960
    static let celtOverlap = 120
    static let celtDeemphasis = 0.85
    static let celtTriage = 6
    static let celtCandidates = 16

    static let vorbisTriage = 8
    static let vorbisCandidates = 8
    // Vorbis triages на равномерно распределённых позициях, НЕ на самых громких
    // (на транзиентах громкие кадры — drum hits, короткие блоки без long-grid).

    // MARK: - Windows

    /// Vorbis long window: sin(pi/2 * sin^2(pi/N * (n+0.5))).
    static func vorbisWindow(length: Int = 2048) -> [Float] {
        var w = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let inner = Double.pi / Double(length) * (Double(i) + 0.5)
            let s = sin(inner)
            w[i] = Float(sin(Double.pi / 2.0 * s * s))
        }
        return w
    }

    /// CELT low-overlap window над 2*frame сэмплами.
    static func celtWindow(frame: Int = 960, overlap: Int = 120) -> [Float] {
        var rise = [Float](repeating: 0, count: overlap)
        for k in 0..<overlap {
            let inner = 0.5 * Double.pi * (Double(k) + 0.5) / Double(overlap)
            let s2 = sin(inner) * sin(inner)
            rise[k] = Float(sin(0.5 * Double.pi * s2))
        }
        let zeros = (frame - overlap) / 2
        var w = [Float](repeating: 0, count: zeros)
        w.append(contentsOf: rise)
        w.append(contentsOf: [Float](repeating: 1.0, count: frame - overlap))
        w.append(contentsOf: rise.reversed())
        w.append(contentsOf: [Float](repeating: 0, count: zeros))
        return w  // length = 2*frame = 1920
    }

    // MARK: - MDCT basis (cached)

    nonisolated(unsafe) private static var basisCache: [String: [[Float]]] = [:]

    private static func mdctBasis(windowLen: Int, kLo: Int, kHi: Int) -> [[Float]] {
        let key = "\(windowLen)_\(kLo)_\(kHi)"
        if let cached = basisCache[key] { return cached }
        let half = windowLen / 2
        let piOverN = Double.pi / Double(half)
        var basis = [[Float]](repeating: [Float](repeating: 0, count: windowLen), count: kHi - kLo)
        for (i, k) in (kLo..<kHi).enumerated() {
            let kk = Double(k) + 0.5
            var row = [Float](repeating: 0, count: windowLen)
            for n in 0..<windowLen {
                let ang = piOverN * (Double(n) + 0.5 + Double(half) / 2.0) * kk
                row[n] = Float(cos(ang))
            }
            basis[i] = row
        }
        basisCache[key] = basis
        return basis
    }

    /// MDCT magnitude, batch по блокам. band [2000, 16000] Hz.
    static func mdctMagnitudes(
        blocks: [[Float]], windowLen: Int, sampleRate: Int
    ) -> [[Float]] {
        let half = windowLen / 2
        let nyquist = Double(sampleRate) / 2.0
        let kLo = max(1, Int(bandLoHz / nyquist * Double(half)))
        let kHi = min(half, Int(bandHiHz / nyquist * Double(half)))
        guard kHi > kLo, !blocks.isEmpty else { return [] }
        let basis = mdctBasis(windowLen: windowLen, kLo: kLo, kHi: kHi)
        let nBins = kHi - kLo
        var result = [[Float]](repeating: [Float](repeating: 0, count: nBins), count: blocks.count)
        for (bi, block) in blocks.enumerated() {
            for k in 0..<nBins {
                var sum: Double = 0
                let bRow = basis[k]
                for n in 0..<windowLen {
                    sum += Double(block[n]) * Double(bRow[n])
                }
                result[bi][k] = Float(abs(sum))
            }
        }
        return result
    }

    // MARK: - Local median (evaluated every `every`, held in between)

    static func localMedian(_ spec: [[Float]], size: Int, every: Int) -> [[Float]] {
        let half = size / 2
        let nRows = spec.count
        guard nRows > 0, let first = spec.first, !first.isEmpty else { return [] }
        let width = first.count
        var centres = [Int]()
        var c = 0
        while c < width { centres.append(c); c += every }
        let nCentres = centres.count
        var med = [[Float]](repeating: [Float](repeating: 0, count: nCentres), count: nRows)
        var buf = [Float](repeating: 0, count: size)
        for r in 0..<nRows {
            for (ci, cen) in centres.enumerated() {
                for k in 0..<size {
                    let idx = max(0, min(width - 1, cen - half + k))
                    buf[k] = spec[r][idx]
                }
                buf.sort()
                med[r][ci] = buf[size / 2]
            }
        }
        // Held: index[i] = min(round(i / every), nCentres - 1)
        var out = [[Float]](repeating: [Float](repeating: 0, count: width), count: nRows)
        for r in 0..<nRows {
            for i in 0..<width {
                let idx = min(Int((Double(i) / Double(every)).rounded()), nCentres - 1)
                out[r][i] = med[r][idx]
            }
        }
        return out
    }

    // MARK: - Hole fractions

    /// Доля «дыр» в кадре, начинающемся с каждого offset.
    /// Python: `hole_fractions`. Возвращает nil, если средняя ref < 1e-7.
    static func holeFractions(
        segment: [Float],
        offsets: [Int],
        window: [Float],
        sampleRate: Int,
        refSize: Int
    ) -> [Float]? {
        let length = window.count
        var blocks = [[Float]]()
        blocks.reserveCapacity(offsets.count)
        for off in offsets {
            guard off >= 0, off + length <= segment.count else { return nil }
            var block = [Float](repeating: 0, count: length)
            for i in 0..<length {
                block[i] = segment[off + i] * window[i]
            }
            blocks.append(block)
        }
        let spec = mdctMagnitudes(blocks: blocks, windowLen: length, sampleRate: sampleRate)
        guard !spec.isEmpty else { return nil }
        let every = refSize >= 17 ? 8 : 4
        let ref = localMedian(spec, size: refSize, every: every)
        var refSum: Double = 0
        for row in ref {
            for v in row { refSum += Double(v) }
        }
        refSum /= Double(ref.count * ref[0].count)
        if refSum <= 1e-7 { return nil }

        let thr = Float(pow(10.0, -holeDepthDb / 20.0))
        var fractions = [Float](repeating: 0, count: spec.count)
        for r in 0..<spec.count {
            var holes = 0
            for k in 0..<spec[r].count where spec[r][k] < ref[r][k] * thr {
                holes += 1
            }
            fractions[r] = Float(holes) / Float(spec[r].count)
        }
        return fractions
    }

    // MARK: - Geometry

    struct Geometry {
        let window: [Float]
        let sampleRate: Int
        let step: Int
        let nTotal: Int

        var length: Int { window.count }
        var hop: Int { length / 2 }
        var usable: Int { nTotal - length - hop }

        /// `count` равномерно распределённых позиций чтения, кратных hop.
        func positions(count: Int) -> [Int] {
            let strideVal = max(hop, (usable / max(1, count)) / hop * hop)
            var result = [Int]()
            for f in 0..<count {
                let pos = f * strideVal
                if pos + hop + length <= nTotal {
                    result.append(pos)
                }
            }
            return result
        }

        /// Среднее по позициям чтения от лучшей фазы каждого residue.
        func accumulate(
            read: (Int, Int) -> [Float]?,
            residues: [Int],
            bases: [Int],
            refSize: Int
        ) -> [Float]? {
            let phases = hop / step
            var offsets = [Int]()
            offsets.reserveCapacity(residues.count * phases)
            for r in residues {
                for p in 0..<phases {
                    offsets.append(r + step * p)
                }
            }
            var total = [Float](repeating: 0, count: residues.count)
            var used = 0
            for base in bases {
                guard let segment = read(base, hop + length) else { continue }
                guard let fractions = holeFractions(
                    segment: segment, offsets: offsets, window: window,
                    sampleRate: sampleRate, refSize: refSize
                ) else { continue }
                // reshape (residues, phases).max(axis=1)
                for (ri, _) in residues.enumerated() {
                    var best: Float = 0
                    for p in 0..<phases {
                        let v = fractions[ri * phases + p]
                        if v > best { best = v }
                    }
                    total[ri] += best
                }
                used += 1
            }
            guard used > 0 else { return nil }
            for i in 0..<total.count { total[i] /= Float(used) }
            return total
        }

        /// Где читает triage: громкие из широкого набора ИЛИ сам набор.
        func triageBases(
            read: (Int, Int) -> [Float]?,
            nTriage: Int,
            loudest: Bool
        ) -> [Int] {
            let pool = positions(count: loudest ? nTriage * 3 : nTriage)
            var loudness = [Double]()
            loudness.reserveCapacity(pool.count)
            for base in pool {
                guard let seg = read(base, hop + length) else {
                    loudness.append(-1); continue
                }
                var e: Double = 0
                for v in seg { e += Double(v) * Double(v) }
                loudness.append(e / Double(seg.count))
            }
            if loudest {
                let ranked = pool.indices.sorted { loudness[$0] > loudness[$1] }
                return ranked.prefix(nTriage).map { pool[$0] }
            }
            // floor = 0.01 * median(positive loudness)
            var positive = loudness.filter { $0 > 0 }
            let floor: Double
            if positive.isEmpty {
                floor = 0
            } else {
                positive.sort()
                floor = 0.01 * positive[positive.count / 2]
            }
            var result = [Int]()
            for (b, v) in zip(pool, loudness) where v > floor {
                result.append(b)
            }
            return result
        }

        /// Residues, дальше чем guard от любого из candidates.
        func baseline(candidates: [Int]) -> [Int] {
            var spread = [Int]()
            for i in 0..<(nBaseline * 3) {
                spread.append(Int(Double(step - 1) * Double(i) / Double(nBaseline * 3 - 1)))
            }
            var far = Set<Int>()
            for r in spread {
                var minDist = Int.max
                for c in candidates {
                    let d = min((r - c + step) % step, (c - r + step) % step)
                    if d < minDist { minDist = d }
                }
                if minDist > guardDistance { far.insert(r) }
            }
            return Array(far.sorted().prefix(nBaseline))
        }
    }

    // MARK: - Grid ratio

    /// Peak-to-baseline hole ratio. step == hop → fixed grid; меньше — multi-phase.
    static func gridRatio(
        read: @escaping (Int, Int) -> [Float]?,
        nTotal: Int,
        window: [Float],
        sampleRate: Int,
        step: Int,
        fineReaders: [(Int, Int) -> [Float]?]? = nil,
        nTriage: Int = nTriage,
        nCandidates: Int = nCandidates,
        loudest: Bool = true
    ) -> (Double, Int) {
        let geo = Geometry(window: window, sampleRate: sampleRate, step: step, nTotal: nTotal)
        guard geo.usable > 0 else { return (.nan, -1) }

        guard let triage = geo.accumulate(
            read: read, residues: Array(0..<step),
            bases: geo.triageBases(read: read, nTriage: nTriage, loudest: loudest),
            refSize: triageRef
        ) else { return (.nan, -1) }

        let candidates = triage.indices.sorted { triage[$0] > triage[$1] }.prefix(nCandidates).sorted()
        let baseline = geo.baseline(candidates: Array(candidates))
        guard !baseline.isEmpty else { return (.nan, -1) }

        var best = (Double.nan, -1)
        let readers = fineReaders ?? [read]
        for rd in readers {
            guard let fine = geo.accumulate(
                read: rd, residues: candidates + baseline,
                bases: geo.positions(count: nFine), refSize: fineRef
            ) else { continue }

            let baseVals = Array(fine[candidates.count...])
            let medianBase = median(baseVals.map { Double($0) })
            if !medianBase.isFinite || medianBase < minBaselineHoleFraction { continue }
            let candVals = Array(fine[0..<candidates.count])
            var peak: Double = -.infinity
            var peakIdx = -1
            for (i, v) in candVals.enumerated() where Double(v) > peak {
                peak = Double(v)
                peakIdx = i
            }
            guard peakIdx >= 0 else { continue }
            let ratio = peak / medianBase
            if ratio.isFinite && (!best.0.isFinite || ratio > best.0) {
                best = (ratio, candidates[peakIdx])
            }
        }
        return best
    }

    // MARK: - Vorbis block-switch

    /// Vorbis long-block grid, двигающийся кратно 128; читается на L и R.
    static func vorbisSwitchRatio(
        left: [Float], right: [Float], sampleRate: Int
    ) -> (Double, Int) {
        guard !left.isEmpty else { return (.nan, -1) }
        let win = vorbisWindow(length: vorbisBlock)
        let hasRight = !right.isEmpty && right.count == left.count

        // Сегменты копируются при чтении, не весь канал.
        func readLeft(_ start: Int, _ n: Int) -> [Float]? {
            guard start >= 0, start + n <= left.count else { return nil }
            return Array(left[start..<(start + n)])
        }
        func readRight(_ start: Int, _ n: Int) -> [Float]? {
            guard hasRight, start >= 0, start + n <= right.count else { return nil }
            return Array(right[start..<(start + n)])
        }

        var fineReaders: [(Int, Int) -> [Float]?] = [readLeft]
        if hasRight { fineReaders.append(readRight) }

        return gridRatio(
            read: readLeft,
            nTotal: left.count,
            window: win,
            sampleRate: sampleRate,
            step: vorbisSwitchStep,
            fineReaders: fineReaders,
            nTriage: vorbisTriage,
            nCandidates: vorbisCandidates,
            loudest: false
        )
    }

    // MARK: - CELT (Opus)

    /// CELT 960-grid на 48 kHz сигнале с undo de-emphasis.
    static func celtRatio(mono: [Float], sampleRate: Int) -> (Double, Int) {
        let win = celtWindow()
        // De-emphasis undo: y[n] = x[n] - 0.85 * x[n-1] (FIR).
        func preEmphasis(_ x: [Float]) -> [Float] {
            var y = [Float](repeating: 0, count: x.count)
            var prev: Float = 0
            for i in 0..<x.count {
                y[i] = x[i] - Float(celtDeemphasis) * prev
                prev = x[i]
            }
            return y
        }

        if sampleRate == celtRate {
            let filtered = preEmphasis(mono)
            func readNative(_ start: Int, _ n: Int) -> [Float]? {
                guard start >= 0, start + n <= filtered.count else { return nil }
                return Array(filtered[start..<(start + n)])
            }
            return gridRatio(
                read: readNative, nTotal: filtered.count, window: win,
                sampleRate: celtRate, step: celtFrame,
                nTriage: celtTriage, nCandidates: celtCandidates, loudest: true
            )
        }

        if sampleRate != 44100 { return (.nan, -1) }

        // Resample 44.1k → 48k целиком (упрощение vs Python's per-segment,
        // но результат эквивалентен).
        guard let resampled = resample(mono, from: 44100, to: 48000) else {
            return (.nan, -1)
        }
        let filtered = preEmphasis(resampled)
        func readResampled(_ start: Int, _ n: Int) -> [Float]? {
            guard start >= 0, start + n <= filtered.count else { return nil }
            return Array(filtered[start..<(start + n)])
        }
        return gridRatio(
            read: readResampled, nTotal: filtered.count, window: win,
            sampleRate: celtRate, step: celtFrame,
            nTriage: celtTriage, nCandidates: celtCandidates, loudest: true
        )
    }

    // MARK: - Resampler (AVAudioConverter)

    static func resample(_ input: [Float], from srcRate: Double, to dstRate: Double) -> [Float]? {
        guard !input.isEmpty else { return nil }
        guard let srcFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: srcRate,
            channels: 1, interleaved: false
        ),
        let dstFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: dstRate,
            channels: 1, interleaved: false
        ),
        let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else { return nil }

        let srcFrames = AVAudioFrameCount(input.count)
        let dstFrames = AVAudioFrameCount(Double(input.count) * dstRate / srcRate + 4096)
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: srcFrames),
              let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: dstFrames) else {
            return nil
        }
        srcBuf.frameLength = srcFrames
        input.withUnsafeBufferPointer { ip in
            if let dst = srcBuf.floatChannelData?[0] {
                dst.update(from: ip.baseAddress!, count: input.count)
            }
        }

        var consumed = false
        var error: NSError?
        let block: AVAudioConverterInputBlock = { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return srcBuf
        }
        converter.convert(to: dstBuf, error: &error, withInputFrom: block)
        guard error == nil, let ptr = dstBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(dstBuf.frameLength)))
    }

    // MARK: - Median helper

    private static func median(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return .nan }
        let s = x.sorted()
        if s.count % 2 == 0 {
            return (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
        }
        return s[s.count / 2]
    }
}
