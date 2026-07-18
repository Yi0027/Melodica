// Services,LyricsParser.swift
import Foundation

enum LyricsParser {
    
    static var searchPaths: [URL] = []
    
    static func findLyrics(for audioURL: URL) -> URL? {
        // 1. Ищем рядом с аудиофайлом
        let base = audioURL.deletingPathExtension()
        let lrcURL = base.appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            return lrcURL
        }
        
        // 2. Ищем во всех папках библиотеки
        let lrcFileName = audioURL.deletingPathExtension().lastPathComponent + ".lrc"
        for path in searchPaths {
            let url = path.appendingPathComponent(lrcFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }
    
    static func parse(_ url: URL) -> [LyricsLine] {
        guard let content = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .ascii) else {
            return []
        }
        
        var lines: [LyricsLine] = []
        
        let regex = try? NSRegularExpression(
            pattern: #"\[(\d{2}):(\d{2})(?:[\.:](\d{2,3}))?\](.*)"#,
            options: []
        )
        
        for line in content.components(separatedBy: .newlines) {
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let minR = Range(match.range(at: 1), in: line),
                  let secR = Range(match.range(at: 2), in: line),
                  let min = Int(line[minR]), let sec = Int(line[secR])
            else { continue }
            
            var total = TimeInterval(min * 60 + sec)
            
            if let msR = Range(match.range(at: 3), in: line) {
                let msStr = String(line[msR])
                if let ms = Int(msStr) {
                    total += msStr.count == 3
                        ? TimeInterval(ms) / 1000.0
                        : TimeInterval(ms) / 100.0
                }
            }
            
            let textRange = Range(match.range(at: 4), in: line)
            let text = textRange
                .map { line[$0].trimmingCharacters(in: .whitespaces) }
                ?? ""
            
            lines.append(LyricsLine(time: total, text: text))
        }
        
        // Сортируем по времени
        lines.sort { $0.time < $1.time }

        // Добавляем пустую строку в начало если первая строка не с нуля
        if let firstLine = lines.first, firstLine.time > 0 {
            let pauseLine = LyricsLine(time: 0, text: "", pauseUntil: firstLine.time)
            lines.insert(pauseLine, at: 0)
        }
        
        // Вычисляем паузы для пустых строк
        for i in 0..<lines.count {
            if lines[i].text.isEmpty {
                let currentTime = lines[i].time
                var nextTextTime: TimeInterval?
                for j in (i + 1)..<lines.count {
                    if !lines[j].text.isEmpty {
                        nextTextTime = lines[j].time
                        break
                    }
                }
                lines[i].pauseUntil = nextTextTime
            }
        }
        
        return lines
    }
}
