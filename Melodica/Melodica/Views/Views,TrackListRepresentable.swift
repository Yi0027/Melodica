// Views/TrackListRepresentable.swift
import SwiftUI
import AppKit

struct TrackListRepresentable: NSViewRepresentable {
    let tracks: [Track]
    let rowHeight: CGFloat
    let scrollKey: String?
    let scrollToTopTrigger: AnyHashable?
    let scrollToID: Track.ID?
    let highlightedTrackID: UUID?
    let currentTrackID: UUID?
    let menuProvider: (([Track]) -> NSMenu?)?
    let onDoubleClick: (Track) -> Void
    let configure: (AppKitTrackRowCell, Track) -> Void

    init(
        tracks: [Track],
        rowHeight: CGFloat = 52,
        scrollKey: String? = nil,
        scrollToTopTrigger: AnyHashable? = nil,
        scrollToID: Track.ID? = nil,
        highlightedTrackID: UUID? = nil,
        currentTrackID: UUID? = nil,
        menuProvider: (([Track]) -> NSMenu?)? = nil,
        onDoubleClick: @escaping (Track) -> Void,
        configure: @escaping (AppKitTrackRowCell, Track) -> Void
    ) {
        self.tracks = tracks
        self.rowHeight = rowHeight
        self.scrollKey = scrollKey
        self.scrollToTopTrigger = scrollToTopTrigger
        self.scrollToID = scrollToID
        self.highlightedTrackID = highlightedTrackID
        self.currentTrackID = currentTrackID
        self.menuProvider = menuProvider
        self.onDoubleClick = onDoubleClick
        self.configure = configure
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = AppKitTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
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

        context.coordinator.attach(tableView: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(tracks: tracks)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.saveOnDismantle()
    }

    final class Coordinator: NSObject, NSTableViewDelegate {
        var parent: TrackListRepresentable

        private weak var tableView: NSTableView?
        private weak var scrollView: NSScrollView?
        private var dataSource: NSTableViewDiffableDataSource<Int, Track.ID>!
        private var tracksByID: [Track.ID: Track] = [:]
        private var boundsObserver: NSObjectProtocol?
        

        private var myScrollKey: String?

        // Fade-swap: пока идёт fade-out, данные не применяем,
        // а держим последний snapshot в pending. Применим его
        // ровно в момент, когда alpha уже 0.
        private var isFadingOut = false
        private var pendingSnapshot: NSDiffableDataSourceSnapshot<Int, Track.ID>?
        private var pendingScrollKey: String?
        private var pendingSelection: IndexSet?

        private var lastSaveTime: Date = .distantPast
        private var lastScrollToTopTrigger: AnyHashable?
        private var lastScrollToID: Track.ID?
        private var lastCurrentTrackID: UUID?
        private var isRestoringScroll = false

        private var lastHighlightedTrackID: UUID?
        private var fadingTrackID: UUID?
        private var fadeStartTime: Date?
        private var highlightFadeTimer: Timer?

        init(_ parent: TrackListRepresentable) {
            self.parent = parent
            super.init()
        }

        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            highlightFadeTimer?.invalidate()
        }

        func attach(tableView: NSTableView, scrollView: NSScrollView) {
            self.tableView = tableView
            self.scrollView = scrollView
            self.lastScrollToTopTrigger = parent.scrollToTopTrigger
            self.lastCurrentTrackID = parent.currentTrackID

            if let customTable = tableView as? AppKitTableView {
                customTable.menuForRows = { [weak self] rows in
                    guard let self, !rows.isEmpty else { return nil }
                    var selected: [Track] = []
                    selected.reserveCapacity(rows.count)
                    for row in rows {
                        guard let id = self.dataSource.itemIdentifier(forRow: row),
                              let track = self.tracksByID[id] else { continue }
                        selected.append(track)
                    }
                    guard !selected.isEmpty else { return nil }
                    return self.parent.menuProvider?(selected)
                }
            }

            if let trackScroll = scrollView as? TrackScrollView {
                trackScroll.onWillMoveToWindow = { [weak self] in
                    self?.saveOnDismantle()
                }
            }

            dataSource = NSTableViewDiffableDataSource<Int, Track.ID>(tableView: tableView) {
                [weak self] tableView, _, row, id in
                guard let self, let track = self.tracksByID[id] else {
                    return NSTableCellView()
                }
                let cell = (tableView.makeView(
                    withIdentifier: AppKitTrackRowCell.reuseIdentifier,
                    owner: nil
                ) as? AppKitTrackRowCell) ?? {
                    let c = AppKitTrackRowCell()
                    c.identifier = AppKitTrackRowCell.reuseIdentifier
                    return c
                }()
                let isSelected = tableView.selectedRowIndexes.contains(row)
                cell.setRowSelected(isSelected)
                self.parent.configure(cell, track)
                self.applyHighlightToCell(cell, trackID: track.id)
                return cell
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in self?.saveScrollPositionIfNeeded() }
        }

        // MARK: - Selection

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let selectedRows = tableView.selectedRowIndexes
            let range = tableView.rows(in: tableView.visibleRect)
            guard range.length > 0 else { return }
            for row in range.location..<(range.location + range.length) {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitTrackRowCell else { continue }
                cell.setRowSelected(selectedRows.contains(row))
            }
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0,
                  let id = dataSource.itemIdentifier(forRow: row),
                  let track = tracksByID[id] else { return }
            parent.onDoubleClick(track)
        }

