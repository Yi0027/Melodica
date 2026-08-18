// Models,LyricsLine.swift
import Foundation

struct LyricsLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    let tag: String?          // <ja>, <en>, <orig>, <trans> и т.д.
    let isSpecial: Bool
    var isMain: Bool = false // <inst>, <bg>, <chord> — не обычный текст
    var pauseUntil: TimeInterval?
    
    init(time: TimeInterval, text: String, tag: String? = nil, isSpecial: Bool = false, isMain: Bool = false, pauseUntil: TimeInterval? = nil) {
        self.time = time
        self.text = text
        self.tag = tag
        self.isSpecial = isSpecial
        self.isMain = isMain
        self.pauseUntil = pauseUntil
    }
}

// MARK: - Группировка строк с одинаковым временем
struct LyricsGroup: Identifiable {
    let id = UUID()
    let time: TimeInterval
    var lines: [LyricsLine]
    var pauseUntil: TimeInterval?
}
// MARK: - Метаданные LRC
struct LyricsMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var author: String?
    var length: TimeInterval?
}
