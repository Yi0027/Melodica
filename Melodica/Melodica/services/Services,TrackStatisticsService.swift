import Foundation

final class TrackStatisticsService {
    static let shared = TrackStatisticsService()

    private var statistics: [String: TrackStatistics] = [:]
    private let fileURL: URL

    private init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")

        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        fileURL = folder.appendingPathComponent("track_statistics.json")
        load()
    }

    func recordPlay(
        track: Track,
        context: String,
        listenedDuration: TimeInterval
    ) {
        guard SettingsManager.shared.trackStatisticsEnabled else { return }

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
        save()
    }

    func recordSkip(
        track: Track,
        context: String
    ) {
        guard SettingsManager.shared.trackStatisticsEnabled else { return }

        let hash = Self.hash(for: track)
        var stats = statistics[hash] ?? TrackStatistics(trackHash: hash)

        let now = Date()

        stats.skipCount += 1
        stats.lastSkipDate = now
        stats.skipHistory.append(now)
        stats.skipHistory = Self.limitHistory(stats.skipHistory, days: 120)

        var contextStats = stats.contextStats[context] ?? ContextStatistics()
        contextStats.skipCount += 1
        contextStats.lastPlayedDate = now
        stats.contextStats[context] = contextStats

        statistics[hash] = stats
        save()
    }

    func setBlocked(
        track: Track,
        until date: Date
    ) {
        let hash = Self.hash(for: track)

        guard var stats = statistics[hash] else { return }

        stats.blockedUntil = date
        statistics[hash] = stats
        save()
    }

    func statistics(for track: Track) -> TrackStatistics? {
        statistics[Self.hash(for: track)]
    }

    func allStatistics() -> [String: TrackStatistics] {
        statistics
    }

    static func hash(for track: Track) -> String {
        "\(track.url.path)|\(track.duration)"
    }

    private static func limitHistory(_ dates: [Date], days: Int) -> [Date] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return dates.filter { $0 >= cutoff }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    private func load() {
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
}
