// Services/EQPresetManager.swift
import Foundation
import Combine

struct EQPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gains: [Float]      // order = EqualizerManager.bands
    var genres: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        gains: [Float],
        genres: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gains = gains
        self.genres = genres
        self.createdAt = createdAt
    }
}

@MainActor
final class EQPresetManager: ObservableObject {
    static let shared = EQPresetManager()

    @Published private(set) var presets: [EQPreset] = []
    @Published var activePresetID: UUID?

    /// Automatically apply preset when track genre matches.
    @Published var autoApplyByGenre: Bool = false {
        didSet {
            UserDefaults.standard.set(autoApplyByGenre, forKey: Self.autoApplyKey)
            if !autoApplyByGenre {
                resetAutoStateIfNeeded()
            }
        }
    }

    /// Resets auto state. If an auto-preset was active, restores EQ to baseline.
    private func resetAutoStateIfNeeded() {
        guard isAutoApplied else { return }
        if let snapshot = preAutoApplySnapshot {
            restoreFromSnapshot(snapshot)
        }
        isAutoApplied = false
        preAutoApplySnapshot = nil
        activePresetID = nil
        activePresetSnapshot = []
    }

    private static let autoApplyKey = "melodica.eqPresets.autoApplyByGenre"

    /// Snapshot of gains when preset was applied, to detect manual user tweaks.
    private var activePresetSnapshot: [Float] = []

    /// Baseline EQ snapshot when auto-preset was first applied.
    private var preAutoApplySnapshot: (gains: [Float], isEnabled: Bool)?

    /// true if active preset was applied automatically.
    private var isAutoApplied: Bool = false

    private init() {
        autoApplyByGenre = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        load()
    }

    // MARK: - Storage

    private var presetsURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eq_presets.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: presetsURL.path),
              let data = try? Data(contentsOf: presetsURL),
              let decoded = try? JSONDecoder().decode([EQPreset].self, from: data)
        else { return }
        presets = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL, options: .atomicWrite)
    }

    // MARK: - Validation

    /// Returns conflicts for genres already assigned to other presets.
    func conflicts(
        for genres: [String],
        excluding: UUID? = nil
    ) -> [(genre: String, preset: EQPreset)] {
        var result: [(String, EQPreset)] = []
        for genre in genres {
            let lower = genre.lowercased()
            if let existing = presets.first(where: { p in
                p.id != excluding && p.genres.contains { $0.lowercased() == lower }
            }) {
                result.append((genre, existing))
            }
        }
        return result
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, gains: [Float], genres: [String]) -> EQPreset {
        let preset = EQPreset(name: name, gains: gains, genres: genres)
        presets.append(preset)
        save()
        return preset
    }

    func delete(_ preset: EQPreset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id {
            activePresetID = nil
            activePresetSnapshot = []
            isAutoApplied = false
            preAutoApplySnapshot = nil
        }
        save()
    }

    func resetAll() {
        presets.removeAll()
        activePresetID = nil
        activePresetSnapshot = []
        isAutoApplied = false
        preAutoApplySnapshot = nil
        autoApplyByGenre = false
        save()
    }

    func rename(_ preset: EQPreset, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = newName
        save()
    }

    func updateGenres(_ preset: EQPreset, genres: [String]) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].genres = genres
        save()
    }

    // MARK: - Apply

    /// Manual preset application. Sets user baseline.
    func applyPreset(_ preset: EQPreset) {
        isAutoApplied = false
        preAutoApplySnapshot = nil
        applyPresetInternal(preset)
    }

    /// Internal apply without modifying auto flags.
    private func applyPresetInternal(_ preset: EQPreset) {
        let eq = EqualizerManager.shared

        // Snapshot before mutation to prevent slider onChange from clearing activePresetID.
        activePresetSnapshot = preset.gains
        activePresetID = preset.id

        let count = min(preset.gains.count, eq.bands.count)
        for i in 0..<count {
            eq.bands[i].gain = preset.gains[i]
        }
        if !eq.isEnabled { eq.isEnabled = true }
        eq.save()
        NotificationCenter.default.post(name: .eqDidChange, object: nil)
    }

    /// Called on EQ slider changes to detect manual adjustment.
    func syncActivePresetState() {
        guard activePresetID != nil else { return }

        let eq = EqualizerManager.shared
        let current = eq.bands.map { $0.gain }
        let snapshot = activePresetSnapshot

        // Small epsilon for float slider precision.
        let epsilon: Float = 0.05
        let changed = current.count != snapshot.count
            || zip(current, snapshot).contains { abs($0 - $1) > epsilon }

        if changed {
            activePresetID = nil
            activePresetSnapshot = []
            // User took control of EQ — this becomes the new baseline.
            // On the next matching track, auto-mode starts fresh.
            isAutoApplied = false
            preAutoApplySnapshot = nil
        }
    }

    /// Called from PlayerViewModel on track change to auto-apply presets.
    func autoApplyIfNeeded(for genre: String?) {
        guard autoApplyByGenre else { return }

        let preset: EQPreset? = {
            guard let genre, !genre.isEmpty else { return nil }
            let parts = Self.splitGenres(genre)
            return presetForGenres(parts)
        }()

        if let preset {
            // Same auto-preset already active — no action needed.
            if isAutoApplied && activePresetID == preset.id { return }

            // First auto-apply — record baseline state.
            if !isAutoApplied {
                let eq = EqualizerManager.shared
                preAutoApplySnapshot = (eq.bands.map { $0.gain }, eq.isEnabled)
            }

            isAutoApplied = true
            applyPresetInternal(preset)
        } else {
            // Track does not match any preset — restore baseline if needed.
            if isAutoApplied, let snapshot = preAutoApplySnapshot {
                restoreFromSnapshot(snapshot)
                isAutoApplied = false
                preAutoApplySnapshot = nil
                activePresetID = nil
                activePresetSnapshot = []
            }
        }
    }

    private func restoreFromSnapshot(_ snapshot: (gains: [Float], isEnabled: Bool)) {
        let eq = EqualizerManager.shared
        let count = min(snapshot.gains.count, eq.bands.count)
        for i in 0..<count {
            eq.bands[i].gain = snapshot.gains[i]
        }
        eq.isEnabled = snapshot.isEnabled
        eq.save()
        NotificationCenter.default.post(name: .eqDidChange, object: nil)
    }

    // MARK: - Genre matching

    func presetForGenre(_ genre: String) -> EQPreset? {
        let lower = genre.lowercased()
        return presets.first { p in
            p.genres.contains { $0.lowercased() == lower }
        }
    }

    /// Parses raw genre tag into separate values.
    private static func splitGenres(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: "/,&;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Selects preset matching track genres by priority.
    private func presetForGenres(_ genres: [String]) -> EQPreset? {
        for genre in genres {
            if let match = presetForGenre(genre) { return match }
        }
        return nil
    }
}
