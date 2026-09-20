// Views/SmartPlaylistListRepresentable.swift
import SwiftUI
import AppKit

struct SmartPlaylistListRepresentable: NSViewRepresentable {
    let items: [SmartPlaylist]
    let countProvider: (SmartPlaylist) -> Int
    let scrollKey: String?
    let onSelect: (SmartPlaylist) -> Void
    let menuProvider: ((SmartPlaylist) -> NSMenu?)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = AppKitTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 44
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.handleClick(_:))
        tableView.delegate = context.coordinator

        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scrollView = TrackScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        context.coordinator.attach(tableView: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.saveOnDismantle()
    }

    final class Coordinator: NSObject, NSTableViewDelegate {
        var parent: SmartPlaylistListRepresentable
        private weak var tableView: NSTableView?
        private weak var scrollView: NSScrollView?
        private var dataSource: NSTableViewDiffableDataSource<Int, UUID>!
        private var itemsByID: [UUID: SmartPlaylist] = [:]
        private var observer: NSObjectProtocol?
        private var lastSave: Date = .distantPast

        init(_ parent: SmartPlaylistListRepresentable) {
            self.parent = parent
            super.init()
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(tableView: NSTableView, scrollView: NSScrollView) {
            self.tableView = tableView
            self.scrollView = scrollView

            if let custom = tableView as? AppKitTableView {
                custom.menuForRows = { [weak self] rows in
                    guard let self,
                          let firstRow = rows.first,
                          let id = self.dataSource.itemIdentifier(forRow: firstRow),
                          let pl = self.itemsByID[id] else { return nil }
                    return self.parent.menuProvider?(pl)
                }
            }

            dataSource = NSTableViewDiffableDataSource<Int, UUID>(tableView: tableView) {
                [weak self] tableView, _, _, id in
                guard let self, let playlist = self.itemsByID[id] else {
                    return NSTableCellView()
                }
                let cell = (tableView.makeView(
                    withIdentifier: SmartPlaylistCellView.reuseIdentifier,
                    owner: nil
                ) as? SmartPlaylistCellView) ?? {
                    let c = SmartPlaylistCellView()
                    c.identifier = SmartPlaylistCellView.reuseIdentifier
                    return c
                }()
                let count = self.parent.countProvider(playlist)
                cell.configure(playlist: playlist, count: count)
                return cell
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.saveScrollIfNeeded()
            }
        }

        @objc func handleClick(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0,
                  let id = dataSource.itemIdentifier(forRow: row),
                  let pl = itemsByID[id] else { return }
            parent.onSelect(pl)
        }

        func apply(items: [SmartPlaylist]) {
            var dict: [UUID: SmartPlaylist] = [:]
            dict.reserveCapacity(items.count)
            for pl in items { dict[pl.id] = pl }
            itemsByID = dict

            var snap = NSDiffableDataSourceSnapshot<Int, UUID>()
            snap.appendSections([0])
            snap.appendItems(items.map(\.id))
            dataSource.apply(snap, animatingDifferences: false)

            restoreScrollIfNeeded()
        }

        private func restoreScrollIfNeeded() {
            guard let tableView, let key = parent.scrollKey,
                  tableView.numberOfRows > 0,
                  let savedID = ScrollPositionManager.shared.getUUID(key: key) else { return }
            for row in 0..<tableView.numberOfRows {
                if dataSource.itemIdentifier(forRow: row) == savedID {
                    tableView.scrollRowToVisible(row)
                    return
                }
            }
        }

        private func saveScrollIfNeeded() {
            guard let tableView, let key = parent.scrollKey,
                  tableView.numberOfRows > 0 else { return }
            let now = Date()
            guard now.timeIntervalSince(lastSave) > 0.3 else { return }
            lastSave = now

            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else { return }
            let topRow = visible.location
            guard topRow >= 0, topRow < tableView.numberOfRows,
                  let id = dataSource.itemIdentifier(forRow: topRow) else { return }
            ScrollPositionManager.shared.saveUUID(key: key, id: id)
        }

        func saveOnDismantle() {
            saveScrollIfNeeded()
        }
    }
}

// MARK: - Cell

final class SmartPlaylistCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SmartPlaylistCellView")

    private let backgroundView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.02).cgColor
        addSubview(backgroundView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .textMain
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .textMuted
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        addSubview(subtitleLabel)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .textMuted
        countLabel.alignment = .right
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),

            countLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(playlist: SmartPlaylist, count: Int) {
        if let img = NSImage(systemSymbolName: playlist.icon, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [SettingsManager.shared.accentNSColor]))
            iconView.image = img.withSymbolConfiguration(config)
        } else {
            iconView.image = nil
        }
        titleLabel.stringValue = playlist.name
        subtitleLabel.stringValue = "\(playlist.rules.count) \(NSLocalizedString("rules", comment: ""))"
        countLabel.stringValue = "\(count)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        titleLabel.stringValue = ""
        subtitleLabel.stringValue = ""
        countLabel.stringValue = ""
    }
}
