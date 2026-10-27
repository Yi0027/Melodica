import SwiftUI
import AppKit

struct QueueListRepresentable: NSViewRepresentable {
    let items: [QueueItem]
    let currentQueueItemID: UUID?
    let rowHeight: CGFloat
    let onPlayNow: (QueueItem) -> Void
    let onRemove: (QueueItem) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onInsertExternal: ([UUID], Int) -> Void
    let configure: (AppKitTrackRowCell, QueueItem, Bool) -> Void

    init(
        items: [QueueItem],
        currentQueueItemID: UUID?,
        rowHeight: CGFloat = 40,
        onPlayNow: @escaping (QueueItem) -> Void,
        onRemove: @escaping (QueueItem) -> Void,
        onMove: @escaping (IndexSet, Int) -> Void,
        onInsertExternal: @escaping ([UUID], Int) -> Void,
        configure: @escaping (AppKitTrackRowCell, QueueItem, Bool) -> Void
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

        context.coordinator.attach(tableView: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, currentQueueItemID: currentQueueItemID)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: QueueListRepresentable
        private weak var tableView: NSTableView?
        private var dataSource: QueueDataSource!
        private var itemsByID: [UUID: QueueItem] = [:]
        private var order: [UUID] = []
        private var currentQueueItemID: UUID?
        private var hasApplied = false

        init(_ parent: QueueListRepresentable) { self.parent = parent }

        func attach(tableView: NSTableView) {
            self.tableView = tableView

            let ds = QueueDataSource(tableView: tableView) { [weak self] tableView, _, _, id in
                guard let self, let item = self.itemsByID[id] else {
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
                let isCurrent = (item.id == self.currentQueueItemID)
                self.parent.configure(cell, item, isCurrent)
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

            // Порядок тот же, но поменялся играющий → перезагружаем
            // ячейки без анимации, чтобы подсветка обновилась мгновенно.
            if !orderChanged && currentChanged {
                snapshot.reloadItems(newOrder)
                dataSource.apply(snapshot, animatingDifferences: false)
                hasApplied = true
                return
            }

            // Первое появление — без анимации.
            // Reorder / insert / delete → с анимацией (AppKit сам всё раздвинет).
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

@MainActor
final class QueueDataSource: NSTableViewDiffableDataSource<Int, UUID> {

    var pasteboardWriter: ((UUID) -> NSPasteboardWriting?)?
    var onValidateDrop: ((NSDraggingInfo, Int) -> NSDragOperation)?
    var onAcceptDrop: ((NSDraggingInfo, Int) -> Bool)?

    deinit {
        // НЕ УДАЛЯТЬ. Пустой deinit нужен для обхода креша компилятора
        // Swift 5 Release на пассе EarlyPerfInliner для синтезированного
        // деструктора generic-подкласса NSTableViewDiffableDataSource.
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
