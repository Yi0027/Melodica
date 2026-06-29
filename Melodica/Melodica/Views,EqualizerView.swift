// Views,EqualizerView.swift
import SwiftUI

extension Notification.Name {
    static let eqDidChange = Notification.Name("eqDidChange")
}

struct EqualizerView: View {
    @ObservedObject var eqManager = EqualizerManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            HStack {
                Text("Эквалайзер")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(settings.textMain)
                
                Spacer()
                
                Toggle("", isOn: $eqManager.isEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.9)
                    .onChange(of: eqManager.isEnabled) { _ in
                        eqManager.save()
                        NotificationCenter.default.post(name: .eqDidChange, object: nil)
                    }
                
                Button("Сброс") {
                    eqManager.reset()
                    NotificationCenter.default.post(name: .eqDidChange, object: nil)
                }
                .font(.system(size: 12))
                .foregroundColor(settings.textMuted)
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Ползунки
            HStack(alignment: .bottom, spacing: 16) {
                ForEach($eqManager.bands) { $band in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", band.gain))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(settings.textMuted.opacity(0.6))
                        
                        Slider(value: $band.gain, in: -12...12)
                            .frame(width: 140, height: 20)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 140)
                            .tint(settings.accent)
                        
                        Text(band.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(settings.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .onChange(of: band.gain) { _ in
                        eqManager.save()
                        NotificationCenter.default.post(name: .eqDidChange, object: nil)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Кнопка "Готово"
            Button("Готово") {
                dismiss()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(settings.accent)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(settings.darkSurface.opacity(0.5))
            .buttonStyle(.plain)
        }
        .frame(width: 520, height: 360)
        .background(settings.darkBg)
    }
}
