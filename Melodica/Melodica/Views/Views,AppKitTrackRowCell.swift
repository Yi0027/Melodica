// Views/AppKitTrackRowCell.swift
import AppKit

struct TrackCellState {
    var showTrackNumber: Bool = true
    var showRating: Bool = false
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    var isFavorite: Bool = false
    var isInQueue: Bool = false
    var isHighlighted: Bool = false
    var showAddButton: Bool = true
    var showFavoriteButton: Bool = true
    var onAdd: (() -> Void)?
    var onFavorite: (() -> Void)?
    var menu: NSMenu?
}

final class AppKitTrackRowCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppKitTrackRowCell")

    private let baseBackgroundView = NSView()
    private let highlightOverlayView = NSView()
    private let addButton = NSButton()
    private let numberLabel = NSTextField(labelWithString: "")
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton()
    private let starViews: [NSImageView] = (0..<5).map { _ in NSImageView() }
    private var ratingStack: NSStackView!

    var onAdd: (() -> Void)?
    var onFavorite: (() -> Void)?

    private var loadTask: Task<Void, Never>?
    private var currentArtURL: URL?
    private var numberWidthConstraint: NSLayoutConstraint!

    private var isPlaying: Bool = false
    private var isRowSelected: Bool = false
    private var lastTrackID: UUID?

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
        highlightOverlayView.layer?.backgroundColor = SettingsManager.shared.accentNSColor.withAlphaComponent(0.40).cgColor
        highlightOverlayView.alphaValue = 0
        addSubview(highlightOverlayView)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 5
        artworkView.layer?.masksToBounds = true
        artworkView.layer?.backgroundColor = NSColor.darkSurface.cgColor
        addSubview(artworkView)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.isBordered = false
        addButton.imagePosition = .imageOnly
        addButton.target = self
        addButton.action = #selector(handleAdd)
        addSubview(addButton)

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        numberLabel.textColor = NSColor.textMuted.withAlphaComponent(0.5)
        numberLabel.alignment = .right
        addSubview(numberLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .textMain
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .textMuted
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        addSubview(subtitleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = .textMuted
        durationLabel.alignment = .right
        addSubview(durationLabel)

        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.isBordered = false
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.target = self
        favoriteButton.action = #selector(handleFavorite)
        addSubview(favoriteButton)

        ratingStack = NSStackView(views: starViews)
        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.orientation = .horizontal
        ratingStack.spacing = 1
        addSubview(ratingStack)

        for iv in starViews {
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.imageScaling = .scaleProportionallyDown
            iv.widthAnchor.constraint(equalToConstant: 10).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 10).isActive = true
        }

        numberWidthConstraint = numberLabel.widthAnchor.constraint(equalToConstant: 22)

        NSLayoutConstraint.activate([
            baseBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            baseBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            baseBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            baseBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            highlightOverlayView.leadingAnchor.constraint(equalTo: baseBackgroundView.leadingAnchor),
            highlightOverlayView.trailingAnchor.constraint(equalTo: baseBackgroundView.trailingAnchor),
            highlightOverlayView.topAnchor.constraint(equalTo: baseBackgroundView.topAnchor),
            highlightOverlayView.bottomAnchor.constraint(equalTo: baseBackgroundView.bottomAnchor),

            addButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),

            numberLabel.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numberWidthConstraint,

            artworkView.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 6),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: 38),
            artworkView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: artworkView.topAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: ratingStack.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: ratingStack.leadingAnchor, constant: -8),

            favoriteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            favoriteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 28),
            favoriteButton.heightAnchor.constraint(equalToConstant: 28),

            durationLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -4),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 44),

            ratingStack.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -6),
            ratingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @objc private func handleAdd() { onAdd?() }
    @objc private func handleFavorite() { onFavorite?() }

    // MARK: - Background

    func setRowSelected(_ selected: Bool) {
        if isRowSelected != selected {
            isRowSelected = selected
            updateBaseBackground()
        }
    }

    private func updateBaseBackground() {
        let color: NSColor
        if isRowSelected {
            color = SettingsManager.shared.accentNSColor.withAlphaComponent(0.28)
        } else if isPlaying {
            color = SettingsManager.shared.accentNSColor.withAlphaComponent(0.12)
        } else {
            color = .clear
        }
        baseBackgroundView.layer?.backgroundColor = color.cgColor
    }

    /// Мгновенно устанавливает alpha overlay.
    /// Анимацией управляет Coordinator — ячейка только принимает значение.
    func setHighlightAlpha(_ alpha: CGFloat) {
        highlightOverlayView.alphaValue = alpha
    }

    // MARK: - Configure

    func configure(with track: Track, state: TrackCellState) {
        let artURL = track.thumbURL(size: "84") ?? track.albumArtURL
        loadArtwork(from: artURL)

        if state.showTrackNumber, let n = track.trackNumber {
            numberLabel.stringValue = "\(n)"
            numberLabel.isHidden = false
            numberWidthConstraint.constant = 22
        } else {
            numberLabel.stringValue = ""
            numberLabel.isHidden = true
            numberWidthConstraint.constant = 0
        }

        titleLabel.stringValue = track.title
        titleLabel.textColor = (state.isCurrent && state.isPlaying) ? .accent : .textMain
        subtitleLabel.stringValue = buildSubtitle(track)
        durationLabel.stringValue = formatDuration(track.duration)

        if state.showAddButton {
            addButton.isHidden = false
            let symbol = state.isInQueue ? "checkmark.circle.fill" : "plus.circle"
            addButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            addButton.contentTintColor = state.isInQueue
                ? NSColor.textMuted.withAlphaComponent(0.3)
                : NSColor.accent.withAlphaComponent(0.7)
            addButton.isEnabled = !state.isInQueue
        } else {
            addButton.isHidden = true
        }

        if state.showFavoriteButton {
            favoriteButton.isHidden = false
            let symbol = state.isFavorite ? "star.fill" : "star"
            favoriteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            favoriteButton.contentTintColor = state.isFavorite
                ? .accent
                : NSColor.textMuted.withAlphaComponent(0.3)
        } else {
            favoriteButton.isHidden = true
        }

        let stars = (state.showRating && (track.rating ?? 0) > 0) ? starRating(from: track.rating ?? 0) : 0
        ratingStack.isHidden = (stars == 0)
        for (i, iv) in starViews.enumerated() {
            let name = (i < stars) ? "star.fill" : "star"
            iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .regular))
            iv.contentTintColor = NSColor.accent.withAlphaComponent(0.7)
        }

        onAdd = state.onAdd
        onFavorite = state.onFavorite

        let newPlaying = state.isCurrent
        if isPlaying != newPlaying {
            isPlaying = newPlaying
            updateBaseBackground()
        }

        lastTrackID = track.id
        // highlight управляется Coordinator'ом через setHighlightAlpha
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentArtURL = nil
        artworkView.image = nil
        titleLabel.stringValue = ""
        subtitleLabel.stringValue = ""
        numberLabel.stringValue = ""
        durationLabel.stringValue = ""
        onAdd = nil
        onFavorite = nil
        menu = nil
        isPlaying = false
        isRowSelected = false
        lastTrackID = nil
        baseBackgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        highlightOverlayView.alphaValue = 0
    }

    // MARK: - Artwork

    private func loadArtwork(from url: URL?) {
        guard currentArtURL != url else { return }
        currentArtURL = url
        loadTask?.cancel()

        guard let url else {
            artworkView.image = nil
            return
        }
        if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: 84) {
            artworkView.image = cached
            return
        }
        artworkView.image = nil
        loadTask = Task { [weak self] in
            let loaded = await ImageCache.shared.loadImage(for: url, maxPixelSize: 84)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self, self.currentArtURL == url else { return }
                self.artworkView.image = loaded
            }
        }
    }

    // MARK: - Formatting

    private func buildSubtitle(_ track: Track) -> String {
        var parts: [String] = [track.artist]
        if let genre = track.genre, !genre.isEmpty { parts.append(genre) }
        if let year = track.year { parts.append(String(year)) }
        return parts.joined(separator: "  •  ")
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
