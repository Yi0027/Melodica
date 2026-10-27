// Views/LiquidGlass/LiquidGlassAppKitTrackRowCell.swift
import AppKit

@available(macOS 26.0, *)
final class LiquidGlassAppKitTrackRowCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LiquidGlassAppKitTrackRowCell")

    private let baseBackgroundView = NSView()
    private let hoverOverlayView = NSView()
    private let highlightOverlayView = NSView()
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let ratingStack = NSStackView()
    private let favoriteButton = NSButton()
    private let removeButton = NSButton()
    private let starViews: [NSImageView] = (0..<5).map { _ in NSImageView() }

    /// Right stack: [rating] [duration] [favorite] [remove]. NSStackView automatically
    /// collapses hidden subviews.
    private let rightStack = NSStackView()

    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    private var isScrolling: Bool = false
    private var scrollEndWorkItem: DispatchWorkItem?
    private var clipViewObserver: NSObjectProtocol?
    private var willScrollObserver: NSObjectProtocol?
    private var didScrollObserver: NSObjectProtocol?

    private var loadTask: Task<Void, Never>?
    private var currentArtURL: URL?
    private var isCurrent: Bool = false
    private var isEven: Bool = false
    private var isRowSelected: Bool = false
    private var isHighlighted: Bool = false
    private var isFavorite: Bool = false

    var onFavorite: (() -> Void)?
    var onRemove: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        baseBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        baseBackgroundView.wantsLayer = true
        baseBackgroundView.layer?.cornerRadius = 6
        baseBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(baseBackgroundView)

        hoverOverlayView.translatesAutoresizingMaskIntoConstraints = false
        hoverOverlayView.wantsLayer = true
        hoverOverlayView.layer?.cornerRadius = 6
        hoverOverlayView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        hoverOverlayView.alphaValue = 0
        addSubview(hoverOverlayView)

        highlightOverlayView.translatesAutoresizingMaskIntoConstraints = false
        highlightOverlayView.wantsLayer = true
        highlightOverlayView.layer?.cornerRadius = 6
        highlightOverlayView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.40).cgColor
        highlightOverlayView.alphaValue = 0
        addSubview(highlightOverlayView)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 4
        artworkView.layer?.masksToBounds = true
        addSubview(artworkView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 9)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        addSubview(subtitleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        durationLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.orientation = .horizontal
        ratingStack.spacing = 1
        for iv in starViews {
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.imageScaling = .scaleProportionallyDown
            iv.widthAnchor.constraint(equalToConstant: 9).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 9).isActive = true
            ratingStack.addArrangedSubview(iv)
        }

        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.isBordered = false
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.target = self
        favoriteButton.action = #selector(handleFavorite)
        favoriteButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        favoriteButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        favoriteButton.alphaValue = 0
        favoriteButton.isEnabled = false

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isBordered = false
        removeButton.imagePosition = .imageOnly
        removeButton.target = self
        removeButton.action = #selector(handleRemove)
        removeButton.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 22).isActive = true

        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 6
        rightStack.addArrangedSubview(ratingStack)
        rightStack.addArrangedSubview(durationLabel)
        rightStack.addArrangedSubview(favoriteButton)
        rightStack.addArrangedSubview(removeButton)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            baseBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            baseBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            baseBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            baseBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            hoverOverlayView.leadingAnchor.constraint(equalTo: baseBackgroundView.leadingAnchor),
            hoverOverlayView.trailingAnchor.constraint(equalTo: baseBackgroundView.trailingAnchor),
            hoverOverlayView.topAnchor.constraint(equalTo: baseBackgroundView.topAnchor),
            hoverOverlayView.bottomAnchor.constraint(equalTo: baseBackgroundView.bottomAnchor),

            highlightOverlayView.leadingAnchor.constraint(equalTo: baseBackgroundView.leadingAnchor),
            highlightOverlayView.trailingAnchor.constraint(equalTo: baseBackgroundView.trailingAnchor),
            highlightOverlayView.topAnchor.constraint(equalTo: baseBackgroundView.topAnchor),
            highlightOverlayView.bottomAnchor.constraint(equalTo: baseBackgroundView.bottomAnchor),

            artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 32),
            artworkView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: artworkView.topAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
            if isHovered {
                isHovered = false
                hoverOverlayView.alphaValue = 0
                updateFavoriteButtonVisibility(animated: false)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hoverOverlayView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        highlightOverlayView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.40).cgColor
        updateBaseBackground()
        updateFavoriteButtonAppearance()
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
                    self.setHovered(false)
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
                    self.setHovered(false)
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
            if isHovered { setHovered(false) }
            return
        }
        guard let window = self.window,
              let sv = enclosingScrollView,
              window.isVisible else {
            if isHovered { setHovered(false) }
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInScroll = sv.convert(mouseInWindow, from: nil)
        guard sv.bounds.contains(mouseInScroll) else {
            if isHovered { setHovered(false) }
            return
        }
        let mouseInView = convert(mouseInWindow, from: nil)
        let isInside = bounds.contains(mouseInView) && visibleRect.contains(mouseInView)
        if isHovered != isInside {
            setHovered(isInside)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInActiveApp,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !isScrolling else { return }
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        let shouldShow = (hovered || isRowSelected || isFavorite) && (onFavorite != nil)
        favoriteButton.isEnabled = shouldShow
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = hovered ? 0.12 : 0.06
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hoverOverlayView.animator().alphaValue = hovered ? 1.0 : 0.0
            favoriteButton.animator().alphaValue = shouldShow ? 1.0 : 0.0
        }
    }

    @objc private func handleFavorite() {
        isFavorite.toggle()
        updateFavoriteButtonAppearance()
        updateFavoriteButtonVisibility(animated: true)
        onFavorite?()
    }

    @objc private func handleRemove() { onRemove?() }

    func configure(
        track: Track,
        isCurrent: Bool,
        isPlaying: Bool,
        isEven: Bool,
        isFavorite: Bool = false,
        showRating: Bool,
        showRemoveButton: Bool = false,
        onFavorite: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        setupScrollObservers()
        updateHoverState()
        self.isCurrent = isCurrent
        self.isEven = isEven
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
        self.onRemove = onRemove

        titleLabel.stringValue = track.title
        titleLabel.font = .systemFont(ofSize: 11, weight: isCurrent ? .semibold : .regular)
        titleLabel.textColor = (isCurrent && isPlaying)
            ? NSColor.controlAccentColor
            : .labelColor

        var subtitle = track.artist
        if let year = track.year {
            subtitle += "  •  \(year)"
        }
        subtitleLabel.stringValue = subtitle

        durationLabel.stringValue = formatDuration(track.duration)

        if showRating, let rating = track.rating, rating > 0 {
            ratingStack.isHidden = false
            let stars = starRating(from: rating)
            for (i, iv) in starViews.enumerated() {
                let name = i < stars ? "star.fill" : "star"
                iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 8, weight: .regular))
                iv.contentTintColor = NSColor.controlAccentColor.withAlphaComponent(0.7)
            }
        } else {
            ratingStack.isHidden = true
        }

        if onFavorite != nil {
            favoriteButton.isHidden = false
            updateFavoriteButtonAppearance()
            updateFavoriteButtonVisibility(animated: false)
        } else {
            favoriteButton.isHidden = true
            favoriteButton.alphaValue = 0
            favoriteButton.isEnabled = false
        }

        removeButton.isHidden = !showRemoveButton

        updateBaseBackground()
        loadArtwork(from: track.thumbURL(size: "84") ?? track.albumArtURL)
    }

    func setRowSelected(_ selected: Bool) {
        if isRowSelected != selected {
            isRowSelected = selected
            updateBaseBackground()
            updateFavoriteButtonVisibility(animated: true)
        }
    }

    func setHighlightAlpha(_ alpha: CGFloat) {
        highlightOverlayView.alphaValue = alpha
        isHighlighted = alpha > 0.01
    }

    private func updateFavoriteButtonAppearance() {
        let name = isFavorite ? "star.fill" : "star"
        favoriteButton.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: isFavorite ? .semibold : .regular))
        favoriteButton.contentTintColor = isFavorite
            ? NSColor.controlAccentColor
            : NSColor.secondaryLabelColor.withAlphaComponent(0.65)
        favoriteButton.toolTip = isFavorite
            ? NSLocalizedString("remove_from_favorites", comment: "")
            : NSLocalizedString("add_to_favorites", comment: "")
    }

    private func updateFavoriteButtonVisibility(animated: Bool = false) {
        guard onFavorite != nil else {
            favoriteButton.alphaValue = 0
            favoriteButton.isEnabled = false
            return
        }
        let shouldShow = isHovered || isRowSelected || isFavorite
        favoriteButton.isEnabled = shouldShow
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = shouldShow ? 0.12 : 0.06
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                favoriteButton.animator().alphaValue = shouldShow ? 1.0 : 0.0
            }
        } else {
            favoriteButton.alphaValue = shouldShow ? 1.0 : 0.0
        }
    }

    private func updateBaseBackground() {
        let color: NSColor
        if isRowSelected {
            color = NSColor.labelColor.withAlphaComponent(0.12)
        } else if isCurrent {
            color = NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else if isEven {
            color = NSColor.labelColor.withAlphaComponent(0.04)
        } else {
            color = .clear
        }
        baseBackgroundView.layer?.backgroundColor = color.cgColor
    }

    private func loadArtwork(from url: URL?) {
        guard currentArtURL != url else { return }
        currentArtURL = url
        loadTask?.cancel()

        guard let url else {
            artworkView.image = nil
            return
        }

        if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: 64) {
            artworkView.image = cached
            return
        }

        artworkView.image = nil
        loadTask = Task { [weak self] in
            let loaded = await ImageCache.shared.loadImage(for: url, maxPixelSize: 64)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self, self.currentArtURL == url else { return }
                self.artworkView.image = loaded
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil
        isScrolling = false
        loadTask?.cancel()
        loadTask = nil
        currentArtURL = nil
        artworkView.image = nil
        titleLabel.stringValue = ""
        subtitleLabel.stringValue = ""
        durationLabel.stringValue = ""
        isCurrent = false
        isEven = false
        isRowSelected = false
        isHighlighted = false
        isHovered = false
        baseBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverOverlayView.alphaValue = 0
        highlightOverlayView.alphaValue = 0
        favoriteButton.alphaValue = 0
        favoriteButton.isEnabled = false
        ratingStack.isHidden = true
        removeButton.isHidden = true
        onFavorite = nil
        onRemove = nil
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec.isFinite else { return "--:--" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func starRating(from rating: Int) -> Int {
        switch rating {
        case 1...51: return 1
        case 52...102: return 2
        case 103...153: return 3
        case 154...204: return 4
        case 205...255: return 5
        default: return 0
        }
    }
}

@available(macOS 26.0, *)
extension LiquidGlassAppKitTrackRowCell: TrackRowHighlightableCell {}
