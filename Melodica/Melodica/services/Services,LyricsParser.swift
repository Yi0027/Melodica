import Foundation

enum LyricsParser {
    
    static var searchPaths: [URL] = []
    
    // MARK: - Все поддерживаемые теги
    
    /// Теги реальных языков (ISO 639-1)
    static let languageTags: Set<String> = [
        "ja", "en", "ko", "zh", "zh-hant", "zh-hans",
        "ru", "uk", "fr", "de", "es", "it", "pt",
        "nl", "sv", "no", "da", "fi", "el", "pl",
        "ar", "he", "tr", "fa", "hi", "th", "vi",
        "id", "ms", "tl"
    ]
    
    /// Теги произношения/транслитерации
    static let pronunciationTags: Set<String> = [
        "ja-rom", "ja-furi", "ja-hira",
        "ko-rom",
        "zh-pinyin", "zh-bpmf",
        "ru-lat", "el-lat", "hi-lat", "th-lat"
    ]
    
    /// Специальные теги (не языки, а роли)
    static let specialTags: Set<String> = [
        "lit", "note", "inst", "bg", "rap", "chord", "duet-m", "duet-f"
    ]
    
    /// Все известные теги
    static var allKnownTags: Set<String> {
        languageTags.union(pronunciationTags).union(specialTags)
    }
    
    // MARK: - Поиск LRC
    
    static func findLyrics(for audioURL: URL) -> URL? {
        let base = audioURL.deletingPathExtension()
        let lrcURL = base.appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) { return lrcURL }
        
        let lrcFileName = audioURL.deletingPathExtension().lastPathComponent + ".lrc"
        for path in searchPaths {
            let url = path.appendingPathComponent(lrcFileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
    
    // MARK: - Парсинг
    
    static func parse(_ url: URL) -> [LyricsLine] {
        guard let content = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .ascii) else { return [] }
        
        return parseContent(content)
    }
    static var lastMetadata = LyricsMetadata()
    static func parseContent(_ content: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        lastMetadata = LyricsMetadata()
        var offsetShift: TimeInterval = 0
        
        // Регулярка: [MM:SS.xx]<tag>text или [MM:SS.xx]text
        let regex = try? NSRegularExpression(
            pattern: #"\[(\d{2}):(\d{2})(?:[\.:](\d{2,3}))?\](?:<([^>]+)>)?\s*(.*)"#,
            options: []
        )
        
        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Проверяем ID-теги: [буквы: значение]
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    
                    // Если ключ состоит только из букв — это ID-тег
                    if key.allSatisfy({ $0.isLetter }) {
                        switch key {
                        case "ti": lastMetadata.title = value
                        case "ar": lastMetadata.artist = value
                        case "al": lastMetadata.album = value
                        case "by": lastMetadata.author = value
                        case "length":
                            if let seconds = Double(value) {
                                lastMetadata.length = seconds
                            } else {
                                // Пробуем парсить MM:SS
                                let timeParts = value.split(separator: ":")
                                if timeParts.count == 2,
                                   let min = Double(timeParts[0]),
                                   let sec = Double(timeParts[1]) {
                                    lastMetadata.length = min * 60 + sec
                                }
                            }
                        case "offset":
                            if let ms = Int(value) {
                                offsetShift = TimeInterval(ms) / 1000.0
                            }
                        default:
                            break
                        }
                        continue // Пропускаем, это не строка с таймкодом
                    }
                }
            }
            
            // Основной парсинг строк с таймкодами
            // Извлекаем все таймкоды из строки
            var times: [TimeInterval] = []
            var lastIndex = rawLine.startIndex
            var searchRange = rawLine.startIndex..<rawLine.endIndex

