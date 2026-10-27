import Foundation
import os

nonisolated enum SimulationScenario: String, CaseIterable, Identifiable, Sendable {
    case freshLibrary = "fresh_library"
    case heavyListener = "heavy_listener"
    case nightOwl = "night_owl"
    case weekendLover = "weekend_lover"
    case underratedGems = "underrated_gems"
    case archiveRevival = "archive_revival"
    case highSkips = "high_skips"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freshLibrary: return "Fresh Library (Zero Plays)"
        case .heavyListener: return "Active Listener (Diverse History)"
        case .nightOwl: return "Night Owl (23:00 - 04:00 Plays)"
        case .weekendLover: return "Weekend Listener (Sat/Sun Plays)"
        case .underratedGems: return "Underrated Gems (High Ratings, 0-1 Plays)"
        case .archiveRevival: return "Archive Revival (Played 6+ Months Ago)"
        case .highSkips: return "High Skips (Test Track Blocking)"
        }
    }
}

actor TrackStatisticsService {
    static let shared = TrackStatisticsService()

    private final class Storage: @unchecked Sendable {
        let lock = OSAllocatedUnfairLock()
        var encodedSnapshot: Data?
        var isDirty = false
    }

    private let storage = Storage()
    private var statistics: [String: TrackStatistics] = [:]
    private var isLoaded = false
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var isDirty = false

    private nonisolated static var storageFileURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")

        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        return folder.appendingPathComponent("track_statistics.json")
    }

    private init() {
        fileURL = Self.storageFileURL
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(
                [String: TrackStatistics].self,
                from: data
            )
        else {
            return
        }
        statistics = decoded
    }

    func recordPlay(
        track: Track,
        context: String,
        listenedDuration: TimeInterval
    ) {
        loadIfNeeded()
        let hash = Self.hash(for: track)
        var stats = statistics[hash] ?? TrackStatistics(trackHash: hash)

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let weekday = Calendar.current.component(.weekday, from: now) - 1

        stats.playCount += 1
        stats.lastPlayedDate = now
        stats.totalTimeListened += listenedDuration

        if stats.firstPlayedDate == nil {
            stats.firstPlayedDate = now
        }

        if stats.libraryAddedDate == nil {
            stats.libraryAddedDate = now
        }

        if hour >= 0, hour < stats.timeOfDay.count {
            stats.timeOfDay[hour] += 1
        }

        if weekday >= 0, weekday < stats.dayOfWeek.count {
            stats.dayOfWeek[weekday] += 1
        }

        stats.playbackContext[context, default: 0] += 1
        stats.playHistory.append(now)
        stats.playHistory = Self.limitHistory(stats.playHistory, days: 120)

        var contextStats = stats.contextStats[context] ?? ContextStatistics()
        contextStats.playCount += 1
        contextStats.totalListened += listenedDuration
        contextStats.lastPlayedDate = now
        stats.contextStats[context] = contextStats

        statistics[hash] = stats
        scheduleSave()
    }

    func recordSkip(
        track: Track,
        context: String,
        listenedDuration: TimeInterval = 0
    ) {
        loadIfNeeded()
        let hash = Self.hash(for: track)
        var stats = statistics[hash] ?? TrackStatistics(trackHash: hash)

        let now = Date()

        stats.skipCount += 1
        stats.lastSkipDate = now
        stats.skipHistory.append(now)
        stats.skipHistory = Self.limitHistory(stats.skipHistory, days: 120)
        if listenedDuration > 0 {
            stats.totalTimeListened += listenedDuration
        }

        var contextStats = stats.contextStats[context] ?? ContextStatistics()
        contextStats.skipCount += 1
        if listenedDuration > 0 {
            contextStats.totalListened += listenedDuration
        }
        contextStats.lastPlayedDate = now
        stats.contextStats[context] = contextStats

        statistics[hash] = stats
        scheduleSave()
    }

    func setBlocked(
        track: Track,
        until date: Date
    ) {
        loadIfNeeded()
        let hash = Self.hash(for: track)

        guard var stats = statistics[hash] else { return }

        stats.blockedUntil = date
        statistics[hash] = stats
        scheduleSave()
    }

    func unblockTrack(track: Track) {
        loadIfNeeded()
        let hash = Self.hash(for: track)
        guard var stats = statistics[hash] else { return }
        stats.blockedUntil = nil
        stats.skipCount = 0
        stats.skipHistory = []
        let now = Date()
        if let lastPlayed = stats.lastPlayedDate, now.timeIntervalSince(lastPlayed) < 21 * 60 {
            stats.lastPlayedDate = now.addingTimeInterval(-21 * 60)
        }
        statistics[hash] = stats
        scheduleSave()
    }

    func resetAll() {
        loadIfNeeded()
        statistics = [:]
        isDirty = true
        flush()
        scheduleRecommendationsUpdate(debounce: 0)
    }

    func seedSimulation(tracks: [Track], scenario: SimulationScenario) {
        loadIfNeeded()
        let now = Date()

        switch scenario {
        case .freshLibrary:
            statistics = [:]
            isDirty = true
            flush()

        case .heavyListener:
            statistics = [:]
            let sampleCount = min(tracks.count, 60)
            let chosenTracks = tracks.shuffled().prefix(sampleCount)
            for (idx, track) in chosenTracks.enumerated() {
                let hash = Self.hash(for: track)
                var stat = TrackStatistics(trackHash: hash)
                let plays = max(1, (sampleCount - idx) / 2)
                stat.playCount = plays
                stat.lastPlayedDate = now.addingTimeInterval(-Double(idx * 3600 + 1800))
                stat.firstPlayedDate = now.addingTimeInterval(-45 * 86_400)
                stat.libraryAddedDate = now.addingTimeInterval(-60 * 86_400)
                stat.totalTimeListened = Double(plays) * (track.duration > 0 ? track.duration : 180)

                for i in 0..<plays {
                    let h = (8 + i * 2) % 24
                    stat.timeOfDay[h] += 1
                    let d = (1 + i) % 7
                    stat.dayOfWeek[d] += 1
                    stat.playHistory.append(now.addingTimeInterval(-Double(i * 86_400 + 3600)))
                }
                statistics[hash] = stat
            }
            isDirty = true
            flush()

        case .nightOwl:
            statistics = [:]
            let sampleTracks = tracks.shuffled().prefix(min(tracks.count, 25))
            for track in sampleTracks {
                let hash = Self.hash(for: track)
                var stat = TrackStatistics(trackHash: hash)
                stat.playCount = Int.random(in: 5...20)
                stat.lastPlayedDate = now.addingTimeInterval(-Double.random(in: 3600...86400))
                stat.totalTimeListened = Double(stat.playCount) * (track.duration > 0 ? track.duration : 180)
                for _ in 0..<stat.playCount {
                    let nightHour = [23, 0, 1, 2, 3].randomElement()!
                    stat.timeOfDay[nightHour] += 1
                    stat.playHistory.append(now.addingTimeInterval(-Double.random(in: 3600...604800)))
                }
                statistics[hash] = stat
            }
            isDirty = true
            flush()

        case .weekendLover:
            statistics = [:]
            let sampleTracks = tracks.shuffled().prefix(min(tracks.count, 25))
            for track in sampleTracks {
                let hash = Self.hash(for: track)
                var stat = TrackStatistics(trackHash: hash)
                stat.playCount = Int.random(in: 6...24)
                stat.lastPlayedDate = now.addingTimeInterval(-Double.random(in: 3600...172800))
                stat.totalTimeListened = Double(stat.playCount) * (track.duration > 0 ? track.duration : 180)
                for _ in 0..<stat.playCount {
                    let weekendDay = [0, 6].randomElement()!
                    stat.dayOfWeek[weekendDay] += 1
                    stat.playHistory.append(now.addingTimeInterval(-Double.random(in: 3600...604800)))
                }
                statistics[hash] = stat
            }
            isDirty = true
            flush()

        case .underratedGems:
            let sampleTracks = tracks.shuffled().prefix(min(tracks.count, 20))
            for track in sampleTracks {
                let hash = Self.hash(for: track)
                var stat = statistics[hash] ?? TrackStatistics(trackHash: hash)
                stat.playCount = Int.random(in: 0...1)
                stat.skipCount = 0
                stat.totalTimeListened = stat.playCount > 0 ? 120 : 0
                statistics[hash] = stat
            }
            isDirty = true
            flush()

        case .archiveRevival:
            statistics = [:]
            let sampleTracks = tracks.shuffled().prefix(min(tracks.count, 25))
            for track in sampleTracks {
                let hash = Self.hash(for: track)
                var stat = TrackStatistics(trackHash: hash)
                stat.playCount = Int.random(in: 12...35)
                let daysAgo = Double.random(in: 200...400)
                stat.lastPlayedDate = now.addingTimeInterval(-daysAgo * 86_400)
                stat.firstPlayedDate = now.addingTimeInterval(-(daysAgo + 60) * 86_400)
                stat.totalTimeListened = Double(stat.playCount) * (track.duration > 0 ? track.duration : 200)
                statistics[hash] = stat
            }
            isDirty = true
            flush()

        case .highSkips:
            let sampleTracks = tracks.shuffled().prefix(min(tracks.count, 15))
            for track in sampleTracks {
                let hash = Self.hash(for: track)
                var stat = TrackStatistics(trackHash: hash)
                stat.playCount = 1
                stat.skipCount = 6
                stat.totalTimeListened = 4
                stat.lastSkipDate = now
                stat.skipHistory = [now, now.addingTimeInterval(-1000), now.addingTimeInterval(-5000)]
                statistics[hash] = stat
            }
            isDirty = true
            flush()
        }
    }

    func statistics(for track: Track) -> TrackStatistics? {
        loadIfNeeded()
        return statistics[Self.hash(for: track)]
    }

    func allStatistics() -> [String: TrackStatistics] {
        loadIfNeeded()
        return statistics
    }

    nonisolated static func hash(for track: Track) -> String {
        if let cue = track.cueStartTime {
            return "\(track.url.path)|cue_\(cue)|\(track.duration)"
        }
        return "\(track.url.path)|\(track.duration)"
    }

    private static func limitHistory(_ dates: [Date], days: Int) -> [Date] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return dates.filter { $0 >= cutoff }
    }

    private func scheduleRecommendationsUpdate(debounce: TimeInterval = 0.5) {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = self
            await RecommendationService.shared.invalidateCache()
            await MainActor.run {
                NotificationCenter.default.post(name: .recommendationsDidUpdate, object: nil)
            }
        }
    }

    private func scheduleSave(debounce: TimeInterval = 1.0) {
        isDirty = true
        let snapshot = try? JSONEncoder().encode(statistics)
        storage.lock.withLock {
            storage.encodedSnapshot = snapshot
            storage.isDirty = true
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            if !Task.isCancelled {
                await self?.flush()
            }
        }
        scheduleRecommendationsUpdate(debounce: 0.5)
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        isDirty = false
        storage.lock.withLock { storage.isDirty = false }
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    nonisolated func flushSync() {
        let (data, shouldWrite): (Data?, Bool) = storage.lock.withLock {
            guard storage.isDirty, let data = storage.encodedSnapshot else { return (nil, false) }
            storage.isDirty = false
            return (data, true)
        }
        guard shouldWrite, let data else { return }
        try? data.write(to: Self.storageFileURL, options: .atomicWrite)
    }
}
