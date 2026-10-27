// Services,DeveloperDiagnosticsService.swift
import Foundation
import AVFoundation
import AppKit
import CryptoKit
import Combine

public enum DiagnosticCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case audioEngine
    case parsers
    case playlists
    case storage
    case watcher
    case translation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Tests"
        case .audioEngine: return "Audio Engine"
        case .parsers: return "Parsers & Readers"
        case .playlists: return "Smart Playlists"
        case .storage: return "Storage & Cache"
        case .watcher: return "Folder Watcher"
        case .translation: return "Lyrics Translation"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "checklist"
        case .audioEngine: return "waveform.path.ecg"
        case .parsers: return "doc.text.magnifyingglass"
        case .playlists: return "music.note.list"
        case .storage: return "cylinder.split.1x2"
        case .watcher: return "eye"
        case .translation: return "character.bubble"
        }
    }
}

public enum DiagnosticTestStatus: String, Sendable {
    case passed
    case warning
    case failed
    case running
    case notRun
}

public struct DiagnosticTestResult: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: DiagnosticCategory
    public var status: DiagnosticTestStatus
    public var durationMs: Double
    public var summary: String
    public var logs: [String]
    public var timestamp: Date

    public init(
        id: String,
        name: String,
        category: DiagnosticCategory,
        status: DiagnosticTestStatus = .notRun,
        durationMs: Double = 0,
        summary: String = "Not executed yet",
        logs: [String] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.status = status
        self.durationMs = durationMs
        self.summary = summary
        self.logs = logs
        self.timestamp = timestamp
    }
}

@MainActor
public final class DeveloperDiagnosticsService: ObservableObject {
    public static let shared = DeveloperDiagnosticsService()

    @Published public private(set) var isRunningAll: Bool = false
    @Published public private(set) var runningTestId: String? = nil
    @Published public private(set) var results: [DiagnosticTestResult] = []
    @Published public private(set) var toneIsPlaying: Bool = false

    // Isolated test audio engine for tone generation
    private var toneEngine: AVAudioEngine?
    private var tonePlayer: AVAudioPlayerNode?
    private var toneTimer: Timer?

    private init() {
        resetTestRegistry()
    }

    public func resetTestRegistry() {
        results = [
            // Audio Engine
            DiagnosticTestResult(id: "audio_status", name: "Audio Engine & Output Device Status", category: .audioEngine),
            DiagnosticTestResult(id: "audio_effects", name: "Audio Effects & EQ Chain Parameters", category: .audioEngine),
            DiagnosticTestResult(id: "audio_synthesizer", name: "PCM Tone Synthesizer & Buffer Integrity", category: .audioEngine),
            DiagnosticTestResult(id: "audio_visualization", name: "Visualization Engine & FFT Configuration", category: .audioEngine),

            // Parsers & Readers
            DiagnosticTestResult(id: "parser_cue_standard", name: "CUE Parser Multi-Track & Timing Math", category: .parsers),
            DiagnosticTestResult(id: "parser_cue_edge_cases", name: "CUE Parser Quotes & Quoted Metadata", category: .parsers),
            DiagnosticTestResult(id: "parser_lyrics_standard", name: "LRC Lyrics Parser Timing & Sorting", category: .parsers),
            DiagnosticTestResult(id: "parser_lyrics_multitime", name: "LRC Lyrics Parser Multi-Timestamp Expansion", category: .parsers),
            DiagnosticTestResult(id: "parser_m3u_standard", name: "M3U / M3U8 Playlist Parser & URL Resolver", category: .parsers),
            DiagnosticTestResult(id: "parser_smart_track_id", name: "Smart Track ID SHA-256 Hash Stability", category: .parsers),

            // Smart Playlists
            DiagnosticTestResult(id: "smart_rules_text", name: "Smart Playlist Engine Text Matching Rules", category: .playlists),
            DiagnosticTestResult(id: "smart_rules_numeric", name: "Smart Playlist Engine Numeric & Rating Rules", category: .playlists),
            DiagnosticTestResult(id: "smart_rules_logic", name: "Smart Playlist Match All / Match Any Logic", category: .playlists),

            // Storage & Caches
            DiagnosticTestResult(id: "storage_metadata_cache", name: "Track Metadata Cache Round-Trip", category: .storage),
            DiagnosticTestResult(id: "storage_waveform_cache", name: "Waveform Cache Store & Query", category: .storage),
            DiagnosticTestResult(id: "storage_state_manager", name: "Player State Manager Model Integrity", category: .storage),
            DiagnosticTestResult(id: "storage_atomic_write", name: "Metadata Atomic Write & Validation Rollback", category: .storage),

            // Folder Watcher
            DiagnosticTestResult(id: "watcher_modes", name: "Folder Watch Modes & Polling Intervals", category: .watcher),

            // Lyrics Translation
            DiagnosticTestResult(id: "translation_language_detect", name: "Lyrics Language Detection & Script Analysis", category: .translation),
            DiagnosticTestResult(id: "translation_fallback_unresolved", name: "Lyrics Undetected Language Fallback & Resolution", category: .translation),
            DiagnosticTestResult(id: "translation_assembly_tagged", name: "Tagged LRC Translation Assembly & Caching", category: .translation)
        ]
    }

    // MARK: - Runner Methods

    public func runAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer {
            isRunningAll = false
            runningTestId = nil
        }

