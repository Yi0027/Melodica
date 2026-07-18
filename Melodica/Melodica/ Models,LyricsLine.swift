// Models,LyricsLine.swift
import Foundation

struct LyricsLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    var pauseUntil: TimeInterval? 
}
