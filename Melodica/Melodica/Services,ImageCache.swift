// Services,ImageCache.swift
import AppKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    
    private var memoryCache: [URL: NSImage] = [:]
    private let maxMemoryImages = 50
    
    func image(for url: URL) -> NSImage? {
        if let cached = memoryCache[url] {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        
        if memoryCache.count >= maxMemoryImages {
            memoryCache.removeAll()
        }
        memoryCache[url] = image
        return image
    }
    
    func clearAll() {   
        memoryCache.removeAll()
    }
}

struct CachedImage: View {
    let url: URL?
    let size: CGSize
    var trackId: UUID? = nil  // При смене трека — сбрасываем
    
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    
    var body: some View {
        Group {
            if let nsImage = image, loadedURL == url {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
                    .task(id: trackId) {
                        // task(id:) перезапускается при смене trackId
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        image = nil
        loadedURL = nil
        guard let url = url else { return }
        let loaded = await ImageCache.shared.image(for: url)
        await MainActor.run {
            image = loaded
            loadedURL = url
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
        .frame(width: size.width, height: size.height)
    }
}