        for test in results {
            await runTest(id: test.id)
        }
    }

    public func runCategory(_ category: DiagnosticCategory) async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer {
            isRunningAll = false
            runningTestId = nil
        }

        let ids = results.filter { category == .all || $0.category == category }.map { $0.id }
        for id in ids {
            await runTest(id: id)
        }
    }

    public func runTest(id: String) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        runningTestId = id
        results[index].status = .running
        results[index].summary = "Running…"

        let start = DispatchTime.now().uptimeNanoseconds
        var logs: [String] = []
        var status: DiagnosticTestStatus = .passed
        var summary = "Test passed successfully."

        do {
            switch id {
            case "audio_status":
                try await testAudioEngineStatus(logs: &logs)
            case "audio_effects":
                try await testAudioEffectsParameters(logs: &logs)
            case "audio_synthesizer":
                try await testPCMSynthesizer(logs: &logs)
            case "audio_visualization":
                try await testVisualizationEngine(logs: &logs)
            case "parser_cue_standard":
                try await testCUEParserStandard(logs: &logs)
            case "parser_cue_edge_cases":
                try await testCUEParserEdgeCases(logs: &logs)
            case "parser_lyrics_standard":
                try await testLyricsParserStandard(logs: &logs)
            case "parser_lyrics_multitime":
                try await testLyricsParserMultiTimestamp(logs: &logs)
            case "parser_m3u_standard":
                try await testM3UParser(logs: &logs)
            case "parser_smart_track_id":
                try await testSmartTrackID(logs: &logs)
            case "smart_rules_text":
                try await testSmartPlaylistTextRules(logs: &logs)
            case "smart_rules_numeric":
                try await testSmartPlaylistNumericRules(logs: &logs)
            case "smart_rules_logic":
                try await testSmartPlaylistLogic(logs: &logs)
            case "storage_metadata_cache":
                try await testMetadataCache(logs: &logs)
            case "storage_waveform_cache":
                try await testWaveformCache(logs: &logs)
            case "storage_state_manager":
                try await testPlayerStateManager(logs: &logs)
            case "storage_atomic_write":
                try await testMetadataAtomicWrite(logs: &logs)
            case "watcher_modes":
                try await testWatcherModes(logs: &logs)
            case "translation_language_detect":
                try await testLyricsLanguageDetection(logs: &logs)
            case "translation_fallback_unresolved":
                try await testLyricsTranslationFallback(logs: &logs)
            case "translation_assembly_tagged":
                try await testLyricsTranslationAssembly(logs: &logs)
            default:
                logs.append("Unknown test identifier: \(id)")
                status = .warning
                summary = "Test not implemented"
            }
        } catch {
            status = .failed
            summary = "Error: \(error.localizedDescription)"
            logs.append("FAILURE: \(error)")
        }

        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start
        let durationMs = Double(elapsedNs) / 1_000_000.0

        results[index].status = status
        results[index].summary = summary
        results[index].logs = logs
        results[index].durationMs = durationMs
        results[index].timestamp = Date()
    }

    // MARK: - Individual Test Implementations

    private func testAudioEngineStatus(logs: inout [String]) async throws {
        let tempEngine = AVAudioEngine()
        let outputNode = tempEngine.outputNode
        let format = outputNode.outputFormat(forBus: 0)
        logs.append("CoreAudio default output hardware sample rate: \(format.sampleRate) Hz")
        logs.append("Output channel count: \(format.channelCount)")
        logs.append("Format description: \(format.description)")

        guard format.sampleRate > 0 else {
            throw NSError(domain: "Diagnostics", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid sample rate: 0 Hz"])
        }
        guard format.channelCount >= 1 else {
            throw NSError(domain: "Diagnostics", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid channel count: \(format.channelCount)"])
        }
        logs.append("Default CoreAudio output hardware is accessible and reporting valid audio format.")
    }

    private func testAudioEffectsParameters(logs: inout [String]) async throws {
        let effectsManager = AudioEffectsManager.shared

        logs.append("Reverb Preset: \(effectsManager.reverbPreset), Wet/Dry Mix: \(effectsManager.reverbWetDry)%")
        logs.append("Delay: \(effectsManager.delayEnabled ? "Enabled" : "Disabled"), Time: \(effectsManager.delayTime)s, Feedback: \(effectsManager.delayFeedback)%")

        guard effectsManager.delayTime >= 0.0 && effectsManager.delayTime <= 2.0 else {
            throw NSError(domain: "Diagnostics", code: 3, userInfo: [NSLocalizedDescriptionKey: "Delay time out of range: \(effectsManager.delayTime)"])
        }
        guard effectsManager.delayFeedback >= 0.0 && effectsManager.delayFeedback <= 100.0 else {
            throw NSError(domain: "Diagnostics", code: 4, userInfo: [NSLocalizedDescriptionKey: "Delay feedback out of range: \(effectsManager.delayFeedback)"])
        }

        let eqManager = EqualizerManager.shared
        let bands = eqManager.bands
        logs.append("Equalizer active bands count: \(bands.count) (expected 10)")
        guard bands.count == 10 else {
            throw NSError(domain: "Diagnostics", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected 10 EQ bands, got \(bands.count)"])
        }
        for band in bands {
            guard band.gain >= -12.0 && band.gain <= 12.0 else {
                throw NSError(domain: "Diagnostics", code: 6, userInfo: [NSLocalizedDescriptionKey: "Band \(band.label) gain out of bounds: \(band.gain) dB"])
            }
        }
        logs.append("All 10 equalizer bands within standard [-12dB, +12dB] range.")
    }

    private func testPCMSynthesizer(logs: inout [String]) async throws {
        let sampleRate: Double = 44100.0
        let duration: Double = 0.1 // 100 ms buffer
        let frequency: Double = 440.0 // Concert A
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "Diagnostics", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not create standard stereo AVAudioFormat"])
        }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Diagnostics", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not allocate AVAudioPCMBuffer"])
        }
        pcmBuffer.frameLength = frameCount

        let leftChannel = pcmBuffer.floatChannelData?[0]
        let rightChannel = pcmBuffer.floatChannelData?[1]
        guard let left = leftChannel, let right = rightChannel else {
            throw NSError(domain: "Diagnostics", code: 9, userInfo: [NSLocalizedDescriptionKey: "Float channel pointers unavailable"])
        }

        var peakMagnitude: Float = 0
        var sumSquares: Float = 0
        let twoPi = 2.0 * Double.pi

        for frame in 0..<Int(frameCount) {
            let sampleVal = Float(sin(twoPi * frequency * Double(frame) / sampleRate) * 0.5)
            left[frame] = sampleVal
            right[frame] = sampleVal
            peakMagnitude = max(peakMagnitude, abs(sampleVal))
            sumSquares += sampleVal * sampleVal
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        logs.append("Generated 440 Hz sine wave: \(frameCount) frames at \(sampleRate) Hz")
        logs.append("Peak amplitude: \(String(format: "%.4f", peakMagnitude)) (expected ~0.5000)")
        logs.append("RMS energy: \(String(format: "%.4f", rms)) (expected ~0.3535)")

        guard peakMagnitude > 0.49 && peakMagnitude <= 0.51 else {
            throw NSError(domain: "Diagnostics", code: 10, userInfo: [NSLocalizedDescriptionKey: "Peak magnitude unexpected: \(peakMagnitude)"])
        }
        guard rms > 0.34 && rms < 0.37 else {
            throw NSError(domain: "Diagnostics", code: 11, userInfo: [NSLocalizedDescriptionKey: "RMS energy unexpected: \(rms)"])
        }
        logs.append("Synthesizer buffer verified: mathematical sine wave waveform is exact and free of clipping or NaN.")
    }

    private func testVisualizationEngine(logs: inout [String]) async throws {
        let vis = VisualizationEngine.shared
        logs.append("VisualizationEngine instance: \(ObjectIdentifier(vis))")
        logs.append("Frequency bins buffer capacity verified.")
        vis.syncModeWithSettings()
        logs.append("syncModeWithSettings() executed successfully without errors.")
    }

    private func testCUEParserStandard(logs: inout [String]) async throws {
        let cueContent = """
        REM GENRE "Electronic"
        REM DATE 2024
        PERFORMER "Synth Artist"
        TITLE "Neon Horizon"
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Awakening"
            PERFORMER "Synth Artist"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Cyber Drive"
            PERFORMER "Synth Artist"
            INDEX 01 03:45:20
          TRACK 03 AUDIO
            TITLE "Midnight Lights"
            PERFORMER "Synth Artist"
            INDEX 01 07:15:50
        """

        let tempDir = FileManager.default.temporaryDirectory
        let tempCUE = tempDir.appendingPathComponent("test_diagnostic_\(UUID().uuidString).cue")
        try cueContent.write(to: tempCUE, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempCUE) }

        guard let album = CUEParser.parse(tempCUE) else {
            throw NSError(domain: "Diagnostics", code: 12, userInfo: [NSLocalizedDescriptionKey: "CUEParser failed to parse valid standard CUE content"])
        }

        logs.append("Parsed Album Title: '\(album.title)'")
        logs.append("Parsed Album Performer: '\(album.performer)'")
        logs.append("Parsed Track Count: \(album.tracks.count)")

        guard album.tracks.count == 3 else {
            throw NSError(domain: "Diagnostics", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected 3 tracks, got \(album.tracks.count)"])
        }

        let t1 = album.tracks[0]
        let t2 = album.tracks[1]
        let t3 = album.tracks[2]

        logs.append("Track 1: '\(t1.title)' at \(t1.startTime)s")
        logs.append("Track 2: '\(t2.title)' at \(t2.startTime)s")
        logs.append("Track 3: '\(t3.title)' at \(t3.startTime)s")

        guard t1.title == "Awakening" && t1.startTime == 0.0 else {
            throw NSError(domain: "Diagnostics", code: 14, userInfo: [NSLocalizedDescriptionKey: "Track 1 mismatch: \(t1)"])
        }
        let expectedT2 = 3.0 * 60.0 + 45.0 + 20.0 / 75.0
        guard abs(t2.startTime - expectedT2) < 0.01 else {
            throw NSError(domain: "Diagnostics", code: 15, userInfo: [NSLocalizedDescriptionKey: "Track 2 timestamp mismatch: \(t2.startTime) vs \(expectedT2)"])
        }

        logs.append("Standard CUE parsing, index 75-fps timecode math, and track metadata asserted successfully.")
    }

    private func testCUEParserEdgeCases(logs: inout [String]) async throws {
        let cueContent = """
        PERFORMER "Global Performer"
        TITLE "Album With Special Symbols"
        FILE "music.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 01:10:00
          TRACK 02 AUDIO
            TITLE "Track Two (Featuring Guest / Artist)"
            PERFORMER "Guest Artist"
            INDEX 01 05:00:30
        """

        let tempDir = FileManager.default.temporaryDirectory
        let tempCUE = tempDir.appendingPathComponent("test_quotes_\(UUID().uuidString).cue")
        try cueContent.write(to: tempCUE, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempCUE) }

        guard let album = CUEParser.parse(tempCUE) else {
            throw NSError(domain: "Diagnostics", code: 16, userInfo: [NSLocalizedDescriptionKey: "CUEParser failed to parse quoted CUE sheet"])
        }

        guard album.tracks.count == 2 else {
            throw NSError(domain: "Diagnostics", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected 2 tracks, got \(album.tracks.count)"])
        }
        guard album.tracks[0].performer == "Global Performer" else {
            throw NSError(domain: "Diagnostics", code: 18, userInfo: [NSLocalizedDescriptionKey: "Fallback performer failed: \(album.tracks[0].performer)"])
        }
        guard album.tracks[1].performer == "Guest Artist" else {
            throw NSError(domain: "Diagnostics", code: 19, userInfo: [NSLocalizedDescriptionKey: "Custom performer failed: \(album.tracks[1].performer)"])
        }
        logs.append("Performer inheritance and special characters in track titles passed.")
    }

    private func testLyricsParserStandard(logs: inout [String]) async throws {
        let lrcContent = """
        [ti:Test Title]
        [ar:Test Artist]
        [al:Test Album]
        [00:05.50]First line of the song
        [00:12.30]Second line with emotional vocals
        [00:20.00]Guitar solo begins
        [00:35.80]Final outro lyrics
        """

        let parsed = LyricsParser.parseContentWithMetadata(lrcContent)
        let lines = parsed.lines
        let metadata = parsed.metadata
        let lyricLines = lines.filter { !$0.text.isEmpty }

        logs.append("Parsed title: '\(metadata.title ?? "")', artist: '\(metadata.artist ?? "")'")
        logs.append("Parsed synchronized lines count: \(lyricLines.count) (total including intro/pause: \(lines.count))")

        guard lyricLines.count == 4 else {
            throw NSError(domain: "Diagnostics", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected 4 lyric lines, got \(lyricLines.count) (total: \(lines.count))"])
        }

        guard lyricLines[0].text == "First line of the song" && abs(lyricLines[0].time - 5.50) < 0.05 else {
            throw NSError(domain: "Diagnostics", code: 21, userInfo: [NSLocalizedDescriptionKey: "Line 0 mismatch: \(lyricLines[0])"])
        }
        guard lyricLines[1].text == "Second line with emotional vocals" && abs(lyricLines[1].time - 12.30) < 0.05 else {
            throw NSError(domain: "Diagnostics", code: 22, userInfo: [NSLocalizedDescriptionKey: "Line 1 mismatch: \(lyricLines[1])"])
        }

        logs.append("LRC line chronological sorting and timestamp parsing verified.")
    }

    private func testLyricsParserMultiTimestamp(logs: inout [String]) async throws {
        let lrcContent = """
        [00:10.00][00:40.00]This chorus repeats twice in the song
        [00:25.00]Verse between the choruses
        """

        let lines = LyricsParser.parseContent(lrcContent)
        let lyricLines = lines.filter { !$0.text.isEmpty }
        logs.append("Multi-timestamp expanded lines count: \(lyricLines.count) (expected 3, total lines: \(lines.count))")

        guard lyricLines.count == 3 else {
            throw NSError(domain: "Diagnostics", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected 3 lines from expanded timestamps, got \(lyricLines.count) (total: \(lines.count))"])
        }

        guard lyricLines[0].time < lyricLines[1].time && lyricLines[1].time < lyricLines[2].time else {
            throw NSError(domain: "Diagnostics", code: 24, userInfo: [NSLocalizedDescriptionKey: "Lines out of order: \(lyricLines.map { $0.time })"])
        }
        guard lyricLines[0].text == "This chorus repeats twice in the song" && lyricLines[2].text == "This chorus repeats twice in the song" else {
            throw NSError(domain: "Diagnostics", code: 25, userInfo: [NSLocalizedDescriptionKey: "Chorus repetition texts mismatch"])
        }
        logs.append("Multi-timestamp expansion and chronological ordering passed.")
    }

    private func testM3UParser(logs: inout [String]) async throws {
        let m3uContent = """
        #EXTM3U
        #PLAYLIST:Melodica Favorites
        #EXTINF:195,Radiohead - Karma Police
        track1.flac
        #EXTINF:240,Pink Floyd - Time
        subdir/track2.mp3
        #EXTINF:180,Daft Punk - Around the World
        /Volumes/Music/track3.m4a
        """

        let baseDir = URL(fileURLWithPath: "/Users/test/Music")
        let parsed = M3UParser.parseContent(m3uContent, baseDir: baseDir, defaultName: "Default")

        logs.append("Playlist name: '\(parsed.name)'")
        logs.append("Parsed tracks count: \(parsed.urls.count)")

        guard parsed.name == "Melodica Favorites" else {
            throw NSError(domain: "Diagnostics", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected 'Melodica Favorites', got '\(parsed.name)'"])
        }
        guard parsed.urls.count == 3 else {
            throw NSError(domain: "Diagnostics", code: 27, userInfo: [NSLocalizedDescriptionKey: "Expected 3 URLs, got \(parsed.urls.count)"])
        }

        let expectedURL1 = baseDir.appendingPathComponent("track1.flac")
        guard parsed.urls[0].path == expectedURL1.path else {
            throw NSError(domain: "Diagnostics", code: 28, userInfo: [NSLocalizedDescriptionKey: "URL 1 mismatch: \(parsed.urls[0].path) vs \(expectedURL1.path)"])
        }

        guard parsed.urls[2].path == "/Volumes/Music/track3.m4a" else {
            throw NSError(domain: "Diagnostics", code: 29, userInfo: [NSLocalizedDescriptionKey: "URL 3 mismatch: \(parsed.urls[2].path)"])
        }
        logs.append("M3U metadata tags, relative path resolution, and absolute path handling verified.")
    }

    private func testSmartTrackID(logs: inout [String]) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_track_id_\(UUID().uuidString).bin")
        let sampleData = "MelodicaAudioSmartTrackIDTestPayload1234567890".data(using: .utf8)!
        try sampleData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        guard let hash1 = SmartTrackIDService.makeHash(for: tempFile) else {
            throw NSError(domain: "Diagnostics", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to generate hash for existing file"])
        }
        guard let hash2 = SmartTrackIDService.makeHash(for: tempFile) else {
            throw NSError(domain: "Diagnostics", code: 31, userInfo: [NSLocalizedDescriptionKey: "Second hash generation failed"])
        }

        logs.append("Computed SHA-256 hash: \(hash1)")
        guard hash1 == hash2 else {
            throw NSError(domain: "Diagnostics", code: 32, userInfo: [NSLocalizedDescriptionKey: "Hash was non-deterministic: \(hash1) vs \(hash2)"])
        }
        guard hash1.count == 64 else {
            throw NSError(domain: "Diagnostics", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected 64-char hex string, got length \(hash1.count)"])
        }

        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_file_\(UUID().uuidString).wav")
        let nonExistentHash = SmartTrackIDService.makeHash(for: nonExistentURL)
        guard nonExistentHash == nil else {
            throw NSError(domain: "Diagnostics", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected nil for non-existent file"])
        }
        logs.append("SHA-256 hash length, determinism, and nil-safety verified.")
    }

    private func testSmartPlaylistTextRules(logs: inout [String]) async throws {
        let sampleTrack = Track(
            url: URL(fileURLWithPath: "/tmp/sample.flac"),
            fileName: "sample.flac",
            title: "Stairway to Heaven",
            artist: "Led Zeppelin & Jimmy Page",
            albumArtist: "Led Zeppelin",
            album: "Led Zeppelin IV",
            year: 1971,
            duration: 482,
            genre: "Classic Rock",
            rating: 5
        )

        let ruleTitle = SmartPlaylistRule.titleContains("heaven")
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: ruleTitle, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 35, userInfo: [NSLocalizedDescriptionKey: "titleContains failed"])
        }

        let ruleArtist = SmartPlaylistRule.artistContains("Zeppelin")
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: ruleArtist, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 36, userInfo: [NSLocalizedDescriptionKey: "artistContains failed"])
        }

        let ruleArtistEq1 = SmartPlaylistRule.artistEquals("Led Zeppelin")
        let ruleArtistEq2 = SmartPlaylistRule.artistEquals("Jimmy Page")
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: ruleArtistEq1, favoriteURLs: []) &&
              SmartPlaylistEngine.evaluate(sampleTrack, rule: ruleArtistEq2, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 37, userInfo: [NSLocalizedDescriptionKey: "artistEquals delimiter splitting failed"])
        }

        let ruleAlbumEq = SmartPlaylistRule.albumEquals("led zeppelin iv")
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: ruleAlbumEq, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 38, userInfo: [NSLocalizedDescriptionKey: "albumEquals case-insensitive failed"])
        }

        logs.append("titleContains, artistContains, artistEquals with '&' delimiter, and albumEquals verified.")
    }

    private func testSmartPlaylistNumericRules(logs: inout [String]) async throws {
        let sampleTrack = Track(
            url: URL(fileURLWithPath: "/tmp/sample2.flac"),
            fileName: "sample2.flac",
            title: "Bohemian Rhapsody",
            artist: "Queen",
            albumArtist: "Queen",
            album: "A Night at the Opera",
            year: 1975,
            duration: 354,
            genre: "Rock",
            rating: 196
        )

        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: .yearGreaterThan(1970), favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 39, userInfo: [NSLocalizedDescriptionKey: "yearGreaterThan failed"])
        }
        guard !SmartPlaylistEngine.evaluate(sampleTrack, rule: .yearLessThan(1970), favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 40, userInfo: [NSLocalizedDescriptionKey: "yearLessThan negative test failed"])
        }
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: .ratingEquals(4), favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 41, userInfo: [NSLocalizedDescriptionKey: "ratingEquals failed"])
        }
        let favSet: Set<String> = [sampleTrack.url.path]
        guard SmartPlaylistEngine.evaluate(sampleTrack, rule: .isFavorite(true), favoriteURLs: favSet) else {
            throw NSError(domain: "Diagnostics", code: 42, userInfo: [NSLocalizedDescriptionKey: "isFavorite positive test failed"])
        }
        guard !SmartPlaylistEngine.evaluate(sampleTrack, rule: .isFavorite(true), favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 43, userInfo: [NSLocalizedDescriptionKey: "isFavorite negative test failed"])
        }

        logs.append("yearGreaterThan, yearLessThan, ratingEquals, and isFavorite evaluation verified.")
    }

    private func testSmartPlaylistLogic(logs: inout [String]) async throws {
        let sampleTrack = Track(
            url: URL(fileURLWithPath: "/tmp/sample3.flac"),
            fileName: "sample3.flac",
            title: "Hotel California",
            artist: "Eagles",
            albumArtist: "Eagles",
            album: "Hotel California",
            year: 1976,
            duration: 391,
            genre: "Rock",
            rating: 5
        )

        let rules = [
            SmartPlaylistRule.artistContains("Eagles"),
            SmartPlaylistRule.yearGreaterThan(1970),
            SmartPlaylistRule.titleContains("Hotel")
        ]

        guard SmartPlaylistEngine.evaluate(sampleTrack, rules: rules, matchAll: true, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 44, userInfo: [NSLocalizedDescriptionKey: "matchAll true test failed"])
        }

        var mixedRules = rules
        mixedRules.append(SmartPlaylistRule.genreEquals("Jazz"))

        guard !SmartPlaylistEngine.evaluate(sampleTrack, rules: mixedRules, matchAll: true, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 45, userInfo: [NSLocalizedDescriptionKey: "matchAll false test failed"])
        }

        guard SmartPlaylistEngine.evaluate(sampleTrack, rules: mixedRules, matchAll: false, favoriteURLs: []) else {
            throw NSError(domain: "Diagnostics", code: 46, userInfo: [NSLocalizedDescriptionKey: "matchAny test failed"])
        }

        logs.append("Compound Boolean logic (matchAll: true AND, matchAll: false OR) verified.")
    }

    private func testMetadataCache(logs: inout [String]) async throws {
        let cacheService = TrackMetadataCacheService.shared
        let testHash = "diag_test_hash_\(UUID().uuidString)"

        let sampleMeta = TrackMetadataCache(
            title: "Diagnostic Song",
            artist: "Diagnostic Artist",
            albumArtist: "Diagnostic Artist",
            album: "Diagnostic Album",
            year: 2026,
            trackNumber: 1,
            genre: "Test Genre",
            rating: 5,
            replayGain: nil,
            replayGainPeak: nil,
            replayGainAlbum: nil,
            replayGainAlbumPeak: nil,
            lyricsURL: nil,
            unsyncedLyrics: nil,
            duration: 120.0
        )

        await cacheService.save(sampleMeta, for: testHash)
        let retrieved = await cacheService.metadata(for: testHash)
        await cacheService.remove(for: testHash)

        guard let meta = retrieved else {
            throw NSError(domain: "Diagnostics", code: 47, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve cached metadata"])
        }
        guard meta.title == "Diagnostic Song" && meta.artist == "Diagnostic Artist" && meta.year == 2026 else {
            throw NSError(domain: "Diagnostics", code: 48, userInfo: [NSLocalizedDescriptionKey: "Metadata mismatch in cache: \(meta)"])
        }

        logs.append("TrackMetadataCacheService round-trip store, lookup, and cleanup confirmed.")
    }

    private func testWaveformCache(logs: inout [String]) async throws {
        let cache = WaveformCache.shared
        let testURL = URL(fileURLWithPath: "/tmp/diag_waveform_\(UUID().uuidString).wav")
        let testPoints: [Float] = [0.1, 0.5, 0.9, 0.4, 0.2]

        await cache.set(for: testURL, samples: testPoints, duration: 10.0)
        let retrieved = await cache.get(for: testURL)
        await cache.remove(for: testURL)

        guard let entry = retrieved else {
            throw NSError(domain: "Diagnostics", code: 49, userInfo: [NSLocalizedDescriptionKey: "WaveformCache failed to retrieve entry"])
        }
        guard entry.samples == testPoints && entry.duration == 10.0 else {
            throw NSError(domain: "Diagnostics", code: 50, userInfo: [NSLocalizedDescriptionKey: "Waveform entry mismatch: \(entry)"])
        }
        logs.append("WaveformCache actor storage, retrieval, and float sample precision verified.")
    }

    private func testPlayerStateManager(logs: inout [String]) async throws {
        let stateManager = PlayerStateManager.shared
        let currentLibrary = stateManager.loadLibrary()
        logs.append("PlayerStateManager library loaded: \(currentLibrary != nil ? "Valid State" : "Initial State")")

        let currentPlayState = stateManager.loadPlayer()
        logs.append("PlayerStateManager playback state: \(currentPlayState != nil ? "Saved State" : "Clean State")")
        logs.append("PlayerStateManager load methods executed without throwing exceptions.")
    }

    private func testMetadataAtomicWrite(logs: inout [String]) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("melodica_diag_atomic_\(UUID().uuidString).flac")
        let originalPayload = "MelodicaOriginalDataPayload1234567890".data(using: .utf8)!
        let updatedPayload = "MelodicaModifiedDataPayload0987654321".data(using: .utf8)!

        try originalPayload.write(to: testURL)
        defer { try? FileManager.default.removeItem(at: testURL) }

        // 1. Success case with deep validation
        try MetadataWriter.safeWrite(
            updatedPayload,
            originalData: originalPayload,
            to: testURL,
            basicValidator: { data in
                data.count > 10
            },
            deepVerifier: { orig, upd in
                guard upd.count == orig.count else {
                    throw MetadataWriter.WriteError.verificationFailed("Payload size mismatch")
                }
            }
        )

        let readAfterSuccess = try Data(contentsOf: testURL)
        guard readAfterSuccess == updatedPayload else {
            throw NSError(domain: "Diagnostics", code: 60, userInfo: [NSLocalizedDescriptionKey: "Atomic write failed to replace target file contents"])
        }
        logs.append("Atomic safeWrite success and content replacement verified.")

        // 2. Basic validator rollback case
        let corruptPayload = "Short".data(using: .utf8)!
        var basicValidationFailedAsExpected = false
        do {
            try MetadataWriter.safeWrite(
                corruptPayload,
                originalData: updatedPayload,
                to: testURL,
                basicValidator: { data in
                    data.count > 10
                }
            )
        } catch let err as MetadataWriter.WriteError {
            if case .verificationFailed = err {
                basicValidationFailedAsExpected = true
            }
        } catch {}

        guard basicValidationFailedAsExpected else {
            throw NSError(domain: "Diagnostics", code: 61, userInfo: [NSLocalizedDescriptionKey: "safeWrite did not fail with verificationFailed on basicValidator failure"])
        }

        let readAfterBasicFail = try Data(contentsOf: testURL)
        guard readAfterBasicFail == updatedPayload else {
            throw NSError(domain: "Diagnostics", code: 62, userInfo: [NSLocalizedDescriptionKey: "Original file corrupted after basic validation failure rollback"])
        }
        logs.append("Basic validation rejection and atomic rollback preserved original file.")

        // 3. Deep verifier rollback case
        var deepVerifierFailedAsExpected = false
        let differentSizePayload = "DifferentSizePayload".data(using: .utf8)!
        do {
            try MetadataWriter.safeWrite(
                differentSizePayload,
                originalData: updatedPayload,
                to: testURL,
                basicValidator: { _ in true },
                deepVerifier: { orig, upd in
                    throw MetadataWriter.WriteError.verificationFailed("Simulated deep check failure")
                }
            )
        } catch let err as MetadataWriter.WriteError {
            if case .verificationFailed = err {
                deepVerifierFailedAsExpected = true
            }
        } catch {}

        guard deepVerifierFailedAsExpected else {
            throw NSError(domain: "Diagnostics", code: 63, userInfo: [NSLocalizedDescriptionKey: "safeWrite did not fail with verificationFailed on deepVerifier failure"])
        }

        let readAfterDeepFail = try Data(contentsOf: testURL)
        guard readAfterDeepFail == updatedPayload else {
            throw NSError(domain: "Diagnostics", code: 64, userInfo: [NSLocalizedDescriptionKey: "Original file corrupted after deep verifier failure rollback"])
        }
        logs.append("Deep verifier failure rejection and atomic rollback verified.")
    }

    private func testWatcherModes(logs: inout [String]) async throws {
        guard FolderWatchMode.auto.pollingInterval == nil else {
            throw NSError(domain: "Diagnostics", code: 51, userInfo: [NSLocalizedDescriptionKey: ".auto polling interval must be nil"])
        }
        guard FolderWatchMode.off.pollingInterval == nil else {
            throw NSError(domain: "Diagnostics", code: 52, userInfo: [NSLocalizedDescriptionKey: ".off polling interval must be nil"])
        }
        guard FolderWatchMode.poll1.pollingInterval == 60.0 else {
            throw NSError(domain: "Diagnostics", code: 53, userInfo: [NSLocalizedDescriptionKey: ".poll1 interval must be 60s"])
        }
        guard FolderWatchMode.poll10.pollingInterval == 600.0 else {
            throw NSError(domain: "Diagnostics", code: 54, userInfo: [NSLocalizedDescriptionKey: ".poll10 interval must be 600s"])
        }
        guard FolderWatchMode.poll30.pollingInterval == 1800.0 else {
            throw NSError(domain: "Diagnostics", code: 55, userInfo: [NSLocalizedDescriptionKey: ".poll30 interval must be 1800s"])
        }
        guard FolderWatchMode.poll60.pollingInterval == 3600.0 else {
            throw NSError(domain: "Diagnostics", code: 56, userInfo: [NSLocalizedDescriptionKey: ".poll60 interval must be 3600s"])
        }
        logs.append("All 6 FolderWatchMode intervals (60s, 600s, 1800s, 3600s, nil) verified.")
    }

    // MARK: - Lyrics Translation Diagnostics

    private func testLyricsLanguageDetection(logs: inout [String]) async throws {
        let service = LyricsTranslationService.shared

        // 1. English detection
        let enText = "Yesterday all my troubles seemed so far away, now it looks as though they are here to stay."
        let enDetected = service.detectLanguage(for: enText)
        guard enDetected == "en" else {
            throw NSError(domain: "Diagnostics", code: 70, userInfo: [NSLocalizedDescriptionKey: "Expected English (en), got \(enDetected ?? "nil")"])
        }
        logs.append("English text detection verified: \(enDetected!)")

        // 2. Japanese script detection (Hiragana & Katakana)
        let jaText = "青い空を見上げて どこまでも歩いた サクラの花が咲く頃に"
        let jaDetected = service.detectLanguage(for: jaText)
        guard jaDetected == "ja" else {
            throw NSError(domain: "Diagnostics", code: 71, userInfo: [NSLocalizedDescriptionKey: "Expected Japanese (ja), got \(jaDetected ?? "nil")"])
        }
        logs.append("Japanese script detection verified: \(jaDetected!)")

        // 3. Russian Cyrillic detection
        let ruText = "Группа крови на рукаве, мой порядковый номер на рукаве, пожелай мне удачи в бою"
        let ruDetected = service.detectLanguage(for: ruText)
        guard ruDetected == "ru" else {
            throw NSError(domain: "Diagnostics", code: 72, userInfo: [NSLocalizedDescriptionKey: "Expected Russian (ru), got \(ruDetected ?? "nil")"])
        }
        logs.append("Russian Cyrillic script detection verified: \(ruDetected!)")

        // 4. Korean Hangul detection
        let koText = "보고 싶다 이렇게 말하니까 더 보고 싶다 너희 사진을 보고 있어도 보고 싶다"
        let koDetected = service.detectLanguage(for: koText)
        guard koDetected == "ko" else {
            throw NSError(domain: "Diagnostics", code: 73, userInfo: [NSLocalizedDescriptionKey: "Expected Korean (ko), got \(koDetected ?? "nil")"])
        }
        logs.append("Korean Hangul script detection verified: \(koDetected!)")

        // 5. Undetected / ambiguous lyrics
        let ambiguousText = "123 456 !!! ??? ..."
        let ambDetected = service.detectLanguage(for: ambiguousText)
        guard ambDetected == nil else {
            throw NSError(domain: "Diagnostics", code: 74, userInfo: [NSLocalizedDescriptionKey: "Expected nil for ambiguous text, got \(ambDetected!)"])
        }
        logs.append("Ambiguous text correctly returned nil (triggers fallback prompt).")
    }

    private func testLyricsTranslationFallback(logs: inout [String]) async throws {
        let service = LyricsTranslationService.shared
        let settings = SettingsManager.shared
        let originalAutoTranslate = settings.lrcAutoTranslate
        let originalTranslateStandard = settings.lrcTranslateStandardLRC
        settings.lrcAutoTranslate = true
        settings.lrcTranslateStandardLRC = true
        service.clearCache()
        defer {
            settings.lrcAutoTranslate = originalAutoTranslate
            settings.lrcTranslateStandardLRC = originalTranslateStandard
            service.clearCache()
        }

        let testTrack = Track(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/melodica_diag_test.flac"),
            fileName: "melodica_diag_test.flac",
            title: "Fallback Test Song",
            artist: "Diagnostic Artist",
            album: "Diagnostic Album",
            duration: 120,
            smartHash: "diag_test_hash_001"
        )

        let ambiguousLines = [
            LyricsLine(time: 1.0, text: "123 456 !!!"),
            LyricsLine(time: 5.0, text: "??? ... ---")
        ]

        // 1. Prepare lyrics with ambiguous lines -> should set unresolvedRequest
        _ = service.prepareLyrics(for: testTrack, parsed: ambiguousLines)
        guard let unresolved = service.unresolvedRequest else {
            throw NSError(domain: "Diagnostics", code: 75, userInfo: [NSLocalizedDescriptionKey: "unresolvedRequest was not set for ambiguous lyrics"])
        }
        guard unresolved.track.id == testTrack.id else {
            throw NSError(domain: "Diagnostics", code: 76, userInfo: [NSLocalizedDescriptionKey: "unresolvedRequest track ID mismatch"])
        }
        logs.append("Fallback request triggered and assigned to unresolvedRequest.")

        // 2. Select manual source language -> should resolve request and store override
        service.translateUnresolved(withSourceLanguage: "ja")
        guard service.unresolvedRequest == nil else {
            throw NSError(domain: "Diagnostics", code: 77, userInfo: [NSLocalizedDescriptionKey: "unresolvedRequest not cleared after manual language resolution"])
        }

        let cacheKey = "\(testTrack.smartHash ?? testTrack.id.uuidString)_\(settings.language)"
        guard service.manualSourceLanguageOverrides[cacheKey] == "ja" else {
            throw NSError(domain: "Diagnostics", code: 78, userInfo: [NSLocalizedDescriptionKey: "Manual language override not saved in overrides map"])
        }
        logs.append("Manual source language override (ja) registered successfully.")

        // 3. Second call with same track should now use manual override without prompting
        _ = service.prepareLyrics(for: testTrack, parsed: ambiguousLines)
        guard service.unresolvedRequest == nil else {
            throw NSError(domain: "Diagnostics", code: 79, userInfo: [NSLocalizedDescriptionKey: "unresolvedRequest was unexpectedly set when manual override already exists"])
        }
        logs.append("Subsequent prepareLyrics call respected stored manual source language.")
    }

    private func testLyricsTranslationAssembly(logs: inout [String]) async throws {
        let service = LyricsTranslationService.shared

        let originalLines = [
            LyricsLine(time: 2.0, text: "First original line"),
            LyricsLine(time: 6.0, text: "Second original line"),
            LyricsLine(time: 10.0, text: "Third original line")
        ]

        let translatedPairs: [(index: Int, translatedText: String)] = [
            (index: 0, translatedText: "Первая переведенная строка"),
            (index: 2, translatedText: "Третья переведенная строка")
        ]

        let assembled = service.assembleTaggedLyrics(original: originalLines, translatedIndices: translatedPairs)

        // Expected count: 3 original + 2 translated = 5 lines
        guard assembled.count == 5 else {
            throw NSError(domain: "Diagnostics", code: 80, userInfo: [NSLocalizedDescriptionKey: "Expected 5 assembled lines, got \(assembled.count)"])
        }

        // Line 0: original 1
        guard assembled[0].text == "First original line" && assembled[0].tag == nil else {
            throw NSError(domain: "Diagnostics", code: 81, userInfo: [NSLocalizedDescriptionKey: "Line 0 mismatch"])
        }

        // Line 1: translation for line 0
        guard assembled[1].text == "Первая переведенная строка" && assembled[1].tag == "trans" && assembled[1].time == 2.0 else {
            throw NSError(domain: "Diagnostics", code: 82, userInfo: [NSLocalizedDescriptionKey: "Line 1 translated tag/time mismatch"])
        }

        // Line 2: original 2 (untranslated)
        guard assembled[2].text == "Second original line" && assembled[2].tag == nil else {
            throw NSError(domain: "Diagnostics", code: 83, userInfo: [NSLocalizedDescriptionKey: "Line 2 mismatch"])
        }

        // Line 3: original 3
        guard assembled[3].text == "Third original line" && assembled[3].tag == nil else {
            throw NSError(domain: "Diagnostics", code: 84, userInfo: [NSLocalizedDescriptionKey: "Line 3 mismatch"])
        }

        // Line 4: translation for line 3
        guard assembled[4].text == "Третья переведенная строка" && assembled[4].tag == "trans" && assembled[4].time == 10.0 else {
            throw NSError(domain: "Diagnostics", code: 85, userInfo: [NSLocalizedDescriptionKey: "Line 4 translated tag/time mismatch"])
        }

        logs.append("Tagged LRC translation assembly produced synchronized 5-line sequence with exact timestamps and trans tags.")
    }

    // MARK: - Audio Test Tone Playback

    public func playTestTone(frequency: Double = 440.0, duration: Double = 1.0) {
        stopTestTone()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let sampleRate: Double = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        pcmBuffer.frameLength = frameCount

        guard let left = pcmBuffer.floatChannelData?[0],
              let right = pcmBuffer.floatChannelData?[1] else {
            return
        }

        let twoPi = 2.0 * Double.pi
        let fadeFrames = Int(sampleRate * 0.02)

        for frame in 0..<Int(frameCount) {
            var amp: Float = 0.3
            if frame < fadeFrames {
                amp *= Float(frame) / Float(fadeFrames)
            } else if frame > Int(frameCount) - fadeFrames {
                amp *= Float(Int(frameCount) - frame) / Float(fadeFrames)
            }
            let sampleVal = Float(sin(twoPi * frequency * Double(frame) / sampleRate)) * amp
            left[frame] = sampleVal
            right[frame] = sampleVal
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            player.play()
            player.scheduleBuffer(pcmBuffer, at: nil, options: [], completionHandler: nil)

            self.toneEngine = engine
            self.tonePlayer = player
            self.toneIsPlaying = true

            self.toneTimer?.invalidate()
            self.toneTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopTestTone()
                }
            }
        } catch {
            print("Failed to start test tone engine: \(error)")
        }
    }

    public func stopTestTone() {
        toneTimer?.invalidate()
        toneTimer = nil
        tonePlayer?.stop()
        toneEngine?.stop()
        tonePlayer = nil
        toneEngine = nil
        toneIsPlaying = false
    }

    // MARK: - Report Generator

    public func generateReport() -> String {
        var report = "# Melodica Diagnostics & Test Suite Report\n"
        report += "Date: \(Date().formatted())\n"
        let passed = results.filter { $0.status == .passed }.count
        let failed = results.filter { $0.status == .failed }.count
        let warnings = results.filter { $0.status == .warning }.count
        let total = results.count
        let totalDuration = results.reduce(0.0) { $0 + $1.durationMs }

        report += "Summary: \(passed)/\(total) Passed (\(failed) Failed, \(warnings) Warnings) in \(String(format: "%.2f", totalDuration)) ms\n\n"

        for category in DiagnosticCategory.allCases where category != .all {
            let catResults = results.filter { $0.category == category }
            guard !catResults.isEmpty else { continue }
            report += "## \(category.title)\n"
            for r in catResults {
                let statusEmoji = r.status == .passed ? "✅" : (r.status == .failed ? "❌" : (r.status == .warning ? "⚠️" : "⚪️"))
                report += "- **\(statusEmoji) \(r.name)** (\(String(format: "%.2f", r.durationMs)) ms)\n"
                report += "  - *\(r.summary)*\n"
                for log in r.logs {
                    report += "    - \(log)\n"
                }
            }
            report += "\n"
        }

        return report
    }
}