            while let openBracket = rawLine[searchRange].firstIndex(of: "["),
                  let closeBracket = rawLine[openBracket...].firstIndex(of: "]") {
                
                let timecode = String(rawLine[rawLine.index(after: openBracket)..<closeBracket])
                
                // Пробуем распарсить как таймкод MM:SS.xx
                let parts = timecode.split(separator: ":")
                if parts.count == 2,
                   let min = Double(parts[0]),
                   let sec = Double(parts[1]) {
                    var total = min * 60 + sec
                    total += offsetShift
                    times.append(total)
                }
                
                searchRange = rawLine.index(after: closeBracket)..<rawLine.endIndex
                lastIndex = rawLine.index(after: closeBracket)
            }

            guard !times.isEmpty else { continue }

            // Всё что после последнего таймкода — тег + текст
            let remainder = String(rawLine[lastIndex...]).trimmingCharacters(in: .whitespaces)

            let tag: String?
            let text: String

            let tagTextRegex = try? NSRegularExpression(pattern: #"<([^>]+)>\s*(.*)"#, options: [])
            if let tagMatch = tagTextRegex?.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)),
               let tagR = Range(tagMatch.range(at: 1), in: remainder) {
                tag = String(remainder[tagR])
                text = Range(tagMatch.range(at: 2), in: remainder).map { String(remainder[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            } else {
                tag = nil
                text = remainder.isEmpty ? "" : remainder
            }

            let isSpecial = tag.map { specialTags.contains($0) } ?? false

            for time in times {
                lines.append(LyricsLine(time: time, text: text, tag: tag, isSpecial: isSpecial))
            }
        }
        
        lines.sort { $0.time < $1.time }
        
        // Определяем основной язык для каждой группы
        var timeGroups: [TimeInterval: [Int]] = [:]
        for (index, line) in lines.enumerated() {
            if timeGroups[line.time] == nil { timeGroups[line.time] = [] }
            timeGroups[line.time]?.append(index)
        }

        for (_, indices) in timeGroups {
            let groupLines = indices.map { lines[$0] }
            
            if let origIdx = groupLines.firstIndex(where: { $0.tag == "orig" }) {
                lines[indices[origIdx]].isMain = true
            } else if SettingsManager.shared.lrcOrigOverride {
                if let mainIdx = groupLines.firstIndex(where: { line in
                    guard let tag = line.tag else { return false }
                    return !LyricsParser.specialTags.contains(tag)
                }) {
                    lines[indices[mainIdx]].isMain = true
                }
            }
        }
        
        // Добавляем пустую строку в начало
        if let first = lines.first, first.time > 0 {
            lines.insert(LyricsLine(time: 0, text: "", pauseUntil: first.time), at: 0)
        }
        
        // Вычисляем паузы
        for i in 0..<lines.count {
            if lines[i].text.isEmpty {
                var nextTime: TimeInterval?
                for j in (i + 1)..<lines.count {
                    if !lines[j].text.isEmpty { nextTime = lines[j].time; break }
                }
                lines[i].pauseUntil = nextTime
            }
        }
        
        return lines
    }
    
    // MARK: - Группировка по времени (для многоязычного отображения)
    
    static func groupLines(_ lines: [LyricsLine]) -> [LyricsGroup] {
        var groups: [TimeInterval: [LyricsLine]] = [:]
        
        for line in lines {
            if groups[line.time] == nil {
                groups[line.time] = []
            }
            groups[line.time]?.append(line)
        }
        
        return groups
            .sorted { $0.key < $1.key }
            .map { LyricsGroup(time: $0.key, lines: $0.value, pauseUntil: $0.value.first?.pauseUntil) }
    }
    
    // MARK: - Сбор статистики по тегам в файле
    
    static func availableTags(in content: String) -> Set<String> {
        var tags: Set<String> = []
        let regex = try? NSRegularExpression(pattern: #"<([^>]+)>"#, options: [])
        
        for line in content.components(separatedBy: .newlines) {
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let tagRange = Range(match.range(at: 1), in: line)
            else { continue }
            tags.insert(String(line[tagRange]))
        }
        
        return tags
    }
}
