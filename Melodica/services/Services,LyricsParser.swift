import Foundation
import CoreGraphics

enum LyricsParser {
    @MainActor static var lastMetadata = LyricsMetadata()

    // MARK: - All Supported Tags

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

    // MARK: - Precompiled Regexes (reused across lines)

    private static let timecodeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?$"#)
    }()

    private static let inlineTagRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"<(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?(?:,(\d{1,2}):(\d{1,2})(?:[\.:](\d{1,3}))?)?>"#
        )
    }()

    // MARK: - Find LRC

    nonisolated static func findLyrics(for audioURL: URL) -> URL? {
        let base = audioURL.deletingPathExtension()
        let lrcURL = base.appendingPathExtension("lrc")
        return FileManager.default.fileExists(atPath: lrcURL.path) ? lrcURL : nil
    }

    // MARK: - Parsing

    @MainActor
    static func parse(_ url: URL) -> [LyricsLine] {
        guard var content = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .windowsCP1251))
                ?? (try? String(contentsOf: url, encoding: .windowsCP1252))
                ?? (try? String(contentsOf: url, encoding: .shiftJIS))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                ?? (try? String(contentsOf: url, encoding: .ascii))
        else {
            lastMetadata = LyricsMetadata()
            return []
        }

        // Remove UTF-8 BOM if present so the first line with metadata
        // (or timecode) is properly recognized.
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }

        return parseContent(content)
    }

    // MARK: - Formats

    private enum LRCFormat {
        case a   // tag AFTER word
        case b   // tag BEFORE word
        case c   // ranges <start,end> (canonical)
    }

    // MARK: - Normalized Models

    private struct NormalizedWord {
        let time: TimeInterval
        var endTime: TimeInterval?
        let text: String
    }

    private struct NormalizedLine {
        let words: [NormalizedWord]
        let trailingTimecode: TimeInterval?   // trailing <...> without text after
        let cleanText: String
    }

    // MARK: - Main Parsing

    @MainActor
    static func parseContent(_ content: String) -> [LyricsLine] {
        let result = parseContentWithMetadata(content)
        lastMetadata = result.metadata
        return result.lines
    }

    static func parseContentWithMetadata(_ content: String) -> (lines: [LyricsLine], metadata: LyricsMetadata) {
        var lines: [LyricsLine] = []
        var metadata = LyricsMetadata()

        let rawLines = expandMultiTimestampLines(content.components(separatedBy: .newlines))

        // 1. Collect global offset from entire file
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

        // 2. Anchors and next anchors
        let (anchors, nextAnchorTimes) = computeAnchors(rawLines: rawLines, offsetShift: offsetShift)

        // 3. Main pass
        for (lineIndex, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Metadata
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

                    if key.allSatisfy({ $0.isLetter }) {
                        switch key.lowercased() {
                        case "ti": metadata.title = value
                        case "ar": metadata.artist = value
                        case "al": metadata.album = value
                        case "by": metadata.author = value
                        case "length": metadata.length = value
                        default: break
                        }
                        continue
                    }
                }
            }

            guard let anchor = anchors[lineIndex] else { continue }

            // Text after the last []
            let textStartIndex = rawLine.lastIndex(of: "]").map { rawLine.index(after: $0) } ?? rawLine.startIndex
            var remainder = String(rawLine[textStartIndex...]).trimmingCharacters(in: .whitespaces)

            // Tag <ja> / <trans>, etc.
            let tag: String?
            if remainder.hasPrefix("<"), let tagEnd = remainder.firstIndex(of: ">") {
                let potentialTag = String(remainder[remainder.index(after: remainder.startIndex)..<tagEnd])
                if potentialTag.contains(":") || potentialTag.contains(",") {
                    tag = nil
                } else {
                    tag = potentialTag.lowercased()
                    remainder = String(remainder[remainder.index(after: tagEnd)...]).trimmingCharacters(in: .whitespaces)
                }
            } else {
                tag = nil
            }

            // Word-by-word
            let normalized = parseInlineWords(remainder, baseTime: anchor)

            let isSpecial = tag.map { specialTags.contains($0) } ?? false
            let isMain = tag == nil || tag == "orig"

            let words = buildLyricsWords(from: normalized.words, nextAnchorTime: nextAnchorTimes[lineIndex])

            let line = LyricsLine(
                time: anchor,
                endTime: nextAnchorTimes[lineIndex],
                text: normalized.cleanText,
                words: words,
                tag: tag,
                isSpecial: isSpecial,
                isMain: isMain
            )
            lines.append(line)
        }

        // Sort by time
        lines.sort { a, b in
            if a.time != b.time { return a.time < b.time }
            if a.isMain != b.isMain { return a.isMain }
            return (a.tag ?? "") < (b.tag ?? "")
        }

        if let first = lines.first, first.time > 0 {
            lines.insert(LyricsLine(time: 0, endTime: first.time, text: "", isMain: true, pauseUntil: first.time), at: 0)
        }

        // Завершающая пустая строка — если в конце нет пустой строки
        if let last = lines.last, !last.text.isEmpty {
            let endTime = last.words.compactMap({ $0.endTime }).max() ?? last.endTime
            if let endTime = endTime {
                lines.append(LyricsLine(time: endTime, text: "", isMain: true))
            }
        }

        calculatePauses(for: &lines)

        return (lines, metadata)
    }

    private static func expandMultiTimestampLines(_ rawLines: [String]) -> [String] {
        var expanded: [String] = []
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else {
                expanded.append(raw)
                continue
            }

            var search = trimmed[...]
            var timecodes: [String] = []

            while search.hasPrefix("["), let close = search.firstIndex(of: "]") {
                let inside = String(search[search.index(after: search.startIndex)..<close])
                if parseTimecode(inside) != nil {
                    timecodes.append(inside)
                    search = search[search.index(after: close)...]
                    let stripped = search.trimmingCharacters(in: .whitespaces)
                    if stripped.hasPrefix("[") {
                        search = stripped[...]
                    }
                } else {
                    break
                }
            }

            if timecodes.count > 1 {
                let remainder = String(search)
                for tc in timecodes {
                    expanded.append("[\(tc)]\(remainder)")
                }
            } else {
                expanded.append(raw)
            }
        }
        return expanded
    }

    private static func calculatePauses(for lines: inout [LyricsLine]) {
        for i in 0..<lines.count where lines[i].text.isEmpty && lines[i].words.isEmpty {
            var nextTime: TimeInterval?
            for j in (i + 1)..<lines.count where !lines[j].text.isEmpty || !lines[j].words.isEmpty {
                nextTime = lines[j].time
                break
            }
            if lines[i].pauseUntil == nil {
                lines[i].pauseUntil = nextTime
            }
            if lines[i].endTime == nil {
                lines[i].endTime = nextTime
            }
        }
    }

    // MARK: - Anchors Computation

    private static func computeAnchors(
        rawLines: [String],
        offsetShift: TimeInterval
    ) -> (anchors: [Int: TimeInterval], nextAnchorTimes: [Int: TimeInterval]) {
        var anchors: [Int: TimeInterval] = [:]

        for (i, raw) in rawLines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }

            var search = trimmed[...]
            var bestTime: TimeInterval?

            while search.hasPrefix("["), let close = search.firstIndex(of: "]") {
                let inside = String(search[search.index(after: search.startIndex)..<close])
                if let t = parseTimecode(inside) {
                    bestTime = max(0, t + offsetShift)
                    break
                }
                search = search[search.index(after: close)...].trimmingCharacters(in: .whitespaces)[...]
            }

            if let t = bestTime {
                anchors[i] = t
            }
        }

        // Calculate nextAnchorTimes: for each anchor, find time of next anchor
        var nextTimes: [Int: TimeInterval] = [:]
        let sortedIndices = anchors.keys.sorted { anchors[$0]! < anchors[$1]! }

        for (order, lineIdx) in sortedIndices.enumerated() {
            let thisTime = anchors[lineIdx]!
            var nextT: TimeInterval?
            for laterIdx in sortedIndices[(order + 1)...] {
                let t = anchors[laterIdx]!
                if t > thisTime {
                    nextT = t
                    break
                }
            }
            nextTimes[lineIdx] = nextT
        }

        return (anchors, nextTimes)
    }

    // MARK: - Inline Word Parsing

    private static func parseInlineWords(_ text: String, baseTime: TimeInterval) -> NormalizedLine {
        guard let regex = inlineTagRegex else {
            return NormalizedLine(words: [], trailingTimecode: nil, cleanText: text)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            return NormalizedLine(words: [], trailingTimecode: nil, cleanText: text)
        }

        let format = detectFormat(matches: matches, textLength: nsText.length)

        switch format {
        case .c: return parseFormatC(text: text, matches: matches, baseTime: baseTime)
        case .a: return parseFormatA(text: text, matches: matches, baseTime: baseTime)
        case .b: return parseFormatB(text: text, matches: matches, baseTime: baseTime)
        }
    }

    private static func detectFormat(matches: [NSTextCheckingResult], textLength: Int) -> LRCFormat {
        for m in matches {
            if m.range(at: 4).location != NSNotFound {
                return .c
            }
        }
        if let first = matches.first, first.range.location == 0 {
            return .b
        }
        return .a
    }

    // MARK: - Format C: <start,end>

    private static func parseFormatC(
        text: String,
        matches: [NSTextCheckingResult],
        baseTime: TimeInterval
    ) -> NormalizedLine {
        let nsText = text as NSString
        var words: [NormalizedWord] = []
        var cleanPieces: [String] = []

        for i in 0..<matches.count {
            let m = matches[i]
            let startT = parseTimecode(from: m, startGroup: 1, in: nsText) ?? baseTime
            let endT = parseTimecode(from: m, startGroup: 4, in: nsText)

            let wordStart = m.range.location + m.range.length
            let wordEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let wordRange = NSRange(location: wordStart, length: max(0, wordEnd - wordStart))
            let wordText = nsText.substring(with: wordRange)

            if !wordText.isEmpty {
                words.append(NormalizedWord(time: startT, endTime: endT, text: wordText))
                cleanPieces.append(wordText)
            }
        }

        return NormalizedLine(words: words, trailingTimecode: nil, cleanText: cleanPieces.joined())
    }

    // MARK: - Format A: word <time>

    private static func parseFormatA(
        text: String,
        matches: [NSTextCheckingResult],
        baseTime: TimeInterval
    ) -> NormalizedLine {
        let nsText = text as NSString
        var words: [NormalizedWord] = []
        var cleanPieces: [String] = []

        var lastEnd = 0
        var prevTime = baseTime

        for (i, m) in matches.enumerated() {
            let tagTime = parseTimecode(from: m, startGroup: 1, in: nsText) ?? prevTime
            let wordRange = NSRange(location: lastEnd, length: m.range.location - lastEnd)
            let wordText = nsText.substring(with: wordRange)

            if !wordText.isEmpty {
                words.append(NormalizedWord(
                    time: i == 0 ? baseTime : prevTime,
                    endTime: tagTime,
                    text: wordText
                ))
                cleanPieces.append(wordText)
            }

            prevTime = tagTime
            lastEnd = m.range.location + m.range.length
        }

        let trailingText = nsText.substring(from: lastEnd)
        let trailingTimecode: TimeInterval? = lastEnd < nsText.length ? nil : prevTime

        if !trailingText.isEmpty {
            words.append(NormalizedWord(time: prevTime, endTime: nil, text: trailingText))
            cleanPieces.append(trailingText)
        }

        return NormalizedLine(
            words: words,
            trailingTimecode: trailingTimecode,
            cleanText: cleanPieces.joined()
        )
    }

    // MARK: - Format B: <time> word

    private static func parseFormatB(
        text: String,
        matches: [NSTextCheckingResult],
        baseTime: TimeInterval
    ) -> NormalizedLine {
        let nsText = text as NSString
        var words: [NormalizedWord] = []
        var cleanPieces: [String] = []

        for i in 0..<matches.count {
            let m = matches[i]
            let startT = parseTimecode(from: m, startGroup: 1, in: nsText) ?? baseTime

            let wordStart = m.range.location + m.range.length
            let wordEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let wordRange = NSRange(location: wordStart, length: max(0, wordEnd - wordStart))
            let wordText = nsText.substring(with: wordRange)

            let nextT: TimeInterval? = (i + 1 < matches.count)
                ? parseTimecode(from: matches[i + 1], startGroup: 1, in: nsText)
                : nil

            if !wordText.isEmpty {
                words.append(NormalizedWord(time: startT, endTime: nextT, text: wordText))
                cleanPieces.append(wordText)
            }
        }

        return NormalizedLine(words: words, trailingTimecode: nil, cleanText: cleanPieces.joined())
    }

    // MARK: - Build LyricsWord

    private static func buildLyricsWords(
        from normalized: [NormalizedWord],
        nextAnchorTime: TimeInterval?
    ) -> [LyricsWord] {
        guard !normalized.isEmpty else { return [] }

        var result: [LyricsWord] = []

        for (i, nw) in normalized.enumerated() {
            var w = LyricsWord(time: nw.time, text: nw.text, endTime: nw.endTime)

            if w.endTime == nil {
                if i + 1 < normalized.count {
                    w.endTime = normalized[i + 1].time
                } else if let nat = nextAnchorTime {
                    let totalLen = max(0, nat - nw.time)
                    let sensibleMax = min(totalLen, max(Double(nw.text.count) * 0.25, 0.4))
                    w.endTime = nw.time + sensibleMax
                } else {
                    w.endTime = nw.time + max(Double(nw.text.count) * 0.25, 0.5)
                }
            }

            if let e = w.endTime, e < w.time {
                w.endTime = w.time + 0.1
            }

            result.append(w)
        }

        return result
    }

    // MARK: - Timecode Parsing

    private static func parseTimecode(_ string: String) -> TimeInterval? {
        guard let regex = timecodeRegex else { return nil }
        let ns = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return parseTimecode(from: match, startGroup: 1, in: ns)
    }

    private static func parseTimecode(
        from match: NSTextCheckingResult,
        startGroup: Int,
        in nsText: NSString
    ) -> TimeInterval? {
        let minRange = match.range(at: startGroup)
        let secRange = match.range(at: startGroup + 1)
        guard minRange.location != NSNotFound, secRange.location != NSNotFound else { return nil }

        guard let min = Double(nsText.substring(with: minRange)),
              let sec = Double(nsText.substring(with: secRange))
        else { return nil }

        var ms: Double = 0
        let msRange = match.range(at: startGroup + 2)
        if msRange.location != NSNotFound {
            let msStr = nsText.substring(with: msRange)
            if let parsed = Double(msStr) {
                switch msStr.count {
                case 1: ms = parsed / 10.0
                case 2: ms = parsed / 100.0
                case 3: ms = parsed / 1000.0
                default: ms = parsed / pow(10.0, Double(msStr.count))
                }
            }
        }

        return min * 60.0 + sec + ms
    }

    // MARK: - Grouping

    static func groupLines(_ lines: [LyricsLine]) -> [LyricsGroup] {
        var groups: [LyricsGroup] = []
        let threshold = 0.2

        for line in lines {
            if let last = groups.last, abs(last.time - line.time) < threshold {
                groups[groups.count - 1].lines.append(line)
            } else {
                groups.append(LyricsGroup(time: line.time, lines: [line], pauseUntil: line.pauseUntil))
            }
        }

        return groups
    }

    // MARK: - Parse All Tags (for Settings UI)

    @MainActor
    static func parseAllTags(from content: String) -> Set<String> {
        var tags: Set<String> = []
        let regex = try? NSRegularExpression(pattern: #"<([a-zA-Z0-9_-]+)>"#)

        for line in content.components(separatedBy: .newlines) {
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let tagRange = Range(match.range(at: 1), in: line)
            else { continue }
            tags.insert(String(line[tagRange]))
        }

        return tags
    }
}

