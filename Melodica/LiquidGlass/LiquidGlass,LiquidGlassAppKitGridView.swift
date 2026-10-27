// Views/LiquidGlass/LiquidGlassAppKitGridView.swift
import SwiftUI
import AppKit

final class LiquidGlassGridScrollView: NSScrollView {
    var onWillMoveToWindow: (() -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            onWillMoveToWindow?()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

@available(macOS 26.0, *)
struct LiquidGlassAppKitGridView<Item>: NSViewRepresentable {
    let items: [Item]
    let itemSize: CGSize
    let itemSpacing: CGFloat
    let sectionInset: NSEdgeInsets
    let scrollKey: String?
    let reloadToken: AnyHashable?
    let identifier: (Item) -> String
    let onSelect: (Item) -> Void
    let onPlay: ((Item) -> Void)?
    let canPlay: ((Item) -> Bool)?
    let contextMenu: ((Item) -> NSMenu?)?
    let configure: (LiquidGlassTileCollectionViewItem, Item) -> Void

    init(
        items: [Item],
        itemSize: CGSize,
        itemSpacing: CGFloat = 12,
        sectionInset: NSEdgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
        scrollKey: String? = nil,
        reloadToken: AnyHashable? = nil,
        identifier: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void = { _ in },
        onPlay: ((Item) -> Void)? = nil,
        canPlay: ((Item) -> Bool)? = nil,
        contextMenu: ((Item) -> NSMenu?)? = nil,
        configure: @escaping (LiquidGlassTileCollectionViewItem, Item) -> Void
    ) {
        self.items = items
        self.itemSize = itemSize
        self.itemSpacing = itemSpacing
        self.sectionInset = sectionInset
        self.scrollKey = scrollKey
        self.reloadToken = reloadToken
        self.identifier = identifier
        self.onSelect = onSelect
        self.onPlay = onPlay
        self.canPlay = canPlay
        self.contextMenu = contextMenu
        self.configure = configure
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = itemSize
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        layout.sectionInset = sectionInset

        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.isSelectable = true
        cv.allowsMultipleSelection = false
        cv.backgroundColors = [.clear]
        cv.register(LiquidGlassTileCollectionViewItem.self,
                    forItemWithIdentifier: LiquidGlassTileCollectionViewItem.reuseIdentifier)

        let sv = LiquidGlassGridScrollView()
        sv.documentView = cv
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.autohidesScrollers = true
        sv.verticalScrollElasticity = .none
        sv.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(cv: cv, sv: sv)
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateLayout(itemSize: itemSize, spacing: itemSpacing, inset: sectionInset)
        context.coordinator.apply(items: items)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.saveScroll(force: true)
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, NSCollectionViewDelegate {
        var parent: LiquidGlassAppKitGridView
        private weak var cv: NSCollectionView?
        private weak var sv: LiquidGlassGridScrollView?
        private var ds: NSCollectionViewDiffableDataSource<String, String>!
        private var byID: [String: Item] = [:]
        private var observer: NSObjectProtocol?
        private var willScrollObserver: NSObjectProtocol?
        private var didScrollObserver: NSObjectProtocol?
        private var lastKey: String?
        private var hasRestoredForCurrentKey = false
        private var isRestoring = false
        private var lastSave: Date = .distantPast
        private var lastReloadToken: AnyHashable?

        private var currentSize: CGSize = .zero
        private var currentSpacing: CGFloat = 0
        private var currentInset: NSEdgeInsets = NSEdgeInsets()

        init(_ p: LiquidGlassAppKitGridView) { self.parent = p }

        func cleanup() {
            sv?.onWillMoveToWindow = nil
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
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

        func attach(cv: NSCollectionView, sv: LiquidGlassGridScrollView) {
            self.cv = cv
            self.sv = sv

            sv.onWillMoveToWindow = { [weak self] in
                self?.saveScroll(force: true)
            }

            ds = NSCollectionViewDiffableDataSource<String, String>(collectionView: cv) {
                [weak self] cv, indexPath, itemID in
                guard let self, let item = self.byID[itemID] else { return nil }

                let cell = cv.makeItem(
                    withIdentifier: LiquidGlassTileCollectionViewItem.reuseIdentifier,
                    for: indexPath
                )

                if let tile = cell as? LiquidGlassTileCollectionViewItem {
                    if let onPlay = self.parent.onPlay, (self.parent.canPlay?(item) ?? true) {
                        tile.onPlay = { [weak self] in
                            self?.saveScroll(force: true)
                            onPlay(item)
                        }
                    } else {
                        tile.onPlay = nil
                    }
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
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveScroll()
                    self?.updateHoverForVisibleItems()
                }
            }

            willScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: sv,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.clearHoverForVisibleItems()
                }
            }

            didScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: sv,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveScroll(force: true)
                    self?.updateHoverForVisibleItems()
                }
            }
        }

        private func updateHoverForVisibleItems() {
            guard let cv else { return }
            for item in cv.visibleItems() {
                (item as? LiquidGlassTileCollectionViewItem)?.drawView.updateHoverState()
            }
        }

        private func clearHoverForVisibleItems() {
            guard let cv else { return }
            for item in cv.visibleItems() {
                (item as? LiquidGlassTileCollectionViewItem)?.drawView.resetHover()
            }
        }

        func updateLayout(itemSize: CGSize, spacing: CGFloat, inset: NSEdgeInsets) {
            let insetChanged = inset.top != currentInset.top ||
                               inset.left != currentInset.left ||
                               inset.bottom != currentInset.bottom ||
                               inset.right != currentInset.right

            guard itemSize != currentSize || spacing != currentSpacing || insetChanged else { return }

            currentSize = itemSize
            currentSpacing = spacing
            currentInset = inset

            if let layout = cv?.collectionViewLayout as? NSCollectionViewFlowLayout {
                layout.itemSize = itemSize
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
                layout.sectionInset = inset
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

            let token = parent.reloadToken
            let tokenChanged = token != lastReloadToken
            lastReloadToken = token
            if tokenChanged, !ids.isEmpty {
                snap.reloadItems(ids)
            }

            ds.apply(snap, animatingDifferences: false)

            if let key = parent.scrollKey {
                if key != lastKey {
                    lastKey = key
                    hasRestoredForCurrentKey = false
                }
                if !hasRestoredForCurrentKey, !items.isEmpty {
                    hasRestoredForCurrentKey = true
                    isRestoring = true
                    DispatchQueue.main.async { [weak self] in
                        self?.restoreScroll(key: key, attempt: 0)
                    }
                }
            }
        }

        func saveScroll(force: Bool = false) {
            guard !isRestoring, let cv, let sv, let key = parent.scrollKey else { return }

            let now = Date()
            if !force {
                guard now.timeIntervalSince(lastSave) > 0.2 else { return }
            }
            lastSave = now

            let visibleRect = cv.visibleRect
            let scrollY = sv.contentView.bounds.origin.y

            if scrollY <= 5 {
                ScrollPositionManager.shared.save(key: key, id: "__TOP__")
                ScrollPositionManager.shared.saveOffset(key: key, offset: 0)
                ScrollPositionManager.shared.saveOffset(key: "\(key)_abs", offset: 0)
                return
            }

            let visibleIPs = cv.indexPathsForVisibleItems()
            guard !visibleIPs.isEmpty else {
                ScrollPositionManager.shared.saveOffset(key: "\(key)_abs", offset: scrollY)
                return
            }

            var bestIP: IndexPath?
            var bestFrame: CGRect = .zero
            var minDiff: CGFloat = .greatestFiniteMagnitude

            for ip in visibleIPs {
                guard let attr = cv.layoutAttributesForItem(at: ip) else { continue }
                let frame = attr.frame
                if frame.maxY > visibleRect.minY {
                    let diff = abs(frame.minY - visibleRect.minY)
                    if frame.minY <= visibleRect.minY {
                        if diff < minDiff {
                            minDiff = diff
                            bestIP = ip
                            bestFrame = frame
                        }
                    } else if bestIP == nil || frame.minY < bestFrame.minY {
                        minDiff = diff
                        bestIP = ip
                        bestFrame = frame
                    }
                }
            }

            if let bestIP, let id = ds.itemIdentifier(for: bestIP) {
                let relOffset = max(0, visibleRect.minY - bestFrame.minY)
                ScrollPositionManager.shared.save(key: key, id: id)
                ScrollPositionManager.shared.saveOffset(key: key, offset: relOffset)
                ScrollPositionManager.shared.saveOffset(key: "\(key)_abs", offset: scrollY)
            } else {
                ScrollPositionManager.shared.saveOffset(key: "\(key)_abs", offset: scrollY)
            }
        }

        private func restoreScroll(key: String, attempt: Int) {
            guard let cv, let sv else {
                isRestoring = false
                return
            }

            let savedID = ScrollPositionManager.shared.get(key: key)
            let savedOffset = ScrollPositionManager.shared.getOffset(key: key)
            let savedAbs = ScrollPositionManager.shared.getOffset(key: "\(key)_abs")

            if savedID == nil && savedAbs == 0 {
                isRestoring = false
                return
            }

            if savedID == "__TOP__" || (savedID == nil && savedAbs <= 0) {
                sv.contentView.scroll(to: NSPoint(x: 0, y: 0))
                sv.reflectScrolledClipView(sv.contentView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.isRestoring = false
                }
                return
            }

            cv.layoutSubtreeIfNeeded()
            sv.layoutSubtreeIfNeeded()

            let contentHeight = cv.collectionViewLayout?.collectionViewContentSize.height ?? cv.frame.height
            let clipHeight = sv.contentView.bounds.height
            let itemCount = cv.numberOfItems(inSection: 0)

            let maxAttempts = 35
            if (cv.numberOfSections == 0 || itemCount == 0 || contentHeight <= clipHeight) && attempt < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                    self?.restoreScroll(key: key, attempt: attempt + 1)
                }
                return
            }

            var targetY: CGFloat? = nil
            let maxScroll = max(0, contentHeight - clipHeight)

            if let savedID {
                for item in 0..<itemCount {
                    let ip = IndexPath(item: item, section: 0)
                    if ds.itemIdentifier(for: ip) == savedID {
                        if let attr = cv.layoutAttributesForItem(at: ip), attr.frame.height > 0 {
                            let relOffset = savedOffset
                            targetY = max(0, min(maxScroll, attr.frame.minY + relOffset))
                        }
                        break
                    }
                }
            }

            if targetY == nil, savedAbs > 0 {
                targetY = max(0, min(maxScroll, savedAbs))
            }

            if let y = targetY {
                sv.contentView.scroll(to: NSPoint(x: 0, y: y))
                sv.reflectScrolledClipView(sv.contentView)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isRestoring = false
            }
        }

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt ips: Set<IndexPath>) {
            defer { cv.deselectItems(at: ips) }
            saveScroll(force: true)
            for ip in ips {
                if let id = ds.itemIdentifier(for: ip), let item = byID[id] {
                    parent.onSelect(item)
                }
            }
        }
    }
}
