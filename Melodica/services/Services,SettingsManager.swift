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
    var language: String = SettingsManager.detectSystemLanguage()
    var progressUpdateInterval: Double = 100
    var gaplessEnabled: Bool = false
    var gaplessThreshold: Double = -24
    var crossfadeEnabled: Bool = false
    var crossfadeDuration: Double = 5
    var silenceSkipEnabled: Bool = false
    var silenceSkipThreshold: Double = -50
    var albumGridSize: Double = 150
    var rgMode: String = "track"
    var autoVolumeLevelingEnabled: Bool? = false
    var thumbnailCreationSpeed: Double = 0.05
    var circularSensitivity: Double = 20.0
    var circularFrequencyRange: String = "sub_bass"
    var spectrumMultiplier: Double = 10.0
    var spectrumProcessingEnabled: Bool = true
    var spectrumSmoothDecayEnabled: Bool? = true
    var spectrumFPSLimit: Int? = 60
    
    var waveformCacheMode: String = "off"
    var lrcEnabledTags: [String: Bool] = [
        "orig": true, "trans": true, "en": true, "ru": true, "inst": true
    ]
    var lrcShowMetadata: Bool = false
    var lrcMetadataPosition: String = "after" // "before" or "after"
    var lrcMetadataColor: String = "#AAAAAA"
    var lrcMetadataFields: [String: Bool] = [
        "title": true, "artist": true, "album": true, "author": false, "length": false
    ]
    var lrcOrigOverride: Bool = true
    var lrcTagColors: [String: String] = [
        // Core
        "orig": "#FFFFFF",        // Original - white
        "trans": "#FFB8A8",       // Translation - warm peach
        
        // Languages
        "ja": "#FFFFFF",          // Japanese - white
        "en": "#CCCCCC",          // English - light gray
        "ko": "#CCCCCC",          // Korean
        "zh": "#CCCCCC",          // Chinese
        "ru": "#CCCCCC",          // Russian
        "uk": "#CCCCCC",          // Ukrainian
        "fr": "#CCCCCC",          // French
        "de": "#CCCCCC",          // German
        "es": "#CCCCCC",          // Spanish
        "it": "#CCCCCC",          // Italian
        "pt": "#CCCCCC",          // Portuguese
        
        // Pronunciation (all identical color - soft bluish gray)
        "ja-rom": "#A8C8E8",      // Romaji
        "ja-furi": "#A8C8E8",     // Furigana
        "ja-hira": "#A8C8E8",     // Hiragana
        "ko-rom": "#A8C8E8",      // Romaja
        "zh-pinyin": "#A8C8E8",   // Pinyin
        "zh-bpmf": "#A8C8E8",     // Bopomofo
        "ru-lat": "#A8C8E8",      // Cyrillic-Latin
        
        // Special
        "inst": "#B8B8D0",        // Instrumental - soft violet-gray
        "bg": "#C8C0A0",          // Background - warm beige
        "rap": "#FFB888",         // Rap - orange
        "chord": "#98D898",       // Chords - green
        "note": "#D0C0E8",        // Notes - lavender
        "lit": "#FFE0A0"          // Literal translation - light yellow
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
      var lrcAutoTranslate: Bool? = false
      var lrcTranslateStandardLRC: Bool? = true
      var spatialAudioEnabled: Bool = false
      var spatialAlgorithm: String = "hrtf"   // equalPower / spherical / hrtf / hrtfHQ / soundField
      var spatialPan: Float? = 0.0
      var spatialDistance: Float? = 1.0
      var spatialElevation: Float? = 0.0
      var spatialRoomPreset: String? = "off"
      var spatialReverbBlend: Float? = 0.0
      var spatialObstruction: Float? = 0.0
      var spatialOcclusion: Float? = 0.0
      var spatialRolloff: Float? = 0.0
      var spatialStereoSpeakers: Bool? = true
      var spatialSpeakerSpread: Float? = 2.0
      var lastReverbPreset: String? = "mediumRoom"
  }

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // MARK: - Supported Languages & Detection
    static let supportedLanguages: [String] = ["en", "ru", "de", "fr", "it", "ja", "zh-Hans"]
    
    static func detectSystemLanguage(preferences: [String] = Locale.preferredLanguages) -> String {
        let matched = Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: preferences)
        if let best = matched.first, supportedLanguages.contains(best) {
            return best
        }
        for pref in preferences {
            let lower = pref.lowercased()
            if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") {
                return "zh-Hans"
            }
            let code = String(lower.prefix(2))
            if let direct = supportedLanguages.first(where: { $0.lowercased() == code }) {
                return direct
            }
        }
        return "en"
    }
    
    @Published var theme = ThemeColors()
    @Published var activeTheme: String = "default"
    @Published var language: String = SettingsManager.detectSystemLanguage()
    @Published var progressUpdateInterval: Double = 100
    @Published var gaplessEnabled: Bool = false
    @Published var gaplessThreshold: Double = -24
    @Published var crossfadeEnabled: Bool = false
    @Published var crossfadeDuration: Double = 5
    @Published var silenceSkipEnabled: Bool = false
    @Published var silenceSkipThreshold: Double = -50
    @Published var albumGridSize: Double = 150
    @Published var rgMode: String = "track"
    @Published var autoVolumeLevelingEnabled: Bool = false
    @Published var thumbnailCreationSpeed: Double = 0.05
    @Published var circularSensitivity: Double = 20.0
    @Published var circularFrequencyRange: String = "sub_bass"
    @Published var spectrumMultiplier: Double = 10.0
    @Published var spectrumProcessingEnabled: Bool = true
    @Published var spectrumSmoothDecayEnabled: Bool = true
    @Published var spectrumFPSLimit: Int = 60
    @Published var waveformCacheMode: String = "off"
    @Published var lrcEnabledTags: [String: Bool] = [
        "orig": true, "trans": true, "ja": true, "en": true,
        "ja-rom": false, "ko-rom": false, "zh-pinyin": false,
        "inst": true, "bg": false, "rap": false, "chord": false, "note": false
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
    @Published var lrcAutoTranslate: Bool = false
    @Published var lrcTranslateStandardLRC: Bool = true
    @Published var spatialAudioEnabled: Bool = false
    @Published var spatialAlgorithm: String = "hrtf"
    @Published var spatialPan: Float = 0.0
    @Published var spatialDistance: Float = 1.0
    @Published var spatialElevation: Float = 0.0
    @Published var spatialRoomPreset: String = "off"
    @Published var spatialReverbBlend: Float = 0.0
    @Published var spatialObstruction: Float = 0.0
    @Published var spatialOcclusion: Float = 0.0
    @Published var spatialRolloff: Float = 0.0
    @Published var spatialStereoSpeakers: Bool = true
    @Published var spatialSpeakerSpread: Float = 2.0
    @Published var lastReverbPreset: String = "mediumRoom"
    
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
            // First launch — automatically select language based on system preferences
            if firstLaunch {
                let initialLanguage = SettingsManager.detectSystemLanguage()
                language = initialLanguage
                UserDefaults.standard.set([initialLanguage], forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
                save()
            }
            return
        }
        
        theme = decoded.theme
        activeTheme = decoded.activeTheme
        if SettingsManager.supportedLanguages.contains(decoded.language) {
            language = decoded.language
        } else {
            language = SettingsManager.detectSystemLanguage()
        }
        progressUpdateInterval = decoded.progressUpdateInterval
        gaplessEnabled = decoded.gaplessEnabled
        gaplessThreshold = decoded.gaplessThreshold
        crossfadeEnabled = decoded.crossfadeEnabled
        crossfadeDuration = decoded.crossfadeDuration
        silenceSkipEnabled = decoded.silenceSkipEnabled
        silenceSkipThreshold = decoded.silenceSkipThreshold
        albumGridSize = decoded.albumGridSize
        rgMode = decoded.rgMode
        autoVolumeLevelingEnabled = decoded.autoVolumeLevelingEnabled ?? false
        thumbnailCreationSpeed = decoded.thumbnailCreationSpeed
        circularSensitivity = decoded.circularSensitivity
        circularFrequencyRange = decoded.circularFrequencyRange
        spectrumMultiplier = decoded.spectrumMultiplier
        spectrumProcessingEnabled = decoded.spectrumProcessingEnabled
        spectrumSmoothDecayEnabled = decoded.spectrumSmoothDecayEnabled ?? true
        spectrumFPSLimit = decoded.spectrumFPSLimit ?? 60
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
        if !lrcUnlimitedFields {
            let infoTags = ["orig"] + LyricsParser.languageTags.map { $0 } + LyricsParser.pronunciationTags.map { $0 } + ["trans", "lit", "bg", "rap", "chord"]
            var count = 0
            for tag in infoTags {
                if lrcEnabledTags[tag] == true {
                    count += 1
                    if count > 5 {
                        lrcEnabledTags[tag] = false
                    }
                }
            }
        }
        visualizationMode = decoded.visualizationMode
        trackStatisticsEnabled = decoded.trackStatisticsEnabled
        lrcWordHighlight = decoded.lrcWordHighlight
        lrcAutoTranslate = decoded.lrcAutoTranslate ?? false
        lrcTranslateStandardLRC = decoded.lrcTranslateStandardLRC ?? true
        spatialAudioEnabled = decoded.spatialAudioEnabled
        spatialAlgorithm = decoded.spatialAlgorithm
        spatialPan = decoded.spatialPan ?? 0.0
        spatialDistance = decoded.spatialDistance ?? 1.0
        spatialElevation = decoded.spatialElevation ?? 0.0
        spatialRoomPreset = decoded.spatialRoomPreset ?? "off"
        spatialReverbBlend = decoded.spatialReverbBlend ?? 0.0
        spatialObstruction = decoded.spatialObstruction ?? 0.0
        spatialOcclusion = decoded.spatialOcclusion ?? 0.0
        spatialRolloff = decoded.spatialRolloff ?? 0.0
        spatialStereoSpeakers = decoded.spatialStereoSpeakers ?? true
        spatialSpeakerSpread = decoded.spatialSpeakerSpread ?? 2.0
        lastReverbPreset = decoded.lastReverbPreset ?? "mediumRoom"
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
            autoVolumeLevelingEnabled: autoVolumeLevelingEnabled,
            thumbnailCreationSpeed: thumbnailCreationSpeed,
            circularSensitivity: circularSensitivity,
            circularFrequencyRange: circularFrequencyRange,
            spectrumMultiplier: spectrumMultiplier,
            spectrumProcessingEnabled: spectrumProcessingEnabled,
            spectrumSmoothDecayEnabled: spectrumSmoothDecayEnabled,
            spectrumFPSLimit: spectrumFPSLimit,
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
            lrcAutoTranslate: lrcAutoTranslate,
            lrcTranslateStandardLRC: lrcTranslateStandardLRC,
            spatialAudioEnabled: spatialAudioEnabled,
            spatialAlgorithm: spatialAlgorithm,
            spatialPan: spatialPan,
            spatialDistance: spatialDistance,
            spatialElevation: spatialElevation,
            spatialRoomPreset: spatialRoomPreset,
            spatialReverbBlend: spatialReverbBlend,
            spatialObstruction: spatialObstruction,
            spatialOcclusion: spatialOcclusion,
            spatialRolloff: spatialRolloff,
            spatialStereoSpeakers: spatialStereoSpeakers,
            spatialSpeakerSpread: spatialSpeakerSpread,
            lastReverbPreset: lastReverbPreset
        )
        
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: settingsURL, options: .atomicWrite)
        }
    }
    
    func saveTheme() { save() }
    
    func resetToDefaults() {
        theme = ThemeColors()
        thumbnailCreationSpeed = 0.05
        language = SettingsManager.detectSystemLanguage()
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
        // Dismiss all sheets
        dismissAllSheets {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", Bundle.main.bundlePath]
            try? task.run()
            exit(0)
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
            // Wait for sheets to dismiss
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
    
    private var lastCrossfadeToggleTime: Date = .distantPast
    private var lastGaplessToggleTime: Date = .distantPast

    func setGapless(enabled: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastGaplessToggleTime) >= 0.25 else { return }
        lastGaplessToggleTime = now
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
        let now = Date()
        guard now.timeIntervalSince(lastCrossfadeToggleTime) >= 0.25 else { return }
        lastCrossfadeToggleTime = now
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
    
    func setAutoVolumeLevelingEnabled(_ enabled: Bool) {
        autoVolumeLevelingEnabled = enabled
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.spectrumMultiplier = min(max(value, 1), 30)
            self.save()
        }
    }

    func setSpectrumProcessing(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.spectrumProcessingEnabled = enabled
            self.save()
        }
    }

    func setSpectrumSmoothDecay(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.spectrumSmoothDecayEnabled = enabled
            self.save()
        }
    }

    func setSpectrumFPSLimit(_ value: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.spectrumFPSLimit = value
            self.save()
        }
    }

    func setWaveformCacheMode(_ mode: String) {
        waveformCacheMode = mode
        save()
        NotificationCenter.default.post(name: .waveformCacheModeChanged, object: mode)
    }
    func setLRCMode(_ mode: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMode = mode
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCEnabledTags(_ tags: [String: Bool]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcEnabledTags = tags
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCTagColors(_ colors: [String: String]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcTagColors = colors
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCTagOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcTagOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCInstColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInstColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCInstOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInstOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCNoteIconColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteIconColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCNoteIconOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteIconOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCNoteTextColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteTextColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCNoteBgColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteBgColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCNoteBgOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcNoteBgOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCActiveColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcActiveColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCActiveOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcActiveOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCInactiveColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInactiveColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCInactiveOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcInactiveOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCChordsColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcChordsColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCChordsOpacity(_ val: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcChordsOpacity = min(max(val, 0), 100)
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCDimInactive(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcDimInactive = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCShowMetadata(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcShowMetadata = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCMetadataPosition(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataPosition = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCMetadataColor(_ val: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataColor = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCMetadataFields(_ val: [String: Bool]) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcMetadataFields = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCOrigOverride(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcOrigOverride = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    
    func resetLRCSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lrcMode = "auto"
            var defaultTags: [String: Bool] = ["orig": true, "trans": true, "en": true, "inst": true]
            let sysLang = SettingsManager.detectSystemLanguage().components(separatedBy: "-").first?.lowercased() ?? "en"
            defaultTags[sysLang] = true
            self.lrcEnabledTags = defaultTags
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
            self.lrcAutoTranslate = false
            self.lrcTranslateStandardLRC = true
            self.save()
            LyricsTranslationService.shared.clearCache()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setVisualizationMode(_ mode: String) {
        visualizationMode = mode
        save()
    }
    func setTrackStatisticsEnabled(_ value: Bool) {
        trackStatisticsEnabled = value
        save()
        Task { @MainActor in
            if !value, LibraryViewModel.shared?.sortField == .recommendations {
                LibraryViewModel.shared?.sortField = .album
            }
            NotificationCenter.default.post(name: .recommendationsDidUpdate, object: nil)
        }
    }
    func setLRCWordHighlight(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.lrcWordHighlight = val
            self?.save()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCAutoTranslate(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lrcAutoTranslate = val
            if val && !self.lrcTranslateStandardLRC {
                self.lrcTranslateStandardLRC = true
            }
            self.save()
            LyricsTranslationService.shared.clearCache()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setLRCTranslateStandardLRC(_ val: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lrcTranslateStandardLRC = val
            self.save()
            LyricsTranslationService.shared.clearCache()
            NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        }
    }
    func setSpatialAudioEnabled(_ value: Bool) {
        spatialAudioEnabled = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialAlgorithm(_ value: String) {
        spatialAlgorithm = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialPan(_ value: Float) {
        spatialPan = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialDistance(_ value: Float) {
        spatialDistance = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialElevation(_ value: Float) {
        spatialElevation = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialRoomPreset(_ value: String) {
        spatialRoomPreset = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialReverbBlend(_ value: Float) {
        spatialReverbBlend = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialObstruction(_ value: Float) {
        spatialObstruction = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialOcclusion(_ value: Float) {
        spatialOcclusion = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialRolloff(_ value: Float) {
        spatialRolloff = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialStereoSpeakers(_ value: Bool) {
        spatialStereoSpeakers = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func setSpatialSpeakerSpread(_ value: Float) {
        spatialSpeakerSpread = value
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    func resetSpatialSettings() {
        spatialAlgorithm = "hrtf"
        spatialPan = 0.0
        spatialDistance = 1.0
        spatialElevation = 0.0
        spatialRoomPreset = "off"
        spatialReverbBlend = 0.0
        spatialObstruction = 0.0
        spatialOcclusion = 0.0
        spatialRolloff = 0.0
        spatialStereoSpeakers = true
        spatialSpeakerSpread = 2.0
        save()
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }

    @MainActor
    func resetAllSoundSettings() {
        EqualizerManager.shared.reset()
        EQPresetManager.shared.activePresetID = nil
        EQPresetManager.shared.autoApplyByGenre = false
        EQPresetManager.shared.syncActivePresetState()

        AudioEffectsManager.shared.reset()
        lastReverbPreset = "mediumRoom"

        spatialAudioEnabled = false
        spatialAlgorithm = "hrtf"
        spatialPan = 0.0
        spatialDistance = 1.0
        spatialElevation = 0.0
        spatialRoomPreset = "off"
        spatialReverbBlend = 0.0
        spatialObstruction = 0.0
        spatialOcclusion = 0.0
        spatialRolloff = 0.0
        spatialStereoSpeakers = true
        spatialSpeakerSpread = 2.0

        gaplessEnabled = false
        gaplessThreshold = -24
        crossfadeEnabled = false
        crossfadeDuration = 5
        silenceSkipEnabled = false
        silenceSkipThreshold = -50
        rgMode = "track"
        autoVolumeLevelingEnabled = false

        save()

        NotificationCenter.default.post(name: .eqDidChange, object: nil)
        NotificationCenter.default.post(name: .audioEffectsDidChange, object: nil)
        NotificationCenter.default.post(name: .spatialAudioChanged, object: nil)
    }
    func setLastReverbPreset(_ preset: String) {
        guard preset != "off", preset != lastReverbPreset else { return }
        lastReverbPreset = preset
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
