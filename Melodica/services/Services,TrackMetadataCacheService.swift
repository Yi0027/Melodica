import Foundation

actor TrackMetadataCacheService {
    static let shared = TrackMetadataCacheService()

    private var cache: [String: TrackMetadataCache] = [:]
    private var isLoaded = false
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var isDirty = false

    private init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("metadata_cache.json")
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TrackMetadataCache].self, from: data) else { return }
        cache = decoded
    }

    private func scheduleSave(debounce: TimeInterval = 0.5) {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            if !Task.isCancelled {
                await self?.flush()
            }
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        isDirty = false
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    func metadata(for hash: String) -> TrackMetadataCache? {
        loadIfNeeded()
        return cache[hash]
    }

    func save(_ metadata: TrackMetadataCache, for hash: String) {
        loadIfNeeded()
        cache[hash] = metadata
        scheduleSave()
    }

    func saveBatch(_ items: [(hash: String, metadata: TrackMetadataCache)]) {
        loadIfNeeded()
        for item in items {
            cache[item.hash] = item.metadata
        }
        scheduleSave()
    }

    func remove(for hash: String) {
        loadIfNeeded()
        cache.removeValue(forKey: hash)
        scheduleSave()
    }

    func clearAll() {
        loadIfNeeded()
        cache.removeAll()
        isDirty = true
        flush()
    }

    func updateRating(for hash: String, rating: Int?) {
        loadIfNeeded()
        guard var existing = cache[hash] else {
            let minimal = TrackMetadataCache(
                title: "", artist: "", albumArtist: nil, album: "",
                year: nil, trackNumber: nil, genre: nil, rating: rating,
                replayGain: nil, replayGainPeak: nil,
                replayGainAlbum: nil, replayGainAlbumPeak: nil,
                lyricsURL: nil, unsyncedLyrics: nil, duration: 0
            )
            cache[hash] = minimal
            scheduleSave()
            return
        }
        existing.rating = rating
        cache[hash] = existing
        scheduleSave()
    }

    func updateTags(
        oldHash: String?,
        newHash: String,
        title: String,
        artist: String,
        albumArtist: String?,
        album: String,
        year: Int?,
        trackNumber: Int?,
        genre: String?,
        fallbackTrack: Track? = nil
    ) {
        loadIfNeeded()
        let existing = (oldHash.flatMap { cache[$0] }) ?? cache[newHash]

        let duration = existing?.duration ?? fallbackTrack?.duration ?? 0
        let rating = existing?.rating ?? fallbackTrack?.rating
        let replayGain = existing?.replayGain ?? fallbackTrack?.replayGain
        let replayGainPeak = existing?.replayGainPeak ?? fallbackTrack?.replayGainPeak
        let replayGainAlbum = existing?.replayGainAlbum ?? fallbackTrack?.replayGainAlbum
        let replayGainAlbumPeak = existing?.replayGainAlbumPeak ?? fallbackTrack?.replayGainAlbumPeak
        let lyricsURL = existing?.lyricsURL ?? fallbackTrack?.lyricsURL?.path
        let unsyncedLyrics = existing?.unsyncedLyrics ?? fallbackTrack?.unsyncedLyrics

        let updated = TrackMetadataCache(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            year: year,
            trackNumber: trackNumber,
            genre: genre,
            rating: rating,
            replayGain: replayGain,
            replayGainPeak: replayGainPeak,
            replayGainAlbum: replayGainAlbum,
            replayGainAlbumPeak: replayGainAlbumPeak,
            lyricsURL: lyricsURL,
            unsyncedLyrics: unsyncedLyrics,
            duration: duration
        )

        let targetKey = newHash.isEmpty ? (oldHash ?? "") : newHash
        if !targetKey.isEmpty {
            cache[targetKey] = updated
        }
        if let old = oldHash, !old.isEmpty, old != targetKey {
            cache.removeValue(forKey: old)
        }
        scheduleSave()
    }

    func updateTags(
        for hash: String,
        title: String,
        artist: String,
        albumArtist: String?,
        album: String,
        year: Int?,
        trackNumber: Int?,
        genre: String?
    ) {
        loadIfNeeded()
        if var existing = cache[hash] {
            existing.title = title
            existing.artist = artist
            existing.albumArtist = albumArtist
            existing.album = album
            existing.year = year
            existing.trackNumber = trackNumber
            existing.genre = genre
            cache[hash] = existing
        } else {
            let minimal = TrackMetadataCache(
                title: title,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                year: year,
                trackNumber: trackNumber,
                genre: genre,
                rating: nil,
                replayGain: nil,
                replayGainPeak: nil,
                replayGainAlbum: nil,
                replayGainAlbumPeak: nil,
                lyricsURL: nil,
                unsyncedLyrics: nil,
                duration: 0
            )
            cache[hash] = minimal
        }
        scheduleSave()
    }
}
