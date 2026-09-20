// Models,TrackMetadataCache.swift
import Foundation

struct TrackMetadataCache: Codable {
    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var year: Int?
    var trackNumber: Int?
    var genre: String?
    var rating: Int?
    var replayGain: Float?
    var replayGainPeak: Float?
    var replayGainAlbum: Float?
    var replayGainAlbumPeak: Float?
    var lyricsURL: String?
    var unsyncedLyrics: String?
    var duration: TimeInterval
}
