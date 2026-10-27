import Foundation

/// Rule 16: MPEG-1 Layer III granule grid.
///
/// Пропускает декодированный PCM обратно через analysis-фильтрбанк,
/// который использовал энкодер: 32-полосный полифазный банк (ISO window C[i]),
/// 18-точечный MDCT на субполосу, frequency inversion нечётных субполос и
/// alias-reduction butterflies. На правильном выравнивании granule (одно из 576)
/// нули, оставленные квантованием, снова становятся видны как «дыры».
///
/// Statistic: hole fraction на лучшем выравнивании / медиана по остальным.
/// Witness без очков — только corroboration-семья `mp3grid`.
nonisolated enum MP3GridRule {

    // MARK: - Constants (from flac-detective rules/mp3_grid.py)

    static let granule = 576
    static let nGranules = 48
    static let holeDepthDb = 40.0
    static let refSize = 33
    static let excerptSeconds = 30.0
    static let gridBar = 1.6       // для FLAC (lossless-ветка)
    static let gridBarLossy = 3.5  // для native MP3: медианы honest 96/128 ~4,
                                    // так что 3.5 ниже них, но выше honest 320 (1.27)
                                    // и honest 256 (1.33)

    // MARK: - ISO/IEC 11172-3 analysis window C[0..256] * 2^21

    static let halfWindow: [Double] = [
        0, -1, -1, -1, -1, -1, -1, -2, -2, -2, -2, -3, -3, -4, -4, -5,
        -5, -6, -7, -7, -8, -9, -10, -11, -13, -14, -16, -17, -19, -21, -24, -26,
        -29, -31, -35, -38, -41, -45, -49, -53, -58, -63, -68, -73, -79, -85, -91, -97,
        -104, -111, -117, -125, -132, -139, -147, -154, -161, -169, -176, -183, -190, -196, -202, -208,
        213, 218, 222, 225, 227, 228, 228, 227, 224, 221, 215, 208, 200, 189, 177, 163,
        146, 127, 106, 83, 57, 29, -2, -36, -72, -111, -153, -197, -244, -294, -347, -401,
        -459, -519, -581, -645, -711, -779, -848, -919, -991, -1064, -1137, -1210, -1283, -1356, -1428, -1498,
        -1567, -1634, -1698, -1759, -1817, -1870, -1919, -1962, -2001, -2032, -2057, -2075, -2085, -2087, -2080, -2063,
        2037, 2000, 1952, 1893, 1822, 1739, 1644, 1535, 1414, 1280, 1131, 970, 794, 605, 402, 185,
        -45, -288, -545, -814, -1095, -1388, -1692, -2006, -2330, -2663, -3004, -3351, -3705, -4063, -4425, -4788,
        -5153, -5517, -5879, -6237, -6589, -6935, -7271, -7597, -7910, -8209, -8491, -8755, -8998, -9219, -9416, -9585,
        -9727, -9838, -9916, -9959, -9966, -9935, -9863, -9750, -9592, -9389, -9139, -8840, -8492, -8092, -7640, -7134,
        6574, 5959, 5288, 4561, 3776, 2935, 2037, 1082, 70, -998, -2122, -3300, -4533, -5818, -7154, -8540,
        -9975, -11455, -12980, -14548, -16155, -17799, -19478, -21189, -22929, -24694, -26482, -28289, -30112, -31947, -33791, -35640,
        -37489, -39336, -41176, -43006, -44821, -46617, -48390, -50137, -51853, -53534, -55178, -56778, -58333, -59838, -61289, -62684,
        -64019, -65290, -66494, -67629, -68692, -69679, -70590, -71420, -72169, -72835, -73415, -73908, -74313, -74630, -74856, -74992,
        75038
    ]

    /// Полное окно 512 семплов, нормированное на 2^21.
    static let window: [Double] = {
        var c = [Double](repeating: 0, count: 512)
        for i in 0..<halfWindow.count {
            let v = halfWindow[i]
            c[i] = v
            if i > 0 {
                c[512 - i] = (i & 63) != 0 ? -v : v
            }
        }
        let scale = 1.0 / pow(2.0, 21.0)
        for i in 0..<512 { c[i] *= scale }
        return c
    }()

    // MARK: - Polyphase matrix (32 x 64)

    static let polyphaseMatrix: [[Double]] = {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 64), count: 32)
        for k in 0..<32 {
            for i in 0..<64 {
                m[k][i] = cos(Double((2 * k + 1) * (i - 16)) * .pi / 64.0)
            }
        }
        return m
    }()

    // MARK: - MDCT-36 (18 x 36)

    static let mdct36: [[Double]] = {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 36), count: 18)
        for mi in 0..<18 {
            for ni in 0..<36 {
                m[mi][ni] = cos(.pi / 72.0 * Double(2 * ni + 1 + 18) * Double(2 * mi + 1))
            }
        }
        return m
    }()

    static let sine36: [Double] = (0..<36).map { sin(.pi / 36.0 * (Double($0) + 0.5)) }

    // MARK: - Alias reduction

    static let ci: [Double] = [-0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037]
    static let cs: [Double] = ci.map { 1.0 / (1.0 + $0 * $0).squareRoot() }
    static let ca: [Double] = ci.map { $0 / (1.0 + $0 * $0).squareRoot() }

    static let abA: [[Int]] = (1...31).map { sb in (0..<8).map { 18 * sb - 1 - $0 } }
    static let abB: [[Int]] = (1...31).map { sb in (0..<8).map { 18 * sb + $0 } }

    // MARK: - Polyphase bank

    /// Subband samples (T x 32). `newest` входного семпла для момента t:
    /// `phase + 32*t + 31` (учитывая padding слева из 512 нулей).
    static func polyphaseAt(padded: [Double], phase: Int, tIdx: [Int]) -> [[Double]] {
        var result = [[Double]](
            repeating: [Double](repeating: 0, count: 32),
            count: tIdx.count
        )
        let limit = padded.count
        for (ti, t) in tIdx.enumerated() {
            let newest = 512 + phase + 31 + 32 * t
            var zsum = [Double](repeating: 0, count: 64)
            for m2 in 0..<64 {
                var s: Double = 0
                for m1 in 0..<8 {
                    let m = m1 * 64 + m2
                    let idx = newest - m
                    if idx >= 0 && idx < limit {
                        s += padded[idx] * window[m]
                    }
                }
                zsum[m2] = s
            }
            for k in 0..<32 {
                let row = polyphaseMatrix[k]
                var sum: Double = 0
                for m2 in 0..<64 {
                    sum += row[m2] * zsum[m2]
                }
                result[ti][k] = sum
            }
        }
        return result
    }

    // MARK: - Granule lines (MDCT + alias reduction)

    /// blk: (G, 36, 32) — G гранул по 36 субполосных сэмплов в каждой из 32 полос.
    /// Возвращает (G, 576) — 576 линий на гранулу.
    static func granuleLines(_ blk: [[[Double]]]) -> [[Double]] {
        let G = blk.count
        var lines = [[Double]](repeating: [Double](repeating: 0, count: 576), count: G)

        for g in 0..<G {
            var b = blk[g]
            // Frequency inversion: нечётные субполосы × нечётные сэмплы
            for n in 0..<36 {
                if n % 2 == 1 {
                    for k in 0..<32 where k % 2 == 1 {
                        b[n][k] = -b[n][k]
                    }
                }
            }
            // MDCT-36 по каждой субполосе
            for k in 0..<32 {
                for mi in 0..<18 {
                    let row = mdct36[mi]
                    var sum: Double = 0
                    for n in 0..<36 {
                        sum += row[n] * b[n][k] * sine36[n]
                    }
                    lines[g][k * 18 + mi] = sum
                }
            }
            // Alias reduction butterflies
            for sb in 1..<32 {
                let aRow = abA[sb - 1]
                let bRow = abB[sb - 1]
                for i in 0..<8 {
                    let aIdx = aRow[i]
                    let bIdx = bRow[i]
                    let bu = lines[g][aIdx]
                    let bd = lines[g][bIdx]
                    lines[g][aIdx] = bu * cs[i] - bd * ca[i]
                    lines[g][bIdx] = bd * cs[i] + bu * ca[i]
                }
            }
        }
        return lines
    }

    // MARK: - Hole fraction

    /// lines: (G, 576). Считаем долю линий, которые на 40 dB ниже медианы
    /// локального окружения (окно 33), усреднённую по энергетическим гранулам.
    static func holeFraction(_ lines: [[Double]]) -> Double {
        let G = lines.count
        guard G > 0 else { return .nan }
        let thr = pow(10.0, -holeDepthDb / 20.0)
        let half = refSize / 2
        var total: Double = 0
        var energetic = 0

        for g in 0..<G {
            var mag = [Double](repeating: 0, count: 576)
            for j in 0..<576 { mag[j] = abs(lines[g][j]) }

            var ref = [Double](repeating: 0, count: 576)
            for j in 0..<576 {
                let lo = max(0, j - half)
                let hi = min(575, j + half)
                var vals = Array(mag[lo...hi])
                vals.sort()
                ref[j] = vals[vals.count / 2]
            }

            var meanRef: Double = 0
            for v in ref { meanRef += v }
            meanRef /= Double(ref.count)
            if meanRef <= 1e-7 { continue }

            var holes = 0
            for j in 0..<576 {
                if mag[j] < ref[j] * thr { holes += 1 }
            }
            total += Double(holes) / 576.0
            energetic += 1
        }

        if energetic == 0 { return .nan }
        return total / Double(energetic)
    }

    // MARK: - Alignment curve

    /// Доля «дыр» для каждого из 576 выравниваний granule.
    static func alignmentCurve(
        _ audio: [Double],
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> [Double] {
        var curve = [Double](repeating: .nan, count: granule)
        let totalT = audio.count / 32 - 16
        let usable = totalT / 18 - 3
        guard usable >= 2 else { return curve }

        let stride = max(1, usable / nGranules)
        var starts: [Int] = []
        for i in 0..<nGranules {
            let s = 18 + 18 * stride * i
            if s + 18 + 36 <= totalT {
                starts.append(s)
            }
        }
        guard !starts.isEmpty else { return curve }

        var needSet = Set<Int>()
        for s in starts {
            for j in 0..<54 { needSet.insert(s + j) }
        }
        let need = needSet.sorted()

        var padded = [Double](repeating: 0, count: 512 + audio.count)
        for i in 0..<audio.count { padded[512 + i] = audio[i] }

        for phase in 0..<32 {
            onProgress?(Double(phase) / 32.0)
            let sub = polyphaseAt(padded: padded, phase: phase, tIdx: need)

            var base = [Int](repeating: 0, count: starts.count)
            for (gi, s) in starts.enumerated() {
                var lo = 0, hi = need.count - 1
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if need[mid] < s { lo = mid + 1 } else { hi = mid }
                }
                base[gi] = lo
            }

            for q in 0..<18 {
                var blk = [[[Double]]]()
                for g in 0..<starts.count {
                    var granule = [[Double]](
                        repeating: [Double](repeating: 0, count: 32),
                        count: 36
                    )
                    for n in 0..<36 {
                        let idx = base[g] + q + n
                        if idx < sub.count {
                            for k in 0..<32 {
                                granule[n][k] = sub[idx][k]
                            }
                        }
                    }
                    blk.append(granule)
                }
                let lines = granuleLines(blk)
                curve[phase + 32 * q] = holeFraction(lines)
            }
        }
        return curve
    }

    // MARK: - Public entry

    static func gridPeakRatio(
        _ audio: [Float],
        sampleRate: Int,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> (Double, Int) {
        onProgress?(0.00)
        let n = Int(excerptSeconds * Double(sampleRate))
        guard audio.count > n, n > 0 else { return (.nan, -1) }
        let start = max(0, (audio.count - n) / 2)
        let end = min(audio.count, start + n)

        var mono = [Double](repeating: 0, count: end - start)
        for i in 0..<(end - start) { mono[i] = Double(audio[start + i]) }

        let curve = alignmentCurve(mono, onProgress: onProgress)
        onProgress?(1.00)
        var good: [Double] = []
        for v in curve where v.isFinite { good.append(v) }
        guard good.count >= granule / 2 else { return (.nan, -1) }

        good.sort()
        let med = good[good.count / 2]
        guard med > 0 else { return (.nan, -1) }

        var maxVal: Double = -.infinity
        var maxIdx = 0
        for (i, v) in curve.enumerated() where v.isFinite {
            if v > maxVal { maxVal = v; maxIdx = i }
        }
        return (maxVal / med, maxIdx)
    }

    /// Возвращает (0, reasons, witness). Всегда 0 очков.
    static func apply(_ ctx: ScoringContext) -> (score: Int, reasons: [String], witness: Bool) {
        guard let audio = ctx.loadedAudio, let sr = ctx.loadedAudioSampleRate else {
            return (0, [], false)
        }
        let (ratio, offset) = gridPeakRatio(audio, sampleRate: sr)
        ctx.mp3GridRatio = ratio

        guard ratio.isFinite else {
            return (0, [], false)
        }
        // Witness только если ratio выше bar. Пороги 1.6 — из flac-detective,
        // откалиброван на lossless; для raw MP3 мы пока собираем данные.
        let isWitness = ratio >= gridBar
        return (
            0,
            ["R16: MP3 granule grid (alignment \(offset), holes \(String(format: "%.2f", ratio))x)"],
            isWitness
        )
    }
}
