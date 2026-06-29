// Services,EqualizerManager.swift
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

class EqualizerManager: ObservableObject {
    static let shared = EqualizerManager()
    
    @Published var bands: [EqualizerBand] = []
    @Published var isEnabled: Bool = false {
        didSet { save() }
    }
    
    private let defaults = UserDefaults.standard
    private let bandsKey = "melodica_eq_bands"
    private let enabledKey = "melodica_eq_enabled"
    
    init() {
        loadBands()
        isEnabled = defaults.bool(forKey: enabledKey)
    }
    
    func loadBands() {
        if let data = defaults.data(forKey: bandsKey),
           let decoded = try? JSONDecoder().decode([EqualizerBand].self, from: data) {
            bands = decoded
        } else {
            bands = [
                EqualizerBand(frequency: 32, label: "32", gain: 0),
                EqualizerBand(frequency: 64, label: "64", gain: 0),
                EqualizerBand(frequency: 125, label: "125", gain: 0),
                EqualizerBand(frequency: 250, label: "250", gain: 0),
                EqualizerBand(frequency: 500, label: "500", gain: 0),
                EqualizerBand(frequency: 1000, label: "1K", gain: 0),
                EqualizerBand(frequency: 2000, label: "2K", gain: 0),
                EqualizerBand(frequency: 4000, label: "4K", gain: 0),
                EqualizerBand(frequency: 8000, label: "8K", gain: 0),
                EqualizerBand(frequency: 16000, label: "16K", gain: 0)
            ]
        }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(bands) {
            defaults.set(data, forKey: bandsKey)
        }
        defaults.set(isEnabled, forKey: enabledKey)
    }
    
    func reset() {
        for i in 0..<bands.count {
            bands[i].gain = 0
        }
        isEnabled = false
        save()
    }
}
