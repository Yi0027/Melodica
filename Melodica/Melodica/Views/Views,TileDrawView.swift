// Views/TileDrawView.swift
import AppKit

final class TileDrawView: NSView {
    var artwork: CGImage?        { didSet { needsDisplay = true } }
    var placeholderSymbol: String = "music.note" { didSet { needsDisplay = true } }
    var placeholderLabel: String = ""            { didSet { needsDisplay = true } }
    var title: String = ""       { didSet { needsDisplay = true } }
    var subtitle: String = ""    { didSet { needsDisplay = true } }
    var tertiary: String = ""    { didSet { needsDisplay = true } }
    var countText: String = ""   { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private static let symbolCache = NSCache<NSString, NSImage>()

    private static var titleAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
         .foregroundColor: NSColor.textMain]
    }
    private static var subtitleAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10),
         .foregroundColor: NSColor.textMuted]
    }
    private static var tertiaryAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9),
         .foregroundColor: NSColor.textMuted.withAlphaComponent(0.5)]
    }
    private static var countAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9),
         .foregroundColor: NSColor.textMuted.withAlphaComponent(0.6)]
    }

    override func draw(_ dirtyRect: NSRect) {
        // 1. Фон
        let cardPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.darkSurface.setFill()
        cardPath.fill()
        NSColor.accent.withAlphaComponent(0.2).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        // 2. Обложка
        let padding: CGFloat = 10
        let artSide = bounds.width - padding * 2
        let artRect = NSRect(x: padding, y: padding, width: artSide, height: artSide)
        let clipPath = NSBezierPath(roundedRect: artRect, xRadius: 8, yRadius: 8)

        if let artwork {
            let nsImage = NSImage(
                cgImage: artwork,
                size: NSSize(width: artwork.width, height: artwork.height)
            )
            NSGraphicsContext.saveGraphicsState()
            clipPath.addClip()
            nsImage.draw(in: artRect, from: .zero, operation: .sourceOver,
                         fraction: 1.0, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.darkSurface.setFill()
            clipPath.fill()

            if let symbol = Self.symbol(named: placeholderSymbol, pointSize: artSide * 0.25) {
                let s = symbol.size
                let origin = NSPoint(
                    x: artRect.midX - s.width / 2,
                    y: artRect.midY - s.height / 2 - (placeholderLabel.isEmpty ? 0 : 8)
                )
                symbol.draw(in: NSRect(origin: origin, size: s),
                            from: .zero, operation: .sourceOver,
                            fraction: 1.0, respectFlipped: true, hints: nil)
            }
            if !placeholderLabel.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: NSColor.accent.withAlphaComponent(0.6),
                    .paragraphStyle: style,
                ]
                let str = NSAttributedString(string: placeholderLabel, attributes: attrs)
                let size = str.size()
                str.draw(at: NSPoint(x: artRect.midX - size.width / 2, y: artRect.midY + 6))
            }
        }

        // 3. Тексты
        var y = artRect.maxY + 8
        let textX = padding
        let textW = bounds.width - padding * 2

        if !title.isEmpty {
            y = drawText(title, attrs: Self.titleAttrs, x: textX, y: y, width: textW, maxLines: 2)
        }
        if !subtitle.isEmpty {
            y = drawText(subtitle, attrs: Self.subtitleAttrs, x: textX, y: y + 2, width: textW, maxLines: 1)
        }
        if !tertiary.isEmpty {
            y = drawText(tertiary, attrs: Self.tertiaryAttrs, x: textX, y: y + 2, width: textW, maxLines: 1)
        }
        if !countText.isEmpty {
            _ = drawText(countText, attrs: Self.countAttrs, x: textX, y: y + 2, width: textW, maxLines: 1)
        }
    }

    @discardableResult
    private func drawText(
        _ string: String,
        attrs: [NSAttributedString.Key: Any],
        x: CGFloat, y: CGFloat, width: CGFloat, maxLines: Int
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        style.maximumLineHeight = 14

        var merged = attrs
        merged[.paragraphStyle] = style

        let attributed = NSAttributedString(string: string, attributes: merged)
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = min(bounding.height, CGFloat(maxLines) * 14)
        let drawRect = CGRect(x: x, y: y, width: width, height: height)
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return y + height
    }

    private static func symbol(named name: String, pointSize: CGFloat) -> NSImage? {
        let key = "\(name)-\(Int(pointSize))" as NSString
        if let cached = symbolCache.object(forKey: key) { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        symbolCache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Универсальная ячейка

final class TileCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TileCollectionViewItem")

    let drawView = TileDrawView()
    private var loadTask: Task<Void, Never>?
    private var currentURL: URL?

    override func loadView() {
        view = drawView
    }

    func configure(
        title: String, subtitle: String, tertiary: String, count: Int,
        placeholderSymbol: String, placeholderLabel: String,
        artworkURL: URL?, maxPixel: CGFloat,
        menu: NSMenu? = nil
    ) {
        drawView.title = title
        drawView.subtitle = subtitle
        drawView.tertiary = tertiary
        drawView.countText = String(
            format: NSLocalizedString("tracks_count", comment: ""),
            count
        )
        drawView.placeholderSymbol = placeholderSymbol
        drawView.placeholderLabel = placeholderLabel
        view.menu = menu
        loadArtwork(from: artworkURL, maxPixel: maxPixel)
    }

    private func loadArtwork(from url: URL?, maxPixel: CGFloat) {
        guard currentURL != url else { return }
        currentURL = url
        loadTask?.cancel()

        guard let url else { drawView.artwork = nil; return }

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
        view.menu = nil
        drawView.artwork = nil
        drawView.title = ""
        drawView.subtitle = ""
        drawView.tertiary = ""
        drawView.countText = ""
        drawView.placeholderSymbol = "music.note"
        drawView.placeholderLabel = ""
    }
}
