// Views,LiquidGlass,LiquidGlassCircularVisualizationView.swift
import SwiftUI
import Combine

struct LiquidGlassCircularVisualizationView: View {
    var spectrumData: [Float] = []
    var waveformData: [Float] = []
    var color: Color = Color.accentColor
    var artworkSize: CGFloat? = nil
    var baseCornerRadius: CGFloat? = nil
    
    @ObservedObject private var visEngine = VisualizationEngine.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var rings: [RingState] = []
    @State private var lastTriggerTime: Date = .distantPast
    @State private var rollingAverage: Float = 0.20
    @State private var ambientEnergy: Float = 0.0
    
    private static let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if visEngine.mode == .circular && visEngine.isRunning {
            GeometryReader { geo in
                let frameDimension = min(geo.size.width, geo.size.height)
                let coverSize = artworkSize ?? (frameDimension * 0.85)
                let cornerRadius = baseCornerRadius ?? max(8, coverSize * (12.0 / 220.0))
                let sensitivity = Float(settings.circularSensitivity / 100.0)
                let minHaloThreshold = 0.18 - sensitivity * 0.14
                
                ZStack {
                    // Мягкое фоновое дыхание (Halo) непосредственно по контуру обложки
                    if ambientEnergy > minHaloThreshold {
                        let haloAlpha = Double(min(ambientEnergy * 0.5, 0.6)) * Double(0.3 + sensitivity * 0.7)
                        RoundedRectangle(cornerRadius: cornerRadius + 2)
                            .stroke(
                                color.opacity(haloAlpha),
                                lineWidth: 1.5 + CGFloat(ambientEnergy) * 2.5
                            )
                            .frame(width: coverSize + 4, height: coverSize + 4)
                            .blur(radius: 2.0 + CGFloat(ambientEnergy) * 3.5)
                    }
                    
                    // Расходящиеся параллельные ударные кольца
                    ForEach(rings) { ring in
                        let ringDimension = coverSize + 2 * ring.offset
                        let ringRadius = cornerRadius + ring.offset
                        
                        RoundedRectangle(cornerRadius: ringRadius)
                            .stroke(
                                color.opacity(ring.opacity),
                                style: StrokeStyle(
                                    lineWidth: ring.lineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: ringDimension, height: ringDimension)
                            .blur(radius: ring.blur)
                    }
                }
                .frame(width: frameDimension, height: frameDimension)
                .onReceive(Self.timer) { _ in
                    checkAudio(coverSize: coverSize)
                    updateRings(coverSize: coverSize)
                }
            }
        }
    }
    
    struct RingState: Identifiable {
        let id = UUID()
        var offset: CGFloat = 2.0
        var maxOffset: CGFloat
        var opacity: Double
        var initialOpacity: Double
        var lineWidth: CGFloat
        var blur: CGFloat = 0.0
        var age: Double = 0.0
        var maxAge: Double
    }
    
