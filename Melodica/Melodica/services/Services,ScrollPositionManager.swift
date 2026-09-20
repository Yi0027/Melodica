// Services/ScrollPositionManager.swift
import Foundation

class ScrollPositionManager {
    static let shared = ScrollPositionManager()

    private var positions: [String: String] = [:]
    private var offsets: [String: CGFloat] = [:]

    func save(key: String, id: String) { positions[key] = id }
    func get(key: String) -> String? { positions[key] }

    func saveUUID(key: String, id: UUID) { positions[key] = id.uuidString }
    func getUUID(key: String) -> UUID? {
        guard let str = positions[key] else { return nil }
        return UUID(uuidString: str)
    }

    func saveOffset(key: String, offset: CGFloat) { offsets[key] = offset }
    func getOffset(key: String) -> CGFloat { offsets[key] ?? 0 }

    func clear(key: String) {
        positions.removeValue(forKey: key)
        offsets.removeValue(forKey: key)
    }

    func clearAll() {
        positions.removeAll()
        offsets.removeAll()
    }
}
