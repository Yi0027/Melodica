// Services/ScrollPositionManager.swift
import Foundation

class ScrollPositionManager {
    static let shared = ScrollPositionManager()
    
    private var positions: [String: String] = [:]
    
    // Для String (альбомы, плейлисты)
    func save(key: String, id: String) {
        positions[key] = id
    }
    
    func get(key: String) -> String? {
        positions[key]
    }
    
    // Для UUID (треки)
    func saveUUID(key: String, id: UUID) {
        positions[key] = id.uuidString
    }
    
    func getUUID(key: String) -> UUID? {
        guard let str = positions[key] else { return nil }
        return UUID(uuidString: str)
    }
    
    func clear(key: String) {
        positions.removeValue(forKey: key)
    }
    
    func clearAll() {
        positions.removeAll()
    }
    
}

