import Foundation

struct TrackStatistics: Codable {
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

    var isEffectivelyBlocked: Bool {
        if let blockedUntil, Date() < blockedUntil {
            return true
        }

        if skipCount > 3, totalTimeListened < 5 {
            return true
        }

        if skipCount > playCount, playCount > 1 {
            return true
        }

        if playCount > 10 {
            let cutoff = Date().addingTimeInterval(-7 * 86_400)

            let lastWeekAttempts = playHistory.filter {
                $0 >= cutoff
            }.count

            let lastWeekSkips = skipHistory.filter {
                $0 >= cutoff
            }.count

            if lastWeekAttempts > 3 {
                let skipRate = Double(lastWeekSkips) / Double(lastWeekAttempts)

                if skipRate > 0.3 {
                    return true
                }
            }
        }

        if let lastPlayed = lastPlayedDate,
           Date().timeIntervalSince(lastPlayed) < 30 * 60 {
            return true
        }

        return false
    }
}

struct ContextStatistics: Codable {
    var playCount: Int = 0
    var skipCount: Int = 0
    var totalListened: TimeInterval = 0
    var lastPlayedDate: Date?
}
