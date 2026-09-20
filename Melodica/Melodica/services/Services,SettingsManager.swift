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
    var activeTheme: String = "default"
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
    var thumbnailCreationSpeed: Double = 0.05
    var circularSensitivity: Double = 20.0
    var circularFrequencyRange: String = "sub_bass"
    var spectrumMultiplier: Double = 10.0
    var spectrumProcessingEnabled: Bool = true
    
    var waveformCacheMode: String = "off"
    var lrcEnabledTags: [String: Bool] = [
        "orig": true, "trans": true, "ja": true, "en": true
    ]
    var lrcShowMetadata: Bool = false
    var lrcMetadataPosition: String = "after" // "before" или "after"
    var lrcMetadataColor: String = "#AAAAAA"
    var lrcMetadataFields: [String: Bool] = [
        "title": true, "artist": true, "album": true, "author": false, "length": false
    ]
    var lrcOrigOverride: Bool = true
    var lrcTagColors: [String: String] = [
        // Основные
        "orig": "#FFFFFF",        // Оригинал - белый
        "trans": "#FFB8A8",       // Перевод - тёплый персиковый
        
        // Языки
        "ja": "#FFFFFF",          // Японский - белый
        "en": "#CCCCCC",          // Английский - светло-серый
        "ko": "#CCCCCC",          // Корейский
        "zh": "#CCCCCC",          // Китайский
        "ru": "#CCCCCC",          // Русский
        "uk": "#CCCCCC",          // Украинский
        "fr": "#CCCCCC",          // Французский
        "de": "#CCCCCC",          // Немецкий
        "es": "#CCCCCC",          // Испанский
        "it": "#CCCCCC",          // Итальянский
        "pt": "#CCCCCC",          // Португальский
        
        // Произношение (все одинакового цвета - приятный голубовато-серый)
        "ja-rom": "#A8C8E8",      // Romaji
        "ja-furi": "#A8C8E8",     // Фуригана
        "ja-hira": "#A8C8E8",     // Хирагана
        "ko-rom": "#A8C8E8",      // Romaja
        "zh-pinyin": "#A8C8E8",   // Pinyin
        "zh-bpmf": "#A8C8E8",     // Bopomofo
        "ru-lat": "#A8C8E8",      // Кириллица-латиница
        
        // Специальные
        "inst": "#B8B8D0",        // Инструментал - мягкий фиолетово-серый
        "bg": "#C8C0A0",          // Фон - тёплый бежевый
        "rap": "#FFB888",         // Рэп - оранжевый
        "chord": "#98D898",       // Аккорды - зелёный
        "note": "#D0C0E8",        // Примечания - лавандовый
        "lit": "#FFE0A0"          // Дословный перевод - светло-жёлтый
    ]
      var lrcMode: String = "auto"
      var lrcTagOpacity: Double = 100
      var lrcInstColor: String = "#888888"
      var lrcInstOpacity: Double = 100
      var lrcNoteIconColor: String = "#AAAAAA"
      var lrcNoteIconOpacity: Double = 100
      var lrcNoteTextColor: String = "#CCCCCC"
      var lrcNoteBgColor: String = "#1E1E2E"
      var lrcNoteBgOpacity: Double = 90
      var lrcActiveColor: String = "#FFD91A"
      var lrcActiveOpacity: Double = 100
      var lrcInactiveColor: String = "#888888"
      var lrcInactiveOpacity: Double = 100
      var lrcChordsColor: String = "#88CC88"
      var lrcChordsOpacity: Double = 100
      var lrcDimInactive: Bool = true
      var lrcUnlimitedFields: Bool = false
      var visualizationMode: String = "off"
      var trackStatisticsEnabled: Bool = false
      var lrcWordHighlight: Bool = false
    
    
  }

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var theme = ThemeColors()
    @Published var activeTheme: String = "default"
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
    @Published var thumbnailCreationSpeed: Double = 0.05
    @Published var circularSensitivity: Double = 20.0
    @Published var circularFrequencyRange: String = "sub_bass"
    @Published var spectrumMultiplier: Double = 10.0
    @Published var spectrumProcessingEnabled: Bool = true
    @Published var waveformCacheMode: String = "off"
    @Published var lrcEnabledTags: [String: Bool] = [
        "orig": true, "trans": true, "ja": true, "en": true,
        "ja-rom": false, "ko-rom": false, "zh-pinyin": false,
        "inst": true, "bg": true, "rap": true, "chord": false, "note": false
    ]
    @Published var lrcTagColors: [String: String] = [
        "orig": "#FFFFFF", "trans": "#888888", "ja": "#FFFFFF", "en": "#CCCCCC",
        "ja-rom": "#88AACC", "ko-rom": "#88AACC",
        "inst": "#888888", "bg": "#AAAAAA", "rap": "#FFAA55", "chord": "#88CC88"
    ]
    @Published var lrcMode: String = "auto"
    @Published var lrcTagOpacity: Double = 100
    @Published var lrcInstColor: String = "#888888"
    @Published var lrcInstOpacity: Double = 100
    @Published var lrcNoteIconColor: String = "#AAAAAA"
    @Published var lrcNoteIconOpacity: Double = 100
    @Published var lrcNoteTextColor: String = "#CCCCCC"
    @Published var lrcNoteBgColor: String = "#1E1E2E"
    @Published var lrcNoteBgOpacity: Double = 90
    @Published var lrcActiveColor: String = "#FFD91A"
    @Published var lrcActiveOpacity: Double = 100
    @Published var lrcInactiveColor: String = "#888888"
    @Published var lrcInactiveOpacity: Double = 100
    @Published var lrcChordsColor: String = "#88CC88"
    @Published var lrcChordsOpacity: Double = 100
    @Published var lrcDimInactive: Bool = true
    @Published var lrcUnlimitedFields: Bool = false
    @Published var lrcShowMetadata: Bool = false
    @Published var lrcMetadataPosition: String = "after"
    @Published var lrcMetadataColor: String = "#AAAAAA"
    @Published var lrcMetadataFields: [String: Bool] = [
        "title": true, "artist": true, "album": true, "author": false, "length": false
    ]
    @Published var lrcOrigOverride: Bool = true
    enum RGMode: String, CaseIterable {
        case off = "off"
        case track = "track"
        case album = "album"
    }
    @Published var visualizationMode: String = "off"
    @Published var trackStatisticsEnabled: Bool = false
    @Published var lrcWordHighlight: Bool = false
    
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
        activeTheme = decoded.activeTheme
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
        thumbnailCreationSpeed = decoded.thumbnailCreationSpeed
        circularSensitivity = decoded.circularSensitivity
        circularFrequencyRange = decoded.circularFrequencyRange
        spectrumMultiplier = decoded.spectrumMultiplier
        spectrumProcessingEnabled = decoded.spectrumProcessingEnabled
        waveformCacheMode = decoded.waveformCacheMode
        lrcEnabledTags = decoded.lrcEnabledTags
        lrcTagColors = decoded.lrcTagColors
        lrcMode = decoded.lrcMode
        lrcTagOpacity = decoded.lrcTagOpacity
        lrcInstColor = decoded.lrcInstColor
        lrcInstOpacity = decoded.lrcInstOpacity
        lrcNoteIconColor = decoded.lrcNoteIconColor
        lrcNoteIconOpacity = decoded.lrcNoteIconOpacity
        lrcNoteTextColor = decoded.lrcNoteTextColor
        lrcNoteBgColor = decoded.lrcNoteBgColor
        lrcNoteBgOpacity = decoded.lrcNoteBgOpacity
        lrcActiveColor = decoded.lrcActiveColor
        lrcActiveOpacity = decoded.lrcActiveOpacity
        lrcInactiveColor = decoded.lrcInactiveColor
        lrcInactiveOpacity = decoded.lrcInactiveOpacity
        lrcChordsColor = decoded.lrcChordsColor
        lrcChordsOpacity = decoded.lrcChordsOpacity
        lrcDimInactive = decoded.lrcDimInactive
        lrcShowMetadata = decoded.lrcShowMetadata
        lrcMetadataPosition = decoded.lrcMetadataPosition
        lrcMetadataColor = decoded.lrcMetadataColor
        lrcMetadataFields = decoded.lrcMetadataFields
        lrcOrigOverride = decoded.lrcOrigOverride
        lrcUnlimitedFields = decoded.lrcUnlimitedFields
        visualizationMode = decoded.visualizationMode
        trackStatisticsEnabled = decoded.trackStatisticsEnabled
        lrcWordHighlight = decoded.lrcWordHighlight
    }
    
    func save() {
        let data = SettingsData(
            theme: theme,
            activeTheme: activeTheme,
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
            thumbnailCreationSpeed: thumbnailCreationSpeed,
            circularSensitivity: circularSensitivity,
            circularFrequencyRange: circularFrequencyRange,
            spectrumMultiplier: spectrumMultiplier,
            spectrumProcessingEnabled: spectrumProcessingEnabled,
            waveformCacheMode: waveformCacheMode,
            lrcEnabledTags: lrcEnabledTags,
            lrcShowMetadata: lrcShowMetadata,
            lrcMetadataPosition: lrcMetadataPosition,
            lrcMetadataColor: lrcMetadataColor,
            lrcMetadataFields: lrcMetadataFields,
            lrcOrigOverride: lrcOrigOverride,
            lrcTagColors: lrcTagColors,
            lrcMode: lrcMode,
            lrcTagOpacity: lrcTagOpacity,
            lrcInstColor: lrcInstColor,
            lrcInstOpacity: lrcInstOpacity,
            lrcNoteIconColor: lrcNoteIconColor,
            lrcNoteIconOpacity: lrcNoteIconOpacity,
            lrcNoteTextColor: lrcNoteTextColor,
            lrcNoteBgColor: lrcNoteBgColor,
            lrcNoteBgOpacity: lrcNoteBgOpacity,
            lrcActiveColor: lrcActiveColor,
            lrcActiveOpacity: lrcActiveOpacity,
            lrcInactiveColor: lrcInactiveColor,
            lrcInactiveOpacity: lrcInactiveOpacity,
            lrcChordsColor: lrcChordsColor,
            lrcChordsOpacity: lrcChordsOpacity,
            lrcDimInactive: lrcDimInactive,
            lrcUnlimitedFields: lrcUnlimitedFields,
            visualizationMode: visualizationMode,
            trackStatisticsEnabled: trackStatisticsEnabled,
            lrcWordHighlight: lrcWordHighlight,
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
    func setTheme(_ id: String) {
        activeTheme = id
        save()
    }

    private func restartApp() {
        // Закрываем все sheet'ы
        dismissAllSheets {
            // Создаем shell-скрипт для перезапуска
            let bundlePath = Bundle.main.bundlePath
            let script = """
            #!/bin/bash
            sleep 1
            open "\(bundlePath)"
            """
            
            let tempDir = FileManager.default.temporaryDirectory
            let scriptURL = tempDir.appendingPathComponent("restart_\(UUID().uuidString).sh")
            
            do {
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                
                // Делаем скрипт исполняемым
                let chmodTask = Process()
                chmodTask.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodTask.arguments = ["+x", scriptURL.path]
                try? chmodTask.run()
                chmodTask.waitUntilExit()
                
                // Запускаем скрипт в фоне
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = [scriptURL.path]
                try? task.run()
                
                // Принудительно завершаем приложение
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            } catch {
            }
        }
    }

    private func dismissAllSheets(completion: @escaping () -> Void) {
        let windows = NSApp.windows
        var sheetCount = 0
        
        for window in windows {
            if let sheet = window.attachedSheet {
                sheetCount += 1
                window.endSheet(sheet, returnCode: .cancel)
            }
        }
        
        if sheetCount == 0 {
            completion()
        } else {
            // Ждем пока sheet'ы закроются
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion()
            }
        }
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
    
    func setThumbnailCreationSpeed(_ speed: Double) {
        thumbnailCreationSpeed = min(max(speed, 0), 0.2)
        save()
    }
    func setCircularSensitivity(_ value: Double) {
        circularSensitivity = min(max(value, 1), 100)
        save()
    }

    func setCircularFrequencyRange(_ value: String) {
        circularFrequencyRange = value
        save()
    }
    func setSpectrumMultiplier(_ value: Double) {
        spectrumMultiplier = min(max(value, 1), 30)
        save()
    }

    func setSpectrumProcessing(_ enabled: Bool) {
        spectrumProcessingEnabled = enabled
        save()
    }

    func setWaveformCacheMode(_ mode: String) {
        waveformCacheMode = mode
        save()
    }
    func setLRCMode(_ mode: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMode = mode
            self?.save()
        }
    }
    func setLRCEnabledTags(_ tags: [String: Bool]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcEnabledTags = tags
            self?.save()
        }
    }
    func setLRCTagColors(_ colors: [String: String]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcTagColors = colors
            self?.save()
        }
    }
    func setLRCTagOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcTagOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCInstColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInstColor = val
            self?.save()
        }
    }
    func setLRCInstOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInstOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCNoteIconColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteIconColor = val
            self?.save()
        }
    }
    func setLRCNoteIconOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteIconOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCNoteTextColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteTextColor = val
            self?.save()
        }
    }
    func setLRCNoteBgColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteBgColor = val
            self?.save()
        }
    }
    func setLRCNoteBgOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteBgOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCActiveColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcActiveColor = val
            self?.save()
        }
    }
    func setLRCActiveOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcActiveOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCInactiveColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInactiveColor = val
            self?.save()
        }
    }
    func setLRCInactiveOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInactiveOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCChordsColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcChordsColor = val
            self?.save()
        }
    }
    func setLRCChordsOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcChordsOpacity = min(max(val, 0), 100)
            self?.save()
        }
    }
    func setLRCDimInactive(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcDimInactive = val
            self?.save()
        }
    }
    func setLRCShowMetadata(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcShowMetadata = val
            self?.save()
        }
    }
    func setLRCMetadataPosition(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataPosition = val
            self?.save()
        }
    }
    func setLRCMetadataColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataColor = val
            self?.save()
        }
    }
    func setLRCMetadataFields(_ val: [String: Bool]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataFields = val
            self?.save()
        }
    }
    func setLRCOrigOverride(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcOrigOverride = val
            self?.save()
        }
    }
    
    func resetLRCSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lrcMode = "auto"
            self.lrcEnabledTags = [
                "orig": true, "trans": true, "ja": true, "en": true
            ]
            self.lrcTagColors = [
                "orig": "#FFFFFF", "trans": "#FFB8A8",
                "ja": "#FFFFFF", "en": "#CCCCCC", "ko": "#CCCCCC", "zh": "#CCCCCC",
                "ru": "#CCCCCC", "uk": "#CCCCCC", "fr": "#CCCCCC", "de": "#CCCCCC",
                "es": "#CCCCCC", "it": "#CCCCCC", "pt": "#CCCCCC",
                "ja-rom": "#A8C8E8", "ja-furi": "#A8C8E8", "ja-hira": "#A8C8E8",
                "ko-rom": "#A8C8E8", "zh-pinyin": "#A8C8E8", "zh-bpmf": "#A8C8E8", "ru-lat": "#A8C8E8",
                "inst": "#B8B8D0", "bg": "#C8C0A0", "rap": "#FFB888",
                "chord": "#98D898", "note": "#D0C0E8", "lit": "#FFE0A0"
            ]
            self.lrcShowMetadata = false
            self.lrcMetadataPosition = "after"
            self.lrcMetadataColor = "#AAAAAA"
            self.lrcMetadataFields = ["title": true, "artist": true, "album": true, "author": false, "length": false]
            self.lrcOrigOverride = true
            self.lrcTagOpacity = 100
            self.lrcInstColor = "#888888"; self.lrcInstOpacity = 100
            self.lrcNoteIconColor = "#AAAAAA"; self.lrcNoteIconOpacity = 100
            self.lrcNoteTextColor = "#CCCCCC"; self.lrcNoteBgColor = "#1E1E2E"; self.lrcNoteBgOpacity = 90
            self.lrcActiveColor = "#FFD91A"; self.lrcActiveOpacity = 100
            self.lrcInactiveColor = "#888888"; self.lrcInactiveOpacity = 100
            self.lrcChordsColor = "#88CC88"; self.lrcChordsOpacity = 100
            self.lrcDimInactive = true
            self.lrcUnlimitedFields = false
            self.save()
        }
    }
    func setVisualizationMode(_ mode: String) {
        visualizationMode = mode
        save()
    }
    func setTrackStatisticsEnabled(_ value: Bool) {
        trackStatisticsEnabled = value
        save()
    }
    func setLRCWordHighlight(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcWordHighlight = val
            self?.save()
        }
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