        // MARK: - Apply

        func apply(tracks: [Track]) {
            defer { syncHighlightIfNeeded() }

            let newKey = parent.scrollKey
            let keyChanged = newKey != myScrollKey
            let lastMyScrollKeyBeforeUpdate = myScrollKey

            if keyChanged, let oldKey = myScrollKey {
                let wasRestoring = isRestoringScroll
                isRestoringScroll = false
                tableView?.layoutSubtreeIfNeeded()
                saveScrollFor(key: oldKey)
                isRestoringScroll = wasRestoring
            }

            myScrollKey = newKey

            var dict: [Track.ID: Track] = [:]
            dict.reserveCapacity(tracks.count)
            for t in tracks { dict[t.id] = t }

            let oldByID = tracksByID
            tracksByID = dict

            let savedSelection = tableView?.selectedRowIndexes ?? IndexSet()

            var snapshot = NSDiffableDataSourceSnapshot<Int, Track.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(tracks.map(\.id))
            var changed: [Track.ID] = []
            for t in tracks {
                if let old = oldByID[t.id], old != t { changed.append(t.id) }
            }
            if !changed.isEmpty { snapshot.reloadItems(changed) }

            // Пока идёт fade-out — не применяем snapshot.
            // Держим самый свежий и применим в момент завершения fade-out.
            if isFadingOut {
                pendingSnapshot = snapshot
                pendingScrollKey = newKey
                pendingSelection = savedSelection
                return
            }

            let isFirstAppearance = keyChanged && (lastMyScrollKeyBeforeUpdate == nil)
            let shouldAnimate = keyChanged && !isFirstAppearance

            if shouldAnimate {
                isFadingOut = true
                pendingSnapshot = snapshot
                pendingScrollKey = newKey
                pendingSelection = savedSelection
                isRestoringScroll = true
                startFadeSwap()
                return
            }

            // Обычный путь без анимации
            dataSource.apply(snapshot, animatingDifferences: false)

            if let tableView, !savedSelection.isEmpty,
               tableView.selectedRowIndexes != savedSelection {
                tableView.selectRowIndexes(savedSelection, byExtendingSelection: false)
            }

            if isFirstAppearance {
                isRestoringScroll = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let newID = self.parent.scrollToID, newID != self.lastScrollToID {
                        self.lastScrollToID = newID
                        self.attemptScrollToRow(id: newID, attempt: 0, applyOffset: false)
                        return
                    }
                    self.restoreImmediately(key: newKey)
                    self.reloadVisibleCells()
                    self.syncCurrentTrackCell()
                    self.isRestoringScroll = false
                }
                return
            }

