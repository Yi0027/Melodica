import Foundation

final class RecommendationService {
    static let shared = RecommendationService()

    private init() {}

    private enum Rec {
        static let highRating = 200
        static let underratedLower = 160
        static let lowPlays = 5
        static let minDaysNotPlayed = 45.0
        static let recentDays = 30.0
        static let archiveDays = 180.0
        static let maxTracksPerArtist = 3
        static let listenRatio = 0.3
        static let maxSectionItems = 1000

        static let explorationNoiseRatio = 0.05
        static let playCountHalfLifeDays = 30.0
    }

    private var statsCache: [UUID: TrackStatistics] = [:]
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 60
    private var explorationSeed: UInt64 = 0

    // MARK: - Главный метод

    func buildSections(
        from tracks: [Track],
        limit: Int = 10
    ) -> [RecommendationSection] {
        guard !tracks.isEmpty else { return [] }
        guard limit > 0 else { return [] }

        updateExplorationSeedIfNeeded()

        let safeLimit = min(limit, Rec.maxSectionItems)

        let stats = statisticsMap(for: tracks)

        let availableTracks = tracks.filter { track in
            guard let stat = stats[track.id] else { return true }
            return !stat.isEffectivelyBlocked
        }

        var sections: [RecommendationSection] = []

        if let section = timeOfDaySection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = weekdaySection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = highRatingLowPlaysSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = underratedSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = favoriteArtistsSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = notPlayedLongTimeSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = archiveRevivalSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = recentlyAddedSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = favoriteGenresSection(
            tracks: availableTracks,
            stats: stats,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        sections.sort {
            sectionPriority($0.type) < sectionPriority($1.type)
        }

        return sections
    }

    // MARK: - Общий список рекомендаций

    func buildMixedRecommendations(
        from tracks: [Track],
        limit: Int = 30
    ) -> [RecommendationItem] {
        let sections = buildSections(from: tracks, limit: 50)

        guard !sections.isEmpty else { return [] }

        var mixedItems: [RecommendationItem] = []
        var seenTracks: Set<UUID> = []

        for section in sections {
            if let firstItem = section.items.first,
               !seenTracks.contains(firstItem.track.id) {
                seenTracks.insert(firstItem.track.id)
                mixedItems.append(firstItem)
            }
        }

        let remaining = sections
            .flatMap { $0.items }
            .filter { !seenTracks.contains($0.track.id) }
            .sorted { $0.score > $1.score }

        for item in remaining {
            if seenTracks.contains(item.track.id) { continue }
            seenTracks.insert(item.track.id)
            mixedItems.append(item)
        }

        let normalized = normalizeScores(mixedItems)

        return Array(
            normalized
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }

    // MARK: - Приоритет секций

    private func sectionPriority(_ type: RecommendationType) -> Int {
        switch type {
        case .timeOfDay: return 0
        case .weekday: return 1
        case .highRatingLowPlays: return 2
        case .underrated: return 3
        case .favoriteArtist: return 4
        case .notPlayedLongTime: return 5
        case .archiveRevival: return 6
        case .recentlyAdded: return 7
        case .favoriteGenre: return 8
        }
    }

    // MARK: - Время суток

    private func timeOfDaySection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        let hour = Calendar.current.component(.hour, from: Date())
        let slot = timeSlot(for: hour)

        var items: [RecommendationItem] = []

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let hours = (slot.lower...slot.upper).map { (($0 % 24) + 24) % 24 }

            let totalPlays = hours.reduce(0) { sum, h in
                sum + (stat.timeOfDay.indices.contains(h) ? stat.timeOfDay[h] : 0)
            }

            guard totalPlays > 0 else { continue }

            let score = Double(totalPlays) * 20 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .timeOfDay,
                    score: score,
                    reason: slot.name
                )
            )
        }

        return createSection(type: .timeOfDay, from: items, limit: limit)
    }

    // MARK: - День недели

    private func weekdaySection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        let weekday = Calendar.current.component(.weekday, from: Date()) - 1
        let isWeekend = weekday == 0 || weekday == 6

        var items: [RecommendationItem] = []

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let weekendPlays = stat.dayOfWeek[0] + stat.dayOfWeek[6]

            let weekdayPlays = stat.dayOfWeek
                .enumerated()
                .filter { $0.offset >= 1 && $0.offset <= 5 }
                .reduce(0) { $0 + $1.element }

            let relevantPlays = isWeekend ? weekendPlays : weekdayPlays
            let oppositePlays = isWeekend ? weekdayPlays : weekendPlays

            guard relevantPlays > 0, relevantPlays > oppositePlays else {
                continue
            }

            let score = Double(relevantPlays) * 15 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .weekday,
                    score: score,
                    reason: isWeekend
                        ? NSLocalizedString("rec_weekend", comment: "")
                        : NSLocalizedString("rec_weekday", comment: "")
                )
            )
        }

        return createSection(type: .weekday, from: items, limit: limit)
    }

    // MARK: - Высокий рейтинг + мало прослушиваний

    private func highRatingLowPlaysSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []

        for track in tracks {
            if let rating = track.rating {
                guard rating >= Rec.highRating else { continue }
            }

            let playCount = stats[track.id]?.playCount ?? 0
            guard playCount <= Rec.lowPlays else { continue }

            let ratingScore: Double

            if let rating = track.rating {
                ratingScore = min(Double(rating) / 2.55, 100)
            } else {
                ratingScore = 50
            }

            let score = ratingScore - Double(playCount) * 2 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .highRatingLowPlays,
                    score: score,
                    reason: track.rating.map { "\($0)" } ?? ""
                )
            )
        }

        return createSection(type: .highRatingLowPlays, from: items, limit: limit)
    }

    // MARK: - Недооценённые

    private func underratedSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []

        for track in tracks {
            if let rating = track.rating {
                guard rating >= Rec.underratedLower, rating < Rec.highRating else {
                    continue
                }
            }

            let stat = stats[track.id]
            let playCount = stat?.playCount ?? 0
            let skipCount = stat?.skipCount ?? 0

            guard playCount <= Rec.lowPlays else { continue }
            guard skipCount == 0 else { continue }

            let ratingScore: Double

            if let rating = track.rating {
                ratingScore = min(Double(rating) / 2.5, 75)
            } else {
                ratingScore = 40
            }

            let score = ratingScore - Double(playCount) * 2 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .underrated,
                    score: score,
                    reason: track.rating.map { "\($0)" } ?? ""
                )
            )
        }

        return createSection(type: .underrated, from: items, limit: limit)
    }

    // MARK: - Любимые исполнители

    private func favoriteArtistsSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var artistPlays: [String: Double] = [:]

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let plays = weightedPlayCount(for: stat)
            guard plays > 0 else { continue }

            let artist = track.albumArtist ?? track.artist
            artistPlays[artist, default: 0] += plays
        }

        guard !artistPlays.isEmpty else { return nil }

        let topArtists = artistPlays
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        var items: [RecommendationItem] = []

        for track in tracks {
            let artist = track.albumArtist ?? track.artist
            guard topArtists.contains(artist) else { continue }

            let stat = stats[track.id]
            let plays = stat.map { weightedPlayCount(for: $0) } ?? 0

            let score = min(plays, 100) + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .favoriteArtist,
                    score: score,
                    reason: artist
                )
            )
        }

        guard !items.isEmpty else { return nil }

        var artistTrackCounts: [String: Int] = [:]
        var limitedItems: [RecommendationItem] = []

        for item in items.sorted(by: { $0.score > $1.score }) {
            let artist = item.track.albumArtist ?? item.track.artist

            if artistTrackCounts[artist, default: 0] < Rec.maxTracksPerArtist {
                artistTrackCounts[artist, default: 0] += 1
                limitedItems.append(item)
            }
        }

        return createSection(type: .favoriteArtist, from: limitedItems, limit: limit)
    }

    // MARK: - Давно не слушали

    private func notPlayedLongTimeSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard let stat = stats[track.id] else { continue }
            guard stat.playCount > 2, stat.playCount <= 10 else { continue }
            guard let lastPlayed = stat.lastPlayedDate else { continue }

            let daysSince = now.timeIntervalSince(lastPlayed) / 86_400
            
            guard daysSince >= 0,
                  daysSince > Rec.minDaysNotPlayed,
                  !daysSince.isNaN,
                  !daysSince.isInfinite else {
                continue
            }

            let score = min(daysSince, 365) / 3.65 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .notPlayedLongTime,
                    score: score,
                    reason: "\(Int(daysSince))"
                )
            )
        }

        return createSection(type: .notPlayedLongTime, from: items, limit: limit)
    }

    // MARK: - Реанимация архива

    private func archiveRevivalSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard let stat = stats[track.id] else { continue }
            guard stat.playCount > 10 else { continue }
            guard let lastPlayed = stat.lastPlayedDate else { continue }

            let daysSince = now.timeIntervalSince(lastPlayed) / 86_400
            
            guard daysSince >= 0,
                  daysSince > Rec.archiveDays,
                  !daysSince.isNaN,
                  !daysSince.isInfinite else {
                continue
            }

            let score = min(daysSince, 365) / 5 + Double(min(stat.playCount, 100)) / 2
            items.append(
                RecommendationItem(
                    track: track,
                    type: .archiveRevival,
                    score: score,
                    reason: "\(Int(daysSince))"
                )
            )
        }

        return createSection(type: .archiveRevival, from: items, limit: limit)
    }

    // MARK: - Недавно добавленные

    private func recentlyAddedSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard track.duration > 0 else { continue }

            guard let stat = stats[track.id],
                  let addedDate = stat.libraryAddedDate else {
                continue
            }

            let daysSinceAdded = now.timeIntervalSince(addedDate) / 86_400

            guard daysSinceAdded >= 0,
                  daysSinceAdded <= Rec.recentDays,
                  !daysSinceAdded.isNaN,
                  !daysSinceAdded.isInfinite else {
                continue
            }

            guard stat.totalTimeListened > track.duration * Rec.listenRatio else {
                continue
            }

            let score = (Rec.recentDays - daysSinceAdded) / 0.3 + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .recentlyAdded,
                    score: score,
                    reason: "\(Int(daysSinceAdded))"
                )
            )
        }

        return createSection(type: .recentlyAdded, from: items, limit: limit)
    }

    // MARK: - Любимые жанры

    private func favoriteGenresSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        limit: Int
    ) -> RecommendationSection? {
        var genrePlays: [String: Double] = [:]

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let plays = weightedPlayCount(for: stat)
            guard plays > 0 else { continue }

            for genre in genres(of: track) {
                genrePlays[genre, default: 0] += plays
            }
        }

        guard !genrePlays.isEmpty else { return nil }

        let topGenres = genrePlays
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        var items: [RecommendationItem] = []

        for track in tracks {
            let trackGenres = genres(of: track)
            guard trackGenres.contains(where: { topGenres.contains($0) }) else {
                continue
            }

            let stat = stats[track.id]
            let plays = stat.map { weightedPlayCount(for: $0) } ?? 0

            let score = min(plays, 100) + baseScore(for: track)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .favoriteGenre,
                    score: score,
                    reason: trackGenres.joined(separator: ", ")
                )
            )
        }

        return createSection(type: .favoriteGenre, from: items, limit: limit)
    }

    // MARK: - Вспомогательное

    private func weightedPlayCount(for stat: TrackStatistics) -> Double {
        let now = Date()

        var weighted = 0.0

        for playDate in stat.playHistory {
            let daysAgo = now.timeIntervalSince(playDate) / 86_400
            weighted += exp(-daysAgo / Rec.playCountHalfLifeDays)
        }

        return weighted
    }

    private func timeSlot(for hour: Int) -> (lower: Int, upper: Int, name: String) {
        switch hour {
        case 5..<12:
            return (5, 11, NSLocalizedString("rec_morning", comment: ""))
        case 12..<17:
            return (12, 16, NSLocalizedString("rec_day", comment: ""))
        case 17..<23:
            return (17, 22, NSLocalizedString("rec_evening", comment: ""))
        default:
            return (23, 26, NSLocalizedString("rec_night", comment: ""))
        }
    }

    private func updateExplorationSeedIfNeeded() {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let newSeed = UInt64(day)

        if explorationSeed != newSeed {
            explorationSeed = newSeed
        }
    }

    private func normalizeScores(
        _ items: [RecommendationItem]
    ) -> [RecommendationItem] {
        guard let maxScore = items.map({ $0.score }).max(), maxScore > 0 else {
            return items
        }

        return items.map { item in
            let normalizedScore = min(item.score / maxScore * 100, 100)

            return RecommendationItem(
                track: item.track,
                type: item.type,
                score: normalizedScore,
                reason: item.reason
            )
        }
    }

    private func createSection(
        type: RecommendationType,
        from items: [RecommendationItem],
        limit: Int
    ) -> RecommendationSection? {
        guard !items.isEmpty else { return nil }

        let unique = uniqueItems(items)
            .map { item in
                RecommendationItem(
                    track: item.track,
                    type: item.type,
                    score: item.score + explorationNoise(
                        for: item.score,
                        trackID: item.track.id
                    ),
                    reason: item.reason
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return RecommendationSection(
            type: type,
            items: Array(unique)
        )
    }

    private func explorationNoise(
        for score: Double,
        trackID: UUID
    ) -> Double {
        var hasher = Hasher()
        hasher.combine(trackID)
        hasher.combine(explorationSeed)

        let hashValue = hasher.finalize()
        let normalized = Double(hashValue % 1000) / 500.0 - 1.0

        return normalized * score * Rec.explorationNoiseRatio
    }

    private func uniqueItems(
        _ items: [RecommendationItem]
    ) -> [RecommendationItem] {
        var seen: Set<String> = []
        var result: [RecommendationItem] = []

        for item in items {
            let key = "\(item.track.id.uuidString)|\(item.type.rawValue)"

            if !seen.contains(key) {
                seen.insert(key)
                result.append(item)
            }
        }

        return result
    }

    private func baseScore(for track: Track) -> Double {
        var score = 0.0

        if let rating = track.rating, rating > 0 {
            score += min(Double(rating) / 25.5, 10)
        }

        if track.hasLyrics {
            score += 2
        }

        if track.albumArtURL != nil {
            score += 1
        }

        return min(score, 15)
    }

    private func statisticsMap(
        for tracks: [Track]
    ) -> [UUID: TrackStatistics] {
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration {
            return statsCache
        }

        let allStats = TrackStatisticsService.shared.allStatistics()

        var result: [UUID: TrackStatistics] = [:]

        for track in tracks {
            let hash = TrackStatisticsService.hash(for: track)

            if let stat = allStats[hash] {
                result[track.id] = stat
            }
        }

        statsCache = result
        lastCacheUpdate = Date()

        return result
    }

    private func genres(of track: Track) -> [String] {
        let raw = track.genre ?? "Unknown"

        return raw
            .components(separatedBy: CharacterSet(charactersIn: "/,&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
