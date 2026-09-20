// Models,Track.swift
import Foundation
import AppKit
import CryptoKit

struct Track: Identifiable, Hashable, Codable {
    var id = UUID()
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
    var rating: Int?
    var albumArtURL: URL?
    var replayGain: Float?
    var replayGainPeak: Float?
    var replayGainAlbum: Float?
    var replayGainAlbumPeak: Float?
    var lyricsURL: URL?
    var unsyncedLyrics: String?
    var cueStartTime: TimeInterval?
    var smartHash: String?
    
    var hasLyrics: Bool { lyricsURL != nil || unsyncedLyrics != nil }
    
    var starRating: Int {              
        guard let r = rating, r > 0 else { return 0 }
        if r <= 51  { return 1 }
        if r <= 102 { return 2 }
        if r <= 153 { return 3 }
        if r <= 204 { return 4 }
        return 5
    }
    
    enum SortField: String, CaseIterable {
        case recommendations
        case title
        case artist
        case album
        case genre
        case year
        case rating
        case duration
        case playlists
        case smart
        case cue
    }
    
    func thumbURL(size: String) -> URL? {
        guard let artURL = albumArtURL else { return nil }
        let hash = artURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "melodica_art_", with: "")
        let thumbDir = ImageCache.cacheDirectory()
            .appendingPathComponent("thumb_\(size)")
        let thumbFile = thumbDir.appendingPathComponent("melodica_thumb_\(hash).jpg")
        
        // Ленивое создание миниатюры
        if !FileManager.default.fileExists(atPath: thumbFile.path),
           let image = NSImage(contentsOf: artURL) {
            try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
            let sizeValue = CGFloat(Int(size) ?? 64)
            let scale = min(sizeValue / image.size.width, sizeValue / image.size.height, 1.0)
            let thumb = NSImage(size: NSSize(width: image.size.width * scale, height: image.size.height * scale))
            thumb.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumb.size), from: .zero, operation: .copy, fraction: 1.0)
            thumb.unlockFocus()
            if let tiff = thumb.tiffRepresentation,
               let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                try? jpeg.write(to: thumbFile)
            }
        }
        
        return thumbFile
    }
}
extension Track {
    /// Детерминированный UUID от строки. Используется для cue-треков,
    /// чтобы `id` оставался стабильным между пересозданиями.
    static func stableUUID(from string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex.prefix(32))
        let uuidString = "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
