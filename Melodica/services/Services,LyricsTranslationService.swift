// Services,LyricsTranslationService.swift
import Foundation
import SwiftUI
import Combine
import NaturalLanguage
@preconcurrency import Translation

extension TranslationSession.Request: @retroactive @unchecked Sendable {}

extension Notification.Name {
    static let lyricsDidAutoTranslate = Notification.Name("lyricsDidAutoTranslate")
    static let unsyncedLyricsDidAutoTranslate = Notification.Name("unsyncedLyricsDidAutoTranslate")
}

public struct SourceLanguageOption: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }
    
    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

@MainActor
final class LyricsTranslationService: ObservableObject {
    static let shared = LyricsTranslationService()
    
    public struct UnresolvedTranslationRequest: Identifiable, Sendable {
        public let id: UUID
        public let track: Track
        public let lines: [LyricsLine]
        public let text: String?
        public let targetLang: String
        
        public init(track: Track, lines: [LyricsLine], text: String?, targetLang: String) {
            self.id = UUID()
            self.track = track
            self.lines = lines
            self.text = text
            self.targetLang = targetLang
        }
    }
    
    static let availableLanguages: [SourceLanguageOption] = [
        SourceLanguageOption(code: "en", name: "English"),
        SourceLanguageOption(code: "ja", name: "Japanese (日本語)"),
        SourceLanguageOption(code: "ko", name: "Korean (한국어)"),
        SourceLanguageOption(code: "zh-Hans", name: "Chinese (Simplified, 简体中文)"),
        SourceLanguageOption(code: "zh-Hant", name: "Chinese (Traditional, 繁體中文)"),
        SourceLanguageOption(code: "es", name: "Spanish (Español)"),
        SourceLanguageOption(code: "fr", name: "French (Français)"),
        SourceLanguageOption(code: "de", name: "German (Deutsch)"),
        SourceLanguageOption(code: "it", name: "Italian (Italiano)"),
        SourceLanguageOption(code: "pt", name: "Portuguese (Português)"),
        SourceLanguageOption(code: "ru", name: "Russian (Русский)"),
        SourceLanguageOption(code: "uk", name: "Ukrainian (Українська)"),
        SourceLanguageOption(code: "pl", name: "Polish (Polski)"),
        SourceLanguageOption(code: "tr", name: "Turkish (Türkçe)"),
        SourceLanguageOption(code: "ar", name: "Arabic (العربية)"),
        SourceLanguageOption(code: "nl", name: "Dutch (Nederlands)"),
        SourceLanguageOption(code: "id", name: "Indonesian (Bahasa Indonesia)"),
        SourceLanguageOption(code: "vi", name: "Vietnamese (Tiếng Việt)"),
        SourceLanguageOption(code: "th", name: "Thai (ไทย)")
    ]
    
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var isTranslating: Bool = false
    @Published var unresolvedRequest: UnresolvedTranslationRequest?
    
    // In-memory cache for translated lyrics
    private(set) var lrcCache: [String: [LyricsLine]] = [:]
    private(set) var unsyncedCache: [String: String] = [:]
    private(set) var failedKeys: Set<String> = []
    var manualSourceLanguageOverrides: [String: String] = [:]
    
    // Monotonically increasing version counter to guarantee TranslationSession.Configuration
    // always mutates upon request, immediately triggering SwiftUI's .translationTask
    private var sessionVersion: Int = 1
    
