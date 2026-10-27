// Services/PlayerStateManager.swift
import Foundation

struct PlayerState: Codable, Sendable {
    var currentTrackPath: String?
    var currentTime: TimeInterval
    var volume: Float
    var repeatMode: String
    var shuffleMode: Bool
    var queuePaths: [String]
    var favoriteInfos: [FavoriteInfo]?
    var timestamp: Date
    var currentCueStartTime: TimeInterval? 
    var activeContextID: String? = nil
    var playbackQueuePaths: [String]? = nil
}

struct SavedPlaylist: Codable {
    var name: String
    var m3uContent: String
}

struct LibraryState: Codable {
    var lastFolderPath: String?
    var lastFolderBookmark: Data?
    var watchedFolderPaths: [String: Bool]?
    var playlistPaths: [String]
    var savedPlaylists: [SavedPlaylist]
    var cachedPlaylists: [CachedPlaylist] = []
    var folderWatchModes: [String: String]?
}
struct CachedPlaylist: Codable {
    var name: String
    var trackPaths: [String]
    var totalTrackCount: Int? = nil
}
class PlayerStateManager {
    static let shared = PlayerStateManager()
    
    init() {
        migrateFromOldState()
    }
    
    private var baseURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    
    private var playerStateURL: URL {
        baseURL.appendingPathComponent("player_state.json")
    }
    
    private var libraryStateURL: URL {
        baseURL.appendingPathComponent("library_state.json")
    }
    
    // MARK: - Player State

    private let saveQueue = DispatchQueue(label: "com.melodica.playerStateSave", qos: .utility)
    
    func savePlayer(_ state: PlayerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = playerStateURL
        saveQueue.async {
            try? data.write(to: url, options: .atomicWrite)
        }
    }

    func savePlayerSync(_ state: PlayerState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = playerStateURL
        saveQueue.sync {
            try? data.write(to: url, options: .atomicWrite)
        }
    }
    
    func loadPlayer() -> PlayerState? {
        guard FileManager.default.fileExists(atPath: playerStateURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: playerStateURL)
            return try JSONDecoder().decode(PlayerState.self, from: data)
        } catch {
            return nil
        }
    }
    
    func clearPlayer() {
        try? FileManager.default.removeItem(at: playerStateURL)
    }
    
    // MARK: - Library State
    
    func saveLibrary(_ state: LibraryState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: libraryStateURL, options: .atomicWrite)
        } catch {
        }
    }
    
    func loadLibrary() -> LibraryState? {
        guard FileManager.default.fileExists(atPath: libraryStateURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: libraryStateURL)
            return try JSONDecoder().decode(LibraryState.self, from: data)
        } catch {
            return nil
        }
    }
    
    func clearLibrary() {
        try? FileManager.default.removeItem(at: libraryStateURL)
    }
    
    // MARK: - Migration
    
    private func migrateFromOldState() {
        let oldURL = baseURL.appendingPathComponent("player_state.json")
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }
        
        if FileManager.default.fileExists(atPath: libraryStateURL.path) { return }
        
        guard let data = try? Data(contentsOf: oldURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        var libState = LibraryState(lastFolderPath: nil, playlistPaths: [], savedPlaylists: [])
        var changed = false
        
        if let playlistPaths = json["playlistPaths"] as? [String], !playlistPaths.isEmpty {
            libState.playlistPaths = playlistPaths
            // Пытаемся прочитать содержимое m3u для миграции
            for path in playlistPaths {
                let url = URL(fileURLWithPath: path)
                if let content = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                    let name = url.deletingPathExtension().lastPathComponent
                    libState.savedPlaylists.append(SavedPlaylist(name: name, m3uContent: content))
                }
            }
            changed = true
        }
        
        if let lastFolderPath = json["lastFolderPath"] as? String {
            libState.lastFolderPath = lastFolderPath
            changed = true
        }
        
        if changed {
            saveLibrary(libState)
        }
    }
}
struct FavoriteInfo: Codable, Sendable {
    let path: String
    let title: String
    let artist: String
    var smartHash: String? = nil
}
