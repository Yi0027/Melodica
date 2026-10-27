import Foundation

extension Notification.Name {
    static let recommendationsDidUpdate = Notification.Name("recommendationsDidUpdate")
}

actor RecommendationService {
    static let shared = RecommendationService()

    private init() {}

    private enum Rec {
        static let highRating = 200        // ~4-5 stars (rating out of 255)
        static let underratedLower = 150    // ~3-4 stars
        static let lowPlays = 5
        static let minDaysNotPlayed = 30.0
        static let recentDays = 30.0
        static let archiveDays = 180.0
        static let maxTracksPerArtist = 3
        static let maxSectionItems = 1000

        static let explorationNoiseRatio = 0.05
        static let playCountHalfLifeDays = 30.0
    }

    private var allStatsCache: [String: TrackStatistics] = [:]
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 60
    private var explorationSeed: UInt64 = 0

    // Simulation overrides for developer testing
    private var simulatedHour: Int?
    private var simulatedWeekday: Int?

    // MARK: - Simulation & Testing Controls

    func setSimulatedContext(hour: Int?, weekday: Int?) {
        self.simulatedHour = hour
        self.simulatedWeekday = weekday
    }

    func currentSimulatedContext() -> (hour: Int?, weekday: Int?) {
        (simulatedHour, simulatedWeekday)
    }

    func invalidateCache() {
        allStatsCache = [:]
        lastCacheUpdate = nil
    }

    // MARK: - Single-pass Full Recommendations Builder

    func buildAll(
        from tracks: [Track],
        favoriteTrackIDs: Set<UUID> = [],
        sectionLimit: Int = 10,
        mixedLimit: Int = 30
    ) async -> (sections: [RecommendationSection], mixed: [RecommendationItem]) {
        let sections = await buildSections(
            from: tracks,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: sectionLimit
        )

        let mixed = buildMixedRecommendations(
            from: sections,
            limit: mixedLimit
        )

        return (sections, mixed)
    }

    // MARK: - Main Sections Builder

    func buildSections(
        from tracks: [Track],
        favoriteTrackIDs: Set<UUID> = [],
        limit: Int = 10
    ) async -> [RecommendationSection] {
        guard !tracks.isEmpty else { return [] }
        guard limit > 0 else { return [] }

        updateExplorationSeedIfNeeded()

        let safeLimit = min(limit, Rec.maxSectionItems)
        let stats = await statisticsMap(for: tracks)

        let availableTracks = tracks.filter { track in
            guard let stat = stats[track.id] else { return true }
            return !stat.isEffectivelyBlocked
        }

        var sections: [RecommendationSection] = []

        if let section = timeOfDaySection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = weekdaySection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = highRatingLowPlaysSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = underratedSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = favoriteArtistsSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = notPlayedLongTimeSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = archiveRevivalSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = recentlyAddedSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        if let section = favoriteGenresSection(
            tracks: availableTracks,
            stats: stats,
            favoriteTrackIDs: favoriteTrackIDs,
            limit: safeLimit
        ) {
            sections.append(section)
        }

        sections.sort {
            sectionPriority($0.type) < sectionPriority($1.type)
        }

        return sections
    }

    // MARK: - Mixed Recommendations (Balanced Round-Robin)

    func buildMixedRecommendations(
        from sections: [RecommendationSection],
        limit: Int = 30
    ) -> [RecommendationItem] {
        guard !sections.isEmpty else { return [] }

        // Normalize each section locally (0..100) so sections with higher absolute scores do not displace others
        var sectionQueues: [[RecommendationItem]] = []
        for section in sections {
            guard !section.items.isEmpty else { continue }
            let maxScore = section.items.map { $0.score }.max() ?? 1.0
            let normalized = section.items.map { item in
                let normScore = maxScore > 0 ? (item.score / maxScore) * 100.0 : item.score
                return RecommendationItem(
                    track: item.track,
                    type: item.type,
                    score: normScore,
                    reason: item.reason
                )
            }
            sectionQueues.append(normalized)
        }

        var mixed: [RecommendationItem] = []
        var seenTrackIDs = Set<UUID>()
        var artistCounts: [String: Int] = [:]
        let maxPerArtist = 3

        var hasMore = true
        var round = 0

        while hasMore && mixed.count < limit {
            hasMore = false
            for qIndex in 0..<sectionQueues.count {
                if round < sectionQueues[qIndex].count {
                    hasMore = true
                    let candidate = sectionQueues[qIndex][round]
                    let artist = candidate.track.albumArtist ?? candidate.track.artist

                    if !seenTrackIDs.contains(candidate.track.id) &&
                       artistCounts[artist, default: 0] < maxPerArtist {
                        seenTrackIDs.insert(candidate.track.id)
                        artistCounts[artist, default: 0] += 1
                        mixed.append(candidate)
                        if mixed.count >= limit { break }
                    }
                }
            }
            round += 1
        }

        return mixed
    }

    func buildMixedRecommendations(
        from tracks: [Track],
        favoriteTrackIDs: Set<UUID> = [],
        limit: Int = 30
    ) async -> [RecommendationItem] {
        let sections = await buildSections(from: tracks, favoriteTrackIDs: favoriteTrackIDs, limit: 50)
        return buildMixedRecommendations(from: sections, limit: limit)
    }

    // MARK: - Section Priority

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

    // MARK: - 1. Time of Day (24-Hour Coverage)

    private func timeOfDaySection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        let hour = simulatedHour ?? Calendar.current.component(.hour, from: Date())
        let slot = timeSlot(for: hour)

        var items: [RecommendationItem] = []

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let totalSlotPlays = slot.hours.reduce(0) { sum, h in
                sum + (stat.timeOfDay.indices.contains(h) ? stat.timeOfDay[h] : 0)
            }

            guard totalSlotPlays > 0 else { continue }

            let totalPlays = max(1, stat.playCount)
            let affinity = Double(totalSlotPlays) / Double(totalPlays)
            let isFav = favoriteTrackIDs.contains(track.id)

            // Balance: slot play count + affinity ratio to this specific time window
            let score = Double(totalSlotPlays) * 12.0 + (affinity * 25.0) + baseScore(for: track, isFavorite: isFav)

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

    // MARK: - 2. Day of Week (Weekend vs Weekday Normalization)

    private func weekdaySection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        let weekday = simulatedWeekday ?? (Calendar.current.component(.weekday, from: Date()) - 1)
        let isWeekend = (weekday == 0 || weekday == 6)

        var items: [RecommendationItem] = []

        for track in tracks {
            guard let stat = stats[track.id] else { continue }

            let weekendPlays = stat.dayOfWeek[0] + stat.dayOfWeek[6]
            let weekdayPlays = stat.dayOfWeek.indices.contains(5)
                ? (1...5).reduce(0) { $0 + (stat.dayOfWeek.indices.contains($1) ? stat.dayOfWeek[$1] : 0) }
                : 0

            let avgWeekend = Double(weekendPlays) / 2.0
            let avgWeekday = Double(weekdayPlays) / 5.0

            let relevantAvg = isWeekend ? avgWeekend : avgWeekday
            let oppositeAvg = isWeekend ? avgWeekday : avgWeekend
            let relevantTotal = isWeekend ? weekendPlays : weekdayPlays

            guard relevantTotal > 0, relevantAvg >= oppositeAvg else {
                continue
            }

            let isFav = favoriteTrackIDs.contains(track.id)
            let score = relevantAvg * 15.0 + Double(relevantTotal) * 2.0 + baseScore(for: track, isFavorite: isFav)

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

    // MARK: - 3. High Rating + Low Plays

    private func highRatingLowPlaysSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []

        for track in tracks {
            // Requires an explicitly assigned high rating (4-5 stars)
            guard let rating = track.rating, rating >= Rec.highRating else {
                continue
            }

            let playCount = stats[track.id]?.playCount ?? 0
            guard playCount <= Rec.lowPlays else { continue }

            let ratingScore = min(Double(rating) / 2.55, 100)
            let isFav = favoriteTrackIDs.contains(track.id)
            let score = ratingScore - Double(playCount) * 3 + baseScore(for: track, isFavorite: isFav)

            let stars = String(repeating: "★", count: max(1, track.starRating))
            let playsText = playCount == 1 ? "1 play" : "\(playCount) plays"

            items.append(
                RecommendationItem(
                    track: track,
                    type: .highRatingLowPlays,
                    score: score,
                    reason: "\(stars) · \(playsText)"
                )
            )
        }

        return createSection(type: .highRatingLowPlays, from: items, limit: limit)
    }

    // MARK: - 4. Underrated Gems

    private func underratedSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []

        for track in tracks {
            // Requires an assigned good rating (3-4 stars) with minimal play count
            guard let rating = track.rating,
                  rating >= Rec.underratedLower,
                  rating < Rec.highRating else {
                continue
            }

            let stat = stats[track.id]
            let playCount = stat?.playCount ?? 0
            let skipCount = stat?.skipCount ?? 0

            guard playCount <= Rec.lowPlays else { continue }
            guard skipCount == 0 else { continue }

            let ratingScore = min(Double(rating) / 2.5, 75)
            let isFav = favoriteTrackIDs.contains(track.id)
            let score = ratingScore - Double(playCount) * 2 + baseScore(for: track, isFavorite: isFav)

            let stars = String(repeating: "★", count: max(1, track.starRating))

            items.append(
                RecommendationItem(
                    track: track,
                    type: .underrated,
                    score: score,
                    reason: "\(stars) · Underrated gem"
                )
            )
        }

        return createSection(type: .underrated, from: items, limit: limit)
    }

    // MARK: - 5. Favorite Artists (Filtered Various Artists + Discovery)

    private func favoriteArtistsSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var artistPlays: [String: Double] = [:]
        let ignoredArtists = Set(["various artists", "various", "unknown artist", "unknown", "неизвестный исполнитель"])

        for track in tracks {
            let artist = (track.albumArtist ?? track.artist).trimmingCharacters(in: .whitespaces)
            guard !artist.isEmpty, !ignoredArtists.contains(artist.lowercased()) else { continue }

            guard let stat = stats[track.id] else { continue }
            let plays = weightedPlayCount(for: stat)
            guard plays > 0 else { continue }

            artistPlays[artist, default: 0] += plays
        }

        guard !artistPlays.isEmpty else { return nil }

        let topArtists = artistPlays
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        var items: [RecommendationItem] = []

        for track in tracks {
            let artist = (track.albumArtist ?? track.artist).trimmingCharacters(in: .whitespaces)
            guard topArtists.contains(artist) else { continue }

            let stat = stats[track.id]
            let trackPlays = stat?.playCount ?? 0
            let artistWeight = artistPlays[artist] ?? 0
            let isFav = favoriteTrackIDs.contains(track.id)

            // Discovery: favorite artist provides baseline weight, while unplayed tracks receive discovery bonus
            let artistAffinity = min(artistWeight * 4.0, 50.0)
            let discoveryBonus = (trackPlays == 0) ? 25.0 : ((trackPlays <= 3) ? 15.0 : min(Double(trackPlays), 20.0))
            let score = artistAffinity + discoveryBonus + baseScore(for: track, isFavorite: isFav)

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

    // MARK: - 6. Not Played For a Long Time

    private func notPlayedLongTimeSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard let stat = stats[track.id] else { continue }
            // Requires at least 2 historical plays
            guard stat.playCount >= 2 else { continue }
            guard let lastPlayed = stat.lastPlayedDate else { continue }

            let daysSince = now.timeIntervalSince(lastPlayed) / 86_400

            guard daysSince >= Rec.minDaysNotPlayed,
                  daysSince <= Rec.archiveDays,
                  !daysSince.isNaN,
                  !daysSince.isInfinite else {
                continue
            }

            let isFav = favoriteTrackIDs.contains(track.id)
            let score = min(daysSince, 180) / 2.0 + Double(min(stat.playCount, 20)) + baseScore(for: track, isFavorite: isFav)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .notPlayedLongTime,
                    score: score,
                    reason: "\(Int(daysSince)) days ago"
                )
            )
        }

        return createSection(type: .notPlayedLongTime, from: items, limit: limit)
    }

    // MARK: - 7. Archive Revival (> 180 Days)

    private func archiveRevivalSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard let stat = stats[track.id] else { continue }
            guard stat.playCount >= 5 else { continue }
            guard let lastPlayed = stat.lastPlayedDate else { continue }

            let daysSince = now.timeIntervalSince(lastPlayed) / 86_400

            guard daysSince > Rec.archiveDays,
                  !daysSince.isNaN,
                  !daysSince.isInfinite else {
                continue
            }

            let isFav = favoriteTrackIDs.contains(track.id)
            let score = min(daysSince, 365) / 4.0 + Double(min(stat.playCount, 50)) + baseScore(for: track, isFavorite: isFav)

            items.append(
                RecommendationItem(
                    track: track,
                    type: .archiveRevival,
                    score: score,
                    reason: "\(Int(daysSince)) days ago"
                )
            )
        }

        return createSection(type: .archiveRevival, from: items, limit: limit)
    }

    // MARK: - 8. Recently Added (Library Date or File Creation Date)

    private func recentlyAddedSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var items: [RecommendationItem] = []
        let now = Date()

        for track in tracks {
            guard track.duration > 0 else { continue }

            let stat = stats[track.id]
            let addedDate: Date
            if let date = stat?.libraryAddedDate {
                addedDate = date
            } else if let resourceValues = try? track.url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey]),
                      let fileDate = resourceValues.addedToDirectoryDate ?? resourceValues.creationDate {
                addedDate = fileDate
            } else {
                continue
            }

            let daysSinceAdded = now.timeIntervalSince(addedDate) / 86_400

            guard daysSinceAdded >= 0,
                  daysSinceAdded <= Rec.recentDays,
                  !daysSinceAdded.isNaN,
                  !daysSinceAdded.isInfinite else {
                continue
            }

            let isFav = favoriteTrackIDs.contains(track.id)
            // New files receive high priority; prior playback is not required
            let score = (Rec.recentDays - daysSinceAdded) * 2.5 + baseScore(for: track, isFavorite: isFav)

            let daysInt = Int(daysSinceAdded)
            let timeAgoText = daysInt == 0 ? "Added today" : "\(daysInt)d ago"

            items.append(
                RecommendationItem(
                    track: track,
                    type: .recentlyAdded,
                    score: score,
                    reason: timeAgoText
                )
            )
        }

        return createSection(type: .recentlyAdded, from: items, limit: limit)
    }

    // MARK: - 9. Favorite Genres (Artist Diversity)

    private func favoriteGenresSection(
        tracks: [Track],
        stats: [UUID: TrackStatistics],
        favoriteTrackIDs: Set<UUID>,
        limit: Int
    ) -> RecommendationSection? {
        var genrePlays: [String: Double] = [:]
        let ignoredGenres = Set(["unknown", "неизвестный жанр", "other", ""])

        for track in tracks {
            guard let stat = stats[track.id] else { continue }
            let plays = weightedPlayCount(for: stat)
            guard plays > 0 else { continue }

            for genre in genres(of: track) {
                let clean = genre.trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty, !ignoredGenres.contains(clean.lowercased()) else { continue }
                let normalizedKey = clean.capitalized
                genrePlays[normalizedKey, default: 0] += plays
            }
        }

        guard !genrePlays.isEmpty else { return nil }

        let topGenres = Set(
            genrePlays
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0.key }
        )

        var items: [RecommendationItem] = []

        for track in tracks {
            let trackGenres = genres(of: track).map { $0.trimmingCharacters(in: .whitespaces).capitalized }
            guard trackGenres.contains(where: { topGenres.contains($0) }) else {
                continue
            }

            let stat = stats[track.id]
            let trackPlays = stat?.playCount ?? 0
            let isFav = favoriteTrackIDs.contains(track.id)

            // Discovery bonus for tracks in favorite genres
            let discovery = trackPlays == 0 ? 15.0 : min(Double(trackPlays), 20.0)
            let score = discovery + baseScore(for: track, isFavorite: isFav)

            let matchedGenres = trackGenres.filter { topGenres.contains($0) }
            let reasonText = matchedGenres.isEmpty ? trackGenres.joined(separator: ", ") : matchedGenres.joined(separator: ", ")

            items.append(
                RecommendationItem(
                    track: track,
                    type: .favoriteGenre,
                    score: score,
                    reason: reasonText
                )
            )
        }

        guard !items.isEmpty else { return nil }

        // Cap tracks per artist in genre collection
        var artistCounts: [String: Int] = [:]
        var limitedItems: [RecommendationItem] = []

        for item in items.sorted(by: { $0.score > $1.score }) {
            let artist = item.track.albumArtist ?? item.track.artist
            if artistCounts[artist, default: 0] < Rec.maxTracksPerArtist {
                artistCounts[artist, default: 0] += 1
                limitedItems.append(item)
            }
        }

        return createSection(type: .favoriteGenre, from: limitedItems, limit: limit)
    }

    // MARK: - Helpers

    private func weightedPlayCount(for stat: TrackStatistics) -> Double {
        let now = Date()
        var weighted = 0.0

        for playDate in stat.playHistory {
            let daysAgo = now.timeIntervalSince(playDate) / 86_400
            weighted += exp(-daysAgo / Rec.playCountHalfLifeDays)
        }

        return weighted
    }

    private func timeSlot(for hour: Int) -> (hours: [Int], name: String) {
        switch hour {
        case 5..<12:
            return (Array(5...11), NSLocalizedString("rec_morning", comment: ""))
        case 12..<17:
            return (Array(12...16), NSLocalizedString("rec_day", comment: ""))
        case 17..<23:
            return (Array(17...22), NSLocalizedString("rec_evening", comment: ""))
        default:
            // Night: 23, 0, 1, 2, 3, 4 (all 6 hours of night range)
            return ([23, 0, 1, 2, 3, 4], NSLocalizedString("rec_night", comment: ""))
        }
    }

    private func updateExplorationSeedIfNeeded() {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let newSeed = UInt64(day)

        if explorationSeed != newSeed {
            explorationSeed = newSeed
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

    private func baseScore(for track: Track, isFavorite: Bool = false) -> Double {
        var score = 0.0

        if let rating = track.rating, rating > 0 {
            score += min(Double(rating) / 25.5, 10.0)
        }

        if isFavorite {
            score += 3.0
        }

        if track.hasLyrics {
            score += 2.0
        }

        if track.albumArtURL != nil {
            score += 1.0
        }

        return min(score, 16.0)
    }

    private func statisticsMap(
        for tracks: [Track]
    ) async -> [UUID: TrackStatistics] {
        let stats: [String: TrackStatistics]
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
           allStatsCache.count > 0 {
            stats = allStatsCache
        } else {
            stats = await TrackStatisticsService.shared.allStatistics()
            allStatsCache = stats
            lastCacheUpdate = Date()
        }

        var result: [UUID: TrackStatistics] = [:]

        for track in tracks {
            let hash = TrackStatisticsService.hash(for: track)
            if let stat = stats[hash] {
                result[track.id] = stat
            }
        }

        return result
    }

    private func genres(of track: Track) -> [String] {
        let raw = track.genre ?? ""

        return raw
            .components(separatedBy: CharacterSet(charactersIn: "/,&;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
