import Foundation

enum SmartPlaylistRule: Identifiable, Codable, Hashable {
    case titleContains(String)
    case artistContains(String)
    case artistEquals(String)
    case albumContains(String)
    case albumEquals(String)
    case genreContains(String)
    case genreEquals(String)

    case yearGreaterThan(Int)
    case yearLessThan(Int)
    case yearEquals(Int)

    case durationGreaterThan(TimeInterval)
    case durationLessThan(TimeInterval)

    case ratingGreaterThan(Int)
    case ratingLessThan(Int)
    case ratingEquals(Int)
    case hasRating(Bool)

    case hasLyrics(Bool)
    case hasReplayGain(Bool)
    case isFavorite(Bool)

    var id: String {
        switch self {
        case .titleContains:       return "titleContains"
        case .artistContains:      return "artistContains"
        case .artistEquals:        return "artistEquals"
        case .albumContains:       return "albumContains"
        case .albumEquals:         return "albumEquals"
        case .genreContains:       return "genreContains"
        case .genreEquals:         return "genreEquals"
        case .yearGreaterThan:     return "yearGreaterThan"
        case .yearLessThan:        return "yearLessThan"
        case .yearEquals:          return "yearEquals"
        case .durationGreaterThan: return "durationGreaterThan"
        case .durationLessThan:    return "durationLessThan"
        case .ratingGreaterThan:   return "ratingGreaterThan"
        case .ratingLessThan:      return "ratingLessThan"
        case .ratingEquals:        return "ratingEquals"
        case .hasRating:           return "hasRating"
        case .hasLyrics:           return "hasLyrics"
        case .hasReplayGain:       return "hasReplayGain"
        case .isFavorite:          return "isFavorite"
        }
    }

    var kind: Kind {
        switch self {
        case .titleContains,
             .artistContains,
             .artistEquals,
             .albumContains,
             .albumEquals,
             .genreContains,
             .genreEquals:
            return .text

        case .yearGreaterThan,
             .yearLessThan,
             .yearEquals,
             .durationGreaterThan,
             .durationLessThan,
             .ratingGreaterThan,
             .ratingLessThan,
             .ratingEquals:
            return .number

        case .hasRating,
             .hasLyrics,
             .hasReplayGain,
             .isFavorite:
            return .flag
        }
    }

    enum Kind {
        case text
        case number
        case flag
    }

    static var allCases: [SmartPlaylistRule] {
        [
            .titleContains(""),
            .artistContains(""),
            .artistEquals(""),
            .albumContains(""),
            .albumEquals(""),
            .genreContains(""),
            .genreEquals(""),

            .yearGreaterThan(0),
            .yearLessThan(0),
            .yearEquals(0),

            .durationGreaterThan(0),
            .durationLessThan(0),

            .ratingGreaterThan(0),
            .ratingLessThan(0),
            .ratingEquals(0),
            .hasRating(true),

            .hasLyrics(true),
            .hasReplayGain(true),
            .isFavorite(true)
        ]
    }

    var localizationKey: String {
        switch self {
        case .titleContains:       return "rule_title_contains"
        case .artistContains:      return "rule_artist_contains"
        case .artistEquals:        return "rule_artist_equals"
        case .albumContains:       return "rule_album_contains"
        case .albumEquals:         return "rule_album_equals"
        case .genreContains:       return "rule_genre_contains"
        case .genreEquals:         return "rule_genre_equals"
        case .yearGreaterThan:     return "rule_year_greater"
        case .yearLessThan:        return "rule_year_less"
        case .yearEquals:          return "rule_year_equal"
        case .durationGreaterThan: return "rule_duration_greater"
        case .durationLessThan:    return "rule_duration_less"
        case .ratingGreaterThan:   return "rule_rating_greater"
        case .ratingLessThan:      return "rule_rating_less"
        case .ratingEquals:        return "rule_rating_equal"
        case .hasRating:           return "rule_has_rating"
        case .hasLyrics:           return "rule_has_lyrics"
        case .hasReplayGain:       return "rule_has_replaygain"
        case .isFavorite:          return "rule_is_favorite"
        }
    }

    var displayName: String {
        NSLocalizedString(localizationKey, comment: "")
    }

    var displayValue: String {
        switch self {
        case .titleContains(let v),
             .artistContains(let v),
             .artistEquals(let v),
             .albumContains(let v),
             .albumEquals(let v),
             .genreContains(let v),
             .genreEquals(let v):
            return v

        case .yearGreaterThan(let v),
             .yearLessThan(let v),
             .yearEquals(let v),
             .ratingGreaterThan(let v),
             .ratingLessThan(let v),
             .ratingEquals(let v):
            return String(v)

        case .durationGreaterThan(let v),
             .durationLessThan(let v):
            return formatDuration(v)

        case .hasRating(let v),
             .hasLyrics(let v),
             .hasReplayGain(let v),
             .isFavorite(let v):
            return v ? "YES" : "NO"
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let m = Int(value) / 60
        let s = Int(value) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
