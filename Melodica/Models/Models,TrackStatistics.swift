import Foundation

nonisolated struct TrackStatistics: Codable {
    let trackHash: String

    var playCount: Int = 0
    var skipCount: Int = 0

    var lastPlayedDate: Date?
    var firstPlayedDate: Date?
    var lastSkipDate: Date?

    var totalTimeListened: TimeInterval = 0

    var timeOfDay: [Int] = Array(repeating: 0, count: 24)
    var dayOfWeek: [Int] = Array(repeating: 0, count: 7)

    var playbackContext: [String: Int] = [:]

    var playHistory: [Date] = []
    var skipHistory: [Date] = []
    var libraryAddedDate: Date?
    var contextStats: [String: ContextStatistics] = [:]
    var genrePenalties: [String: Date] = [:]

    var blockedUntil: Date?

    var blockReason: String? {
        if let blockedUntil, Date() < blockedUntil {
            return "Temporarily blocked until \(blockedUntil.formatted(date: .abbreviated, time: .shortened))"
        }

        if skipCount >= 4, totalTimeListened < 10 {
            return "Repeatedly skipped quickly (\(skipCount) skips, <10s listened)"
        }

        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let recentSkips = skipHistory.filter { $0 >= cutoff }.count
        let recentPlays = playHistory.filter { $0 >= cutoff }.count
        if recentSkips >= 3 && recentPlays == 0 {
            return "Skipped 3+ times in the past week with 0 completed plays"
        }
        if (recentSkips + recentPlays) >= 4 {
            let skipRate = Double(recentSkips) / Double(recentSkips + recentPlays)
            if skipRate > 0.65 {
                return "Recent skip rate exceeds 65% in past 7 days"
            }
        }

        if let lastPlayed = lastPlayedDate,
           Date().timeIntervalSince(lastPlayed) < 20 * 60 {
            let minsAgo = Int(Date().timeIntervalSince(lastPlayed) / 60)
            return "Played \(minsAgo)m ago (20m cooldown)"
        }

        return nil
    }

    var isEffectivelyBlocked: Bool {
        blockReason != nil
    }
}

nonisolated struct ContextStatistics: Codable {
    var playCount: Int = 0
    var skipCount: Int = 0
    var totalListened: TimeInterval = 0
    var lastPlayedDate: Date?
}
