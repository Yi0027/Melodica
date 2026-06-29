// Views,SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey("settings"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(settings.textMain)
                Spacer()
                Button(LocalizedStringKey("reset")) {
                    settings.resetToDefaults()
                }
                .font(.system(size: 12))
                .foregroundColor(settings.textMuted)
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LocalizedStringKey("color_theme"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.textMain)
                        
                        ColorRow(label: LocalizedStringKey("background"), r: $settings.theme.darkBgR, g: $settings.theme.darkBgG, b: $settings.theme.darkBgB, alpha: $settings.theme.darkBgAlpha)
                        ColorRow(label: LocalizedStringKey("surface"), r: $settings.theme.darkSurfaceR, g: $settings.theme.darkSurfaceG, b: $settings.theme.darkSurfaceB, alpha: $settings.theme.darkSurfaceAlpha)
                        ColorRow(label: LocalizedStringKey("accent"), r: $settings.theme.accentR, g: $settings.theme.accentG, b: $settings.theme.accentB, alpha: $settings.theme.accentAlpha)
                        ColorRow(label: LocalizedStringKey("text"), r: $settings.theme.textMainR, g: $settings.theme.textMainG, b: $settings.theme.textMainB, alpha: $settings.theme.textMainAlpha)
                        ColorRow(label: LocalizedStringKey("text_secondary"), r: $settings.theme.textMutedR, g: $settings.theme.textMutedG, b: $settings.theme.textMutedB, alpha: $settings.theme.textMutedAlpha)
                        ColorRow(label: LocalizedStringKey("lyrics_text"), r: $settings.theme.lyricActiveR, g: $settings.theme.lyricActiveG, b: $settings.theme.lyricActiveB, alpha: $settings.theme.lyricActiveAlpha)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey("language"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.textMain)
                        
                        HStack(spacing: 16) {
                            Button(action: { settings.setLanguage("ru") }) {
                                HStack {
                                    Image(systemName: settings.language == "ru" ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                    Text(LocalizedStringKey("russian"))
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(settings.language == "ru" ? .accent : settings.textMuted)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { settings.setLanguage("en") }) {
                                HStack {
                                    Image(systemName: settings.language == "en" ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                    Text(LocalizedStringKey("english"))
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(settings.language == "en" ? .accent : settings.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Restart the application to apply the language")
                            .font(.system(size: 10))
                            .foregroundColor(settings.textMuted.opacity(0.5))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: 600)
        .background(settings.darkBg)
        .onDisappear {
            settings.saveTheme()
        }
    }
}

// MARK: - Строка RGB + прозрачность

struct ColorRow: View {
    let label: LocalizedStringKey
    @Binding var r: Double
    @Binding var g: Double
    @Binding var b: Double
    var alpha: Binding<Double>? = nil
    
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: r, green: g, blue: b).opacity(alpha?.wrappedValue ?? 1.0))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 80, alignment: .leading)
            
            // RGB
            HStack(spacing: 4) {
                TextField("0-255", value: Binding(get: { Int(r * 255) }, set: { r = Double($0) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                
                TextField("0-255", value: Binding(get: { Int(g * 255) }, set: { g = Double($0) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                
                TextField("0-255", value: Binding(get: { Int(b * 255) }, set: { b = Double($0) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
            }
            
            // Прозрачность с подписью
            if let alpha = alpha {
                VStack(spacing: 2) {
                    Text(LocalizedStringKey("transparency_short"))
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.35))
                    TextField("0-100", value: Binding(get: { Int(alpha.wrappedValue * 100) }, set: { alpha.wrappedValue = Double($0) / 100.0 }), format: .number)
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                        .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
