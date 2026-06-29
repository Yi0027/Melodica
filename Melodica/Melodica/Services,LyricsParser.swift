import Foundation

enum LyricsParser {
    
    static func findLyrics(for audioURL: URL) -> URL? {
        let base = audioURL.deletingPathExtension()
        let lrcURL = base.appendingPathExtension("lrc")
        return FileManager.default.fileExists(atPath: lrcURL.path) ? lrcURL : nil
    }
    
    static func parse(_ url: URL) -> [LyricsLine] {
        guard let content = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .ascii) else { return [] }
        
        var lines: [LyricsLine] = []
        let regex = try? NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})(?:[\.:](\d{2,3}))?\](.*)"#, options: [])
        
        for line in content.components(separatedBy: .newlines) {
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let minR = Range(match.range(at: 1), in: line), let secR = Range(match.range(at: 2), in: line),
                  let min = Int(line[minR]), let sec = Int(line[secR]) else { continue }
            
            var total = TimeInterval(min * 60 + sec)
            if let msR = Range(match.range(at: 3), in: line) {
                let msStr = String(line[msR])
                if let ms = Int(msStr) {
                    total += msStr.count == 3 ? TimeInterval(ms) / 1000.0 : TimeInterval(ms) / 100.0
                }
            }
            
            let text = Range(match.range(at: 4), in: line).map { line[$0].trimmingCharacters(in: .whitespaces) } ?? ""
            if !text.isEmpty { lines.append(LyricsLine(time: total, text: text)) }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
