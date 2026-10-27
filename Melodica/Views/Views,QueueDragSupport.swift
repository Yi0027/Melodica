import AppKit

final class DragAwareDiffableDataSource<
    SectionIdentifierType: Hashable,
    ItemIdentifierType: Hashable
>: NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType> {

    var pasteboardWriter: ((ItemIdentifierType) -> NSPasteboardWriting?)?

    deinit {
        // НЕ УДАЛЯТЬ. Пустой deinit нужен для обхода креша компилятора
        // Swift 5 в Release на пассе EarlyPerfInliner для синтезированного
        // деструктора generic-подкласса NSTableViewDiffableDataSource.
        // См. обсуждение: ICE "While running pass EarlyPerfInliner on SILFunction ... CfD".
    }

    nonisolated override init(
        tableView: NSTableView,
        cellProvider: @escaping NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider
    ) {
        super.init(tableView: tableView, cellProvider: cellProvider)
    }

    @objc(tableView:pasteboardWriterForRow:)
    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let id = itemIdentifier(forRow: row) else { return nil }
        return pasteboardWriter?(id)
    }
}
