
//  Services,UserArtworkManager.swift
import Foundation
import AppKit
import CryptoKit

enum UserArtworkManager {

    enum ArtworkType: Identifiable {
        case artist(String)
        case genre(String)
        case playlist(String)
        case smartPlaylist(UUID)

        var id: String { identifier }

        var folderName: String {
            switch self {
            case .artist: return "artist"
            case .genre: return "genre"
            case .playlist: return "playlist"
            case .smartPlaylist: return "smart"
            }
        }

        var identifier: String {
            switch self {
            case .artist(let name): return "artist:\(name)"
            case .genre(let name): return "genre:\(name)"
            case .playlist(let name): return "playlist:\(name)"
            case .smartPlaylist(let id): return "smart:\(id.uuidString)"
            }
        }
    }

    // MARK: - Save

    static func save(_ image: NSImage, for type: ArtworkType) -> URL? {
        guard let data = jpegData(from: image) else { return nil }

        let url = fileURL(for: type)
        try? data.write(to: url, options: .atomicWrite)
        return url
    }

    // MARK: - Load

    static func load(for type: ArtworkType) -> NSImage? {
        let url = fileURL(for: type)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Downsample через ImageIO — оригинал в память не попадает
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Delete

    static func delete(for type: ArtworkType) {
        let url = fileURL(for: type)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers
    /// Возвращает URL кастомного артворка, если он существует. Для сеток.
    static func imageURL(for type: ArtworkType) -> URL? {
        let url = fileURL(for: type)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func fileURL(for type: ArtworkType) -> URL {
        let folder = baseFolder().appendingPathComponent(type.folderName)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let hash = SHA256.hash(data: Data(type.identifier.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        return folder.appendingPathComponent("\(hash).jpg")
    }

    private static func baseFolder() -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
            .appendingPathComponent("artwork")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
