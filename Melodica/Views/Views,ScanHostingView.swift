import SwiftUI
import AppKit

/// Корневое hosting-вью окна сканирования. Регистрирует drop-тип
/// на САМОМ корне (не overlay'ем поверх SwiftUI), поэтому скролл и
/// все SwiftUI-жесты работают как обычно, а drag&drop обрабатывается
/// тут же через NSDraggingDestination.
final class ScanHostingView<Content: View>: NSHostingView<Content> {

    var onDrop: (([UUID]) -> Void)?
    var onTargetedChange: ((Bool) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.melodicaTrackIDs])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !extractIDs(sender).isEmpty else { return [] }
        onTargetedChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return extractIDs(sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetedChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetedChange?(false)
        let ids = extractIDs(sender)
        guard !ids.isEmpty else { return false }
        onDrop?(ids)
        return true
    }

    private func extractIDs(_ info: NSDraggingInfo) -> [UUID] {
        guard let items = info.draggingPasteboard.pasteboardItems else { return [] }
        var ids: [UUID] = []
        for item in items {
            guard let str = item.string(forType: .melodicaTrackIDs) else { continue }
            ids.append(contentsOf: TrackDragPayload.decode(str))
        }
        return ids
    }
}
