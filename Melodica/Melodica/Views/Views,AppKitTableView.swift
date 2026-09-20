// Views/AppKitTableView.swift
import AppKit

/// NSTableView с нашим меню по правому клику.
/// Поддерживает множественное выделение: меню строится для всего выделения.
final class AppKitTableView: NSTableView {

    /// Замыкание: для набора выделенных строк вернуть NSMenu (или nil).
    var menuForRows: ((IndexSet) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }

        // Правый клик по невыделенной строке — выделяем только её.
        // Правый клик по выделенной строке — сохраняем текущее выделение
        // (важно для multi-select: не сбрасывать набор).
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuForRows?(selectedRowIndexes)
    }
}
