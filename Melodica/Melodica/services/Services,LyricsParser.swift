import Foundation

enum LyricsParser {
    
    static var searchPaths: [URL] = []
    
    // MARK: - Все поддерживаемые теги
    
    static let languageTags: Set<String> = [
        "ja", "en", "ko", "zh", "zh-hant", "zh-hans",
        "ru", "uk", "fr", "de", "es", "it", "pt",
        "nl", "sv", "no", "da", "fi", "el", "pl",
        "ar", "he", "tr", "fa", "hi", "th", "vi",
        "id", "ms", "tl"
    ]
    
    static let pronunciationTags: Set<String> = [
        "ja-rom", "ja-furi", "ja-hira",
        "ko-rom",
        "zh-pinyin", "zh-bpmf",
        "ru-lat", "el-lat", "hi-lat", "th-lat"
    ]
    
    static let specialTags: Set<String> = [
        "lit", "note", "inst", "bg", "rap", "chord", "duet-m", "duet-f"
    ]
    
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
    
    // MARK: - Форматы
    
    private enum LRCFormat {
        case a   // тег ПОСЛЕ слова
        case b   // тег ПЕРЕД словом
        case c   // диапазоны <start,end> (каноника)
    }
    
    // MARK: - Нормализованные модели
    
    private struct NormalizedWord {
        let time: TimeInterval
        var endTime: TimeInterval?
        let text: String
    }
    
    private struct NormalizedLine {
        let words: [NormalizedWord]
        let trailingTimecode: TimeInterval?   // висячий <...> без текста после
        let cleanText: String
    }
    
    // MARK: - Основной парсинг
    
    static func parseContent(_ content: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        lastMetadata = LyricsMetadata()
        
        let rawLines = content.components(separatedBy: .newlines)
        
        // 1. Собираем offset из всего файла
        var offsetShift: TimeInterval = 0
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { continue }
            let inner = String(trimmed.dropFirst().dropLast())
            let parts = inner.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard key == "offset" else { continue }
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if let ms = Int(value) {
                offsetShift = TimeInterval(ms) / 1000.0
            }
        }
        
        // 2. Якоря и следующие якоря
        let (anchors, nextAnchorTimes) = computeAnchors(rawLines: rawLines, offsetShift: offsetShift)
        
