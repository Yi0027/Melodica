import Foundation
import AVFoundation

/// Размер аудио после пере-сжатия в FLAC — «одна линейка» для Rule 1.
///
/// Rule 1 читает compression ratio как улику: audio, которое сжимается до
/// ~800 kbps, что-то потеряло. Это свойство SAMPLES. Чтение размера контейнера
/// делало это свойством файла: тот же трек в FLAC и WAV читается по-разному
/// (issue #7). Поэтому измеряем через реальный FLAC re-encode.
///
/// Реализация через AVAudioFile + kAudioFormatFLAC (macOS 10.13+).
/// Если writer недоступен — возвращает nil, Rule 1 откатывается к declared
/// bitrate (тот же fallback, что и Python `flac_equivalent_size` при ошибке).
nonisolated enum FlacEquivalentSize {

    static let chunkFrames: AVAudioFrameCount = 1 << 20   // 1 Mi

    /// Размер в байтах, или nil если измерение не удалось.
    static func measure(
        _ url: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> Int? {
        guard let srcFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = srcFile.processingFormat
        let sampleRate = format.sampleRate
        let chCount = format.channelCount
        guard sampleRate > 0, chCount > 0 else { return nil }

        // Битность определяем из stream description. Python использует
        // PCM_16 для <= 16 бит, PCM_24 иначе.
        let asbd = format.streamDescription.pointee
        let srcBits = Int(asbd.mBitsPerChannel)
        let effectiveBits = srcBits <= 16 ? 16 : 24

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: chCount,
            AVEncoderBitDepthHintKey: effectiveBits,
        ]

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("feq_\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            let dstFile = try AVAudioFile(forWriting: tmp, settings: settings)
            guard let buf = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: chunkFrames
            ) else { return nil }
            let totalFrames = Double(srcFile.length)
            var processedFrames: Double = 0
            srcFile.framePosition = 0
            while srcFile.framePosition < srcFile.length {
                buf.frameLength = 0
                try srcFile.read(into: buf, frameCount: chunkFrames)
                if buf.frameLength == 0 { break }
                try dstFile.write(from: buf)
                processedFrames += Double(buf.frameLength)
                if totalFrames > 0 {
                    onProgress?(min(1.0, processedFrames / totalFrames))
                }
            }
        } catch {
            return nil
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path),
              let size = attrs[.size] as? Int, size > 0 else {
            return nil
        }
        return size
    }
}
