// Services,TrackMetadataCacheService.swift
import Foundation

final class TrackMetadataCacheService {
    static let shared = TrackMetadataCacheService()

    private var cache: [String: TrackMetadataCache] = [:]
    private let fileURL: URL

    private init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        fileURL = folder.appendingPathComponent("metadata_cache.json")
        load()
    }

    func metadata(for hash: String) -> TrackMetadataCache? {
        cache[hash]
    }

    func save(_ metadata: TrackMetadataCache, for hash: String) {
        cache[hash] = metadata
        save()
    }

    func remove(for hash: String) {
        cache.removeValue(forKey: hash)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TrackMetadataCache].self, from: data) else { return }
        cache = decoded
    }
    func clearAll() {
        cache.removeAll()
        save()
    }
    func updateRating(for hash: String, rating: Int?) {
        guard var existing = cache[hash] else {
            let minimal = TrackMetadataCache(
                title: "", artist: "", albumArtist: nil, album: "",
                year: nil, trackNumber: nil, genre: nil, rating: rating,
                replayGain: nil, replayGainPeak: nil,
                replayGainAlbum: nil, replayGainAlbumPeak: nil,
                lyricsURL: nil, unsyncedLyrics: nil, duration: 0
            )
            cache[hash] = minimal
            save()
            return
        }
        existing.rating = rating
        cache[hash] = existing
        save()
    }
}
