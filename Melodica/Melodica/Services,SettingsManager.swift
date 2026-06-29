// Services,SettingsManager.swift
import SwiftUI
import Combine

struct ThemeColors: Codable {
    var darkBgR: Double = 0.07
    var darkBgG: Double = 0.07
    var darkBgB: Double = 0.10
    var darkBgAlpha: Double = 1.0
    
    var darkSurfaceR: Double = 0.12
    var darkSurfaceG: Double = 0.12
    var darkSurfaceB: Double = 0.16
    var darkSurfaceAlpha: Double = 1.0
    
    var accentR: Double = 0.95
    var accentG: Double = 0.30
    var accentB: Double = 0.55
    var accentAlpha: Double = 1.0
    
    var textMainR: Double = 1.0
    var textMainG: Double = 1.0
    var textMainB: Double = 1.0
    var textMainAlpha: Double = 1.0
    
    var textMutedR: Double = 1.0
    var textMutedG: Double = 1.0
    var textMutedB: Double = 1.0
    var textMutedAlpha: Double = 0.55
    
    var lyricActiveR: Double = 1.0
    var lyricActiveG: Double = 0.85
    var lyricActiveB: Double = 0.10
    var lyricActiveAlpha: Double = 1.0
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var theme = ThemeColors()
    @Published var language: String = "en"
    
    private let defaults = UserDefaults.standard
    private let themeKey = "melodica_theme"
    private let languageKey = "AppleLanguages"
    
    init() {
        loadTheme()
        loadLanguage()
    }
    
    func loadTheme() {
        guard let data = defaults.data(forKey: themeKey),
              let decoded = try? JSONDecoder().decode(ThemeColors.self, from: data) else { return }
        theme = decoded
    }
    
    func saveTheme() {
        if let data = try? JSONEncoder().encode(theme) {
            defaults.set(data, forKey: themeKey)
        }
    }
    
    func resetToDefaults() {
        theme = ThemeColors()
        saveTheme()
    }
    
    func loadLanguage() {
        if let languages = defaults.array(forKey: languageKey) as? [String],
           let first = languages.first {
            language = first
        } else {
            language = "en"
        }
    }
    
    func setLanguage(_ lang: String) {
        language = lang
        defaults.set([lang], forKey: languageKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
    
    var darkBg: Color {
        Color(red: theme.darkBgR, green: theme.darkBgG, blue: theme.darkBgB).opacity(theme.darkBgAlpha)
    }
    var darkSurface: Color {
        Color(red: theme.darkSurfaceR, green: theme.darkSurfaceG, blue: theme.darkSurfaceB).opacity(theme.darkSurfaceAlpha)
    }
    var accent: Color {
        Color(red: theme.accentR, green: theme.accentG, blue: theme.accentB).opacity(theme.accentAlpha)
    }
    var textMain: Color {
        Color(red: theme.textMainR, green: theme.textMainG, blue: theme.textMainB).opacity(theme.textMainAlpha)
    }
    var textMuted: Color {
        Color(red: theme.textMutedR, green: theme.textMutedG, blue: theme.textMutedB).opacity(theme.textMutedAlpha)
    }
    var lyricActive: Color {
        Color(red: theme.lyricActiveR, green: theme.lyricActiveG, blue: theme.lyricActiveB).opacity(theme.lyricActiveAlpha)
    }
}
