// Services,ImageCache.swift
import AppKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    
    private var memoryCache: [URL: NSImage] = [:]
    private var accessOrder: [URL] = []
    private let maxMemoryImages = 50
    
    static func cacheDirectory() -> URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
            .appendingPathComponent("ArtworkCache")
        
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }
    
    func image(for url: URL) -> NSImage? {
        if let cached = memoryCache[url] {
            accessOrder.removeAll { $0 == url }
            accessOrder.append(url)
            return cached
        }
        
        guard let image = NSImage(contentsOf: url) else { return nil }
        
        while memoryCache.count >= maxMemoryImages {
            if let oldest = accessOrder.first {
                memoryCache.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }
        }
        
        memoryCache[url] = image
        accessOrder.append(url)
        return image
    }
    
    func clearMemory() {
        memoryCache.removeAll()
        accessOrder.removeAll()
    }
    
    func clearAll() {
        memoryCache.removeAll()
        accessOrder.removeAll()
    }
}

struct CachedImage: View {
    let url: URL?
    let size: CGSize
    var trackId: UUID? = nil
    
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width > 50 ? 8 : 5))
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Сбрасываем перед загрузкой
        await MainActor.run { image = nil }
        
        guard let url = url else { return }
        
        let loaded = await ImageCache.shared.image(for: url)
        guard !Task.isCancelled else { return }
        await MainActor.run { image = loaded }
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
