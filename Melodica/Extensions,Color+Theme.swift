// Extensions/Color+Theme.swift
import SwiftUI
import AppKit

extension Color {
    static var darkBg: Color { SettingsManager.shared.darkBg }
    static var darkSurface: Color { SettingsManager.shared.darkSurface }
    static var accent: Color { SettingsManager.shared.accent }
    static var textMain: Color { SettingsManager.shared.textMain }
    static var textMuted: Color { SettingsManager.shared.textMuted }
    static var lyricActive: Color { SettingsManager.shared.lyricActive }

    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((int >> 24) & 0xFF) / 255
            g = CGFloat((int >> 16) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
            a = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - AppKit bridge для темы

extension NSColor {
    static var darkBg: NSColor {
        NSColor(SettingsManager.shared.darkBg)
    }
    static var darkSurface: NSColor {
        NSColor(SettingsManager.shared.darkSurface)
    }
    static var accent: NSColor {
        SettingsManager.shared.accentNSColor
    }
    static var textMain: NSColor {
        NSColor(SettingsManager.shared.textMain)
    }
    static var textMuted: NSColor {
        NSColor(SettingsManager.shared.textMuted)
    }
    static var lyricActive: NSColor {
        SettingsManager.shared.lyricActiveNSColor
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((int >> 24) & 0xFF) / 255
            g = CGFloat((int >> 16) & 0xFF) / 255
            b = CGFloat((int >> 8) & 0xFF) / 255
            a = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#888888" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let a = Int(rgb.alphaComponent * 255)
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
