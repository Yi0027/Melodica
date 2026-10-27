import Foundation

/// Элемент очереди воспроизведения.
/// Объёртка вокруг Track с собственным UUID, чтобы:
/// - разрешить дубликаты одного трека в очереди,
/// - давать стабильные идентификаторы для diffable/NSTableView и drag-and-drop.
struct QueueItem: Identifiable, Equatable {
    let id: UUID
    let track: Track

    init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }
}
