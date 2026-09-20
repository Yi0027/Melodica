import Foundation

enum RecommendationType: String, Codable {
    case favoriteArtist
    case favoriteGenre
    case highRatingLowPlays
    case notPlayedLongTime
    case recentlyAdded
    case timeOfDay
    case archiveRevival
    case underrated
    case weekday

    var titleKey: String {
        switch self {
        case .favoriteArtist:
            return "rec_favorite_artist"
        case .favoriteGenre:
            return "rec_favorite_genre"
        case .highRatingLowPlays:
            return "rec_high_rating_low_plays"
        case .notPlayedLongTime:
            return "rec_not_played_long_time"
        case .recentlyAdded:
            return "rec_recently_added"
        case .timeOfDay:
            return "rec_time_of_day"
        case .weekday:
            return "rec_weekday"
        case .archiveRevival:
            return "rec_archive_revival"
        case .underrated:
            return "rec_underrated"
        }
    }

    var icon: String {
        switch self {
        case .favoriteArtist:
            return "person.crop.circle.fill"
        case .favoriteGenre:
            return "guitars.fill"
        case .highRatingLowPlays:
            return "star.fill"
        case .notPlayedLongTime:
            return "clock.arrow.circlepath"
        case .recentlyAdded:
            return "sparkles"
        case .timeOfDay:
            return "sun.horizon.fill"
        case .weekday:
            return "calendar"
        case .archiveRevival:
            return "archivebox.fill"
        case .underrated:
            return "eye.fill"
        }
    }
}

struct RecommendationItem: Identifiable, Hashable {
    var id: String {
        "\(track.id.uuidString)|\(type.rawValue)"
    }

    let track: Track
    let type: RecommendationType
    let score: Double
    let reason: String

    init(
        track: Track,
        type: RecommendationType,
        score: Double,
        reason: String
    ) {
        self.track = track
        self.type = type
        self.score = score
        self.reason = reason
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(track.id)
        hasher.combine(type)
    }

    static func == (lhs: RecommendationItem, rhs: RecommendationItem) -> Bool {
        lhs.track.id == rhs.track.id && lhs.type == rhs.type
    }
}

struct RecommendationSection: Identifiable {
    let id: UUID
    let type: RecommendationType
    let title: String
    let items: [RecommendationItem]

    init(type: RecommendationType, items: [RecommendationItem]) {
        self.id = UUID()
        self.type = type
        self.title = NSLocalizedString(type.titleKey, comment: "")
        self.items = items
    }
}
