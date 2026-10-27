// Views/LiquidGlass/LiquidGlassTileDrawView.swift
import AppKit

// MARK: - Liquid Glass Play Button

@available(macOS 26.0, *)
final class LiquidGlassPlayButton: NSButton {
    private let visualEffectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?

    var onPlay: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.masksToBounds = false

        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 17
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        addSubview(visualEffectView)

        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.40)
        s.shadowOffset = NSSize(width: 0, height: -2)
        s.shadowBlurRadius = 5
        self.shadow = s

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        let playImg = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .bold))
        iconView.image = playImg
        iconView.contentTintColor = .white
        addSubview(iconView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 1),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])

        target = self
        action = #selector(handleClick)
    }

    @objc private func handleClick() {
        onPlay?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            visualEffectView.animator().layer?.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            visualEffectView.animator().layer?.backgroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Liquid Glass Tile Draw View

@available(macOS 26.0, *)
final class LiquidGlassTileDrawView: NSView {
    var artwork: CGImage? {
        didSet {
            if let artwork {
                cachedArtworkImage = NSImage(cgImage: artwork, size: NSSize(width: artwork.width, height: artwork.height))
            } else {
                cachedArtworkImage = nil
            }
            needsDisplay = true
        }
    }
    private var cachedArtworkImage: NSImage?
    var placeholderSymbol: String = "music.note" { didSet { needsDisplay = true } }
    var title: String = ""       { didSet { needsDisplay = true } }
    var subtitle: String = ""    { didSet { needsDisplay = true } }
    var tertiary: String = ""    { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private let playButton = LiquidGlassPlayButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    private var isScrolling: Bool = false
    private var scrollEndWorkItem: DispatchWorkItem?

    private var clipViewObserver: NSObjectProtocol?
    private var willScrollObserver: NSObjectProtocol?
    private var didScrollObserver: NSObjectProtocol?

    var onPlay: (() -> Void)? {
        didSet {
            playButton.onPlay = onPlay
            if onPlay == nil {
                playButton.isHidden = true
                playButton.alphaValue = 0
            }
        }
    }

    private static let symbolCache = NSCache<NSString, NSImage>()

    private static let titleAttrs: [NSAttributedString.Key: Any] = [        .font: NSFont.systemFont(ofSize: 11, weight: .medium),        .foregroundColor: NSColor.labelColor    ]
    private static let subtitleAttrs: [NSAttributedString.Key: Any] = [        .font: NSFont.systemFont(ofSize: 10),        .foregroundColor: NSColor.secondaryLabelColor    ]
    private static let tertiaryAttrs: [NSAttributedString.Key: Any] = [        .font: NSFont.systemFont(ofSize: 9),        .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.7)    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        playButton.alphaValue = 0
        playButton.isHidden = true
        addSubview(playButton)
    }

    override func layout() {
        super.layout()
        let artSide = bounds.width
        let btnSize: CGFloat = 34
        let margin: CGFloat = 8
        playButton.frame = NSRect(x: margin, y: max(0, artSide - btnSize - margin), width: btnSize, height: btnSize)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        setupScrollObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupScrollObservers()
        updateHoverState()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeScrollObservers()
            resetHover()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func setupScrollObservers() {
        guard clipViewObserver == nil || willScrollObserver == nil || didScrollObserver == nil else { return }
        removeScrollObservers()
        guard let sv = enclosingScrollView else { return }
        let contentView = sv.contentView
        contentView.postsBoundsChangedNotifications = true

        clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScrolling = true
                if self.isHovered {
                    self.resetHover()
                }
                self.scrollEndWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.isScrolling = false
                        self.updateHoverState()
                    }
                }
                self.scrollEndWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
        }

        willScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: sv,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScrolling = true
                self.scrollEndWorkItem?.cancel()
                if self.isHovered {
                    self.resetHover()
                }
            }
        }

        didScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: sv,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scrollEndWorkItem?.cancel()
                self.isScrolling = false
                self.updateHoverState()
            }
        }
    }

    func removeScrollObservers() {
        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil
        isScrolling = false
        if let clipViewObserver {
            NotificationCenter.default.removeObserver(clipViewObserver)
            self.clipViewObserver = nil
        }
        if let willScrollObserver {
            NotificationCenter.default.removeObserver(willScrollObserver)
            self.willScrollObserver = nil
        }
        if let didScrollObserver {
            NotificationCenter.default.removeObserver(didScrollObserver)
            self.didScrollObserver = nil
        }
    }

    func updateHoverState() {
        guard !isScrolling else {
            if isHovered { resetHover() }
            return
        }
        guard let window = self.window,
              let sv = enclosingScrollView,
              window.isVisible else {
            if isHovered { resetHover() }
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInScroll = sv.convert(mouseInWindow, from: nil)
        guard sv.bounds.contains(mouseInScroll) else {
            if isHovered { resetHover() }
            return
        }
        let mouseInView = convert(mouseInWindow, from: nil)
        let isInside = bounds.contains(mouseInView) && visibleRect.contains(mouseInView)
        if isHovered != isInside {
            setHoverState(isInside)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !isScrolling else { return }
        setHoverState(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoverState(false)
    }

    private func setHoverState(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hovered ? 0.15 : 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if hovered && onPlay != nil {
                playButton.isHidden = false
                playButton.animator().alphaValue = 1.0
            } else {
                playButton.animator().alphaValue = 0.0
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if !hovered {
                    self?.playButton.isHidden = true
                }
            }
        }
    }

    func resetHover() {
        isHovered = false
        playButton.alphaValue = 0
        playButton.isHidden = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !playButton.isHidden && playButton.alphaValue > 0.05 && playButton.frame.contains(point) {
            return playButton.hitTest(convert(point, to: playButton))
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        let padding: CGFloat = 0
        let artSide = bounds.width
        let artRect = NSRect(x: padding, y: padding, width: artSide, height: artSide)
        let corner: CGFloat = 8

        // 1. Обложка
        let clipPath = NSBezierPath(roundedRect: artRect, xRadius: corner, yRadius: corner)

        if let cachedArtworkImage {
            NSGraphicsContext.saveGraphicsState()
            clipPath.addClip()
            cachedArtworkImage.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
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

@available(macOS 26.0, *)
final class LiquidGlassTileCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LiquidGlassTileCollectionViewItem")

    let drawView = LiquidGlassTileDrawView()
    private var loadTask: Task<Void, Never>?
    private var currentURL: URL?

    var onPlay: (() -> Void)? {
        get { drawView.onPlay }
        set { drawView.onPlay = newValue }
    }

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
        drawView.setupScrollObservers()
        drawView.updateHoverState()
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
        drawView.onPlay = nil
        drawView.resetHover()
    }
}
