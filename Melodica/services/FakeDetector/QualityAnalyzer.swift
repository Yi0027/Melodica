import Foundation
import AVFoundation

nonisolated struct QualityResult {
    // Clipping
    let hasClipping: Bool
    let clippingPercentage: Double
    let clippedSamples: Int
    let clippingSeverity: String

    // DC offset
    let hasDCOffset: Bool
    let dcOffsetValue: Double
    let dcSeverity: String

    // Silence leading/trailing
    let hasSilenceIssue: Bool
    let leadingSilenceSec: Double
    let trailingSilenceSec: Double
    let silenceIssueType: String
}

/// Порт `analysis/quality.py`. Один проход по файлу.
nonisolated enum QualityAnalyzer {

    static let clippingThreshold: Float = 0.99
    static let dcThreshold: Double = 0.001
    static let silenceThresholdDb: Double = -60.0
    static let silenceIssueSec: Double = 2.0
    static let chunkFrames: AVAudioFrameCount = 1 << 16   // 65536

    static func analyze(_ url: URL) -> QualityResult? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = Int(format.sampleRate)
        let chCount = Int(format.channelCount)
        let totalFrames = file.length
        guard totalFrames > 0, chCount > 0 else { return nil }

        let silenceThreshold = Float(pow(10.0, silenceThresholdDb / 20.0))
        var clippedSamples = 0
        var sumOfSamples: Double = 0
        var firstNonSilent: Int? = nil
        var lastNonSilent: Int? = nil
        var currentFrame: Int = 0

        guard let buf = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: chunkFrames
        ) else { return nil }

        file.framePosition = 0
        while file.framePosition < totalFrames {
            do { try file.read(into: buf) } catch { break }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let ch = buf.floatChannelData else { break }

            for c in 0..<chCount {
                let src = ch[c]
                for i in 0..<n {
                    let v = src[i]
                    let a = abs(v)
                    if a >= clippingThreshold { clippedSamples += 1 }
                    sumOfSamples += Double(v)
                    if a > silenceThreshold {
                        if firstNonSilent == nil { firstNonSilent = currentFrame + i }
                        lastNonSilent = currentFrame + i
                    }
                }
            }
            currentFrame += n
        }

        let totalSamples = Int(totalFrames) * chCount
        guard totalSamples > 0 else { return nil }

        // Clipping
        let clipPct = Double(clippedSamples) / Double(totalSamples) * 100.0
        let clipSeverity: String
        if clipPct == 0 { clipSeverity = "none" }
        else if clipPct < 0.01 { clipSeverity = "light" }
        else if clipPct < 0.1 { clipSeverity = "moderate" }
        else { clipSeverity = "severe" }

        // DC offset
        let dc = sumOfSamples / Double(totalSamples)
        let absDc = abs(dc)
        let dcSeverity: String
        if absDc < dcThreshold { dcSeverity = "none" }
        else if absDc < 0.01 { dcSeverity = "light" }
        else if absDc < 0.05 { dcSeverity = "moderate" }
        else { dcSeverity = "severe" }

        // Silence
        let leading: Double
        let trailing: Double
        let issueType: String
        let hasIssue: Bool
        if firstNonSilent == nil {
            leading = Double(totalFrames) / Double(sampleRate)
            trailing = 0
            issueType = "full_silence"
            hasIssue = true
        } else {
            leading = Double(firstNonSilent!) / Double(sampleRate)
            trailing = Double(Int(totalFrames) - 1 - lastNonSilent!) / Double(sampleRate)
            hasIssue = leading > silenceIssueSec || trailing > silenceIssueSec
            if leading > silenceIssueSec && trailing > silenceIssueSec { issueType = "both" }
            else if leading > silenceIssueSec { issueType = "leading" }
            else if trailing > silenceIssueSec { issueType = "trailing" }
            else { issueType = "none" }
        }

        return QualityResult(
            hasClipping: clipPct > 0.01,
            clippingPercentage: (clipPct * 10000).rounded() / 10000,
            clippedSamples: clippedSamples,
            clippingSeverity: clipSeverity,
            hasDCOffset: absDc >= dcThreshold,
            dcOffsetValue: (dc * 1_000_000).rounded() / 1_000_000,
            dcSeverity: dcSeverity,
            hasSilenceIssue: hasIssue,
            leadingSilenceSec: (leading * 100).rounded() / 100,
            trailingSilenceSec: (trailing * 100).rounded() / 100,
            silenceIssueType: issueType
        )
    }

    /// Порт `BitDepthDetector.detect`. Возвращает (isFake, estimatedDepth) или nil.
    static func detectedBitDepth(
        _ url: URL, reportedDepth: Int
    ) -> (isFake: Bool, estimated: Int)? {
        guard reportedDepth > 16 else { return (false, reportedDepth) }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let totalFrames = file.length
        guard totalFrames > 0 else { return nil }

        // Читаем из середины трека, чтобы избежать ведущей паузы/тишины
        let take = min(totalFrames, 30000)
        let startFrame = max(0, (totalFrames - take) / 2)
        file.framePosition = startFrame

        guard let buf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(take)
        ) else { return nil }
        do { try file.read(into: buf) } catch { return nil }
        guard let ch = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength)
        guard n > 0 else { return nil }

        let src = ch[0]
        var nonSilentCount = 0
        for i in 0..<n {
            let v = src[i]
            // Пропускаем тишину
            if abs(v) < 1e-4 { continue }
            nonSilentCount += 1

            let scaled = Double(v) * 32768.0
            let residual = abs(scaled - scaled.rounded())
            if residual >= 1e-4 {
                return (false, 24)
            }
        }

        // Если не было достаточно не-тихих сэмплов для уверенного анализа, не объявляем фейком
        if nonSilentCount < 500 {
            return (false, reportedDepth)
        }
        return (true, 16)
    }
}
