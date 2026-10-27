import Foundation

struct LibraryStatistics: Codable {
    var totalTracks: Int = 0
    var totalDuration: TimeInterval = 0
    var totalFileSize: UInt64 = 0

    var albumCount: Int = 0
    var artistCount: Int = 0
    var genreCount: Int = 0

    var formatCounts: [String: Int] = [:]
    var topArtists: [TopEntry] = []
    var topAlbums: [TopEntry] = []
    var topGenres: [TopEntry] = []

    var replayGainTracks: Int = 0
    var artworkTracks: Int = 0

    var lyricsTracks: Int = 0
    var embeddedLyricsTracks: Int = 0
    var lrcLyricsTracks: Int = 0

    var averageTrackDuration: TimeInterval {
        guard totalTracks > 0 else { return 0 }
        return totalDuration / Double(totalTracks)
    }

    var formattedTotalDuration: String {
        Self.formatDuration(totalDuration)
    }

    var formattedAverageDuration: String {
        Self.formatDuration(averageTrackDuration)
    }

    var formattedFileSize: String {
        Self.formatBytes(totalFileSize)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)

        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days) \(NSLocalizedString("days_short", comment: "")) \(hours) \(NSLocalizedString("hours_short", comment: "")) \(minutes) \(NSLocalizedString("minutes_short", comment: ""))"
        }

        if hours > 0 {
            return "\(hours) \(NSLocalizedString("hours_short", comment: "")) \(minutes) \(NSLocalizedString("minutes_short", comment: ""))"
        }

        if minutes > 0 {
            return "\(minutes) \(NSLocalizedString("minutes_short", comment: "")) \(seconds) \(NSLocalizedString("seconds_short", comment: ""))"
        }

        return "\(seconds) \(NSLocalizedString("seconds_short", comment: ""))"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct TopEntry: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let count: Int
    let duration: TimeInterval
}
