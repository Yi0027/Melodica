// Services/AudioPlayerService.swift
import AVFoundation
import Combine
import AppKit
import CoreAudio

extension Notification.Name {
    static let eqDidChange = Notification.Name("eqDidChange")
    static let progressIntervalChanged = Notification.Name("progressIntervalChanged")
    static let trackChanged = Notification.Name("trackChanged")
    static let prepareNextTrack = Notification.Name("prepareNextTrack")
    static let crossfadeStarted = Notification.Name("crossfadeStarted")
}

final class AudioPlayerService: NSObject, ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false

    private var engine: AVAudioEngine?
    private var displayLink: DispatchSourceTimer?
    private var completionHandler: (() -> Void)?
    private var currentUserVolume: Float = 0.5
    private var isSeeking = false
    private var isFinishingNormally = false
    private var crossfadeStarted = false
    private var crossfadeTimer: Timer?
    private var crossfadeTimeoutWorkItem: DispatchWorkItem?
    private var crossfadeStartTime: Date?
    private var savedCrossfadeRemaining: TimeInterval = 0

    private var preloadRequested = false

    private var slots: [PlayerSlot] = []
    private var activeSlot: Int = 0
    private var preloadedSlot: Int? = nil
    private var nextCompletion: (() -> Void)?
    private var silenceDetected = false
    private var silenceStartTime: Date?
    private let silenceMinDuration: TimeInterval = 0.5
    private var switchingTrack = false
    private let eqManager = EqualizerManager.shared
    private let settings = SettingsManager.shared

    private let maxAllowedGain: Float = 4.0
    private let rgReferenceGain: Float = 1.0

    private var seekGeneration = 0
    private var playGeneration = 0
    private var preloadGeneration = 0
    private var lastSeekTime: Date = .distantPast
    private var lastPreloadTrackId: UUID?
    private var lastPreloadTime: Date = .distantPast
    private var isSleeping = false
    private var intendedPlaying: Bool = false
    private var recreateWorkItem: DispatchWorkItem?
    private var recreateGeneration = 0
    private var isRecreating = false
    private var suppressRecreateUntil: Date = .distantPast

    private struct PlayerSlot {
        let playerNode: AVAudioPlayerNode
        let eqNode: AVAudioUnitEQ
        let mixerNode: AVAudioMixerNode     // [PATCH] per-slot mixer для плавных фейдов
        var track: Track?
        var file: AVAudioFile?
        var fileLength: AVAudioFramePosition = 0
        var sampleRate: Double = 44100
        var rgLinearGain: Float = 1.0
        var isPreloaded = false
        var format: AVAudioFormat?
        var cueSeekTime: TimeInterval?
        var seekOffset: TimeInterval = 0
    }

    override init() {
        super.init()
        setupEngine()
        setupNotifications()
    }

    // [PATCH] Маршрут: player → eq → slotMixer → mainMixer
    private func setupEngine() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }
        for _ in 0..<2 {
            let playerNode = AVAudioPlayerNode()
            let eqNode = AVAudioUnitEQ(numberOfBands: 10)
            let mixerNode = AVAudioMixerNode()
            engine.attach(playerNode)
            engine.attach(eqNode)
            engine.attach(mixerNode)
            engine.connect(playerNode, to: eqNode, format: nil)
            engine.connect(eqNode, to: mixerNode, format: nil)
            engine.connect(mixerNode, to: engine.mainMixerNode, format: nil)
            let slot = PlayerSlot(playerNode: playerNode, eqNode: eqNode, mixerNode: mixerNode)
            slots.append(slot)
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .eqDidChange, object: nil, queue: .main) { [weak self] _ in self?.updateAllEQs() }
        NotificationCenter.default.addObserver(forName: .progressIntervalChanged, object: nil, queue: .main) { [weak self] _ in self?.restartDisplayLink() }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("gaplessOrCrossfadeDisabled"), object: nil, queue: .main) { [weak self] _ in
            self?.clearPreload()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("crossfadeDisabled"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.crossfadeStarted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    NotificationCenter.default.post(name: NSNotification.Name("crossfadeDisabled"), object: nil)
                }
            } else {
                self.settings.crossfadeEnabled = false
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("rgModeChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.applyCurrentRG()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scheduleRecreateEngine(reason: "configChange")
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("visualizationModeChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.updateMainMixerTap()
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("silenceSkipChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.updateMainMixerTap()
        }

        // MARK: - Sleep / Wake

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isSleeping = true
            for slot in self.slots { slot.playerNode.pause() }
            self.stopDisplayLink()
        }

        workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isSleeping = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, !self.isSleeping else { return }
                self.scheduleRecreateEngine(reason: "wake")
            }
        }
    }

    // MARK: - RG Helper

    private func computeRGGain(for track: Track) -> Float {
        guard settings.rgMode != "off" else { return 1.0 }
        let rgValue: Float?
        let peak: Float?
        switch settings.rgMode {
        case "track":
            rgValue = track.replayGain ?? track.replayGainAlbum
            peak = track.replayGainPeak ?? track.replayGainAlbumPeak
        case "album":
            rgValue = track.replayGainAlbum ?? track.replayGain
            peak = track.replayGainAlbumPeak ?? track.replayGainPeak
        default:
            return 1.0
        }
        let rgGain = rgValue.map { pow(10, $0 / 20.0) } ?? 1.0
        let safeGain = peak.map { min(rgGain, 1.0 / $0) } ?? rgGain
        return min(safeGain, maxAllowedGain) * rgReferenceGain
    }

    // MARK: - Device readiness

    private func isDefaultOutputDeviceReady() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return false }

        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        let streamStatus = AudioObjectGetPropertyDataSize(
            deviceID, &streamAddress, 0, nil, &streamSize
        )
        return streamStatus == noErr && streamSize > 0
    }

    // MARK: - Recreate Engine

    private func scheduleRecreateEngine(reason: String) {
        // [PATCH] Не рвём звук во время перехода.
        if crossfadeStarted || isRecreating {
            return
        }
        let now = Date()
        if now < suppressRecreateUntil {
            return
        }
        recreateWorkItem?.cancel()
        recreateGeneration += 1
        let myGen = recreateGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isSleeping, self.recreateGeneration == myGen else { return }
            self.recreateEngine(gen: myGen, reason: reason)
        }
        recreateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func recreateEngine(gen: Int, reason: String) {
        guard !isSleeping, !isRecreating, recreateGeneration == gen else {
            return
        }
        guard !slots.isEmpty,
              activeSlot >= 0, activeSlot < slots.count,
              let restoreTrack = slots[activeSlot].track else {
            return
        }

        isRecreating = true
        suppressRecreateUntil = Date().addingTimeInterval(4.0)

        let restoreTime = currentTime
        let restorePlaying = intendedPlaying
        let restoreVolume = currentUserVolume > 0 ? currentUserVolume : 0.5

        engine?.mainMixerNode.outputVolume = 0

        stopCrossfade()
        stopDisplayLink()
        for slot in slots {
            slot.playerNode.stop()
            slot.playerNode.reset()
        }
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        slots.removeAll()
        activeSlot = 0
        preloadedSlot = nil
        nextCompletion = nil
        preloadRequested = false

        isPlaying = false
        silenceDetected = false
        silenceStartTime = nil
        isFinishingNormally = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.attemptRestore(gen: gen,
                                 track: restoreTrack,
                                 time: restoreTime,
                                 playing: restorePlaying,
                                 volume: restoreVolume,
                                 attempt: 0)
        }
    }

    private func attemptRestore(gen: Int,
                                track: Track,
                                time: TimeInterval,
                                playing: Bool,
                                volume: Float,
                                attempt: Int) {
        guard recreateGeneration == gen, !isSleeping else {
            isRecreating = false
            return
        }

        guard isDefaultOutputDeviceReady() else {
            if attempt < 10 {
                let delay = 0.5 + 0.2 * Double(attempt)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.attemptRestore(gen: gen, track: track, time: time,
                                         playing: playing, volume: volume,
                                         attempt: attempt + 1)
                }
            } else {
                self.currentUserVolume = volume
                isRecreating = false
            }
            return
        }

        currentUserVolume = 0
        play(track, volume: 0, autoplay: false) { }

        guard let engine = self.engine, engine.isRunning else {
            if attempt < 10 {
                let delay = 0.5 + 0.2 * Double(attempt)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.attemptRestore(gen: gen, track: track, time: time,
                                         playing: playing, volume: volume,
                                         attempt: attempt + 1)
                }
            } else {
                self.currentUserVolume = volume
                isRecreating = false
            }
            return
        }

        engine.mainMixerNode.outputVolume = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.recreateGeneration == gen, !self.isSleeping else { return }
            guard !self.slots.isEmpty,
                  self.activeSlot >= 0, self.activeSlot < self.slots.count else {
                self.isRecreating = false
                return
            }

            if time > 0 { self.seek(to: time) }
            self.currentUserVolume = volume

            if playing {
                self.slots[self.activeSlot].playerNode.play()
                self.isPlaying = true
                self.intendedPlaying = true
                self.startDisplayLink()
            } else {
                self.slots[self.activeSlot].playerNode.pause()
                self.isPlaying = false
                self.intendedPlaying = false
                self.stopDisplayLink()
            }
            self.applyVolume()
            self.engine?.mainMixerNode.outputVolume = 1

            self.isRecreating = false

            if playing {
                let checkGen = gen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self, self.recreateGeneration == checkGen, !self.isSleeping else { return }
                    let engineOK = self.engine?.isRunning == true
                    let playingOK = self.slots.first?.playerNode.isPlaying ?? false
                    if !engineOK || !playingOK {
                        self.scheduleRecreateEngine(reason: "watchdog")
                    }
                }
            }
        }
    }

    func clearPreload() {
        if let idx = preloadedSlot, idx < slots.count {
            slots[idx].playerNode.stop()
            slots[idx].mixerNode.outputVolume = 0
            slots[idx].isPreloaded = false
            preloadedSlot = nil
            nextCompletion = nil
            preloadRequested = false
        }
        if isFinishingNormally && isPlaying,
           activeSlot >= 0, activeSlot < slots.count {
            isFinishingNormally = false
            let slot = slots[activeSlot]
            let maxTime = Double(slot.fileLength) / slot.sampleRate
            if currentTime >= maxTime - 0.5 { handlePlaybackComplete() }
        }
    }

    func play(_ track: Track, volume: Float? = nil, startTime: TimeInterval? = nil, duration: TimeInterval? = nil, autoplay: Bool = true, completion: @escaping () -> Void) {
        playGeneration += 1

        stopCrossfade()
        stopDisplayLink()

        VisualizationEngine.shared.cancelWaveformGeneration()
        VisualizationEngine.shared.waveformData = Array(repeating: 0, count: 64)

        completionHandler = nil
        nextCompletion = nil
        switchingTrack = false

        for slot in slots { slot.playerNode.stop() }
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        slots.removeAll()

        isPlaying = false
        isSeeking = false
        isFinishingNormally = false
        crossfadeStarted = false
        preloadRequested = false
        preloadedSlot = nil
        silenceDetected = false
        silenceStartTime = nil
        lastPreloadTrackId = nil

        if let vol = volume { currentUserVolume = vol }

        let finalGain = computeRGGain(for: track)

        let realURL: URL = {
            if track.url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? track.url
            }
            return track.url
        }()

        guard let audioFile = try? AVAudioFile(forReading: realURL) else { completion(); return }
        let format = audioFile.processingFormat
        VisualizationEngine.shared.setAudioFile(audioFile)

        if SettingsManager.shared.waveformCacheMode != "off" {
            VisualizationEngine.shared.generateWaveformForCurrentTrack(track: track)
        } else if VisualizationEngine.shared.mode == .waveform {
            VisualizationEngine.shared.generateWaveformForCurrentTrack(track: track)
        }

        let newEngine = AVAudioEngine()

        // [PATCH] Общий конструктор слота с mixer
        func makeSlot() -> PlayerSlot {
            let p = AVAudioPlayerNode()
            let e = AVAudioUnitEQ(numberOfBands: 10)
            let m = AVAudioMixerNode()
            newEngine.attach(p)
            newEngine.attach(e)
            newEngine.attach(m)
            newEngine.connect(p, to: e, format: nil)
            newEngine.connect(e, to: m, format: nil)
            newEngine.connect(m, to: newEngine.mainMixerNode, format: nil)
            return PlayerSlot(playerNode: p, eqNode: e, mixerNode: m)
        }

        var slot = makeSlot()
        let slot2 = makeSlot()
        slots = [slot, slot2]
        activeSlot = 0

        slot.track = track
        slot.file = audioFile
        slot.fileLength = audioFile.length
        slot.sampleRate = format.sampleRate
        slot.rgLinearGain = finalGain
        slot.isPreloaded = true
        slot.format = format
        slot.cueSeekTime = 0
        slots[0] = slot

        setupEQBands(slots[0].eqNode)
        setupEQBands(slots[1].eqNode)
        slots[1].mixerNode.outputVolume = 0

        let effectiveStartTime = startTime ?? (track.cueStartTime)
        let effectiveDuration = duration ?? (track.cueStartTime != nil ? track.duration : nil)

        if let start = effectiveStartTime {
            let startFrame = AVAudioFramePosition(start * format.sampleRate)
            let maxFrame: AVAudioFramePosition
            if let dur = effectiveDuration, dur > 0 {
                maxFrame = min(startFrame + AVAudioFramePosition(dur * format.sampleRate), audioFile.length)
            } else {
                maxFrame = audioFile.length
            }
            let remaining = maxFrame - startFrame
            if remaining > 0 {
                slots[0].playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
                slots[0].seekOffset = start
            } else {
                slots[0].playerNode.scheduleFile(audioFile, at: nil)
                slots[0].seekOffset = 0
            }
        } else {
            slots[0].playerNode.scheduleFile(audioFile, at: nil)
            slots[0].seekOffset = 0
        }

        // [PATCH] raw samples на playerNode, громкость — на mixer
        slots[0].playerNode.volume = 1.0
        slots[0].mixerNode.outputVolume = currentUserVolume * finalGain

        do {
            try newEngine.start()
            if autoplay {
                slots[0].playerNode.play()
                isPlaying = true
                intendedPlaying = true
                startDisplayLink()
            } else {
                isPlaying = false
                intendedPlaying = false
            }
            currentTime = effectiveStartTime ?? 0
            completionHandler = completion
            engine = newEngine

            // [PATCH] tap ставим один раз при старте движка
            installTapOnce()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in self?.applyVolume() }
        } catch {
            completion()
            return
        }
    }

    // [PATCH] Один tap на mainMixer — не пересобирается при переходах.
    private func installTapOnce() {
        guard let engine = engine else { return }

        engine.mainMixerNode.removeTap(onBus: 0)

        let needVis = VisualizationEngine.shared.mode != .off
        let needSil = settings.silenceSkipEnabled
        guard needVis || needSil else { return }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if VisualizationEngine.shared.isRunning {
                VisualizationEngine.shared.processBuffer(buffer)
            }
            if self.settings.silenceSkipEnabled {
                self.analyzeBuffer(buffer)
            }
        }
    }

    // [PATCH] Больше не переустанавливаем tap при переходах.
    func updateMainMixerTap() {
        guard !crossfadeStarted, !isRecreating else { return }
        guard engine != nil, engine?.isRunning == true else { return }
        installTapOnce()
    }

    func pause() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        if crossfadeStarted, let startTime = crossfadeStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            savedCrossfadeRemaining = max(0.1, settings.crossfadeDuration - elapsed)
        }
        for slot in slots { slot.playerNode.pause() }
        isPlaying = false
        intendedPlaying = false
        stopDisplayLink()
    }

    func resume() {
        guard let engine = engine, engine.isRunning else { return }

        if crossfadeStarted {
            resumeCrossfade()
        } else {
            guard activeSlot >= 0, activeSlot < slots.count else { return }
            slots[activeSlot].playerNode.play()
            isPlaying = true
            intendedPlaying = true
            startDisplayLink()
            applyVolume()
        }
    }

    func stop() {
        stopCrossfade()
        stopDisplayLink()
        for slot in slots {
            slot.playerNode.stop()
            slot.playerNode.reset()
            slot.mixerNode.outputVolume = 0
        }
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        isPlaying = false
        intendedPlaying = false
        currentTime = 0
        silenceDetected = false
        silenceStartTime = nil
        isSeeking = false
        isFinishingNormally = false
        lastPreloadTrackId = nil
    }

    func seek(to time: TimeInterval) {
        commitCrossfadeForSeek()
        lastSeekTime = Date()

        guard !slots.isEmpty,
              activeSlot >= 0,
              activeSlot < slots.count else { return }

        let slot = slots[activeSlot]
        guard let file = slot.file else { return }
        let wasPlaying = isPlaying
        isSeeking = true
        seekGeneration += 1
        let myGen = seekGeneration

        let effectiveTime: Double
        if let cueStart = slot.track?.cueStartTime, cueStart > 0 {
            effectiveTime = cueStart + time
        } else {
            effectiveTime = time
        }

        let frame = AVAudioFramePosition(effectiveTime * slot.sampleRate)
        let startFrame = min(frame, slot.fileLength)
        let remaining = slot.fileLength - startFrame

        guard remaining > 0 else {
            isSeeking = false
            handlePlaybackComplete()
            return
        }

        currentTime = time

        var updatedSlot = slots[activeSlot]
        updatedSlot.cueSeekTime = time
        updatedSlot.seekOffset = effectiveTime
        slots[activeSlot] = updatedSlot

        silenceDetected = false
        silenceStartTime = nil
        lastPreloadTrackId = nil

        slot.playerNode.stop()
        slot.playerNode.reset()
        slot.playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
        // [PATCH] raw + mixer
        slot.playerNode.volume = 1.0
        slot.mixerNode.outputVolume = currentUserVolume * slot.rgLinearGain

        if wasPlaying { slot.playerNode.play() }
        isFinishingNormally = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.seekGeneration == myGen else { return }
            self.isSeeking = false
        }
    }

    func setVolume(_ volume: Float) { currentUserVolume = volume; applyVolume() }

    private func applyVolume() {
        guard !slots.isEmpty,
              activeSlot >= 0,
              activeSlot < slots.count else { return }
        guard !crossfadeStarted else { return }
        // [PATCH] playerNode = raw, mixer = user * rg
        slots[activeSlot].playerNode.volume = 1.0
        slots[activeSlot].mixerNode.outputVolume = currentUserVolume * slots[activeSlot].rgLinearGain
    }

    func applyCurrentRG() {
        guard !crossfadeStarted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.applyCurrentRG() }
            return
        }
        guard !slots.isEmpty, activeSlot >= 0, activeSlot < slots.count else { return }
        guard let track = slots[activeSlot].track else { return }
        let newGain = computeRGGain(for: track)
        slots[activeSlot].rgLinearGain = newGain
        applyVolume()
        if let preIdx = preloadedSlot, preIdx < slots.count, let preTrack = slots[preIdx].track {
            slots[preIdx].rgLinearGain = computeRGGain(for: preTrack)
        }
    }

    // MARK: - Preload

    func preloadNextTrack(_ track: Track, volume: Float? = nil, completion: @escaping () -> Void) {
        guard !crossfadeStarted else { return }

        let now = Date()
        if lastPreloadTrackId == track.id && now.timeIntervalSince(lastPreloadTime) < 0.5 {
            return
        }
        lastPreloadTrackId = track.id
        lastPreloadTime = now

        let myPlayGen = playGeneration
        let myPreloadGen = preloadGeneration

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.playGeneration == myPlayGen,
                  self.preloadGeneration == myPreloadGen,
                  let engine = self.engine,
                  engine.isRunning,
                  self.slots.count == 2 else {
                self?.preloadRequested = false
                return
            }

            let nextIndex = self.activeSlot == 0 ? 1 : 0

            let realURL: URL
            let preloadStartTime: TimeInterval?
            if track.url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                realURL = components?.url ?? track.url
                preloadStartTime = track.cueStartTime
            } else {
                realURL = track.url
                preloadStartTime = nil
            }

            guard let audioFile = try? AVAudioFile(forReading: realURL) else {
                self.preloadRequested = false
                return
            }
            let newFormat = audioFile.processingFormat

            var slot = self.slots[nextIndex]

            slot.playerNode.stop()
            slot.playerNode.reset()
            // [PATCH] сбрасываем DSP-состояние EQ — иначе «пук» на старте
            slot.eqNode.reset()

            let finalGain = self.computeRGGain(for: track)

            slot.format = newFormat
            slot.track = track
            slot.file = audioFile
            slot.fileLength = audioFile.length
            slot.sampleRate = newFormat.sampleRate
            slot.rgLinearGain = finalGain
            slot.isPreloaded = true
            slot.cueSeekTime = 0                 // [PATCH] иначе остаётся значение от предыдущего трека
            self.setupEQBands(slot.eqNode)

            if let start = preloadStartTime {
                let startFrame = AVAudioFramePosition(start * newFormat.sampleRate)
                let frameCount: AVAudioFrameCount
                if track.duration > 0 {
                    frameCount = AVAudioFrameCount(track.duration * newFormat.sampleRate)
                } else {
                    frameCount = AVAudioFrameCount(audioFile.length - startFrame)
                }
                let safeFrameCount = min(frameCount, AVAudioFrameCount(audioFile.length - startFrame))
                if safeFrameCount > 0 {
                    slot.playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: safeFrameCount, at: nil)
                    slot.seekOffset = start
                } else {
                    slot.playerNode.scheduleFile(audioFile, at: nil)
                    slot.seekOffset = 0
                }
            } else {
                slot.playerNode.scheduleFile(audioFile, at: nil)
                slot.seekOffset = 0
            }

            // [PATCH] raw + mixer, mixer в 0 до момента перехода
            slot.playerNode.volume = 1.0
            slot.mixerNode.outputVolume = 0

            self.slots[nextIndex] = slot

            self.preloadedSlot = nextIndex
            self.nextCompletion = completion
            self.preloadRequested = false
            if let vol = volume { self.currentUserVolume = vol }
        }
    }

    // MARK: - Crossfade

    @discardableResult
    private func startCrossfade() -> Bool {
        guard !crossfadeStarted,
              let nextIndex = preloadedSlot,
              nextIndex < slots.count,
              let engine = engine,
              engine.isRunning,
              activeSlot >= 0, activeSlot < slots.count else {
            return false
        }

        let oldIndex = activeSlot
        let oldSlot = slots[oldIndex]
        let newSlot = slots[nextIndex]

        let oldMaxTime = Double(oldSlot.fileLength) / oldSlot.sampleRate
        let remainingOld = oldMaxTime - currentTime

        guard remainingOld > 0.5 else {
            slots[nextIndex].playerNode.stop()
            slots[nextIndex].mixerNode.outputVolume = 0
            slots[nextIndex].isPreloaded = false
            preloadedSlot = nil
            nextCompletion = nil
            preloadRequested = false
            return false
        }

        stopCrossfade()

        let nextMaxTime = Double(newSlot.fileLength) / newSlot.sampleRate
        let maxByNext = max(0.3, nextMaxTime / 3)
        let duration = min(settings.crossfadeDuration, remainingOld, maxByNext)

        crossfadeStarted = true
        isFinishingNormally = true
        switchingTrack = true
        let savedNextIndex = nextIndex
        let savedNextCompletion = nextCompletion

        if let newTrack = newSlot.track {
            NotificationCenter.default.post(name: .crossfadeStarted, object: newTrack)
        }

        self.currentTime = 0

        // [PATCH] raw + mixer в 0, play()
        newSlot.playerNode.volume = 1.0
        newSlot.mixerNode.outputVolume = 0
        newSlot.playerNode.play()

        let startTime = Date()
        var completed = false
        crossfadeStartTime = startTime

        // [PATCH] 5 мс, крутим outputVolume у mixer — у него внутри есть smoothing
        let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] timer in
            guard let self = self, self.crossfadeStarted && !completed else {
                timer.invalidate()
                return
            }

            let oldTarget = self.currentUserVolume * oldSlot.rgLinearGain
            let newTarget = self.currentUserVolume * newSlot.rgLinearGain

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / duration, 1.0))

            oldSlot.playerNode.volume = 1.0
            newSlot.playerNode.volume = 1.0
            oldSlot.mixerNode.outputVolume = oldTarget * (1.0 - progress)
            newSlot.mixerNode.outputVolume = newTarget * progress

            if progress >= 1.0 {
                completed = true
                timer.invalidate()
                self.crossfadeTimer = nil
                oldSlot.playerNode.stop()
                oldSlot.mixerNode.outputVolume = 0

                self.activeSlot = savedNextIndex
                // [PATCH] installMainMixerTap() — УБРАНО
                self.preloadedSlot = nil
                self.crossfadeStarted = false
                self.isFinishingNormally = false
                self.switchingTrack = false
                self.completionHandler = savedNextCompletion
                self.nextCompletion = nil

                if let newTrack = newSlot.track {
                    NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                }

                DispatchQueue.main.async { [weak self] in
                    self?.applyVolume()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer

        crossfadeTimeoutWorkItem?.cancel()
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.crossfadeStarted,
                  !completed,
                  self.isPlaying else { return }
            self.forceCompleteCrossfade(oldIndex: oldIndex, newIndex: savedNextIndex)
        }
        crossfadeTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0, execute: timeoutItem)

        return true
    }

    private func resumeCrossfade() {
        guard crossfadeStarted else { return }

        guard let newIndex = preloadedSlot, newIndex < slots.count else { return }
        let oldIndex = activeSlot
        guard oldIndex >= 0, oldIndex < slots.count else { return }

        let oldSlot = slots[oldIndex]
        let newSlot = slots[newIndex]

        oldSlot.playerNode.play()
        newSlot.playerNode.play()
        isPlaying = true
        startDisplayLink()

        let newVolume = newSlot.mixerNode.outputVolume
        let newTargetVolume = currentUserVolume * newSlot.rgLinearGain

        let remainingProgress = newTargetVolume > 0 ? 1.0 - (newVolume / newTargetVolume) : 0
        let remainingDuration = savedCrossfadeRemaining > 0
            ? savedCrossfadeRemaining
            : max(0.1, settings.crossfadeDuration * Double(remainingProgress))

        let startTime = Date()
        var completed = false
        let savedNextCompletion = nextCompletion
        // [PATCH] синхронизация currentTime после resume
        let newVolumeForTime = newSlot.mixerNode.outputVolume
        let newTargetForTime = currentUserVolume * newSlot.rgLinearGain
        if newTargetForTime > 0 {
            let frac = newVolumeForTime / newTargetForTime
            self.currentTime = max(0, settings.crossfadeDuration * Double(frac))
        } else {
            self.currentTime = 0
        }

        crossfadeTimer?.invalidate()

        // [PATCH] 5 мс + mixer
        let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] timer in
            guard let self = self, self.crossfadeStarted && !completed else {
                timer.invalidate()
                return
            }

            let oldTarget = self.currentUserVolume * oldSlot.rgLinearGain
            let newTarget = self.currentUserVolume * newSlot.rgLinearGain

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / remainingDuration, 1.0))

            oldSlot.playerNode.volume = 1.0
            newSlot.playerNode.volume = 1.0
            oldSlot.mixerNode.outputVolume = oldTarget * (1.0 - progress)
            newSlot.mixerNode.outputVolume = newVolume + (newTarget - newVolume) * progress

            if progress >= 1.0 {
                completed = true
                timer.invalidate()
                self.crossfadeTimer = nil
                oldSlot.playerNode.stop()
                oldSlot.mixerNode.outputVolume = 0
                self.activeSlot = newIndex
                // [PATCH] installMainMixerTap() — УБРАНО
                self.preloadedSlot = nil
                self.crossfadeStarted = false
                self.isFinishingNormally = false
                self.switchingTrack = false
                self.completionHandler = savedNextCompletion
                self.nextCompletion = nil

                if let newTrack = newSlot.track {
                    NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                }

                DispatchQueue.main.async { [weak self] in
                    self?.applyVolume()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer
    }

    private func commitCrossfadeForSeek() {
        guard crossfadeStarted else {
            if let idx = preloadedSlot, idx < slots.count {
                slots[idx].playerNode.stop()
                slots[idx].mixerNode.outputVolume = 0
                slots[idx].isPreloaded = false
                preloadedSlot = nil
                nextCompletion = nil
                preloadRequested = false
            }
            return
        }

        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeTimeoutWorkItem?.cancel()
        crossfadeTimeoutWorkItem = nil

        let nextIdx = preloadedSlot ?? (activeSlot == 0 ? 1 : 0)

        if activeSlot >= 0, activeSlot < slots.count {
            slots[activeSlot].playerNode.stop()
            slots[activeSlot].mixerNode.outputVolume = 0
        }

        activeSlot = nextIdx
        if nextIdx >= 0, nextIdx < slots.count {
            // [PATCH] raw + mixer
            slots[nextIdx].playerNode.volume = 1.0
            slots[nextIdx].mixerNode.outputVolume = currentUserVolume * slots[nextIdx].rgLinearGain
        }
        currentTime = 0

        let savedCompletion = nextCompletion

        crossfadeStarted = false
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0
        switchingTrack = false
        isFinishingNormally = false
        preloadedSlot = nil
        preloadRequested = false
        completionHandler = savedCompletion
        nextCompletion = nil

        // [PATCH] installMainMixerTap() — УБРАНО

        if nextIdx >= 0, nextIdx < slots.count, let track = slots[nextIdx].track {
            NotificationCenter.default.post(name: .trackChanged, object: track)
        }
    }

    private func stopCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeTimeoutWorkItem?.cancel()
        crossfadeTimeoutWorkItem = nil
        crossfadeStarted = false
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0
        switchingTrack = false
    }

    private func forceCompleteCrossfade(oldIndex: Int, newIndex: Int) {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeTimeoutWorkItem?.cancel()
        crossfadeTimeoutWorkItem = nil

        if oldIndex >= 0, oldIndex < slots.count {
            slots[oldIndex].playerNode.stop()
            slots[oldIndex].mixerNode.outputVolume = 0
        }
        if newIndex >= 0, newIndex < slots.count {
            slots[newIndex].playerNode.volume = 1.0
            slots[newIndex].mixerNode.outputVolume = currentUserVolume * slots[newIndex].rgLinearGain
        }

        activeSlot = newIndex
        currentTime = 0
        // [PATCH] installMainMixerTap() — УБРАНО
        preloadedSlot = nil
        crossfadeStarted = false
        isFinishingNormally = false
        switchingTrack = false
        completionHandler = nextCompletion
        nextCompletion = nil
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0

        if newIndex >= 0, newIndex < slots.count, let newTrack = slots[newIndex].track {
            NotificationCenter.default.post(name: .trackChanged, object: newTrack)
        }
    }

    // MARK: - EQ

    private func setupEQBands(_ eq: AVAudioUnitEQ) {
        let bands = eqManager.bands
        for (index, band) in bands.enumerated() {
            guard index < eq.bands.count else { break }
            let p = eq.bands[index]
            p.filterType = .parametric
            p.frequency = Float(band.frequency)
            p.bandwidth = 1.0
            p.gain = eqManager.isEnabled ? band.gain : 0
            p.bypass = false
        }
    }

    private func updateAllEQs() { for slot in slots { setupEQBands(slot.eqNode) } }

    // MARK: - Display Link

    private func startDisplayLink() {
        stopDisplayLink()
        let interval = Int(settings.progressUpdateInterval)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval))

        timer.setEventHandler { [weak self] in
            guard let self = self, self.engine?.isRunning == true, self.isPlaying else { return }

            // [PATCH] Читаем время из того слота, который сейчас РЕАЛЬНО играет звук.
            // При кроссфейде это прелоад-слот; иначе — активный.
            let readingIndex: Int
            let isCrossfading = self.crossfadeStarted
            if isCrossfading,
               let nextIdx = self.preloadedSlot,
               nextIdx >= 0, nextIdx < self.slots.count {
                readingIndex = nextIdx
            } else {
                readingIndex = self.activeSlot
            }
            guard readingIndex >= 0, readingIndex < self.slots.count else { return }
            let readingSlot = self.slots[readingIndex]

            // [PATCH] Считаем "сырое" время из playerTime, но с защитой от
            // отрицательных значений (бывает сразу после play()/play(at:)).
            let rawTime: TimeInterval? = {
                guard let nodeTime = readingSlot.playerNode.lastRenderTime,
                      let playerTime = readingSlot.playerNode.playerTime(forNodeTime: nodeTime) else {
                    return nil
                }
                guard playerTime.sampleRate > 0 else { return nil }
                let segmentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                if segmentTime.isNaN || segmentTime.isInfinite { return nil }
                if segmentTime < 0 { return nil }

                if isCrossfading {
                    return segmentTime
                }
                if readingSlot.track?.cueStartTime != nil {
                    return (readingSlot.cueSeekTime ?? 0) + segmentTime
                }
                return readingSlot.seekOffset + segmentTime
            }()

            guard let rawTime else { return }

            // [PATCH] maxTime для того слота, из которого читаем
            let maxTimeForSlot: Double = {
                if let t = readingSlot.track, t.cueStartTime != nil, t.duration > 0 {
                    return t.duration
                }
                return Double(readingSlot.fileLength) / readingSlot.sampleRate
            }()

            // [PATCH] Клампим — UI никогда не увидит значение вне [0, maxTime]
            let currentTimeValue = max(0, min(rawTime, maxTimeForSlot))
            self.currentTime = currentTimeValue

            if !self.crossfadeStarted && !self.isSeeking && self.isPlaying {
                let activeSlot = self.slots[self.activeSlot]
                let maxTime: Double
                if let track = activeSlot.track, track.cueStartTime != nil, track.duration > 0 {
                    maxTime = track.duration
                } else {
                    maxTime = Double(activeSlot.fileLength) / activeSlot.sampleRate
                }
                let remaining = maxTime - currentTimeValue

                let timeSinceSeek = Date().timeIntervalSince(self.lastSeekTime)
                let seekGraceActive = timeSinceSeek < 1.2

                if !seekGraceActive {
                    if self.settings.crossfadeEnabled && remaining <= self.settings.crossfadeDuration + 1.0 && self.preloadedSlot == nil && !self.preloadRequested {
                        self.preloadRequested = true
                        NotificationCenter.default.post(name: .prepareNextTrack, object: nil)
                    }
                    if self.settings.gaplessEnabled && remaining <= 3.0 && self.preloadedSlot == nil && !self.preloadRequested {
                        self.preloadRequested = true
                        NotificationCenter.default.post(name: .prepareNextTrack, object: nil)
                    }
                    if self.settings.crossfadeEnabled && remaining <= self.settings.crossfadeDuration && self.preloadedSlot != nil {
                        self.startCrossfade()
                    }
                }

                if currentTimeValue >= maxTime - 0.1 && self.isPlaying && !self.isSeeking && !self.isFinishingNormally {
                    self.handlePlaybackComplete()
                }
            }
        }
        timer.resume()
        displayLink = timer
    }

    private func stopDisplayLink() {
        displayLink?.cancel()
        displayLink = nil
    }

    private func restartDisplayLink() {
        guard isPlaying else { return }
        stopDisplayLink()
        startDisplayLink()
    }


    private func handlePlaybackComplete() {
        guard !isFinishingNormally else { return }
        isFinishingNormally = true

        if let nextIndex = preloadedSlot, nextIndex < slots.count, slots[nextIndex].isPreloaded {
            if settings.crossfadeEnabled {
                if startCrossfade() { return }
            } else {
                // [PATCH] Настоящий gapless через play(at:) — без дырки
                let oldIndex = activeSlot
                let oldSlot = slots[oldIndex]
                let newSlot = slots[nextIndex]
                guard let engine = engine, engine.isRunning else { return }

                // [PATCH] Стартуем новый трек немедленно. play(at: now+remaining)
                // создавал дырку тишины на remaining секунд, потому что старую
                // ноду мы глушили сразу — и playerTime новой ноды всё это время
                // возвращал nil (бар стоял на 0).
                newSlot.playerNode.volume = 1.0
                newSlot.mixerNode.outputVolume = currentUserVolume * newSlot.rgLinearGain
                newSlot.playerNode.play()

                // Старую ноду гасим через 20 мс — новая уже рендерится,
                // а на слух наложения нет.
                let savedOldTrackId = oldSlot.track?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self else { return }
                    guard oldIndex >= 0, oldIndex < self.slots.count else { return }
                    if let savedOldTrackId, self.slots[oldIndex].track?.id != savedOldTrackId { return }
                    self.slots[oldIndex].playerNode.stop()
                    self.slots[oldIndex].mixerNode.outputVolume = 0
                }

                activeSlot = nextIndex
                preloadedSlot = nil
                currentTime = 0
                isPlaying = true
                intendedPlaying = true
                isFinishingNormally = false
                completionHandler = nextCompletion
                nextCompletion = nil

                if let newTrack = newSlot.track {
                    NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                }
                return
            }
        }

        if let handler = completionHandler {
            completionHandler = nil
            currentTime = 0
            isFinishingNormally = false
            stopDisplayLink()
            handler()
        } else {
            if activeSlot >= 0, activeSlot < slots.count {
                slots[activeSlot].playerNode.stop()
                slots[activeSlot].mixerNode.outputVolume = 0
            }
            isPlaying = false
            intendedPlaying = false
            currentTime = 0
            isFinishingNormally = false
        }
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        installTapOnce()
    }

    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard settings.silenceSkipEnabled || VisualizationEngine.shared.isRunning else { return }
        guard settings.silenceSkipEnabled, isPlaying, !isSeeking, !crossfadeStarted, !settings.gaplessEnabled else { return }
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }
        var sum: Float = 0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for i in 0..<frameLength {
                let sample = data[i]
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(frameLength * channelCount))
        let db = 20 * log10(max(rms, 0.000001))
        let threshold = Float(settings.silenceSkipThreshold)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if db < threshold {
                if !self.silenceDetected {
                    self.silenceDetected = true
                    self.silenceStartTime = Date()
                } else if let start = self.silenceStartTime {
                    let duration = Date().timeIntervalSince(start)
                    if duration >= self.silenceMinDuration { self.handleSilenceDetected() }
                }
            } else {
                if self.silenceDetected {
                    self.silenceDetected = false
                    self.silenceStartTime = nil
                }
            }
        }
    }

    private func handleSilenceDetected() {
        guard silenceDetected else { return }
        silenceDetected = false
        silenceStartTime = nil
        guard !slots.isEmpty, activeSlot >= 0, activeSlot < slots.count else { return }
        let slot = slots[activeSlot]
        let maxTime = Double(slot.fileLength) / slot.sampleRate
        let remaining = maxTime - currentTime
        guard remaining > 1.0 && remaining <= 10.0 else { return }
        slot.mixerNode.outputVolume = 0
        self.seek(to: maxTime - 0.01)
    }
}
