// Views,LiquidGlass,LiquidGlassCircularVisualizationView.swift
import SwiftUI
import Combine

struct LiquidGlassCircularVisualizationView: View {
    let spectrumData: [Float]
    let waveformData: [Float]
    var color: Color = Color.accentColor
    
    @State private var rings: [RingState] = []
    @State private var lastTriggerTime: Date = .distantPast
    @ObservedObject private var settings = SettingsManager.shared
    
    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            
            ZStack {
                ForEach(rings) { ring in
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            color.opacity(ring.opacity),
                            style: StrokeStyle(
                                lineWidth: ring.lineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(
                            width: size * ring.scale,
                            height: size * ring.scale
                        )
                        .blur(radius: ring.blur)
                }
            }
            .frame(width: size, height: size)
            .onReceive(timer) { _ in updateRings() }
            .onChange(of: spectrumData) { _ in checkAudio() }
        }
    }
    
    struct RingState: Identifiable {
        let id = UUID()
        var scale: CGFloat
        var opacity: Double
        var lineWidth: CGFloat
        var blur: CGFloat
        var age: Double
        var maxAge: Double
    }
    
    private func checkAudio() {
        let energy = getFrequencyEnergy()
        let now = Date()
        
        let sensitivity = settings.circularSensitivity / 100.0
        
        let threshold: Double
        if sensitivity < 0.5 {
            threshold = 0.9 - (sensitivity * 0.6)
        } else {
            threshold = 0.6 - ((sensitivity - 0.5) * 0.9)
        }
        
        let minInterval = 0.5 - (sensitivity * 0.35)
        guard now.timeIntervalSince(lastTriggerTime) > minInterval else { return }
        guard rings.count < 3 else { return }
        
        if energy > Float(threshold) {
            let intensity = min((energy - Float(threshold)) / 0.35, 1.0)
            
            let newRing = RingState(
                scale: 0.92,
                opacity: 0.5 + Double(intensity) * 0.5,
                lineWidth: 1.5 + CGFloat(intensity) * 7,
                blur: 0,
                age: 0,
                maxAge: 1.2 - sensitivity * 0.4
            )
            rings.append(newRing)
            lastTriggerTime = now
        }
    }
    
    private func updateRings() {
        for i in rings.indices {
            rings[i].age += 0.016
            let progress = rings[i].age / rings[i].maxAge
            
            rings[i].scale = 0.92 + CGFloat(progress) * 0.18
            rings[i].opacity = 0.8 * (1 - progress)
            
            if progress > 0.5 {
                rings[i].blur = CGFloat(progress - 0.5) * 2
            }
        }
        
        rings.removeAll { $0.age >= $0.maxAge }
    }
    
    private func getFrequencyEnergy() -> Float {
        guard spectrumData.count >= 32 else {
            return spectrumData.reduce(0, +) / Float(max(spectrumData.count, 1))
        }
        
        let energy: Float
        
        switch settings.circularFrequencyRange {
        case "sub_bass":  energy = spectrumData[0..<4].reduce(0, +) / 4
        case "bass":      energy = spectrumData[0..<8].reduce(0, +) / 8
        case "drums":     energy = spectrumData[4..<13].reduce(0, +) / 9
        case "vocals":    energy = spectrumData[10..<19].reduce(0, +) / 9
        case "melody":    energy = spectrumData[14..<25].reduce(0, +) / 11
        case "high_hats": energy = spectrumData[24..<32].reduce(0, +) / 8
        case "full":      energy = spectrumData.reduce(0, +) / Float(spectrumData.count)
        default:          energy = spectrumData[0..<8].reduce(0, +) / 8
        }
        
        return energy
    }
}
