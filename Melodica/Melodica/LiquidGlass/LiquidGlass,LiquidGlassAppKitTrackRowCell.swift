// Views/LiquidGlass/LiquidGlassAppKitTrackRowCell.swift
import AppKit

@available(macOS 26.0, *)
final class LiquidGlassAppKitTrackRowCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LiquidGlassAppKitTrackRowCell")

    private let baseBackgroundView = NSView()
    private let highlightOverlayView = NSView()
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let ratingStack = NSStackView()
    private let starViews: [NSImageView] = (0..<5).map { _ in NSImageView() }

    private var loadTask: Task<Void, Never>?
    private var currentArtURL: URL?
    private var isCurrent: Bool = false
    private var isEven: Bool = false
    private var isRowSelected: Bool = false
    private var isHighlighted: Bool = false

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
        addSubview(durationLabel)

        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.orientation = .horizontal
        ratingStack.spacing = 1
        addSubview(ratingStack)

        for iv in starViews {
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.imageScaling = .scaleProportionallyDown
            iv.widthAnchor.constraint(equalToConstant: 9).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 9).isActive = true
            ratingStack.addArrangedSubview(iv)
        }

        NSLayoutConstraint.activate([
            baseBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            baseBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            baseBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            baseBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: ratingStack.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: ratingStack.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 40),

            ratingStack.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            ratingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(
        track: Track,
        isCurrent: Bool,
        isPlaying: Bool,
        isEven: Bool,
        showRating: Bool
    ) {
        self.isCurrent = isCurrent
        self.isEven = isEven

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

        updateBaseBackground()
        loadArtwork(from: track.thumbURL(size: "84") ?? track.albumArtURL)
    }

    func setRowSelected(_ selected: Bool) {
        if isRowSelected != selected {
            isRowSelected = selected
            updateBaseBackground()
        }
    }

    /// Устанавливает alpha highlight overlay. Управляет Coordinator через ручной timer.
    func setHighlightAlpha(_ alpha: CGFloat) {
        highlightOverlayView.alphaValue = alpha
        isHighlighted = alpha > 0.01
    }

    private func updateBaseBackground() {
        let color: NSColor
        if isRowSelected {
            color = NSColor.controlAccentColor.withAlphaComponent(0.28)
        } else if isCurrent {
            color = NSColor.controlAccentColor.withAlphaComponent(0.08)
        } else if isEven {
            color = NSColor.labelColor.withAlphaComponent(0.03)
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
        baseBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        highlightOverlayView.alphaValue = 0
        ratingStack.isHidden = true
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
