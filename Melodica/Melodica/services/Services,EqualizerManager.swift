// Services/EqualizerManager.swift
import Foundation
import Combine

struct EqualizerBand: Codable, Identifiable {
    var id: Int { frequency }
    let frequency: Int
    let label: String
    var gain: Float

    init(frequency: Int, label: String, gain: Float) {
        self.frequency = frequency
        self.label = label
        self.gain = gain
    }
}

struct EqualizerState: Codable {
    var bands: [EqualizerBand]
    var isEnabled: Bool

    static let `default` = EqualizerState(
        bands: [
            EqualizerBand(frequency: 32,    label: "32",  gain: 0),
            EqualizerBand(frequency: 64,    label: "64",  gain: 0),
            EqualizerBand(frequency: 125,   label: "125", gain: 0),
            EqualizerBand(frequency: 250,   label: "250", gain: 0),
            EqualizerBand(frequency: 500,   label: "500", gain: 0),
            EqualizerBand(frequency: 1000,  label: "1K",  gain: 0),
            EqualizerBand(frequency: 2000,  label: "2K",  gain: 0),
            EqualizerBand(frequency: 4000,  label: "4K",  gain: 0),
            EqualizerBand(frequency: 8000,  label: "8K",  gain: 0),
            EqualizerBand(frequency: 16000, label: "16K", gain: 0)
        ],
        isEnabled: false
    )
}

class EqualizerManager: ObservableObject {
    static let shared = EqualizerManager()

    @Published var bands: [EqualizerBand] = EqualizerState.default.bands
    @Published var isEnabled: Bool = false {
        didSet { if !isLoading { save() } }
    }

    private var isLoading = false

    private init() {
        migrateFromUserDefaultsIfNeeded()
        load()
    }

    // MARK: - Storage

    private var stateURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("equalizer.json")
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(EqualizerState.self, from: data)
        else {
            return
        }
        bands = decoded.bands
        isEnabled = decoded.isEnabled
    }

    func save() {
        let state = EqualizerState(
            bands: bands,
            isEnabled: isEnabled
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomicWrite)
    }

    func reset() {
        for i in 0..<bands.count {
            bands[i].gain = 0
        }
        isEnabled = false
        save()
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        if FileManager.default.fileExists(atPath: stateURL.path) { return }

        let defaults = UserDefaults.standard
        let bandsKey = "melodica_eq_bands"
        let enabledKey = "melodica_eq_enabled"

        var state = EqualizerState.default
        var migrated = false

        if let data = defaults.data(forKey: bandsKey),
           let decodedBands = try? JSONDecoder().decode([EqualizerBand].self, from: data) {
            state.bands = decodedBands
            migrated = true
        }
        if defaults.object(forKey: enabledKey) != nil {
            state.isEnabled = defaults.bool(forKey: enabledKey)
            migrated = true
        }

        guard migrated else { return }

        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomicWrite)
        }

        defaults.removeObject(forKey: bandsKey)
        defaults.removeObject(forKey: enabledKey)
    }
}
