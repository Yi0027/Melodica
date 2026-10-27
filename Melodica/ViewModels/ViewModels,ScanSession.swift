import Foundation
import Observation

@MainActor
@Observable
final class ScanSession {

    struct Item: Identifiable {
        let id = UUID()
        let track: Track
        var status: Status = .queued
        var result: BitrateAnalyzer.Result?
        var stageLabel: String = ""

        enum Status { case queued, scanning, done, failed }
    }

    enum State { case idle, scanning, finished }

    private(set) var items: [Item] = []
    private(set) var state: State = .idle
    private(set) var currentIndex: Int = -1
    private(set) var currentTrackFraction: Double = 0
    private(set) var currentStageLabel: String = ""

    var total: Int { items.count }
    var completedCount: Int {
        items.filter { $0.status == .done || $0.status == .failed }.count
    }
    var remainingCount: Int { total - completedCount }

    // MARK: - Lifecycle

    func start(tracks: [Track]) {
        items = tracks.map { Item(track: $0) }
        state = .scanning
        currentIndex = -1
        currentTrackFraction = 0
        currentStageLabel = ""
    }
    /// Добавляет треки в конец очереди. Возвращает (startIndex, filtered):
    /// глобальный индекс первого нового и сами треки без дубликатов.
    /// `nil` если все треки уже были в очереди.
    @discardableResult
    func appendTracks(_ tracks: [Track]) -> (startIndex: Int, filtered: [Track])? {
        let existingPaths = Set(items.map { $0.track.url.path })
        let newTracks = tracks.filter { !existingPaths.contains($0.url.path) }
        guard !newTracks.isEmpty else { return nil }

        let startIndex = items.count
        items.append(contentsOf: newTracks.map { Item(track: $0) })

        // Если сессия уже была .finished — оживляем.
        if case .finished = state { state = .scanning }
        return (startIndex, newTracks)
    }

    /// Помечает батч завершённым. Вызывается контроллером, когда
    /// pending-очередь опустела.
    func markFinished() {
        state = .finished
        currentIndex = -1
        currentTrackFraction = 0
        currentStageLabel = ""
    }

    func reset() {
        items = []
        state = .idle
        currentIndex = -1
        currentTrackFraction = 0
        currentStageLabel = ""
    }

    // MARK: - Event application

    /// `indexOffset` — сдвиг: события от текущего batch приходят с индексами
    /// 0..N-1, где N — длина переданного в analyze массива. Чтобы получить
    /// глобальный индекс в `items`, прибавляем offset.
    func apply(event: BitrateAnalyzer.ScanEvent, indexOffset: Int = 0) {
        switch event {
        case .trackStarted(let index, _):
            let globalIndex = index + indexOffset
            guard globalIndex < items.count else { return }
            items[globalIndex].status = .scanning
            currentIndex = globalIndex
            currentTrackFraction = 0
            currentStageLabel = BitrateAnalyzer.ScanStage.opened.label

        case .stage(let index, let stage):
            let globalIndex = index + indexOffset
            guard globalIndex == currentIndex, globalIndex < items.count else { return }
            currentTrackFraction = stage.base
            currentStageLabel = stage.label
            items[globalIndex].stageLabel = stage.label

        case .stageProgress(let index, let stage, let sub):
            let globalIndex = index + indexOffset
            guard globalIndex == currentIndex, globalIndex < items.count else { return }
            currentTrackFraction = stage.fullProgress(sub: sub)

        case .trackFinished(let index, let result):
            let globalIndex = index + indexOffset
            guard globalIndex < items.count else { return }
            items[globalIndex].status = .done
            items[globalIndex].result = result
            items[globalIndex].stageLabel = ""
            currentTrackFraction = 1.0

        case .trackFailed(let index):
            let globalIndex = index + indexOffset
            guard globalIndex < items.count else { return }
            items[globalIndex].status = .failed
            items[globalIndex].stageLabel = ""
            currentTrackFraction = 1.0

        case .finished:
            // Batch завершился, но могут быть pending. Контроллер
            // сам вызовет markFinished когда очередь опустеет.
            break
        }
    }
}
