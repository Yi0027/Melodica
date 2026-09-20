import Foundation

struct SmartPlaylistEngine {

    static func evaluate(
        _ track: Track,
        rules: [SmartPlaylistRule],
        matchAll: Bool,
        favoriteURLs: Set<String>
    ) -> Bool {
        guard !rules.isEmpty else { return false }

        let results = rules.map {
            evaluate(track, rule: $0, favoriteURLs: favoriteURLs)
        }

        return matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }

    static func evaluate(
        _ track: Track,
        rule: SmartPlaylistRule,
        favoriteURLs: Set<String>
    ) -> Bool {
        switch rule {
        case .titleContains(let text):
            return track.title.normalized().localizedCaseInsensitiveContains(text.normalized())

        case .artistContains(let text):
            return track.artist.normalized().localizedCaseInsensitiveContains(text.normalized())

        case .artistEquals(let text):
            let artists = track.artist
                .components(separatedBy: CharacterSet(charactersIn: "&,/"))
                .map { $0.normalized() }

            return artists.contains {
                $0.caseInsensitiveCompare(text.normalized()) == .orderedSame
            }

        case .albumContains(let text):
            return track.album.normalized().localizedCaseInsensitiveContains(text.normalized())

        case .albumEquals(let text):
            return track.album.normalized().caseInsensitiveCompare(text.normalized()) == .orderedSame

        case .genreContains(let text):
            return (track.genre ?? "").normalized().localizedCaseInsensitiveContains(text.normalized())

        case .genreEquals(let text):
            let genres = (track.genre ?? "")
                .components(separatedBy: CharacterSet(charactersIn: "&,/"))
                .map { $0.normalized() }

            return genres.contains {
                $0.caseInsensitiveCompare(text.normalized()) == .orderedSame
            }

        case .yearGreaterThan(let year):
            return (track.year ?? .min) > year

        case .yearLessThan(let year):
            return (track.year ?? .max) < year

        case .yearEquals(let year):
            return track.year == year

        case .durationGreaterThan(let duration):
            return track.duration > duration

        case .durationLessThan(let duration):
            return track.duration < duration

        case .hasLyrics(let value):
            return (track.hasLyrics || track.unsyncedLyrics != nil) == value

        case .hasReplayGain(let value):
            return (track.replayGain != nil) == value

        case .hasRating(let value):
            let hasRating = (track.rating ?? 0) > 0
            return hasRating == value

        case .ratingGreaterThan(let value):
            let stars = (track.rating ?? 0) / 51
            return stars > value

        case .ratingLessThan(let value):
            let stars = (track.rating ?? 0) / 51
            return stars < value

        case .ratingEquals(let value):
            let stars = (track.rating ?? 0) / 51
            return stars == value

        case .isFavorite(let value):
            let key = track.url.standardizedFileURL.path
            return favoriteURLs.contains(key) == value
        }
    }
}

private extension String {
    func normalized() -> String {
        self
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
