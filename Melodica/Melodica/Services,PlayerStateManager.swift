// Services,PlayerStateManager.swift
import Foundation

struct PlayerState: Codable {
    var lastFolderBookmark: Data?
    var currentTrackPath: String?
    var currentTime: TimeInterval
    var volume: Float
    var repeatMode: String
    var shuffleMode: Bool
    var queuePaths: [String]
    var favoritePaths: [String]  // ✅ Добавить
    var timestamp: Date
}

class PlayerStateManager {
    static let shared = PlayerStateManager()
    
    private let defaults = UserDefaults.standard
    private let key = "melodica_player_state"
    
    func save(state: PlayerState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
    
    func load() -> PlayerState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PlayerState.self, from: data)
    }
    
    func clear() {
        defaults.removeObject(forKey: key)
    }
}
