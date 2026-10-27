import Foundation
import AVFoundation

/// Могли ли обвиняющие инструменты вообще работать на этом файле.
///
/// AUTHENTIC раньше означал две разные вещи: «инструменты работали и не нашли
/// ничего» и «инструменты не могли работать». Второе — не находка, а её
/// отсутствие; выдавать его за чистый bill of health — typed-absence дефект.
///
/// Порт `analysis/assessability.py`.
nonisolated enum Assessability {

    // Ниже этой частоты нет полосы выше 16 kHz, где читает каждое правило.
    static let minAssessableRateHz = 32000

    // Тишина: нечего читать.
    static let silenceFloorRms = 1e-6

    // Арифметика frame-based witness, а не круглое число.
    // stereo_image.MIN_FRAMES = 16, FFT_SIZE = 2048, HOP = 1024.
    static let stereoFftSize = 2048
    static let stereoHop = 1024
    static let stereoMinFrames = 16
    static let minAssessableSamples = stereoFftSize + stereoHop * (stereoMinFrames - 1)

    /// Почему файл не может быть оценён, или nil.
    static func unassessableReason(
        sampleRate: Int?,
        durationS: Double?,
        cutoffFreq: Double?,
        rms: Double?
    ) -> String? {
        guard let sr = sampleRate else {
            return "the sample rate could not be read"
        }
        if sr < minAssessableRateHz {
            return "sampled at \(sr) Hz, below \(minAssessableRateHz) Hz — there is no band here for the transcode rules to read"
        }
        if let r = rms, r.isFinite, r <= silenceFloorRms {
            return "there is no measurable signal in this file"
        }
        guard let cut = cutoffFreq, cut.isFinite, cut > 0 else {
            return "the spectrum could not be analysed, so no rule had an input"
        }
        if let dur = durationS, dur.isFinite,
           dur * Double(sr) < Double(minAssessableSamples) {
            return String(
                format: "only %.2f s long — fewer than the %d samples the frame-based witness needs for a single reading",
                dur, minAssessableSamples
            )
        }
        return nil
    }

    /// RMS 30-секундного сегмента, или nil.
    static func sampledRms(_ url: URL, sampleRate: Int) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let probeFrames = min(file.length, AVAudioFramePosition(30 * sampleRate))
        guard probeFrames > 0 else { return nil }
        file.framePosition = 0
        guard let buf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(probeFrames)
        ) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        guard let ch = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength)
        let chCount = Int(buf.format.channelCount)
        guard n > 0, chCount > 0 else { return nil }
        var sum: Double = 0
        for c in 0..<chCount {
            let src = ch[c]
            for i in 0..<n {
                let v = Double(src[i])
                sum += v * v
            }
        }
        return (sum / Double(n * chCount)).squareRoot()
    }
}
