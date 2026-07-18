// Models,Track.swift
import Foundation
import AppKit

struct Track: Identifiable, Hashable, Codable {
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
    var replayGainPeak: Float?
    var replayGainAlbum: Float?
    var replayGainAlbumPeak: Float?
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
        case playlists = "Плейлисты"
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
