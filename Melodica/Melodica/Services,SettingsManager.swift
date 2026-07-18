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
    
    var playerControlsR: Double = 1.0
    var playerControlsG: Double = 1.0
    var playerControlsB: Double = 1.0
    var playerControlsAlpha: Double = 1.0
}

struct SettingsData: Codable {
    var theme: ThemeColors = ThemeColors()
    var language: String = "en"
    var progressUpdateInterval: Double = 100
    var gaplessEnabled: Bool = false
    var gaplessThreshold: Double = -24
    var crossfadeEnabled: Bool = false
    var crossfadeDuration: Double = 5
    var silenceSkipEnabled: Bool = false
    var silenceSkipThreshold: Double = -50
    var albumGridSize: Double = 150
    var rgMode: String = "track"
    var autoScanOnStartup: Bool = true
    var thumbnailCreationSpeed: Double = 0.05
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var theme = ThemeColors()
    @Published var language: String = "en"
    @Published var progressUpdateInterval: Double = 100
    @Published var gaplessEnabled: Bool = false
    @Published var gaplessThreshold: Double = -24
    @Published var crossfadeEnabled: Bool = false
    @Published var crossfadeDuration: Double = 5
    @Published var silenceSkipEnabled: Bool = false
    @Published var silenceSkipThreshold: Double = -50
    @Published var albumGridSize: Double = 150
    @Published var rgMode: String = "track"
    @Published var autoScanOnStartup: Bool = true
    @Published var thumbnailCreationSpeed: Double = 0.05
    
    enum RGMode: String, CaseIterable {
        case off = "off"
        case track = "track"
        case album = "album"
    }
    
    private var settingsURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("settings.json")
    }
    
    init() {
        load()
    }
    
    private func load() {
        let firstLaunch = !FileManager.default.fileExists(atPath: settingsURL.path)
        
        guard !firstLaunch,
              let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            // Первый запуск — форсируем английский
            if firstLaunch {
                language = "en"
                UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
            }
            return
        }
        
        theme = decoded.theme
        language = decoded.language
        progressUpdateInterval = decoded.progressUpdateInterval
        gaplessEnabled = decoded.gaplessEnabled
        gaplessThreshold = decoded.gaplessThreshold
        crossfadeEnabled = decoded.crossfadeEnabled
        crossfadeDuration = decoded.crossfadeDuration
        silenceSkipEnabled = decoded.silenceSkipEnabled
        silenceSkipThreshold = decoded.silenceSkipThreshold
        albumGridSize = decoded.albumGridSize
        rgMode = decoded.rgMode
        autoScanOnStartup = decoded.autoScanOnStartup
        thumbnailCreationSpeed = decoded.thumbnailCreationSpeed
    }
    
    private func save() {
        let data = SettingsData(
            theme: theme,
            language: language,
            progressUpdateInterval: progressUpdateInterval,
            gaplessEnabled: gaplessEnabled,
            gaplessThreshold: gaplessThreshold,
            crossfadeEnabled: crossfadeEnabled,
            crossfadeDuration: crossfadeDuration,
            silenceSkipEnabled: silenceSkipEnabled,
            silenceSkipThreshold: silenceSkipThreshold,
            albumGridSize: albumGridSize,
            rgMode: rgMode,
            autoScanOnStartup: autoScanOnStartup,
            thumbnailCreationSpeed: thumbnailCreationSpeed
        )
        
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: settingsURL, options: .atomicWrite)
        }
    }
    
    func saveTheme() { save() }
    
    func resetToDefaults() {
        theme = ThemeColors()
        thumbnailCreationSpeed = 0.05
        save()
    }
    
    func setLanguage(_ lang: String) {
        language = lang
        save()
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restartApp()
        }
    }

    private func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
    
    func setProgressInterval(_ ms: Double) {
        progressUpdateInterval = min(max(ms, 50), 1000)
        save()
        NotificationCenter.default.post(name: .progressIntervalChanged, object: nil)
    }
    
    func setGapless(enabled: Bool) {
        gaplessEnabled = enabled
        save()
        if !enabled {
            NotificationCenter.default.post(name: NSNotification.Name("gaplessOrCrossfadeDisabled"), object: nil)
        }
    }
    
    func setGaplessThreshold(_ db: Double) {
        gaplessThreshold = min(max(db, -60), 0)
        save()
    }
    
    func setCrossfade(enabled: Bool) {
        crossfadeEnabled = enabled
        save()
        if !enabled {
            NotificationCenter.default.post(name: NSNotification.Name("gaplessOrCrossfadeDisabled"), object: nil)
        }
    }
    
    func setCrossfadeDuration(_ sec: Double) {
        crossfadeDuration = min(max(sec, 1), 20)
        save()
    }
    
    func setSilenceSkip(enabled: Bool) {
        silenceSkipEnabled = enabled
        save()
    }
    
    func setSilenceSkipThreshold(_ db: Double) {
        silenceSkipThreshold = min(max(db, -80), -20)
        save()
    }
    
    func setAlbumGridSize(_ size: Double) {
        albumGridSize = min(max(size, 120), 200)
        save()
    }
    
    func setRGMode(_ mode: String) {
        rgMode = mode
        save()
        NotificationCenter.default.post(name: NSNotification.Name("rgModeChanged"), object: nil)
    }
    
    func setAutoScanOnStartup(_ enabled: Bool) {
        autoScanOnStartup = enabled
        save()
    }
    
    func setThumbnailCreationSpeed(_ speed: Double) {
        thumbnailCreationSpeed = min(max(speed, 0), 0.2)
        save()
    }
    
    // MARK: - Colors
    var darkBg: Color { Color(red: theme.darkBgR, green: theme.darkBgG, blue: theme.darkBgB).opacity(theme.darkBgAlpha) }
    var darkSurface: Color { Color(red: theme.darkSurfaceR, green: theme.darkSurfaceG, blue: theme.darkSurfaceB).opacity(theme.darkSurfaceAlpha) }
    var accent: Color { Color(red: theme.accentR, green: theme.accentG, blue: theme.accentB).opacity(theme.accentAlpha) }
    var textMain: Color { Color(red: theme.textMainR, green: theme.textMainG, blue: theme.textMainB).opacity(theme.textMainAlpha) }
    var textMuted: Color { Color(red: theme.textMutedR, green: theme.textMutedG, blue: theme.textMutedB).opacity(theme.textMutedAlpha) }
    var lyricActive: Color { Color(red: theme.lyricActiveR, green: theme.lyricActiveG, blue: theme.lyricActiveB).opacity(theme.lyricActiveAlpha) }
    var playerControlsColor: Color { Color(red: theme.playerControlsR, green: theme.playerControlsG, blue: theme.playerControlsB).opacity(theme.playerControlsAlpha) }
    var lyricActiveNSColor: NSColor {
        NSColor(red: theme.lyricActiveR, green: theme.lyricActiveG, blue: theme.lyricActiveB, alpha: theme.lyricActiveAlpha)
    }
    var lyricInactiveNSColor: NSColor {
        NSColor(red: theme.textMutedR, green: theme.textMutedG, blue: theme.textMutedB, alpha: theme.textMutedAlpha)
    }
    var accentNSColor: NSColor {
        NSColor(red: theme.accentR, green: theme.accentG, blue: theme.accentB, alpha: theme.accentAlpha)
    }
}
