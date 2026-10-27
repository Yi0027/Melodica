// Views/LiquidGlass/LiquidGlassQueueListRepresentable.swift
import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct LiquidGlassQueueListRepresentable: NSViewRepresentable {
    let items: [QueueItem]
    let currentQueueItemID: UUID?
    let rowHeight: CGFloat
    let onPlayNow: (QueueItem) -> Void
    let onRemove: (QueueItem) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onInsertExternal: ([UUID], Int) -> Void
    let configure: (LiquidGlassAppKitTrackRowCell, QueueItem, Bool) -> Void

    init(
        items: [QueueItem],
        currentQueueItemID: UUID?,
        rowHeight: CGFloat = 44,
        onPlayNow: @escaping (QueueItem) -> Void,
        onRemove: @escaping (QueueItem) -> Void,
        onMove: @escaping (IndexSet, Int) -> Void,
        onInsertExternal: @escaping ([UUID], Int) -> Void,
        configure: @escaping (LiquidGlassAppKitTrackRowCell, QueueItem, Bool) -> Void
    ) {
        self.items = items
        self.currentQueueItemID = currentQueueItemID
        self.rowHeight = rowHeight
        self.onPlayNow = onPlayNow
        self.onRemove = onRemove
        self.onMove = onMove
        self.onInsertExternal = onInsertExternal
        self.configure = configure
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []

        let column = NSTableColumn(identifier: .init("queue"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        tableView.registerForDraggedTypes([.melodicaTrackIDs])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .gap

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(tableView: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, currentQueueItemID: currentQueueItemID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate {
        var parent: LiquidGlassQueueListRepresentable
        private weak var tableView: NSTableView?
        private var dataSource: LiquidGlassQueueDataSource!
        private var itemsByID: [UUID: QueueItem] = [:]
        private var order: [UUID] = []
        private var currentQueueItemID: UUID?
        private var hasApplied = false

        init(_ parent: LiquidGlassQueueListRepresentable) { self.parent = parent }

        func attach(tableView: NSTableView) {
            self.tableView = tableView

            let ds = LiquidGlassQueueDataSource(tableView: tableView) { [weak self] tableView, _, row, id in
                guard let self, let item = self.itemsByID[id] else {
                    return NSTableCellView()
                }
                let cell = (tableView.makeView(
                    withIdentifier: LiquidGlassAppKitTrackRowCell.reuseIdentifier,
                    owner: nil
                ) as? LiquidGlassAppKitTrackRowCell) ?? {
                    let c = LiquidGlassAppKitTrackRowCell()
                    c.identifier = LiquidGlassAppKitTrackRowCell.reuseIdentifier
                    return c
                }()
                let isCurrent = (item.id == self.currentQueueItemID)
                self.parent.configure(cell, item, isCurrent)
                let isSelected = tableView.selectedRowIndexes.contains(row)
                cell.setRowSelected(isSelected)
                return cell
            }

            ds.pasteboardWriter = { id in
                let pbItem = NSPasteboardItem()
                pbItem.setString(TrackDragPayload.encode([id]), forType: .melodicaTrackIDs)
                return pbItem
            }

            ds.onValidateDrop = { [weak self] info, row in
                guard let self else { return [] }
                guard let pbItems = info.draggingPasteboard.pasteboardItems,
                      pbItems.contains(where: { $0.string(forType: .melodicaTrackIDs) != nil })
                else { return [] }
                self.tableView?.setDropRow(row, dropOperation: .above)
                let isFromSelf = (info.draggingSource as? NSTableView) === self.tableView
                return isFromSelf ? .move : .copy
            }

            ds.onAcceptDrop = { [weak self] info, row in
                guard let self else { return false }
                guard let pbItems = info.draggingPasteboard.pasteboardItems else { return false }
                var droppedIDs: [UUID] = []
                for pbItem in pbItems {
                    if let str = pbItem.string(forType: .melodicaTrackIDs) {
                        droppedIDs.append(contentsOf: TrackDragPayload.decode(str))
                    }
                }
                guard !droppedIDs.isEmpty else { return false }

                let isFromSelf = (info.draggingSource as? NSTableView) === self.tableView
                if isFromSelf {
                    let sourceIndices = IndexSet(
                        droppedIDs.compactMap { self.order.firstIndex(of: $0) }
                    )
                    guard !sourceIndices.isEmpty else { return false }
                    self.parent.onMove(sourceIndices, row)
                    return true
                } else {
                    self.parent.onInsertExternal(droppedIDs, row)
                    return true
                }
            }

            self.dataSource = ds
            tableView.dataSource = ds
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let selectedRows = tableView.selectedRowIndexes
            let range = tableView.rows(in: tableView.visibleRect)
            guard range.length > 0 else { return }
            for row in range.location..<(range.location + range.length) {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? LiquidGlassAppKitTrackRowCell else { continue }
                cell.setRowSelected(selectedRows.contains(row))
            }
        }

        func apply(items: [QueueItem], currentQueueItemID: UUID?) {
            var byID: [UUID: QueueItem] = [:]
            byID.reserveCapacity(items.count)
            for it in items { byID[it.id] = it }

            let newOrder = items.map(\.id)
            let orderChanged = newOrder != self.order
            let currentChanged = currentQueueItemID != self.currentQueueItemID

            self.itemsByID = byID
            self.order = newOrder
            self.currentQueueItemID = currentQueueItemID

            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(newOrder, toSection: 0)

            if !orderChanged && currentChanged {
                snapshot.reloadItems(newOrder)
                dataSource.apply(snapshot, animatingDifferences: false)
                hasApplied = true
                return
            }

            dataSource.apply(snapshot, animatingDifferences: hasApplied)
            hasApplied = true
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0,
                  order.indices.contains(tableView.clickedRow),
                  let item = itemsByID[order[tableView.clickedRow]] else { return }
            parent.onPlayNow(item)
        }
    }
}

@available(macOS 26.0, *)
@MainActor
final class LiquidGlassQueueDataSource: NSTableViewDiffableDataSource<Int, UUID> {

    var pasteboardWriter: ((UUID) -> NSPasteboardWriting?)?
    var onValidateDrop: ((NSDraggingInfo, Int) -> NSDragOperation)?
    var onAcceptDrop: ((NSDraggingInfo, Int) -> Bool)?

    deinit {
        // DO NOT DELETE. Empty deinit is needed to workaround compiler crash
        // in Swift 5 Release on EarlyPerfInliner pass for synthesized
        // generic subclass deinit of NSTableViewDiffableDataSource.
    }

    nonisolated override init(
        tableView: NSTableView,
        cellProvider: @escaping NSTableViewDiffableDataSource<Int, UUID>.CellProvider
    ) {
        super.init(tableView: tableView, cellProvider: cellProvider)
    }

    @objc(tableView:pasteboardWriterForRow:)
    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let id = itemIdentifier(forRow: row) else { return nil }
        return pasteboardWriter?(id)
    }

    @objc(tableView:validateDrop:proposedRow:proposedDropOperation:)
    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        return onValidateDrop?(info, row) ?? []
    }

    @objc(tableView:acceptDrop:row:dropOperation:)
    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        return onAcceptDrop?(info, row) ?? false
    }
}
