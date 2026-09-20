import Foundation

final class LibraryStatisticsService {
    static let shared = LibraryStatisticsService()

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

        fileURL = folder.appendingPathComponent("library_statistics.json")
    }

    func rebuildAndSave(tracks: [Track]) {
        let stats = calculate(from: tracks)
        save(stats)
    }

    func loadCached() -> LibraryStatistics? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(LibraryStatistics.self, from: data)
        else {
            return nil
        }

        return decoded
    }

    func calculate(from tracks: [Track]) -> LibraryStatistics {
        guard !tracks.isEmpty else { return LibraryStatistics() }

        var stats = LibraryStatistics()

        var albumSet: Set<String> = []
        var artistSet: Set<String> = []
        var genreSet: Set<String> = []

        var artistCounts: [String: (count: Int, duration: TimeInterval)] = [:]
        var albumCounts: [String: (count: Int, duration: TimeInterval)] = [:]
        var genreCounts: [String: (count: Int, duration: TimeInterval)] = [:]

        var formatCounts: [String: Int] = [:]
        var fileSize: UInt64 = 0

        for track in tracks {
            stats.totalTracks += 1
            stats.totalDuration += track.duration

            let size = (try? FileManager.default
                .attributesOfItem(atPath: track.url.path)[.size] as? UInt64) ?? 0

            fileSize += size

            let albumKey = "\(track.albumArtist ?? track.artist)|\(track.album)"
            albumSet.insert(albumKey)

            let displayArtist = track.albumArtist ?? track.artist
            artistSet.insert(displayArtist)

            let rawGenre = track.genre ?? "Unknown"
            let genres = rawGenre
                .components(separatedBy: CharacterSet(charactersIn: "/,&"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if genres.isEmpty {
                genreSet.insert("Unknown")
            } else {
                for genre in genres { genreSet.insert(genre) }
            }

            let ext = track.url.pathExtension.lowercased()
            formatCounts[ext, default: 0] += 1

            if track.replayGain != nil {
                stats.replayGainTracks += 1
            }

            if track.albumArtURL != nil {
                stats.artworkTracks += 1
            }

            // Тексты
            if track.hasLyrics {
                stats.lyricsTracks += 1
            }

            if track.unsyncedLyrics != nil {
                stats.embeddedLyricsTracks += 1
            }

            if track.lyricsURL != nil {
                stats.lrcLyricsTracks += 1
            }

            artistCounts[displayArtist, default: (0, 0)].count += 1
            artistCounts[displayArtist]!.duration += track.duration

            albumCounts[track.album, default: (0, 0)].count += 1
            albumCounts[track.album]!.duration += track.duration

            if genres.isEmpty {
                genreCounts["Unknown", default: (0, 0)].count += 1
                genreCounts["Unknown"]!.duration += track.duration
            } else {
                for genre in genres {
                    genreCounts[genre, default: (0, 0)].count += 1
                    genreCounts[genre]!.duration += track.duration
                }
            }
        }

        stats.totalFileSize = fileSize
        stats.albumCount = albumSet.count
        stats.artistCount = artistSet.count
        stats.genreCount = genreSet.count
        stats.formatCounts = formatCounts

        stats.topArtists = artistCounts
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map {
                TopEntry(
                    name: $0.key,
                    count: $0.value.count,
                    duration: $0.value.duration
                )
            }

        stats.topAlbums = albumCounts
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map {
                TopEntry(
                    name: $0.key,
                    count: $0.value.count,
                    duration: $0.value.duration
                )
            }

        stats.topGenres = genreCounts
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map {
                TopEntry(
                    name: $0.key,
                    count: $0.value.count,
                    duration: $0.value.duration
                )
            }

        return stats
    }

    private func save(_ stats: LibraryStatistics) {
        guard
            let data = try? JSONEncoder().encode(stats)
        else {
            return
        }

        try? data.write(to: fileURL, options: .atomicWrite)
    }
}
