// Services,ArtworkPresetManager.swift
import Foundation
import Combine
import AppKit

final class ArtworkPresetManager: ObservableObject {
    static let shared = ArtworkPresetManager()

    @Published var groups: [ArtworkPresetGroup] = []
    @Published var artworkVersion = 0

    private let fileURL: URL

    private init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        fileURL = folder.appendingPathComponent("artwork_presets.json")
        load()
    }

    // MARK: - Groups

    func addGroup(name: String) {
        let group = ArtworkPresetGroup(name: name)
        groups.append(group)
        save()
    }

    func removeGroup(_ group: ArtworkPresetGroup) {
        for path in group.artworkPaths {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }

        groups.removeAll { $0.id == group.id }
        save()
    }

    // MARK: - Artwork

    func addArtwork(_ sourcePath: String, to group: ArtworkPresetGroup) {
        guard let savedPath = copyToPresetsFolder(sourcePath) else { return }

        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx].artworkPaths.append(savedPath)
        save()
    }

    func removeArtwork(_ path: String, from group: ArtworkPresetGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx].artworkPaths.removeAll { $0 == path }

        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))

        save()
    }

    // MARK: - Saving

    private func save() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)

        DispatchQueue.main.async { [weak self] in
            self?.artworkVersion += 1
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ArtworkPresetGroup].self, from: data) else { return }
        groups = decoded
    }

    // MARK: - Files

    private func baseFolder() -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func presetsFolder() -> URL {
        let folder = baseFolder()
            .appendingPathComponent("artwork")
            .appendingPathComponent("presets")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func copyToPresetsFolder(_ sourcePath: String) -> String? {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard let image = NSImage(contentsOf: sourceURL) else { return nil }

        let destination = presetsFolder()
            .appendingPathComponent(UUID().uuidString + ".jpg")

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }

        try? jpeg.write(to: destination, options: .atomicWrite)

        return destination.path
    }
}