// MARK: - Lyrics Logic Engine (Shared Technical & Calculation Core)

@MainActor
enum LyricsLogicEngine {
    
    // MARK: - Metadata & Formatting
    
    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    
    static func metadataLines(metadata: LyricsMetadata, settings: SettingsManager = SettingsManager.shared) -> [String] {
        var lines: [String] = []
        let fields: [(String, String?)] = [
            ("title", metadata.title),
            ("artist", metadata.artist),
            ("album", metadata.album),
            ("author", metadata.author),
            ("length", metadata.length)
        ]
        for (key, value) in fields {
            guard let value, !value.isEmpty,
                  settings.lrcMetadataFields[key] ?? false else { continue }
            let label = NSLocalizedString("lrc_meta_\(key)", comment: "")
            lines.append("\(label): \(value)")
        }
        return lines
    }
    
    static func shouldShowMetadata(
        lyrics: [LyricsLine],
        currentTime: TimeInterval,
        userScrolled: Bool,
        isNativeScrolling: Bool = false,
        settings: SettingsManager = SettingsManager.shared
    ) -> Bool {
        guard settings.lrcShowMetadata, !userScrolled, !isNativeScrolling else { return false }
        let lines = metadataLines(metadata: LyricsParser.lastMetadata, settings: settings)
        guard !lines.isEmpty else { return false }
        if settings.lrcMetadataPosition == "before" {
            let firstRealTime = lyrics.first(where: { !$0.text.isEmpty })?.time ?? 0
            return currentTime < firstRealTime
        } else {
            let lastTime = lyrics.last?.time ?? 0
            return currentTime > lastTime
        }
    }
    
