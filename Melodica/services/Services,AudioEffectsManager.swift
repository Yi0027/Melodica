// Services/AudioEffectsManager.swift
import Foundation
import Combine

struct AudioEffectsState: Codable {

    // UI state
    var advancedExpanded: Bool = false

    // Reverb
    var reverbPreset: String = "off"
    var reverbWetDry: Float = 0

    // Delay
    var delayEnabled: Bool = false
    var delayTime: Float = 0.2
    var delayFeedback: Float = 20
    var delayAdvanced: Bool = false
    var delayLowPassCutoff: Float = 8000
    var delayWetDry: Float = 20

    static let `default` = AudioEffectsState()
}

extension Notification.Name {
    static let audioEffectsDidChange = Notification.Name("audioEffectsDidChange")
}

class AudioEffectsManager: ObservableObject {
    static let shared = AudioEffectsManager()

    @Published var advancedExpanded: Bool = false {
        didSet { if !isLoading { save() } }
    }

    @Published var reverbPreset: String = "off" {
        didSet { if !isLoading { save(); notify() } }
    }
    @Published var reverbWetDry: Float = 0 {
        didSet { if !isLoading { save(); notify() } }
    }

    @Published var delayEnabled: Bool = false {
        didSet { if !isLoading { save(); notify() } }
    }
    @Published var delayTime: Float = 0.2 {
        didSet { if !isLoading { save(); notify() } }
    }
    @Published var delayFeedback: Float = 20 {
        didSet { if !isLoading { save(); notify() } }
    }
    @Published var delayAdvanced: Bool = false {
        didSet {
            guard !isLoading else { return }
            if !delayAdvanced {
                // Клампим feedback в обычный диапазон [0, 60]
                if delayFeedback > 60 {
                    isLoading = true
                    delayFeedback = 60
                    isLoading = false
                } else if delayFeedback < 0 {
                    isLoading = true
                    delayFeedback = 0
                    isLoading = false
                }
            }
            save(); notify()
        }
    }
    @Published var delayLowPassCutoff: Float = 8000 {
        didSet { if !isLoading { save(); notify() } }
    }
    @Published var delayWetDry: Float = 20 {
        didSet { if !isLoading { save(); notify() } }
    }

    private var isLoading = false

    private init() {
        load()
    }

    private var stateURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audio_effects.json")
    }

    private func notify() {
        NotificationCenter.default.post(name: .audioEffectsDidChange, object: nil)
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AudioEffectsState.self, from: data)
        else { return }

        advancedExpanded = state.advancedExpanded
        reverbPreset = state.reverbPreset
        reverbWetDry = state.reverbWetDry
        delayEnabled = state.delayEnabled
        delayTime = state.delayTime
        delayFeedback = state.delayFeedback
        delayAdvanced = state.delayAdvanced
        delayLowPassCutoff = state.delayLowPassCutoff
        delayWetDry = state.delayWetDry

        // На случай если в файле лежит невалидная комбинация (advanced=false, feedback вне 0...60)
        if !delayAdvanced {
            if delayFeedback > 60 { delayFeedback = 60 }
            if delayFeedback < 0 { delayFeedback = 0 }
        }
    }

    private var saveDebouncer: Timer?

    func save() {
        saveDebouncer?.invalidate()
        saveDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.performSave()
            }
        }
    }

    func performSave() {
        saveDebouncer?.invalidate()
        saveDebouncer = nil
        let state = AudioEffectsState(
            advancedExpanded: advancedExpanded,
            reverbPreset: reverbPreset,
            reverbWetDry: reverbWetDry,
            delayEnabled: delayEnabled,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayAdvanced: delayAdvanced,
            delayLowPassCutoff: delayLowPassCutoff,
            delayWetDry: delayWetDry
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomicWrite)
    }

    func reset() {
        isLoading = true
        advancedExpanded = false
        reverbPreset = "off"
        reverbWetDry = 0
        delayEnabled = false
        delayTime = 0.2
        delayFeedback = 20
        delayAdvanced = false
        delayLowPassCutoff = 8000
        delayWetDry = 20
        isLoading = false
        performSave()
        notify()
    }
}