    private func checkAudio(coverSize: CGFloat) {
        let currentEnergy = getFrequencyEnergy()
        let now = Date()
        
        let sensitivity = Float(settings.circularSensitivity / 100.0) // 0.01...1.0
        
        // 1. Плавное следование амбиентной энергии за сигналом
        if currentEnergy > ambientEnergy {
            ambientEnergy += (currentEnergy - ambientEnergy) * 0.4
        } else {
            ambientEnergy += (currentEnergy - ambientEnergy) * 0.08
        }
        
        // 2. Адаптивные параметры детекции бита:
        // Чувствительность 1% (минимальная): только очень мощные басовые удары и дропы (>0.79), скачок 1.64x.
        // Чувствительность 50% (средняя): чёткий ритмический бит (>0.45), скачок 1.38x.
        // Чувствительность 100% (максимальная): мягкие звуки и тихие треки (>0.10), скачок 1.10x.
        let absThreshold = 0.80 - sensitivity * 0.70
        let ratio = 1.65 - sensitivity * 0.55
        let minDelta = 0.28 - sensitivity * 0.25
        let minInterval = Double(0.50 - sensitivity * 0.38)
        
        guard now.timeIntervalSince(lastTriggerTime) > minInterval else {
            updateRollingAverage(currentEnergy)
            return
        }
        guard rings.count < 5 else {
            updateRollingAverage(currentEnergy)
            return
        }
        
        // 3. Строгая детекция транзиента (удара):
        let delta = currentEnergy - rollingAverage
        let isBeat = currentEnergy >= absThreshold && currentEnergy >= rollingAverage * ratio && delta >= minDelta
        
        if isBeat {
            let intensity = min(max((currentEnergy - absThreshold) / 0.35, 0.25), 1.0)
            let maxTravel = min(coverSize * 0.16, 38.0)
            let calculatedMaxOffset = max(18.0, maxTravel * CGFloat(0.70 + intensity * 0.30))
            let ringOpacity = Double(0.60 + intensity * 0.35) * Double(0.5 + sensitivity * 0.5)
            
            let newRing = RingState(
                offset: 2.0,
                maxOffset: calculatedMaxOffset,
                opacity: ringOpacity,
                initialOpacity: ringOpacity,
                lineWidth: CGFloat(1.8 + intensity * 2.8),
                blur: 0,
                age: 0,
                maxAge: Double(max(0.55, 0.95 - sensitivity * 0.35))
            )
            rings.append(newRing)
            lastTriggerTime = now
        }
        
        updateRollingAverage(currentEnergy)
    }
    
    private func updateRollingAverage(_ energy: Float) {
        if energy > rollingAverage {
            rollingAverage += (energy - rollingAverage) * 0.05
        } else {
            rollingAverage += (energy - rollingAverage) * 0.02
        }
    }
    
    private func updateRings(coverSize: CGFloat) {
        if rings.isEmpty && ambientEnergy > 0 {
            ambientEnergy = max(0, ambientEnergy - 0.02)
        }
        
        guard !rings.isEmpty else { return }
        
        for i in rings.indices {
            rings[i].age += 0.016
            let progress = min(rings[i].age / rings[i].maxAge, 1.0)
            
            let easeOut = 1.0 - pow(1.0 - progress, 2.0)
            rings[i].offset = 2.0 + CGFloat(easeOut) * (rings[i].maxOffset - 2.0)
            rings[i].opacity = rings[i].initialOpacity * pow(1.0 - progress, 1.2)
            
            if progress > 0.65 {
                rings[i].blur = CGFloat(progress - 0.65) * 4.0
            }
        }
        
        rings.removeAll { $0.age >= $0.maxAge }
    }
    
    private func getFrequencyEnergy() -> Float {
        let data = !spectrumData.isEmpty ? spectrumData : visEngine.spectrumData
        
        var energy: Float = 0
        if data.count >= 32 {
            func sliceEnergy(_ range: Range<Int>) -> Float {
                let slice = data[range]
                let maxVal = slice.max() ?? 0
                let avgVal = slice.reduce(0, +) / Float(slice.count)
                return maxVal * 0.6 + avgVal * 0.4
            }
            
            switch settings.circularFrequencyRange {
            case "sub_bass":  energy = sliceEnergy(0..<7)   // 30 - 144 Гц (саб-бас и бочка)
            case "bass":      energy = sliceEnergy(0..<11)  // 30 - 260 Гц (бас и ритм-секция)
            case "drums":     energy = sliceEnergy(3..<14)  // 54 - 468 Гц (ударные и снейр)
            case "vocals":    energy = sliceEnergy(9..<22)  // 175 - 2736 Гц (голос и инструменты)
            case "melody":    energy = sliceEnergy(12..<26) // 316 - 5998 Гц (соло и мелодия)
            case "high_hats": energy = sliceEnergy(23..<32) // 3.3 - 16 кГц (хай-хэты и тарелки)
            case "full":      energy = sliceEnergy(0..<32)  // Весь спектр
            default:          energy = sliceEnergy(0..<11)
            }
        }
        
        // Фолбэк на амплитуду реального времени, если спектр временно пуст
        if energy < 0.01 {
            let waves = !waveformData.isEmpty ? waveformData : visEngine.waveformData
            if let maxAmp = waves.max(), maxAmp > 0.01 {
                energy = maxAmp
            }
        }
        
        return energy
    }
}
