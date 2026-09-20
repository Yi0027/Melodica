// Views/LiquidGlass/LiquidGlassTileDrawView.swift
import AppKit

final class LiquidGlassTileDrawView: NSView {
    var artwork: CGImage?        { didSet { needsDisplay = true } }
    var placeholderSymbol: String = "music.note" { didSet { needsDisplay = true } }
    var title: String = ""       { didSet { needsDisplay = true } }
    var subtitle: String = ""    { didSet { needsDisplay = true } }
    var tertiary: String = ""    { didSet { needsDisplay = true } }   // например "12 tracks"
    
    override var isFlipped: Bool { true }
    
    private static let symbolCache = NSCache<NSString, NSImage>()
    
    // Шрифты и цвета под стиль LiquidGlass
    private static let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.labelColor
    ]
    private static let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    private static let tertiaryAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9),
        .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7)
    ]
    
    override func draw(_ dirtyRect: NSRect) {
        let padding: CGFloat = 0
        let artSide = bounds.width
        let artRect = NSRect(x: padding, y: padding, width: artSide, height: artSide)
        let corner: CGFloat = 8
        
        // 1. Обложка
        let clipPath = NSBezierPath(roundedRect: artRect, xRadius: corner, yRadius: corner)
        
        if let artwork {
            let nsImage = NSImage(cgImage: artwork, size: NSSize(width: artwork.width, height: artwork.height))
            NSGraphicsContext.saveGraphicsState()
            clipPath.addClip()
            nsImage.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // Placeholder фон
            NSColor.gray.withAlphaComponent(0.15).setFill()
            clipPath.fill()
            
            if let symbol = Self.symbol(named: placeholderSymbol, pointSize: artSide * 0.25) {
                let s = symbol.size
                let origin = NSPoint(
                    x: artRect.midX - s.width / 2,
                    y: artRect.midY - s.height / 2
                )
                symbol.draw(in: NSRect(origin: origin, size: s),
                            from: .zero, operation: .sourceOver,
                            fraction: 1.0, respectFlipped: true, hints: nil)
            }
        }
        
        // 2. Тексты под обложкой
        var y = artRect.maxY + 6
        let textX: CGFloat = 0
        let textW = bounds.width
        
        if !title.isEmpty {
            y = drawText(title, attrs: Self.titleAttrs, x: textX, y: y, width: textW, maxLines: 1)
        }
        if !subtitle.isEmpty {
            y = drawText(subtitle, attrs: Self.subtitleAttrs, x: textX, y: y + 1, width: textW, maxLines: 1)
        }
        if !tertiary.isEmpty {
            _ = drawText(tertiary, attrs: Self.tertiaryAttrs, x: textX, y: y + 1, width: textW, maxLines: 1)
        }
    }
    
    @discardableResult
    private func drawText(_ string: String, attrs: [NSAttributedString.Key: Any],
                          x: CGFloat, y: CGFloat, width: CGFloat, maxLines: Int) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byTruncatingTail
        
        var merged = attrs
        merged[.paragraphStyle] = style
        
        let attributed = NSAttributedString(string: string, attributes: merged)
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = min(bounding.height, CGFloat(maxLines) * 14)
        attributed.draw(with: CGRect(x: x, y: y, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return y + height
    }
    
    private static func symbol(named name: String, pointSize: CGFloat) -> NSImage? {
        let key = "\(name)-\(Int(pointSize))-accent" as NSString
        if let cached = symbolCache.object(forKey: key) { return cached }
        
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.controlAccentColor.withAlphaComponent(0.75)]))
        
        guard let colored = image.withSymbolConfiguration(config) else { return nil }
        
        symbolCache.setObject(colored, forKey: key)
        return colored
    }
}

// MARK: - Collection Item

final class LiquidGlassTileCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LiquidGlassTileCollectionViewItem")
    
    let drawView = LiquidGlassTileDrawView()
    private var loadTask: Task<Void, Never>?
    private var currentURL: URL?
    
    override func loadView() {
        view = drawView
    }
    
    func configure(
        title: String,
        subtitle: String,
        tertiary: String,
        placeholderSymbol: String,
        artworkURL: URL?,
        maxPixel: CGFloat
    ) {
        drawView.title = title
        drawView.subtitle = subtitle
        drawView.tertiary = tertiary
        drawView.placeholderSymbol = placeholderSymbol
        loadArtwork(from: artworkURL, maxPixel: maxPixel)
    }
    
    private func loadArtwork(from url: URL?, maxPixel: CGFloat) {
        guard currentURL != url else { return }
        currentURL = url
        loadTask?.cancel()
        
        guard let url else {
            drawView.artwork = nil
            return
        }
        
        if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixel) {
            drawView.artwork = cached.cgImage(forProposedRect: nil, context: nil, hints: nil)
            return
        }
        
        drawView.artwork = nil
        loadTask = Task { [weak self] in
            let loaded = await ImageCache.shared.loadImage(for: url, maxPixelSize: maxPixel)
            if Task.isCancelled { return }
            let cg = loaded?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            await MainActor.run {
                guard let self, self.currentURL == url else { return }
                self.drawView.artwork = cg
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        drawView.artwork = nil
        drawView.title = ""
        drawView.subtitle = ""
        drawView.tertiary = ""
        drawView.placeholderSymbol = "music.note"
    }
}
