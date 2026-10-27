import AppKit
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    /// Тип для drag-and-drop треков.
    /// Один и тот же идентификатор используется и в NSPasteboard (AppKit-таблицы),
    /// и в UTType (SwiftUI `.onDrop`).
    static let melodicaTrackIDs = NSPasteboard.PasteboardType("com.melodica.track-ids")
}

extension UTType {
    /// Тот же тип, что `NSPasteboard.PasteboardType.melodicaTrackIDs`,
    /// но для SwiftUI `.onDrop(of:)`, который принимает только `[UTType]`.
    ///
    /// Используем `UTType(_:)` (создаёт «dynamic» тип), а не `importedAs:` /
    /// `exportedAs:` — те два требуют объявления в Info.plist. Для внутреннего
    /// drag-and-drop между окнами одного приложения declaration не нужен.
    static let melodicaTrackIDs = UTType("com.melodica.track-ids")
        ?? UTType.data
}

/// Payload для drag-and-drop треков между списками библиотеки,
/// очередью воспроизведения и окном сканирования.
///
/// Внутри payload лежит UUID:
///   • из списков библиотеки — `Track.id`;
///   • из очереди — `QueueItem.id`.
///
/// Резолвер в приложении (`ScanWindowController.trackResolver`) превращает
/// UUID обратно в `Track`, проверяя сначала `libraryVM.tracks`, потом `playerVM.queue`.
nonisolated enum TrackDragPayload {
    nonisolated static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    static func decode(_ string: String) -> [UUID] {
        string.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}
