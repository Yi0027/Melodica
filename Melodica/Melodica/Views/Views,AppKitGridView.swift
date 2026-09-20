// Views/AppKitGridView.swift
import SwiftUI
import AppKit
import Combine

struct AppKitGridView<Item>: NSViewRepresentable {
    let items: [Item]
    let itemSize: CGSize
    let itemSpacing: CGFloat
    let sectionInset: CGFloat
    let scrollKey: String?
    let reloadToken: AnyHashable?
    let identifier: (Item) -> String
    let onSelect: (Item) -> Void
    let contextMenu: ((Item) -> NSMenu?)?
    let configure: (TileCollectionViewItem, Item) -> Void

    init(
        items: [Item],
        itemSize: CGSize,
        itemSpacing: CGFloat = 16,
        sectionInset: CGFloat = 12,
        scrollKey: String? = nil,
        reloadToken: AnyHashable? = nil,
        identifier: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void = { _ in },
        contextMenu: ((Item) -> NSMenu?)? = nil,
        configure: @escaping (TileCollectionViewItem, Item) -> Void
    ) {
        self.items = items
        self.itemSize = itemSize
        self.itemSpacing = itemSpacing
        self.sectionInset = sectionInset
        self.scrollKey = scrollKey
        self.reloadToken = reloadToken
        self.identifier = identifier
        self.onSelect = onSelect
        self.contextMenu = contextMenu
        self.configure = configure
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = itemSize
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        layout.sectionInset = NSEdgeInsets(top: sectionInset, left: sectionInset,
                                           bottom: sectionInset, right: sectionInset)

        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.isSelectable = true
        cv.allowsMultipleSelection = false
        cv.backgroundColors = [.clear]
        cv.register(TileCollectionViewItem.self,
                    forItemWithIdentifier: TileCollectionViewItem.reuseIdentifier)

        let sv = NSScrollView()
        sv.documentView = cv
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.autohidesScrollers = true
        sv.verticalScrollElasticity = .none

        context.coordinator.attach(cv: cv, sv: sv)
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateLayout(itemSize: itemSize, spacing: itemSpacing, inset: sectionInset)
        context.coordinator.apply(items: items)
    }

    final class Coordinator: NSObject, NSCollectionViewDelegate {
        var parent: AppKitGridView
        private weak var cv: NSCollectionView?
        private weak var sv: NSScrollView?
        private var ds: NSCollectionViewDiffableDataSource<String, String>!
        private var byID: [String: Item] = [:]
        private var observer: NSObjectProtocol?
        private var lastKey: String?
        private var lastSave: Date = .distantPast
        private var restoring = false
        private var lastReloadToken: AnyHashable?

        private var currentSize: CGSize = .zero
        private var currentSpacing: CGFloat = 0
        private var currentInset: CGFloat = 0

        private var themeCancellable: AnyCancellable?

        init(_ p: AppKitGridView) { self.parent = p }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            themeCancellable?.cancel()
        }

        func attach(cv: NSCollectionView, sv: NSScrollView) {
            self.cv = cv
            self.sv = sv

            ds = NSCollectionViewDiffableDataSource<String, String>(collectionView: cv) {
                [weak self] cv, indexPath, itemID in
                guard let self, let item = self.byID[itemID] else { return nil }
                let cell = cv.makeItem(
                    withIdentifier: TileCollectionViewItem.reuseIdentifier,
                    for: indexPath
                )
                if let tile = cell as? TileCollectionViewItem {
                    self.parent.configure(tile, item)
                    if let builder = self.parent.contextMenu {
                        tile.view.menu = builder(item)
                    }
                }
                return cell
            }

            cv.delegate = self
            sv.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: sv.contentView,
                queue: .main
            ) { [weak self] _ in self?.saveScroll() }

            // Реакция на смену темы Melodica — перезагружаем видимые ячейки,
            // потому что TileDrawView рисует текст через NSColor, а не SwiftUI.
            themeCancellable = SettingsManager.shared.$theme
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.cv?.reloadData()
                }
        }

        func updateLayout(itemSize: CGSize, spacing: CGFloat, inset: CGFloat) {
            guard itemSize != currentSize || spacing != currentSpacing || inset != currentInset else { return }
            currentSize = itemSize
            currentSpacing = spacing
            currentInset = inset
            if let layout = cv?.collectionViewLayout as? NSCollectionViewFlowLayout {
                layout.itemSize = itemSize
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
                layout.sectionInset = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
                layout.invalidateLayout()
            }
        }

        func apply(items: [Item]) {
            var dict: [String: Item] = [:]
            var ids: [String] = []
            dict.reserveCapacity(items.count)
            ids.reserveCapacity(items.count)
            for item in items {
                let key = parent.identifier(item)
                dict[key] = item
                ids.append(key)
            }
            byID = dict

            var snap = NSDiffableDataSourceSnapshot<String, String>()
            snap.appendSections(["main"])
            snap.appendItems(ids, toSection: "main")

            // reloadToken — перезагружаем ВСЁ только когда явно сменилось (например, кастомная обложка)
            let token = parent.reloadToken
            let tokenChanged = token != lastReloadToken
            lastReloadToken = token
            if tokenChanged, !ids.isEmpty {
                snap.reloadItems(ids)
            }

            ds.apply(snap, animatingDifferences: false)

            if let key = parent.scrollKey, key != lastKey {
                lastKey = key
                DispatchQueue.main.async { [weak self] in self?.restoreScroll(key: key) }
            }
        }

        private func saveScroll() {
            guard !restoring, let cv, let key = parent.scrollKey else { return }
            let now = Date()
            guard now.timeIntervalSince(lastSave) > 0.3 else { return }
            lastSave = now

            let visible = cv.visibleRect
            guard let first = cv.indexPathsForVisibleItems().min(by: {
                ($0.section, $0.item) < ($1.section, $1.item)
            }), let id = ds.itemIdentifier(for: first) else { return }

            let itemFrame = cv.layoutAttributesForItem(at: first)?.frame ?? .zero
            let offset = max(0, visible.minY - itemFrame.minY)

            ScrollPositionManager.shared.save(key: key, id: id)
            ScrollPositionManager.shared.saveOffset(key: key, offset: offset)
        }

        private func restoreScroll(key: String) {
            guard let cv, let sv,
                  let savedID = ScrollPositionManager.shared.get(key: key) else { return }

            for i in 0..<cv.numberOfItems(inSection: 0) {
                let ip = IndexPath(item: i, section: 0)
                guard ds.itemIdentifier(for: ip) == savedID else { continue }

                restoring = true
                cv.scrollToItems(at: [ip], scrollPosition: .top)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let offset = ScrollPositionManager.shared.getOffset(key: key)
                    if offset > 0, let frame = cv.layoutAttributesForItem(at: ip)?.frame {
                        let targetY = frame.minY + offset
                        sv.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                        sv.reflectScrolledClipView(sv.contentView)
                    }
                    DispatchQueue.main.async { self.restoring = false }
                }
                return
            }
        }

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt ips: Set<IndexPath>) {
            defer { cv.deselectItems(at: ips) }
            for ip in ips {
                if let id = ds.itemIdentifier(for: ip), let item = byID[id] {
                    parent.onSelect(item)
                }
            }
        }
    }
}
