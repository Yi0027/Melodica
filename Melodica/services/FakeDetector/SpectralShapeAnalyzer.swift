// FakeDetector/SpectralShapeAnalyzer.swift
import Foundation

/// Анализ формы спектра: ищет резкий обрыв (lowpass codec)
/// независимо от абсолютного уровня сигнала.
nonisolated enum SpectralShapeAnalyzer {

    struct ShapeReading {
        let dropCutoffHz: Double       // где обрыв, NaN если не нашли
        let dropDb: Double             // глубина обрыва в дБ
        let dropConfidence: Double     // 0..1
        let spectrumSummary: String    // 8..22 кГц, шаг 200 Гц, dB через ";"
        let hfSlopeDbPerKhz: Double    // средний наклон 15-20 кГц
        let energyAbove18k: Double     // средний уровень powerDb в 18-20 кГц (дБ)
    }

    /// Ищет максимальный локальный обрыв в спектре.
    /// Работает по сглаженной кривой, не зависит от абсолютного уровня.
    nonisolated static func analyze(
        powerDb: [Float],
        binWidth: Double,
        sampleRate: Int
    ) -> ShapeReading {
        let nyquist = Double(sampleRate) / 2.0
        let searchLo = max(0, Int(8000.0 / binWidth))
        let searchHi = min(powerDb.count - 2, Int((nyquist - 500.0) / binWidth))

        let fallback = ShapeReading(
            dropCutoffHz: .nan,
            dropDb: 0,
            dropConfidence: 0,
            spectrumSummary: buildSpectrumSummary(powerDb, binWidth: binWidth),
            hfSlopeDbPerKhz: slopeBetween(powerDb, loHz: 15000, hiHz: 20000, binWidth: binWidth),
            energyAbove18k: meanDbBetween(powerDb, loHz: 18000, hiHz: 20000, binWidth: binWidth)
        )
        guard searchHi > searchLo + 20 else { return fallback }

        // Сглаживание 100 Гц — убираем джиттер FFT
        let smoothBins = max(1, Int(100.0 / binWidth))
        var smooth = [Float](repeating: 0, count: powerDb.count)
        for i in 0..<powerDb.count {
            let lo = max(0, i - smoothBins)
            let hi = min(powerDb.count - 1, i + smoothBins)
            var s: Float = 0
            for j in lo...hi { s += powerDb[j] }
            smooth[i] = s / Float(hi - lo + 1)
        }

        // Разница средних 500 Гц слева и 500 Гц справа
        let windowBins = max(1, Int(500.0 / binWidth))
        var bestDrop: Float = 0
        var bestBin = -1

        for i in searchLo...searchHi {
            let loLo = max(0, i - windowBins)
            let loHi = i
            let hiLo = i
            let hiHi = min(powerDb.count - 1, i + windowBins)
            guard loHi > loLo, hiHi > hiLo else { continue }

            var sumBefore: Float = 0
            var sumAfter: Float = 0
            for j in loLo..<loHi { sumBefore += smooth[j] }
            for j in hiLo..<hiHi { sumAfter += smooth[j] }
            let meanBefore = sumBefore / Float(loHi - loLo)
            let meanAfter = sumAfter / Float(hiHi - hiLo)
            let drop = meanBefore - meanAfter

            if drop > bestDrop {
                bestDrop = drop
                bestBin = i
            }
        }

        // Порог 8 дБ — ниже этого естественный спад, не кодек
        guard bestBin > 0, bestDrop >= 8.0 else { return fallback }

        return ShapeReading(
            dropCutoffHz: Double(bestBin) * binWidth,
            dropDb: Double(bestDrop),
            dropConfidence: min(1.0, Double(bestDrop) / 30.0),
            spectrumSummary: buildSpectrumSummary(powerDb, binWidth: binWidth),
            hfSlopeDbPerKhz: slopeBetween(powerDb, loHz: 15000, hiHz: 20000, binWidth: binWidth),
            energyAbove18k: meanDbBetween(powerDb, loHz: 18000, hiHz: 20000, binWidth: binWidth)
        )
    }

    /// Спектр 8..22 кГц с шагом 200 Гц → строка "a;b;c;..."
    private nonisolated static func buildSpectrumSummary(
        _ powerDb: [Float], binWidth: Double
    ) -> String {
        var parts: [String] = []
        var hz = 8000.0
        while hz <= 22000.0 {
            let bin = Int(hz / binWidth)
            if bin >= 0 && bin < powerDb.count {
                parts.append(String(format: "%.1f", powerDb[bin]))
            } else {
                parts.append("")
            }
            hz += 200.0
        }
        return parts.joined(separator: ";")
    }
    /// Среднее значение powerDb в диапазоне [loHz, hiHz].
    /// Возвращает NaN, если бинов меньше трёх.
    private nonisolated static func meanDbBetween(
        _ powerDb: [Float], loHz: Double, hiHz: Double, binWidth: Double
    ) -> Double {
        let loBin = Int(loHz / binWidth)
        let hiBin = min(powerDb.count - 1, Int(hiHz / binWidth))
        guard hiBin > loBin + 2 else { return .nan }
        var sum: Double = 0
        for i in loBin...hiBin { sum += Double(powerDb[i]) }
        return sum / Double(hiBin - loBin + 1)
    }
    /// Средний наклон дБ/кГц между loHz и hiHz.
    private nonisolated static func slopeBetween(
        _ powerDb: [Float], loHz: Double, hiHz: Double, binWidth: Double
    ) -> Double {
        let loBin = Int(loHz / binWidth)
        let hiBin = min(powerDb.count - 1, Int(hiHz / binWidth))
        guard hiBin > loBin + 4 else { return .nan }

        let meanX = Double(loBin + hiBin) / 2.0
        var sumY: Double = 0
        for i in loBin...hiBin { sumY += Double(powerDb[i]) }
        let meanY = sumY / Double(hiBin - loBin + 1)

        var sxy: Double = 0
        var sxx: Double = 0
        for i in loBin...hiBin {
            let x = Double(i) - meanX
            sxy += x * (Double(powerDb[i]) - meanY)
            sxx += x * x
        }
        guard sxx > 0 else { return .nan }
        return (sxy / sxx) * (1000.0 / binWidth)
    }
}