    // MARK: - Tags & Advanced Mode
    
    static func isTagEnabled(_ tag: String, settings: SettingsManager = SettingsManager.shared) -> Bool {
        if tag == "trans" && (settings.lrcAutoTranslate || (settings.lrcEnabledTags["trans"] ?? false)) {
            return true
        }
        if tag == "orig" || tag == "inst" {
            return settings.lrcEnabledTags[tag] ?? true
        }
        return settings.lrcEnabledTags[tag] ?? false
    }
    
    static func shouldUseAdvancedMode(lyrics: [LyricsLine], settings: SettingsManager = SettingsManager.shared) -> Bool {
        switch settings.lrcMode {
        case "on": return true
        case "off": return false
        case "auto": return lyrics.contains { $0.tag != nil && $0.tag != "trans" && $0.tag != "orig" }
        default: return false
        }
    }
    
    // MARK: - Grouping & Visible Lines
    
    static func getVisibleLines(from group: LyricsGroup, limit: Int = 5, settings: SettingsManager = SettingsManager.shared) -> [LyricsLine] {
        if let inst = group.lines.first(where: { $0.tag == "inst" }) {
            var instResult: [LyricsLine] = []
            if isTagEnabled("inst", settings: settings) {
                instResult.append(inst)
            }
            // Include translation lines (e.g. "trans" or enabled language tags)
            for line in group.lines where line.tag != "inst" && line.tag != "note" {
                if let tag = line.tag, isTagEnabled(tag, settings: settings) {
                    instResult.append(line)
                }
            }
            if !instResult.isEmpty {
                return Array(instResult.prefix(limit))
            }
        }
        var result: [LyricsLine] = []
        if let mainLine = group.lines.first(where: { ($0.isMain || $0.tag == nil || $0.tag == "orig") && ($0.tag == nil || isTagEnabled($0.tag!, settings: settings)) }) {
            result.append(mainLine)
        } else if let fallback = group.lines.first(where: { line in
            guard let tag = line.tag else { return true }
            return !LyricsParser.specialTags.contains(tag)
        }) {
            var mainFallback = fallback
            mainFallback.isMain = true
            result.append(mainFallback)
        }
        let tagGroups: [[LyricsLine]] = [
            group.lines.filter { LyricsParser.pronunciationTags.contains($0.tag ?? "") && isTagEnabled($0.tag!, settings: settings) },
            group.lines.filter { $0.tag == "trans" && isTagEnabled("trans", settings: settings) },
            group.lines.filter { LyricsParser.languageTags.contains($0.tag ?? "") && isTagEnabled($0.tag!, settings: settings) },
            group.lines.filter { LyricsParser.specialTags.contains($0.tag ?? "") && isTagEnabled($0.tag!, settings: settings) && !["inst", "orig", "trans", "note"].contains($0.tag ?? "") }
        ]
        for tagGroup in tagGroups {
            for line in tagGroup where result.count < limit && !result.contains(where: { $0.id == line.id }) {
                result.append(line)
            }
        }
        return Array(result.prefix(limit))
    }
    
