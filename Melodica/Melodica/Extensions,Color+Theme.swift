// Extensions,Color+Theme.swift
import SwiftUI

extension Color {
    static var darkBg: Color { SettingsManager.shared.darkBg }
    static var darkSurface: Color { SettingsManager.shared.darkSurface }
    static var accent: Color { SettingsManager.shared.accent }
    static var textMain: Color { SettingsManager.shared.textMain }
    static var textMuted: Color { SettingsManager.shared.textMuted }
    static var lyricActive: Color { SettingsManager.shared.lyricActive }
}
