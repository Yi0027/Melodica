// Services/ImageCache.swift
import AppKit
import SwiftUI
import ImageIO

final class ImageCache {
    static let shared = ImageCache()

    // Ключ = (URL, maxPixelSize).
    private final class CacheKey: NSObject {
        let url: NSURL
        let size: CGFloat
        init(_ url: NSURL, _ size: CGFloat) { self.url = url; self.size = size }
        override var hash: Int { url.hash ^ Int(size) }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return other.url == url && other.size == size
        }
    }

    private let cache = NSCache<CacheKey, NSImage>()
    private let queue = DispatchQueue(
        label: "melodica.imagecache.downsample",
        qos: .userInitiated
    )

    private init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 80
    }

    static func cacheDirectory() -> URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
            .appendingPathComponent("ArtworkCache")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    /// Размер обязателен — иначе можно получить картинку другого размера
    /// и растянуть её (мыло). Именно эта legacy-перегрузка была источником бага.
    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        cache.object(forKey: CacheKey(url as NSURL, maxPixelSize))
    }

    /// Загружает с диска, уменьшая до maxPixelSize.
    func loadImage(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = CacheKey(url as NSURL, maxPixelSize)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: NSImage? = await withCheckedContinuation { cont in
            queue.async {
                let img = Self.downsample(url: url, maxPixelSize: maxPixelSize)
                cont.resume(returning: img)
            }
        }

        if Task.isCancelled { return nil }

        if let image {
            let cost: Int
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                cost = cg.bytesPerRow * cg.height
            } else {
                cost = Int(image.size.width * image.size.height * 4)
            }
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    /// ImageIO: грузит сразу уменьшенную версию, оригинал в память не попадает.
    private static func downsample(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let maxPx = max(maxPixelSize, 1)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func clearMemory() { cache.removeAllObjects() }
    func clearAll() { cache.removeAllObjects() }
}

struct CachedImage: View {
    let url: URL?
    let size: CGSize
    var trackId: UUID? = nil

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width > 50 ? 8 : 5))
        .task(id: url) {
            guard let url else { image = nil; return }

            let maxPixel = max(size.width, size.height) * 2

            if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixel) {
                image = cached
                return
            }

            let loaded = await ImageCache.shared.loadImage(for: url, maxPixelSize: maxPixel)

            if Task.isCancelled { return }
            image = loaded
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width > 50 ? 8 : 5)
                .fill(Color.darkSurface)
            Image(systemName: "music.note")
                .font(.system(size: size.width * 0.25))
                .foregroundColor(.textMuted)
        }
    }
}