    static func buildGroups(from lyrics: [LyricsLine], settings: SettingsManager = SettingsManager.shared) -> (groups: [LyricsGroup], useAdvancedMode: Bool) {
        var groups = LyricsParser.groupLines(lyrics).filter { group in
            !getVisibleLines(from: group, limit: 5, settings: settings).isEmpty
        }
        for i in 0..<groups.count where groups[i].lines.contains(where: { $0.tag == "inst" || ($0.text.isEmpty && $0.words.isEmpty) }) {
            var nextTime: TimeInterval?
            for j in (i + 1)..<groups.count {
                let nextLines = getVisibleLines(from: groups[j], limit: 5, settings: settings)
                if !nextLines.isEmpty && !nextLines.contains(where: { $0.tag == "inst" || ($0.text.isEmpty && $0.words.isEmpty) }) {
                    nextTime = groups[j].time
                    break
                }
            }
            if groups[i].pauseUntil == nil {
                groups[i].pauseUntil = nextTime
            }
        }
        let useAdvanced = shouldUseAdvancedMode(lyrics: lyrics, settings: settings)
        return (groups, useAdvanced)
    }
    
    // MARK: - Layout Calculation
    
    static func calculateLayouts(
        lyrics: [LyricsLine],
        width: CGFloat,
        settings: SettingsManager = SettingsManager.shared,
        measureGroupHeight: (_ lines: [LyricsLine], _ availableWidth: CGFloat, _ settings: SettingsManager) -> CGFloat
    ) -> (layouts: [LyricsLineLayout], totalContentHeight: CGFloat, groups: [LyricsGroup], useAdvancedMode: Bool) {
        guard width > 0 else { return ([], 0, [], false) }
        let (groups, useAdvanced) = buildGroups(from: lyrics, settings: settings)
        
        let contentInsetTop: CGFloat = 15
        let contentInsetBottom: CGFloat = 60
        let groupSpacing: CGFloat = 32
        var currentY: CGFloat = contentInsetTop
        var layouts: [LyricsLineLayout] = []
        
        if useAdvanced {
            let availableWidth = max(width - 32, 1)
            layouts = groups.map { group in
                var lines = getVisibleLines(from: group, limit: 5, settings: settings)
                if let noteLine = group.lines.first(where: { $0.tag == "note" && isTagEnabled("note", settings: settings) }) {
                    lines.append(noteLine)
                }
                if let instIndex = lines.firstIndex(where: { $0.tag == "inst" }) {
                    lines[instIndex].pauseUntil = group.pauseUntil ?? lines[instIndex].pauseUntil
                }
                if let emptyIndex = lines.firstIndex(where: { $0.text.isEmpty && $0.words.isEmpty }) {
                    lines[emptyIndex].pauseUntil = group.pauseUntil ?? lines[emptyIndex].pauseUntil
                }
                let visibleLines = lines.filter { $0.tag != "note" }
                let height = measureGroupHeight(visibleLines, availableWidth, settings)
                let layout = LyricsLineLayout(lines: lines, yPosition: currentY, height: height)
                currentY += height + groupSpacing
                return layout
            }
        } else {
            let availableWidth = max(width - 32, 1)
            let includeTrans = isTagEnabled("trans", settings: settings)
            var layoutsList: [LyricsLineLayout] = []
            var i = 0
            while i < lyrics.count {
                let line = lyrics[i]
                if line.tag == "trans" {
                    i += 1
                    continue
                }
                var pairedLines = [line]
                if includeTrans && (i + 1) < lyrics.count && lyrics[i + 1].tag == "trans" {
                    pairedLines.append(lyrics[i + 1])
                    i += 1
                }
                let height = measureGroupHeight(pairedLines, availableWidth, settings)
                let layout = LyricsLineLayout(lines: pairedLines, yPosition: currentY, height: height)
                currentY += height + groupSpacing
                layoutsList.append(layout)
                i += 1
            }
            layouts = layoutsList
        }
        let totalHeight = max(0, currentY - groupSpacing) + contentInsetBottom
        return (layouts, totalHeight, groups, useAdvanced)
    }
    
    // MARK: - Time Sync & Binary Search
    
    static func findCurrentIndex(for currentTime: TimeInterval, in layouts: [LyricsLineLayout]) -> Int {
        guard !layouts.isEmpty else { return -1 }
        if currentTime < (layouts.first?.lines.first?.time ?? 0) {
            return 0
        }
        var lo = 0
        var hi = layouts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let t = layouts[mid].lines.first?.time ?? 0
            if currentTime >= t {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return max(0, lo - 1)
    }
    
    static func getRemainingTime(for line: LyricsLine, currentTime: TimeInterval) -> String {
        guard let until = line.pauseUntil else { return "♪" }
        let remaining = max(0.0, until - currentTime)
        return remaining > 0 ? String(format: "♪ %0.1fs", remaining) : "♪"
    }
}
