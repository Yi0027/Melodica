// ViewModels,SmartPlaylistViewModel.swift
import SwiftUI
import Combine

@MainActor
final class SmartPlaylistViewModel: ObservableObject {
    @Published var playlists: [SmartPlaylist] = []

    private var trackCache: [UUID: [String]] = [:]

    private var smartURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder.appendingPathComponent("smart_playlists.json")
    }

    private var cacheURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        return folder.appendingPathComponent("smart_playlists_cache.json")
    }

    init() {
        load()
        loadCache()
    }

    // MARK: - Треки по кешу или правилам

    func tracks(
        for playlist: SmartPlaylist,
        library: [Track],
        favoriteURLs: Set<String>,
        useCache: Bool = true
    ) -> [Track] {
        if useCache, let cachedPaths = trackCache[playlist.id] {
            return resolveTracks(from: cachedPaths, library: library)
        }

        return computeTracks(
            for: playlist,
            library: library,
            favoriteURLs: favoriteURLs
        )
    }

    func refreshCache(
        for playlist: SmartPlaylist,
        library: [Track],
        favoriteURLs: Set<String>
    ) {
        let computed = computeTracks(
            for: playlist,
            library: library,
            favoriteURLs: favoriteURLs
        )

        trackCache[playlist.id] = computed.map { $0.url.path }
        saveCache()
    }

    func refreshAllCaches(
        library: [Track],
        favoriteURLs: Set<String>
    ) {
        for playlist in playlists {
            let computed = computeTracks(
                for: playlist,
                library: library,
                favoriteURLs: favoriteURLs
            )
            trackCache[playlist.id] = computed.map { $0.url.path }
        }
        saveCache()
    }

    // MARK: - Вычисление по правилам

    private func computeTracks(
        for playlist: SmartPlaylist,
        library: [Track],
        favoriteURLs: Set<String>
    ) -> [Track] {
        library.filter {
            SmartPlaylistEngine.evaluate(
                $0,
                rules: playlist.rules,
                matchAll: playlist.matchAll,
                favoriteURLs: favoriteURLs
            )
        }
    }

    // MARK: - Преобразование путей в треки

    private func resolveTracks(
        from paths: [String],
        library: [Track]
    ) -> [Track] {
        var resolved: [Track] = []

        for path in paths {
            if let track = library.first(where: { $0.url.path == path }) {
                resolved.append(track)
            } else if let track = library.first(where: {
                $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent
            }) {
                resolved.append(track)
            }
        }

        return resolved
    }

    // MARK: - CRUD

    func add(_ playlist: SmartPlaylist) {
        playlists.append(playlist)
        save()
    }

    func update(_ playlist: SmartPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            return
        }
        playlists[index] = playlist
        save()
    }

    func delete(_ playlist: SmartPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        trackCache.removeValue(forKey: playlist.id)
        save()
        saveCache()
    }

    // MARK: - Сохранение плейлистов

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: smartURL, options: .atomicWrite)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: smartURL),
            let decoded = try? JSONDecoder().decode([SmartPlaylist].self, from: data)
        else {
            return
        }
        playlists = decoded
    }

    // MARK: - Кеш треков

    private func saveCache() {
        let cache = trackCache.map {
            SmartPlaylistCache(
                playlistID: $0.key,
                trackPaths: $0.value,
                updatedAt: Date()
            )
        }

        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomicWrite)
    }

    private func loadCache() {
        guard
            let data = try? Data(contentsOf: cacheURL),
            let decoded = try? JSONDecoder().decode([SmartPlaylistCache].self, from: data)
        else {
            return
        }

        trackCache = Dictionary(
            uniqueKeysWithValues: decoded.map { ($0.playlistID, $0.trackPaths) }
        )
    }
}

struct SmartPlaylistCache: Codable {
    let playlistID: UUID
    let trackPaths: [String]
    let updatedAt: Date
}
