// Models,ArtworkPreset.swift
import Foundation

struct ArtworkPresetGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var artworkPaths: [String]

    init(id: UUID = UUID(), name: String, artworkPaths: [String] = []) {
        self.id = id
        self.name = name
        self.artworkPaths = artworkPaths
    }
}