            syncCurrentTrackCell()
            handleScrollRequests()
        }

        // MARK: - Highlight

        private func syncHighlightIfNeeded() {
            let newValue = parent.highlightedTrackID
            guard newValue != lastHighlightedTrackID else {
                // Даже если новый ID тот же — перерисуем видимые ячейки,
                // чтобы пересозданные получили актуальный alpha.
                applyHighlightToAllVisibleCells()
                return
            }

            lastHighlightedTrackID = newValue
            highlightFadeTimer?.invalidate()
            highlightFadeTimer = nil

            if let newValue {
                fadingTrackID = newValue
                fadeStartTime = Date()
                applyHighlightToAllVisibleCells()
                scheduleAutoFade(trackID: newValue, after: 3.0, duration: 0.5)
            } else if let fadingID = fadingTrackID {
                startFade(trackID: fadingID, duration: 0.5)
            } else {
                applyHighlightToAllVisibleCells()
            }
        }

        private func applyHighlightToCell(_ cell: AppKitTrackRowCell, trackID: UUID) {
            let alpha: CGFloat = currentHighlightAlpha(for: trackID)
            cell.setHighlightAlpha(alpha)
        }

        private func currentHighlightAlpha(for trackID: UUID) -> CGFloat {
            guard let fadingID = fadingTrackID, let start = fadeStartTime else {
                return trackID == parent.highlightedTrackID ? 1.0 : 0.0
            }
            guard trackID == fadingID else { return 0.0 }

            let elapsed = Date().timeIntervalSince(start)
            let fadeBegin: TimeInterval = 3.0
            if elapsed < fadeBegin {
                return 1.0
            } else {
                let p = min(1.0, (elapsed - fadeBegin) / 0.5)
                return CGFloat(1.0 - p)
            }
        }

        private func applyHighlightToAllVisibleCells() {
            guard let tableView else { return }
            let range = tableView.rows(in: tableView.visibleRect)
            guard range.length > 0 else { return }
            for row in range.location..<(range.location + range.length) {
                guard let id = dataSource.itemIdentifier(forRow: row),
                      let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitTrackRowCell else { continue }
                cell.setHighlightAlpha(currentHighlightAlpha(for: id))
            }
        }

        private func scheduleAutoFade(trackID: UUID, after: TimeInterval, duration: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self, self.fadingTrackID == trackID else { return }
                self.startFade(trackID: trackID, duration: duration)
            }
        }

        private func startFade(trackID: UUID, duration: TimeInterval) {
            highlightFadeTimer?.invalidate()
            // Сдвигаем точку отсчёта так, чтобы elapsed сразу начал превышать 3.0
            // и currentHighlightAlpha возвращал убывающие значения.
            let now = Date()
            fadeStartTime = now.addingTimeInterval(-3.0)

            highlightFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }

                let elapsed = Date().timeIntervalSince(now)
                let progress = min(1.0, elapsed / duration)
                let alpha = CGFloat(1.0 - progress)

                if let tableView = self.tableView,
                   let row = self.rowIndex(for: trackID),
                   let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitTrackRowCell {
                    cell.setHighlightAlpha(alpha)
                }

                if progress >= 1.0 {
                    timer.invalidate()
                    self.highlightFadeTimer = nil
                    self.fadingTrackID = nil
                    self.fadeStartTime = nil
                    self.applyHighlightToAllVisibleCells()
                }
            }
        }

        // MARK: - Key change animation

        private func startFadeSwap() {
            guard let scrollView else {
                finishFadeSwap()
                isFadingOut = false
                return
            }

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.20
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                scrollView.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }

                self.finishFadeSwap()
                self.isFadingOut = false

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.30
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.animator().alphaValue = 1
                }
            })
        }

        private func finishFadeSwap() {
            guard let snapshot = pendingSnapshot else {
                isRestoringScroll = false
                return
            }
            let scrollKey = pendingScrollKey
            let selection = pendingSelection ?? IndexSet()

            pendingSnapshot = nil
            pendingScrollKey = nil
            pendingSelection = nil

            dataSource.apply(snapshot, animatingDifferences: false)

            if let tableView, !selection.isEmpty,
               tableView.selectedRowIndexes != selection {
                tableView.selectRowIndexes(selection, byExtendingSelection: false)
            }

            if let newID = parent.scrollToID, newID != lastScrollToID {
                lastScrollToID = newID
                attemptScrollToRow(id: newID, attempt: 0, applyOffset: false)
            } else {
                restoreImmediately(key: scrollKey)
                reloadVisibleCells()
                syncCurrentTrackCell()
                isRestoringScroll = false
            }
        }

        private func restoreImmediately(key: String?) {
            guard let tableView else { return }

            guard let key,
                  let savedID = ScrollPositionManager.shared.getUUID(key: key),
                  let row = rowIndex(for: savedID) else {
                if tableView.numberOfRows > 0 {
                    tableView.scrollRowToVisible(0)
                }
                return
            }

            tableView.scrollRowToVisible(row)

            let offset = ScrollPositionManager.shared.getOffset(key: key)
            if offset > 0, let scrollView {
                let itemFrame = tableView.rect(ofRow: row)
                let targetY = itemFrame.minY + offset
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        private func reloadVisibleCells() {
            guard let tableView else { return }
            let range = tableView.rows(in: tableView.visibleRect)
            guard range.length > 0 else { return }
            tableView.reloadData(
                forRowIndexes: IndexSet(integersIn: range.location..<(range.location + range.length)),
                columnIndexes: IndexSet(integer: 0)
            )
        }

        private func syncCurrentTrackCell() {
            let newCurrentID = parent.currentTrackID
            guard newCurrentID != lastCurrentTrackID else { return }
            let oldID = lastCurrentTrackID
            lastCurrentTrackID = newCurrentID

            DispatchQueue.main.async { [weak self] in
                guard let self, let tableView = self.tableView else { return }
                if let oldID, let r = self.rowIndex(for: oldID),
                   let cell = tableView.view(atColumn: 0, row: r, makeIfNecessary: false) as? AppKitTrackRowCell,
                   let track = self.tracksByID[oldID] {
                    self.parent.configure(cell, track)
                    self.applyHighlightToCell(cell, trackID: track.id)
                }
                if let newID = newCurrentID, let r = self.rowIndex(for: newID),
                   let cell = tableView.view(atColumn: 0, row: r, makeIfNecessary: false) as? AppKitTrackRowCell,
                   let track = self.tracksByID[newID] {
                    self.parent.configure(cell, track)
                    self.applyHighlightToCell(cell, trackID: track.id)
                }
            }
        }

        // MARK: - Scroll requests

        private func handleScrollRequests() {
            let newTrigger = parent.scrollToTopTrigger
            let newID = parent.scrollToID
            let triggerChanged = newTrigger != lastScrollToTopTrigger
            let idChanged = newID != lastScrollToID

            lastScrollToTopTrigger = newTrigger
            lastScrollToID = newID

            if triggerChanged {
                isRestoringScroll = true
                DispatchQueue.main.async { [weak self] in self?.scrollToTop() }
                return
            }
            if idChanged, let id = newID {
                isRestoringScroll = true
                DispatchQueue.main.async { [weak self] in
                    self?.attemptScrollToRow(id: id, attempt: 0, applyOffset: false)
                }
                return
            }
        }

        private func scrollToTop() {
            guard let tableView else { isRestoringScroll = false; return }
            if tableView.numberOfRows > 0 { tableView.scrollRowToVisible(0) }
            if let key = myScrollKey { ScrollPositionManager.shared.clear(key: key) }
            isRestoringScroll = false
        }

        private func attemptScrollToRow(id: Track.ID, attempt: Int, applyOffset: Bool = true) {
            let maxAttempts = 40
            let delay: TimeInterval = attempt == 0 ? 0 : 0.025

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let tableView = self.tableView, let scrollView = self.scrollView else {
                    self?.isRestoringScroll = false
                    return
                }
                tableView.layoutSubtreeIfNeeded()

                guard tableView.numberOfRows > 0,
                      let row = self.rowIndex(for: id) else {
                    if attempt < maxAttempts {
                        self.attemptScrollToRow(id: id, attempt: attempt + 1, applyOffset: applyOffset)
                    } else {
                        self.isRestoringScroll = false
                    }
                    return
                }

                tableView.scrollRowToVisible(row)

                if applyOffset, let key = self.myScrollKey {
                    let offset = ScrollPositionManager.shared.getOffset(key: key)
                    if offset > 0 {
                        let itemFrame = tableView.rect(ofRow: row)
                        let targetY = itemFrame.minY + offset
                        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                }

                tableView.reloadData(
                    forRowIndexes: IndexSet(integer: row),
                    columnIndexes: IndexSet(integer: 0)
                )

                DispatchQueue.main.async { [weak self] in
                    self?.isRestoringScroll = false
                }
            }
        }

        // MARK: - Helpers

        private func rowIndex(for id: Track.ID) -> Int? {
            guard let tableView else { return nil }
            let count = tableView.numberOfRows
            guard count > 0 else { return nil }
            for row in 0..<count {
                if dataSource.itemIdentifier(forRow: row) == id { return row }
            }
            return nil
        }

        private func saveScrollPositionIfNeeded() {
            guard !isRestoringScroll, let key = myScrollKey else { return }
            let now = Date()
            guard now.timeIntervalSince(lastSaveTime) > 0.3 else { return }
            lastSaveTime = now
            saveScrollFor(key: key)
        }

        private func saveScrollFor(key: String) {
            guard let tableView, tableView.numberOfRows > 0 else { return }
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.length > 0 else { return }
            let topRow = visible.location
            guard topRow >= 0, topRow < tableView.numberOfRows,
                  let id = dataSource.itemIdentifier(forRow: topRow) else { return }

            let itemFrame = tableView.rect(ofRow: topRow)
            let pixelOffset = max(0, tableView.visibleRect.minY - itemFrame.minY)

            ScrollPositionManager.shared.saveUUID(key: key, id: id)
            ScrollPositionManager.shared.saveOffset(key: key, offset: pixelOffset)
        }

        func saveOnDismantle() {
            guard let key = myScrollKey else { return }
            guard let tableView, tableView.numberOfRows > 0 else { return }
            tableView.layoutSubtreeIfNeeded()
            saveScrollFor(key: key)
        }
    }
}

final class TrackScrollView: NSScrollView {
    var onWillMoveToWindow: (() -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            onWillMoveToWindow?()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