    // Pending requests for SwiftUI .translationTask
    private var pendingTrack: Track?
    private var pendingOriginalLines: [LyricsLine] = []
    private var pendingUnsyncedText: String?
    private var pendingTargetLang: String = "en"
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: NSNotification.Name("lrcSettingsChanged"),
            object: nil
        )
    }
    
    @objc private func handleSettingsChanged() {
        clearCache()
    }
    
    @objc func clearCache() {
        lrcCache.removeAll()
        unsyncedCache.removeAll()
        failedKeys.removeAll()
        manualSourceLanguageOverrides.removeAll()
        pendingTrack = nil
        pendingOriginalLines = []
        pendingUnsyncedText = nil
        unresolvedRequest = nil
        isTranslating = false
    }
    
    func cacheKey(for track: Track, targetLang: String, prefix: String = "") -> String {
        let identifier: String
        if let hash = track.smartHash, !hash.isEmpty {
            identifier = hash
        } else if let cueStart = track.cueStartTime {
            identifier = "\(track.url.path)#\(cueStart)"
        } else {
            identifier = track.url.path
        }
        return prefix.isEmpty ? "\(identifier)_\(targetLang)" : "\(prefix)_\(identifier)_\(targetLang)"
    }
    
    func dismissUnresolved() {
        self.unresolvedRequest = nil
    }
    
    func translateUnresolved(withSourceLanguage sourceLang: String) {
        guard let req = unresolvedRequest else { return }
        let track = req.track
        let targetLang = req.targetLang
        let key = cacheKey(for: track, targetLang: targetLang, prefix: req.text != nil ? "unsynced" : "")
        self.manualSourceLanguageOverrides[key] = sourceLang
        self.unresolvedRequest = nil
        
        if let text = req.text {
            requestUnsyncedTranslation(for: track, text: text, sourceLang: sourceLang, targetLang: targetLang)
        } else {
            requestTranslation(for: track, lines: req.lines, sourceLang: sourceLang, targetLang: targetLang)
        }
    }
    
    private func appleLanguage(for code: String) -> Locale.Language {
        let normalized = code.components(separatedBy: "-").first?.lowercased() ?? code.lowercased()
        switch normalized {
        case "zh":
            return Locale.Language(identifier: "zh-Hans")
        default:
            return Locale.Language(identifier: normalized)
        }
    }
    
    private func makeConfiguration(source: String, target: String) -> TranslationSession.Configuration {
        let sourceLocale = appleLanguage(for: source)
        let targetLocale = appleLanguage(for: target)
        var config = TranslationSession.Configuration(
            source: sourceLocale,
            target: targetLocale
        )
        for _ in 0..<sessionVersion {
            config.invalidate()
        }
        sessionVersion += 1
        return config
    }
    
    // MARK: - Language Detection & Checks
    
    func detectLanguage(for lines: [LyricsLine]) -> String? {
        let sampleLines = lines
            .compactMap { line -> String? in
                let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty || t.hasPrefix("[") || t.hasPrefix("(") && t.hasSuffix(")") {
                    return nil
                }
                return t
            }
            .prefix(35)
        
        guard !sampleLines.isEmpty else { return nil }
        let sampleText = sampleLines.joined(separator: "\n")
        return detectLanguage(for: sampleText)
    }
    
    func detectLanguage(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 1. Script-based analysis
        var kanaCount = 0
        var hangulCount = 0
        var cyrillicCount = 0
        var cjkCount = 0
        var arabicCount = 0
        
        for scalar in trimmed.unicodeScalars {
            let v = scalar.value
            if (v >= 0x3040 && v <= 0x309F) || (v >= 0x30A0 && v <= 0x30FF) {
                kanaCount += 1
            } else if (v >= 0xAC00 && v <= 0xD7AF) || (v >= 0x1100 && v <= 0x11FF) {
                hangulCount += 1
            } else if (v >= 0x0400 && v <= 0x04FF) {
                cyrillicCount += 1
            } else if (v >= 0x0600 && v <= 0x06FF) {
                arabicCount += 1
            } else if (v >= 0x4E00 && v <= 0x9FFF) {
                cjkCount += 1
            }
        }
        
        if kanaCount >= 2 { return "ja" }
        if hangulCount >= 2 { return "ko" }
        if arabicCount >= 4 { return "ar" }
        if cjkCount >= 4 && kanaCount == 0 && hangulCount == 0 { return "zh-Hans" }
        
        // 2. NaturalLanguage framework
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let dominant = recognizer.dominantLanguage?.rawValue, dominant != "und" {
            return dominant
        }
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        if let top = hypotheses.max(by: { $0.value < $1.value }), top.value >= 0.35, top.key.rawValue != "und" {
            return top.key.rawValue
        }
        
        if cyrillicCount >= 4 {
            return "ru"
        }
        
        return nil
    }
    
    func shouldTranslate(sourceLang: String, targetLang: String) -> Bool {
        let dominantNormalized = sourceLang.components(separatedBy: "-").first?.lowercased() ?? sourceLang.lowercased()
        let targetNormalized = targetLang.components(separatedBy: "-").first?.lowercased() ?? targetLang.lowercased()
        return dominantNormalized != targetNormalized
    }
    
    // MARK: - Prepare Public API
    
    func prepareLyrics(for track: Track, parsed: [LyricsLine]) -> [LyricsLine] {
        let settings = SettingsManager.shared
        guard settings.lrcAutoTranslate else { return parsed }
        
        let targetLang = settings.language
        let key = cacheKey(for: track, targetLang: targetLang)
        
        // 1. Return from cache if translated
        if let cached = lrcCache[key] {
            return cached
        }
        
        let hasTaggedLines = parsed.contains { $0.tag != nil }
        
        if hasTaggedLines {
            let alreadyHasTrans = parsed.contains { $0.tag == "trans" }
            if alreadyHasTrans { return parsed }
            if failedKeys.contains(key) { return parsed }
            
            // Check manual user selection override
            if let manual = manualSourceLanguageOverrides[key] {
                if shouldTranslate(sourceLang: manual, targetLang: targetLang) {
                    requestTranslation(for: track, lines: parsed, sourceLang: manual, targetLang: targetLang)
                }
                return parsed
            }
            
            if let detected = detectLanguage(for: parsed) {
                if shouldTranslate(sourceLang: detected, targetLang: targetLang) {
                    requestTranslation(for: track, lines: parsed, sourceLang: detected, targetLang: targetLang)
                }
            } else {
                // Language could not be detected: prompt user with pop-up
                self.unresolvedRequest = UnresolvedTranslationRequest(
                    track: track,
                    lines: parsed,
                    text: nil,
                    targetLang: targetLang
                )
            }
            return parsed
        } else {
            // Standard simple LRC
            guard settings.lrcTranslateStandardLRC else { return parsed }
            if failedKeys.contains(key) { return parsed }
            
            if let manual = manualSourceLanguageOverrides[key] {
                if shouldTranslate(sourceLang: manual, targetLang: targetLang) {
                    requestTranslation(for: track, lines: parsed, sourceLang: manual, targetLang: targetLang)
                }
                return parsed
            }
            
            if let detected = detectLanguage(for: parsed) {
                if shouldTranslate(sourceLang: detected, targetLang: targetLang) {
                    requestTranslation(for: track, lines: parsed, sourceLang: detected, targetLang: targetLang)
                }
            } else {
                // Language could not be detected: prompt user with pop-up
                self.unresolvedRequest = UnresolvedTranslationRequest(
                    track: track,
                    lines: parsed,
                    text: nil,
                    targetLang: targetLang
                )
            }
            return parsed
        }
    }
    
    func prepareUnsynced(for track: Track, text: String) -> String {
        let settings = SettingsManager.shared
        guard settings.lrcAutoTranslate && settings.lrcTranslateStandardLRC else { return text }
        
        let targetLang = settings.language
        let key = cacheKey(for: track, targetLang: targetLang, prefix: "unsynced")
        
        if let cached = unsyncedCache[key] {
            return cached
        }
        if failedKeys.contains(key) { return text }
        
        if let manual = manualSourceLanguageOverrides[key] {
            if shouldTranslate(sourceLang: manual, targetLang: targetLang) {
                requestUnsyncedTranslation(for: track, text: text, sourceLang: manual, targetLang: targetLang)
            }
            return text
        }
        
        if let detected = detectLanguage(for: text) {
            if shouldTranslate(sourceLang: detected, targetLang: targetLang) {
                requestUnsyncedTranslation(for: track, text: text, sourceLang: detected, targetLang: targetLang)
            }
        } else {
            self.unresolvedRequest = UnresolvedTranslationRequest(
                track: track,
                lines: [],
                text: text,
                targetLang: targetLang
            )
        }
        return text
    }
    
    // MARK: - Tagged LRC Translation Helpers
    
    func filterTranslatableLines(_ lines: [LyricsLine]) -> [(index: Int, line: LyricsLine)] {
        var result: [(index: Int, line: LyricsLine)] = []
        for (idx, line) in lines.enumerated() {
            let tag = line.tag
            if tag == "inst" || tag == "note" || tag == "trans" { continue }
            if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            result.append((index: idx, line: line))
        }
        return result
    }
    
    func assembleTaggedLyrics(
        original: [LyricsLine],
        translatedIndices: [(index: Int, translatedText: String)]
    ) -> [LyricsLine] {
        var translatedMap: [Int: String] = [:]
        for pair in translatedIndices {
            translatedMap[pair.index] = pair.translatedText
        }
        
        var result: [LyricsLine] = []
        
        for (idx, originalLine) in original.enumerated() {
            var updatedOriginal = originalLine
            if originalLine.tag == nil {
                updatedOriginal.isMain = true
            }
            result.append(updatedOriginal)
            
            if let translation = translatedMap[idx],
               !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let transLine = LyricsLine(
                    time: originalLine.time,
                    endTime: originalLine.endTime,
                    text: translation,
                    words: [],
                    tag: "trans",
                    isSpecial: false,
                    isMain: false,
                    pauseUntil: originalLine.pauseUntil
                )
                result.append(transLine)
            }
        }
        
        return result
    }
    
    // MARK: - Internal Translation Triggers
    
    func requestTranslation(for track: Track, lines: [LyricsLine], sourceLang: String, targetLang: String) {
        let sNorm = sourceLang.components(separatedBy: "-").first?.lowercased() ?? sourceLang.lowercased()
        let tNorm = targetLang.components(separatedBy: "-").first?.lowercased() ?? targetLang.lowercased()
        guard sNorm != tNorm else { return }
        
        self.pendingTrack = track
        self.pendingOriginalLines = lines
        self.pendingUnsyncedText = nil
        self.pendingTargetLang = targetLang
        self.isTranslating = true
        
        // Setting a configuration with an incremented version guarantees SwiftUI triggers .translationTask
        self.translationConfiguration = makeConfiguration(source: sourceLang, target: targetLang)
    }
    
    func requestUnsyncedTranslation(for track: Track, text: String, sourceLang: String, targetLang: String) {
        let sNorm = sourceLang.components(separatedBy: "-").first?.lowercased() ?? sourceLang.lowercased()
        let tNorm = targetLang.components(separatedBy: "-").first?.lowercased() ?? targetLang.lowercased()
        guard sNorm != tNorm else { return }
        
        self.pendingTrack = track
        self.pendingOriginalLines = []
        self.pendingUnsyncedText = text
        self.pendingTargetLang = targetLang
        self.isTranslating = true
        
        self.translationConfiguration = makeConfiguration(source: sourceLang, target: targetLang)
    }
    
    /// Called from SwiftUI's .translationTask modifier
    func handleSession(_ session: TranslationSession) async {
        guard let track = pendingTrack else {
            self.isTranslating = false
            return
        }
        
        let currentTargetLang = pendingTargetLang
        let currentLines = pendingOriginalLines
        let currentUnsynced = pendingUnsyncedText
        
        self.pendingTrack = nil
        self.pendingOriginalLines = []
        self.pendingUnsyncedText = nil
        
        if let unsynced = currentUnsynced {
            await translateUnsynced(session: session, track: track, text: unsynced, targetLang: currentTargetLang)
        } else if !currentLines.isEmpty {
            await translateSynced(session: session, track: track, lines: currentLines, targetLang: currentTargetLang)
        } else {
            self.isTranslating = false
        }
    }
    
    private func translateSynced(
        session: TranslationSession,
        track: Track,
        lines: [LyricsLine],
        targetLang: String
    ) async {
        let filtered = filterTranslatableLines(lines)
        guard !filtered.isEmpty else {
            self.isTranslating = false
            return
        }
        
        let requests = filtered.enumerated().map { (itemIdx, item) in
            TranslationSession.Request(sourceText: item.line.text, clientIdentifier: "\(itemIdx)")
        }
        
        do {
            let responses = try await session.translations(from: requests)
            var translatedPairs: [(index: Int, translatedText: String)] = []
            
            for (itemIdx, item) in filtered.enumerated() {
                if let response = responses.first(where: { $0.clientIdentifier == "\(itemIdx)" }) {
                    translatedPairs.append((index: item.index, translatedText: response.targetText))
                }
            }
            
            let combined = assembleTaggedLyrics(original: lines, translatedIndices: translatedPairs)
            let key = cacheKey(for: track, targetLang: targetLang)
            
            self.lrcCache[key] = combined
            self.isTranslating = false
            NotificationCenter.default.post(
                name: .lyricsDidAutoTranslate,
                object: nil,
                userInfo: ["track": track, "lyrics": combined]
            )
        } catch {
            print("[LyricsTranslation] translateSynced error: \(error)")
            let isCancelled = (error is CancellationError) || ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError)
            if !isCancelled {
                let key = cacheKey(for: track, targetLang: targetLang)
                self.failedKeys.insert(key)
            }
            self.isTranslating = false
        }
    }
    
    private func translateUnsynced(
        session: TranslationSession,
        track: Track,
        text: String,
        targetLang: String
    ) async {
        let lines = text.components(separatedBy: .newlines)
        let requests = lines.enumerated().map { idx, line in
            TranslationSession.Request(sourceText: line.isEmpty ? " " : line, clientIdentifier: "\(idx)")
        }
        
        do {
            let responses = try await session.translations(from: requests)
            var translatedLines: [String] = []
            
            for (idx, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    translatedLines.append("")
                } else if let response = responses.first(where: { $0.clientIdentifier == "\(idx)" }) {
                    translatedLines.append(response.targetText)
                } else {
                    translatedLines.append(line)
                }
            }
            
            let combinedText = translatedLines.joined(separator: "\n")
            let key = cacheKey(for: track, targetLang: targetLang, prefix: "unsynced")
            
            self.unsyncedCache[key] = combinedText
            self.isTranslating = false
            NotificationCenter.default.post(
                name: .unsyncedLyricsDidAutoTranslate,
                object: nil,
                userInfo: ["track": track, "unsyncedLyrics": combinedText]
            )
        } catch {
            print("[LyricsTranslation] translateUnsynced error: \(error)")
            let isCancelled = (error is CancellationError) || ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError)
            if !isCancelled {
                let key = cacheKey(for: track, targetLang: targetLang, prefix: "unsynced")
                self.failedKeys.insert(key)
            }
            self.isTranslating = false
        }
    }
}
