// Models,Track.swift
import Foundation
import AppKit

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileName: String
    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var year: Int?
    var duration: TimeInterval
    var trackNumber: Int?
    var genre: String?
    var albumArtURL: URL?
    var replayGain: Float?
    var lyricsURL: URL?
    var unsyncedLyrics: String?
    
    var hasLyrics: Bool { lyricsURL != nil || unsyncedLyrics != nil }
    
    enum SortField: String, CaseIterable {
        case title = "Название"
        case artist = "Исполнитель"
        case album = "Альбом"
        case genre = "Жанр"
        case year = "Год"
        case duration = "Длительность"
        case playlists = "Плейлисты"  // ✅
    }
}