        // 3. Основной проход
        for (lineIndex, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Метаданные
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    
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
                                let timeParts = value.split(separator: ":")
                                if timeParts.count == 2,
                                   let min = Double(timeParts[0]),
                                   let sec = Double(timeParts[1]) {
                                    lastMetadata.length = min * 60 + sec
                                }
                            }
                        default: break
                        }
                        continue
                    }
                }
            }
            
            guard let anchor = anchors[lineIndex] else { continue }
            
            // Текст после последнего []
            let textStartIndex = rawLine.lastIndex(of: "]").map { rawLine.index(after: $0) } ?? rawLine.startIndex
            var remainder = String(rawLine[textStartIndex...]).trimmingCharacters(in: .whitespaces)
            
            // Тег <ja> / <trans> и т.п.
            let tag: String?
            if remainder.hasPrefix("<"), let tagEnd = remainder.firstIndex(of: ">") {
                let potentialTag = String(remainder[remainder.index(after: remainder.startIndex)..<tagEnd])
                if potentialTag.contains(":") || potentialTag.contains(",") {
                    tag = nil
                } else {
                    tag = potentialTag
                    remainder = String(remainder[remainder.index(after: tagEnd)...]).trimmingCharacters(in: .whitespaces)
                }
            } else {
                tag = nil
            }
            
            let isSpecial = tag.map { specialTags.contains($0) } ?? false
            
            // Определяем формат и нормализуем
            let format = detectFormat(remainder)
            let normalized = normalize(
                remainder,
                format: format,
                anchor: anchor,
                offsetShift: offsetShift
            )
            
            // Строим слова
            var words: [LyricsWord] = normalized.words.map {
                LyricsWord(time: $0.time, text: $0.text, endTime: $0.endTime)
            }
            
            // Добиваем endTime
            fillEndTimes(
                words: &words,
                trailing: normalized.trailingTimecode,
                nextLineTime: nextAnchorTimes[lineIndex]
            )
            
            var line = LyricsLine(
                time: anchor,
                endTime: nextAnchorTimes[lineIndex],
                text: normalized.cleanText,
                tag: tag,
                isSpecial: isSpecial
            )
            line.words = words
            lines.append(line)
        }
        
        lines.sort { $0.time < $1.time }
        markMainLines(in: &lines)
        
        if let first = lines.first, first.time > 0 {
            lines.insert(LyricsLine(time: 0, text: "", pauseUntil: first.time), at: 0)
        }
        // Завершающая пустая строка — если в конце нет пустой строки
        if let last = lines.last, !last.text.isEmpty {
            let endTime = last.words.compactMap({ $0.endTime }).max() ?? last.endTime
            if let endTime = endTime {
                lines.append(LyricsLine(time: endTime, text: ""))
            }
        }
        
        calculatePauses(for: &lines)
        return lines
    }
    
    // MARK: - Якоря
    
    private static func computeAnchors(
        rawLines: [String],
        offsetShift: TimeInterval
    ) -> (anchors: [TimeInterval?], nextAnchors: [TimeInterval?]) {
        var anchors: [TimeInterval?] = Array(repeating: nil, count: rawLines.count)
        
        for (i, raw) in rawLines.enumerated() {
            var searchRange = raw.startIndex..<raw.endIndex
            while let open = raw[searchRange].firstIndex(of: "["),
                  let close = raw[open...].firstIndex(of: "]") {
                let tc = String(raw[raw.index(after: open)..<close])
                if !tc.contains(",") && !tc.contains("<"),
                   let t = parseTimecode(tc, offsetShift: offsetShift) {
                    anchors[i] = t
                    break
                }
                searchRange = raw.index(after: close)..<raw.endIndex
            }
        }
        
        var nextAnchors: [TimeInterval?] = Array(repeating: nil, count: rawLines.count)
        var next: TimeInterval? = nil
        for i in stride(from: rawLines.count - 1, through: 0, by: -1) {
            nextAnchors[i] = next
            if let a = anchors[i] { next = a }
        }
        
        return (anchors, nextAnchors)
    }
    
    // MARK: - Определение формата
    
    private static func detectFormat(_ text: String) -> LRCFormat {
        guard let firstOpen = text.firstIndex(of: "<"),
              let firstClose = text[firstOpen...].firstIndex(of: ">") else {
            return .b
        }
        
        let inner = String(text[text.index(after: firstOpen)..<firstClose])
        
        // Диапазон → C
        if inner.contains(",") {
            return .c
        }
        
        // Есть текст до первого <> → A
        let before = text[text.startIndex..<firstOpen].trimmingCharacters(in: .whitespaces)
        if !before.isEmpty {
            return .a
        }
        
        // <> в самом начале → B
        return .b
    }
    
    // MARK: - Нормализация
    
    private static func normalize(
        _ text: String,
        format: LRCFormat,
        anchor: TimeInterval,
        offsetShift: TimeInterval
    ) -> NormalizedLine {
        let nsText = text as NSString
        let pattern = #"<(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?(?:,(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return NormalizedLine(words: [], trailingTimecode: nil, cleanText: text)
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        
        switch format {
        case .c:
            return normalizeC(text: text, nsText: nsText, matches: matches, offsetShift: offsetShift)
        case .a:
            return normalizeA(text: text, nsText: nsText, matches: matches, anchor: anchor, offsetShift: offsetShift)
        case .b:
            return normalizeB(text: text, nsText: nsText, matches: matches, anchor: anchor, offsetShift: offsetShift)
        }
    }
    
    // MARK: - Нормализатор A (тег после слова)
    
    private static func normalizeA(
        text: String,
        nsText: NSString,
        matches: [NSTextCheckingResult],
        anchor: TimeInterval,
        offsetShift: TimeInterval
    ) -> NormalizedLine {
        guard !matches.isEmpty else {
            return NormalizedLine(words: [], trailingTimecode: nil, cleanText: text)
        }
        
        // Собираем сегменты текста между <>:
        // сегмент 0 — до первого <>
        // сегмент i — между <i-1> и <i>
        var segments: [String] = []
        
        let firstText = nsText.substring(with: NSRange(location: 0, length: matches[0].range.location))
            .trimmingCharacters(in: .whitespaces)
        if !firstText.isEmpty { segments.append(firstText) }
        
        var trailing: TimeInterval?
        
        for i in 0..<matches.count {
            let afterPos = matches[i].range.location + matches[i].range.length
            let nextPos = i + 1 < matches.count ? matches[i + 1].range.location : nsText.length
            let seg = nsText.substring(with: NSRange(location: afterPos, length: nextPos - afterPos))
                .trimmingCharacters(in: .whitespaces)
            
            if !seg.isEmpty {
                segments.append(seg)
            } else if i == matches.count - 1 {
                // висячий <> в конце
                trailing = parseTimecodeFromMatch(matches[i], nsText: nsText, offsetShift: offsetShift, isStart: true)
            }
        }
        
        // Таймкоды
        let timecodes: [TimeInterval] = matches.compactMap {
            parseTimecodeFromMatch($0, nsText: nsText, offsetShift: offsetShift, isStart: true)
        }
        
        // Слова
        var words: [NormalizedWord] = []
        var cleanParts: [String] = []
        
        for (i, seg) in segments.enumerated() {
            let start: TimeInterval
            if i == 0 {
                start = anchor
            } else {
                start = i - 1 < timecodes.count ? timecodes[i - 1] : anchor
            }
            
            let end: TimeInterval?
            if i < timecodes.count {
                end = timecodes[i]
            } else {
                end = trailing
            }
            
            words.append(NormalizedWord(time: start, endTime: end, text: seg))
            cleanParts.append(seg)
        }
        
        return NormalizedLine(
            words: words,
            trailingTimecode: trailing,
            cleanText: cleanParts.joined(separator: " ")
        )
    }
    
    // MARK: - Нормализатор B (тег перед словом)
    
    private static func normalizeB(
        text: String,
        nsText: NSString,
        matches: [NSTextCheckingResult],
        anchor: TimeInterval,
        offsetShift: TimeInterval
    ) -> NormalizedLine {
        guard !matches.isEmpty else {
            return NormalizedLine(words: [], trailingTimecode: nil, cleanText: text)
        }
        
        let timecodes: [TimeInterval] = matches.compactMap {
            parseTimecodeFromMatch($0, nsText: nsText, offsetShift: offsetShift, isStart: true)
        }
        
        var words: [NormalizedWord] = []
        var cleanParts: [String] = []
        var trailing: TimeInterval?
        
        for i in 0..<matches.count {
            let afterPos = matches[i].range.location + matches[i].range.length
            let nextPos = i + 1 < matches.count ? matches[i + 1].range.location : nsText.length
            let wordText = nsText.substring(with: NSRange(location: afterPos, length: nextPos - afterPos))
                .trimmingCharacters(in: .whitespaces)
            
            if wordText.isEmpty {
                // висячий <> в конце — конец последнего слова
                if i == matches.count - 1, i < timecodes.count {
                    trailing = timecodes[i]
                    if !words.isEmpty {
                        words[words.count - 1].endTime = timecodes[i]
                    }
                }
                continue
            }
            
            let start = i < timecodes.count ? timecodes[i] : anchor
            let end: TimeInterval?
            if i + 1 < timecodes.count {
                end = timecodes[i + 1]
            } else {
                end = nil   // защита
            }
            
            cleanParts.append(wordText)
            words.append(NormalizedWord(time: start, endTime: end, text: wordText))
        }
        
        return NormalizedLine(
            words: words,
            trailingTimecode: trailing,
            cleanText: cleanParts.joined(separator: " ")
        )
    }
    
    // MARK: - Нормализатор C (диапазоны)
    
    private static func normalizeC(
        text: String,
        nsText: NSString,
        matches: [NSTextCheckingResult],
        offsetShift: TimeInterval
    ) -> NormalizedLine {
        var words: [NormalizedWord] = []
        var cleanParts: [String] = []
        
        for i in 0..<matches.count {
            let afterPos = matches[i].range.location + matches[i].range.length
            let nextPos = i + 1 < matches.count ? matches[i + 1].range.location : nsText.length
            let wordText = nsText.substring(with: NSRange(location: afterPos, length: nextPos - afterPos))
                .trimmingCharacters(in: .whitespaces)
            
            guard !wordText.isEmpty else { continue }
            
            let start = parseTimecodeFromMatch(matches[i], nsText: nsText, offsetShift: offsetShift, isStart: true)
            let end = parseTimecodeFromMatch(matches[i], nsText: nsText, offsetShift: offsetShift, isStart: false)
            
            guard let s = start else { continue }
            cleanParts.append(wordText)
            words.append(NormalizedWord(time: s, endTime: end, text: wordText))
        }
        
        return NormalizedLine(
            words: words,
            trailingTimecode: nil,
            cleanText: cleanParts.joined(separator: " ")
        )
    }
    
    // MARK: - Защита endTime
    
    private static func fillEndTimes(
        words: inout [LyricsWord],
        trailing: TimeInterval?,
        nextLineTime: TimeInterval?
    ) {
        guard !words.isEmpty else { return }
        
        // Между словами: конец = старт следующего (если ещё не задан)
        for i in 0..<(words.count - 1) where words[i].endTime == nil {
            words[i].endTime = words[i + 1].time
        }
        
        // Последнее слово
        let last = words.count - 1
        if words[last].endTime == nil {
            words[last].endTime = trailing
                ?? nextLineTime
                ?? (words[last].time + 1.0)
        }
    }
    
    // MARK: - Парсинг таймкода из матча
    
    private static func parseTimecodeFromMatch(
        _ match: NSTextCheckingResult,
        nsText: NSString,
        offsetShift: TimeInterval,
        isStart: Bool
    ) -> TimeInterval? {
        // Группы:
        // 1,2,3 — start (mm, ss, fraction)
        // 4,5,6 — end   (mm, ss, fraction)
        let baseIndex = isStart ? 1 : 4
        
        guard match.numberOfRanges > baseIndex + 1,
              match.range(at: baseIndex).location != NSNotFound,
              match.range(at: baseIndex + 1).location != NSNotFound,
              let minutes = Double(nsText.substring(with: match.range(at: baseIndex))),
              let seconds = Double(nsText.substring(with: match.range(at: baseIndex + 1))) else {
            return nil
        }
        
        var total = minutes * 60 + seconds
        
        let fractionIndex = baseIndex + 2
        if fractionIndex < match.numberOfRanges && match.range(at: fractionIndex).location != NSNotFound {
            let fractionString = nsText.substring(with: match.range(at: fractionIndex))
            if let fraction = Double(fractionString) {
                if fractionString.count == 3 {
                    total += fraction / 1000.0
                } else if fractionString.count == 2 {
                    total += fraction / 100.0
                } else {
                    total += fraction / 10.0
                }
            }
        }
        
        return total + offsetShift
    }
    
    // MARK: - Парсинг [] таймкода
    
    private static func parseTimecode(_ timecode: String, offsetShift: TimeInterval = 0) -> TimeInterval? {
        let pattern = #"^(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: timecode, range: NSRange(timecode.startIndex..., in: timecode)) else {
            return nil
        }
        
        let nsString = timecode as NSString
        guard let minutes = Double(nsString.substring(with: match.range(at: 1))),
              let seconds = Double(nsString.substring(with: match.range(at: 2))) else {
            return nil
        }
        
        var total = minutes * 60 + seconds
        
        if match.range(at: 3).location != NSNotFound {
            let fractionString = nsString.substring(with: match.range(at: 3))
            if let fraction = Double(fractionString) {
                if fractionString.count == 3 {
                    total += fraction / 1000.0
                } else if fractionString.count == 2 {
                    total += fraction / 100.0
                } else {
                    total += fraction / 10.0
                }
            }
        }
        
        return total + offsetShift
    }
    
    // MARK: - Основные строки
    
    private static func markMainLines(in lines: inout [LyricsLine]) {
        var timeGroups: [TimeInterval: [Int]] = [:]
        for (index, line) in lines.enumerated() {
            timeGroups[line.time, default: []].append(index)
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
    }
    
    // MARK: - Паузы
    
    private static func calculatePauses(for lines: inout [LyricsLine]) {
        for i in 0..<lines.count where lines[i].text.isEmpty {
            var nextTime: TimeInterval?
            for j in (i + 1)..<lines.count where !lines[j].text.isEmpty {
                nextTime = lines[j].time
                break
            }
            lines[i].pauseUntil = nextTime
        }
    }
    
    // MARK: - Группировка
    
    static func groupLines(_ lines: [LyricsLine]) -> [LyricsGroup] {
        var groups: [TimeInterval: [LyricsLine]] = [:]
        
        for line in lines {
            groups[line.time, default: []].append(line)
        }
        
        return groups
            .sorted { $0.key < $1.key }
            .map { LyricsGroup(time: $0.key, lines: $0.value, pauseUntil: $0.value.first?.pauseUntil) }
    }
    
    // MARK: - Статистика по тегам
    
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
