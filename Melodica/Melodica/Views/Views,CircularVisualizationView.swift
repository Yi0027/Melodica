// Views,CircularVisualizationView.swift
import SwiftUI
import Combine

struct CircularVisualizationView: View {
    let spectrumData: [Float]
    let waveformData: [Float]
    var color: Color = .accent
    
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
        
        let sensitivity = settings.circularSensitivity / 100.0  // 0...1
        
        // Комбинированная шкала: квадратичная + линейная
        // Даёт плавное изменение в середине и резкое по краям
        let threshold: Double
        if sensitivity < 0.5 {
            // Первая половина: плавно от 0.9 до 0.6
            threshold = 0.9 - (sensitivity * 0.6)
        } else {
            // Вторая половина: быстро от 0.6 до 0.15
            threshold = 0.6 - ((sensitivity - 0.5) * 0.9)
        }
        
        // Задержка: от 0.5 сек (нечувствительно) до 0.15 сек (чувствительно)
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
                maxAge: 1.2 - sensitivity * 0.4  // 1.2...0.8 сек
            )
            rings.append(newRing)
            lastTriggerTime = now
        }
    }
    
    private func updateRings() {
        for i in rings.indices {
            rings[i].age += 0.016
            let progress = rings[i].age / rings[i].maxAge
            
            // Расширение
            rings[i].scale = 0.92 + CGFloat(progress) * 0.18
            
            // Затухание
            rings[i].opacity = 0.8 * (1 - progress)
            
            // Размытие
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
        
        // Без усиления — используем как есть
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
// MARK: - Настройки визуализации

struct CircularVisualizationSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    let ranges: [(key: String, labelKey: String)] = [
        ("sub_bass", "circ_freq_sub_bass"),
        ("bass", "circ_freq_bass"),
        ("drums", "circ_freq_drums"),
        ("vocals", "circ_freq_vocals"),
        ("melody", "circ_freq_melody"),
        ("high_hats", "circ_freq_high_hats"),
        ("full", "circ_freq_full")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey("circular_settings_title"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(settings.textMain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(LocalizedStringKey("circ_sensitivity"))
                        .font(.system(size: 11))
                        .foregroundColor(settings.textMuted)
                    Spacer()
                    Text("\(Int(settings.circularSensitivity))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(settings.accent)
                }
                Slider(value: Binding(
                    get: { settings.circularSensitivity },
                    set: { settings.setCircularSensitivity($0) }
                ), in: 1...100, step: 1)
                .tint(settings.accent)
                
                Text(LocalizedStringKey("circ_sensitivity_hint"))
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.5))
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("circ_react_to"))
                    .font(.system(size: 11))
                    .foregroundColor(settings.textMuted)
                
                Picker("", selection: Binding(
                    get: { settings.circularFrequencyRange },
                    set: { settings.setCircularFrequencyRange($0) }
                )) {
                    ForEach(ranges, id: \.key) { range in
                        Text(LocalizedStringKey(range.labelKey)).tag(range.key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(settings.darkBg)
    }
}
