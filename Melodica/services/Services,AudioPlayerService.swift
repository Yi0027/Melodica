private struct SendableAudioFile: @unchecked Sendable {
    let file: AVAudioFile
}

// Services/AudioPlayerService.swift
import AVFoundation
import Combine
import AppKit
import CoreAudio
import os

extension Notification.Name {
    static let eqDidChange = Notification.Name("eqDidChange")
    static let progressIntervalChanged = Notification.Name("progressIntervalChanged")
    static let trackChanged = Notification.Name("trackChanged")
    static let prepareNextTrack = Notification.Name("prepareNextTrack")
    static let crossfadeStarted = Notification.Name("crossfadeStarted")
    static let spatialAudioChanged = Notification.Name("spatialAudioChanged")
    static let waveformCacheModeChanged = Notification.Name("waveformCacheModeChanged")
}

@MainActor
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
    private var currentEngineSpatial: Bool = false
    private var currentEngineSpatialStereo: Bool = false
    private var blendMixer: AVAudioMixerNode?
    private var environmentNode: AVAudioEnvironmentNode?
    private var leftSpatialMixer: AVAudioMixerNode?
    private var rightSpatialMixer: AVAudioMixerNode?

    private let maxAllowedGain: Float = 4.0
    private let rgReferenceGain: Float = 1.0

    private var seekGeneration = 0
    private var playGeneration = 0
    private var preloadGeneration = 0
    private var lastSeekTime: Date = .distantPast
    private var lastPlayTime: Date = .distantPast
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
        let reverbNode: AVAudioUnitReverb   // [EFFECTS]
        let delayNode: AVAudioUnitDelay     // [EFFECTS]
        let mixerNode: AVAudioMixerNode
        var track: Track?
        var file: AVAudioFile?
        var fileLength: AVAudioFramePosition = 0
        var sampleRate: Double = 44100
        var rgLinearGain: Float = 1.0
        var isPreloaded = false
        var format: AVAudioFormat?
        var cueSeekTime: TimeInterval?
        var seekOffset: TimeInterval = 0
        var cueBaseTime: TimeInterval = 0
    }

    override init() {
        super.init()
        setupEngine()
        setupNotifications()
    }

    private func setupEngine() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }

        let blend = AVAudioMixerNode()
        engine.attach(blend)
        blendMixer = blend

        for idx in 0..<2 {
            let playerNode = AVAudioPlayerNode()
            let eqNode = AVAudioUnitEQ(numberOfBands: 10)
            let reverbNode = AVAudioUnitReverb()
            let delayNode = AVAudioUnitDelay()
            let mixerNode = AVAudioMixerNode()
            engine.attach(playerNode)
            engine.attach(eqNode)
            engine.attach(reverbNode)
            engine.attach(delayNode)
            engine.attach(mixerNode)
            engine.connect(playerNode, to: eqNode, format: nil)
            engine.connect(eqNode, to: reverbNode, format: nil)
            engine.connect(reverbNode, to: delayNode, format: nil)
            engine.connect(delayNode, to: mixerNode, format: nil)
            engine.connect(mixerNode, to: blend, fromBus: 0, toBus: idx, format: nil)
            let slot = PlayerSlot(
                playerNode: playerNode,
                eqNode: eqNode,
                reverbNode: reverbNode,
                delayNode: delayNode,
                mixerNode: mixerNode
            )
            slots.append(slot)
        }

        let mainFormat = engine.mainMixerNode.outputFormat(forBus: 0)

        if settings.spatialAudioEnabled {
            let env = AVAudioEnvironmentNode()
            engine.attach(env)
            self.environmentNode = env

            env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            env.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
            env.distanceAttenuationParameters.rolloffFactor = 0.0

            let algorithm: AVAudio3DMixingRenderingAlgorithm = {
                switch settings.spatialAlgorithm {
                case "equalPower": return .equalPowerPanning
                case "spherical":  return .sphericalHead
                case "hrtfHQ":     return .HRTFHQ
                default:           return .HRTF
                }
            }()

            engine.connect(blend, to: env, fromBus: 0, toBus: 0, format: mainFormat)
            if let dest = blend.destination(forMixer: env, bus: 0) {
                dest.renderingAlgorithm = algorithm
                dest.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
                dest.reverbBlend = 0
            }
            engine.connect(env, to: engine.mainMixerNode, format: mainFormat)
        } else {
            engine.connect(blend, to: engine.mainMixerNode, format: mainFormat)
        }
        engine.mainMixerNode.outputVolume = currentUserVolume
        currentEngineSpatial = settings.spatialAudioEnabled
        updateAllEffects()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .audioEffectsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAllEffects()
            }
        }
        NotificationCenter.default.addObserver(forName: .eqDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAllEQs()
            }
        }
        NotificationCenter.default.addObserver(forName: .progressIntervalChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartDisplayLink()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("gaplessOrCrossfadeDisabled"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleGaplessOrCrossfadeDisabled()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("crossfadeDisabled"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.settings.crossfadeEnabled = false
                self.handleGaplessOrCrossfadeDisabled()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("rgModeChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyCurrentRG()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleDeviceOrConfigurationChanged(reason: "configChange")
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("visualizationModeChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMainMixerTap()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("silenceSkipChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMainMixerTap()
            }
        }
        NotificationCenter.default.addObserver(forName: .spatialAudioChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reapplySpatialSettings()
            }
        }

        // MARK: - Sleep / Wake

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSleeping = true
                for slot in self.slots { slot.playerNode.pause() }
                self.stopDisplayLink()
            }
        }

        workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSleeping = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.isSleeping else { return }
                        self.scheduleRecreateEngine(reason: "wake")
                    }
                }
            }
        }

        setupAudioDeviceListeners()
    }

    deinit {
        if let block = defaultDeviceListenerBlock {
            var defaultDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultDeviceAddress,
                DispatchQueue.main,
                block
            )
        }
        if currentListenedDeviceID != 0, let dsBlock = dataSourceListenerBlock {
            var dsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(currentListenedDeviceID, &dsAddress, DispatchQueue.main, dsBlock)
        }
    }

    // MARK: - Device Type & Monitoring

    enum AudioDeviceType {
        case headphones
        case speakers
        case unknown
    }

    private var currentOutputDeviceID: AudioDeviceID = 0
    private var currentDeviceType: AudioDeviceType = .unknown
    nonisolated(unsafe) private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var dataSourceListenerBlock: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var currentListenedDeviceID: AudioDeviceID = 0

    private func currentDefaultOutputDeviceID() -> AudioDeviceID {
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
        return status == noErr ? deviceID : 0
    }

    private func getAudioDeviceType(for deviceID: AudioDeviceID) -> AudioDeviceType {
        guard deviceID != 0 else { return .unknown }

        // 1. Check data source (e.g. built-in 3.5mm jack vs internal speakers)
        var dsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSource: UInt32 = 0
        var dsSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &dsAddress, 0, nil, &dsSize, &dataSource) == noErr {
            let code = String(format: "%c%c%c%c",
                              (dataSource >> 24) & 0xff,
                              (dataSource >> 16) & 0xff,
                              (dataSource >> 8) & 0xff,
                              dataSource & 0xff)
            if code == "hdpn" || code == "head" {
                return .headphones
            }
            if code == "ispk" || code == "spkr" {
                return .speakers
            }
        }

        // 2. Check transport type
        var transAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &transAddress, 0, nil, &transSize, &transport)

        if transport == kAudioDeviceTransportTypeHDMI ||
           transport == kAudioDeviceTransportTypeDisplayPort ||
           transport == kAudioDeviceTransportTypeAirPlay {
            return .speakers
        }

        // 3. Check device name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameCF: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = withUnsafeMutablePointer(to: &nameCF) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }

        guard nameStatus == noErr else { return .unknown }
        let name = (nameCF as String).lowercased()

        let headphoneKeywords = [
            "headphone", "headset", "earphone", "airpods", "buds",
            "freeclip", "freebuds", "wh-", "wf-", "quietcomfort",
            "наушник", "навушн", "kopfhörer", "écouteur", "auricular", "cuffie",
            "in-ear", "over-ear", "earbuds", "beats", "galaxy buds", "pixel buds"
        ]
        for kw in headphoneKeywords {
            if name.contains(kw) { return .headphones }
        }

        let speakerKeywords = [
            "speaker", "динамик", "колонк", "soundbar", "lautsprecher",
            "haut-parleur", "altavoz", "altoparlante", "homepod", "echo",
            "tv", "display", "monitor", "audio output", "line out", "jbl flip", "sonos"
        ]
        for kw in speakerKeywords {
            if name.contains(kw) { return .speakers }
        }

        if transport == kAudioDeviceTransportTypeBuiltIn {
            return .speakers
        }

        return .unknown
    }

    private func setupAudioDeviceListeners() {
        let initialDeviceID = currentDefaultOutputDeviceID()
        currentOutputDeviceID = initialDeviceID
        currentDeviceType = getAudioDeviceType(for: initialDeviceID)

        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handleDeviceOrConfigurationChanged(reason: "defaultDeviceChanged")
                }
            }
        }
        defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            block
        )

        updateDataSourceListener(for: initialDeviceID)
    }

    private func updateDataSourceListener(for deviceID: AudioDeviceID) {
        if currentListenedDeviceID != 0, let oldBlock = dataSourceListenerBlock {
            var oldAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSource,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(currentListenedDeviceID, &oldAddress, DispatchQueue.main, oldBlock)
            dataSourceListenerBlock = nil
            currentListenedDeviceID = 0
        }

        guard deviceID != 0 else { return }

        var dsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handleDeviceOrConfigurationChanged(reason: "dataSourceChanged")
                }
            }
        }
        dataSourceListenerBlock = block
        currentListenedDeviceID = deviceID
        AudioObjectAddPropertyListenerBlock(deviceID, &dsAddress, DispatchQueue.main, block)
    }

    private func handleDeviceOrConfigurationChanged(reason: String) {
        let newDeviceID = currentDefaultOutputDeviceID()
        let newDeviceType = getAudioDeviceType(for: newDeviceID)
        let oldDeviceType = currentDeviceType

        let shouldResume: Bool
        if newDeviceType == .headphones {
            // Если подключены наушники, сохраняем состояние как было до подключения
            shouldResume = intendedPlaying
        } else if oldDeviceType == .headphones && newDeviceType == .speakers {
            // Если наушники отключены и переключились на динамики — всегда ставим паузу
            shouldResume = false
        } else if newDeviceType == .unknown {
            // Если тип устройства неизвестен — всегда ставим паузу
            shouldResume = false
        } else {
            shouldResume = intendedPlaying
        }

        currentOutputDeviceID = newDeviceID
        currentDeviceType = newDeviceType
        updateDataSourceListener(for: newDeviceID)

        if !shouldResume {
            intendedPlaying = false
            isPlaying = false
        }

        // Моментально останавливаем displayLink и приглушаем микшер во избежание сбоев в CoreAudio
        stopDisplayLink()
        engine?.mainMixerNode.outputVolume = 0

        scheduleRecreateEngine(reason: reason, resumePlaying: shouldResume)
    }

    // MARK: - RG Helper

    private var rgRampTask: Task<Void, Never>?

    private func computeRGGain(for track: Track) -> Float {
        var rgValue: Float?
        var peak: Float?

        if settings.rgMode == "off" {
            // When RG mode is off: if auto-volume leveling is enabled, all tracks use auto calculation
            if settings.autoVolumeLevelingEnabled {
                if let autoResult = AutoVolumeLevelingService.shared.getCachedLoudness(for: track) {
                    rgValue = autoResult.gain
                    peak = autoResult.peak
                }
            } else {
                return 1.0
            }
        } else {
            // When RG mode is track or album: prefer embedded ReplayGain
            switch settings.rgMode {
            case "track":
                rgValue = track.replayGain ?? track.replayGainAlbum
                peak = track.replayGainPeak ?? track.replayGainAlbumPeak
            case "album":
                rgValue = track.replayGainAlbum ?? track.replayGain
                peak = track.replayGainAlbumPeak ?? track.replayGainPeak
            default:
                break
            }
            
            // Fallback to auto-volume leveling if track lacks embedded ReplayGain
            if rgValue == nil && settings.autoVolumeLevelingEnabled {
                if let autoResult = AutoVolumeLevelingService.shared.getCachedLoudness(for: track) {
                    rgValue = autoResult.gain
                    peak = autoResult.peak
                }
            }
        }
        
        let rgGain = rgValue.map { pow(10, $0 / 20.0) } ?? 1.0
        let safeGain = peak.map { min(rgGain, 1.0 / $0) } ?? rgGain
        return min(safeGain, maxAllowedGain) * rgReferenceGain
    }

    private func triggerAutoVolumeLevelingIfNeeded(for track: Track) {
        guard settings.autoVolumeLevelingEnabled else { return }
        
        if settings.rgMode != "off" {
            let hasRG = (settings.rgMode == "album" ? (track.replayGainAlbum ?? track.replayGain) : (track.replayGain ?? track.replayGainAlbum)) != nil
            if hasRG { return }
        }
        
        if AutoVolumeLevelingService.shared.getCachedLoudness(for: track) == nil {
            let trackId = track.id
            AutoVolumeLevelingService.shared.requestLoudness(for: track) { [weak self] result in
                guard let self = self, let _ = result else { return }
                guard !self.slots.isEmpty, self.activeSlot >= 0, self.activeSlot < self.slots.count else { return }
                guard self.slots[self.activeSlot].track?.id == trackId else { return }
                let targetGain = self.computeRGGain(for: track)
                self.rampRGGain(to: targetGain)
            }
        }
    }

    private func rampRGGain(to targetGain: Float, duration: TimeInterval = 0.3) {
        rgRampTask?.cancel()
        rgRampTask = nil
        
        guard !slots.isEmpty, activeSlot >= 0, activeSlot < slots.count else { return }
        let startGain = slots[activeSlot].rgLinearGain
        if abs(startGain - targetGain) < 0.005 {
            slots[activeSlot].rgLinearGain = targetGain
            applySlotGain()
            return
        }
        
        let steps = 15
        let stepIntervalNanos = UInt64((duration / Double(steps)) * 1_000_000_000)
        
        rgRampTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepIntervalNanos)
                guard !Task.isCancelled, let self = self else { return }
                guard !self.slots.isEmpty, self.activeSlot >= 0, self.activeSlot < self.slots.count else { return }
                
                let progress = Float(step) / Float(steps)
                let currentGain = startGain + (targetGain - startGain) * progress
                self.slots[self.activeSlot].rgLinearGain = currentGain
                self.applySlotGain()
            }
            
            guard !Task.isCancelled, let self = self else { return }
            if !self.slots.isEmpty, self.activeSlot >= 0, self.activeSlot < self.slots.count {
                self.slots[self.activeSlot].rgLinearGain = targetGain
                self.applySlotGain()
            }
            self.rgRampTask = nil
        }
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

        // 1. Устройство должно быть активно (живо)
        var isAlive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(deviceID, &aliveAddress, 0, nil, &aliveSize, &isAlive) == noErr {
            guard isAlive == 1 else { return false }
        }

        // 2. Аппаратная частота дискретизации должна быть сконфигурирована (> 0)
        var sampleRate: Float64 = 0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(deviceID, &srAddress, 0, nil, &srSize, &sampleRate) == noErr {
            guard sampleRate > 0 else { return false }
        }

        // 3. Должны присутствовать доступные выходные потоки
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

    private func scheduleRecreateEngine(reason: String, resumePlaying: Bool? = nil) {
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
        let targetPlaying = resumePlaying ?? intendedPlaying
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isSleeping, self.recreateGeneration == myGen else { return }
                self.recreateEngine(gen: myGen, reason: reason, resumePlaying: targetPlaying)
            }
        }
        recreateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    private func recreateEngine(gen: Int, reason: String, resumePlaying: Bool? = nil) {
        guard !isSleeping, !isRecreating, recreateGeneration == gen else {
            return
        }
        guard !slots.isEmpty,
              activeSlot >= 0, activeSlot < slots.count,
              let restoreTrack = slots[activeSlot].track else {
            return
        }

        isRecreating = true
        suppressRecreateUntil = Date().addingTimeInterval(3.0)

        let restoreTime = currentTime
        let restorePlaying = resumePlaying ?? intendedPlaying
        let restoreVolume = currentUserVolume > 0 ? currentUserVolume : 0.5

        engine?.mainMixerNode.outputVolume = 0

        stopCrossfade()
        stopDisplayLink()

        // Безопасно снимаем tap перед остановкой узлов
        blendMixer?.removeTap(onBus: 0)
        blendMixer?.removeTap(onBus: 0)
        engine?.mainMixerNode.removeTap(onBus: 0)

        for slot in slots {
            slot.playerNode.stop()
            // НЕ вызываем slot.playerNode.reset(), так как на отключенном железе
            // AudioUnitReset выбрасывает неперехватываемое исключение NSException в CoreAudio!
        }
        engine?.stop()
        engine = nil
        blendMixer = nil
        environmentNode = nil
        leftSpatialMixer = nil
        rightSpatialMixer = nil
        slots.removeAll()
        activeSlot = 0
        preloadedSlot = nil
        nextCompletion = nil
        preloadRequested = false

        isPlaying = false
        silenceDetected = false
        silenceStartTime = nil
        isFinishingNormally = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                self?.attemptRestore(gen: gen, track: restoreTrack, time: restoreTime,
                                     playing: restorePlaying, volume: restoreVolume, attempt: 0)
            }
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
                    MainActor.assumeIsolated {
                        self?.attemptRestore(gen: gen, track: track, time: time,
                                             playing: playing, volume: volume,
                                             attempt: attempt + 1)
                    }
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
                    MainActor.assumeIsolated {
                        self?.attemptRestore(gen: gen, track: track, time: time,
                                             playing: playing, volume: volume,
                                             attempt: attempt + 1)
                    }
                }
            } else {
                self.currentUserVolume = volume
                isRecreating = false
            }
            return
        }

        engine.mainMixerNode.outputVolume = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
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
                self.applySlotGain()
                self.applyVolume()

                self.isRecreating = false

                if playing {
                    let checkGen = gen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.recreateGeneration == checkGen, !self.isSleeping else { return }
                            let engineOK = self.engine?.isRunning == true
                            let playingOK = (self.activeSlot < self.slots.count) ? self.slots[self.activeSlot].playerNode.isPlaying : (self.slots.first?.playerNode.isPlaying ?? false)
                            if !engineOK || !playingOK {
                                self.scheduleRecreateEngine(reason: "watchdog")
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleGaplessOrCrossfadeDisabled() {
        cancelActiveCrossfade()
        clearPreload()
    }

    func clearPreload() {
        if crossfadeStarted {
            cancelActiveCrossfade()
            return
        }
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
            let maxTime = (slot.track?.duration ?? 0) > 0 ? slot.track!.duration : (Double(slot.fileLength) / slot.sampleRate)
            if currentTime >= maxTime - 0.5 { handlePlaybackComplete() }
        }
    }

    func play(_ track: Track, volume: Float? = nil, startTime: TimeInterval? = nil, duration: TimeInterval? = nil, autoplay: Bool = true, completion: @escaping () -> Void) {
        playGeneration += 1
        lastPlayTime = Date()

        cancelActiveCrossfade()
        stopDisplayLink()

        if let vol = volume { currentUserVolume = vol; applyVolume() }
        let finalGain = computeRGGain(for: track)
        triggerAutoVolumeLevelingIfNeeded(for: track)

        let effectiveStartTime = startTime ?? (track.cueStartTime)
        let effectiveDuration = duration ?? (track.cueStartTime != nil ? track.duration : nil)

        // MARK: - FAST PATH 1: Preloaded Slot
        // If the requested track was already preloaded into the secondary slot, switch immediately!
        if let engine = self.engine,
           engine.isRunning,
           slots.count == 2,
           currentEngineSpatial == settings.spatialAudioEnabled,
           let preloadedIdx = preloadedSlot,
           preloadedIdx < slots.count,
           slots[preloadedIdx].track?.id == track.id,
           slots[preloadedIdx].isPreloaded,
           effectiveStartTime == nil || effectiveStartTime == 0 || effectiveStartTime == track.cueStartTime {

            let oldIndex = activeSlot
            let newSlot = slots[preloadedIdx]

            newSlot.playerNode.volume = 1.0
            newSlot.mixerNode.outputVolume = newSlot.rgLinearGain
            if autoplay {
                newSlot.playerNode.play()
                isPlaying = true
                intendedPlaying = true
                startDisplayLink()
            } else {
                isPlaying = false
                intendedPlaying = false
            }

            // Smoothly mute & stop the old slot without click
            if oldIndex >= 0 && oldIndex < slots.count && oldIndex != preloadedIdx {
                slots[oldIndex].mixerNode.outputVolume = 0
                let savedOldTrackId = slots[oldIndex].track?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard oldIndex < self.slots.count else { return }
                        if let savedOldTrackId, self.slots[oldIndex].track?.id != savedOldTrackId { return }
                        self.slots[oldIndex].playerNode.stop()
                    }
                }
            }

            activeSlot = preloadedIdx
            preloadedSlot = nil
            currentTime = effectiveStartTime ?? 0
            lastPlayTime = Date()
            completionHandler = completion
            nextCompletion = nil
            isSeeking = false
            isFinishingNormally = false
            crossfadeStarted = false
            preloadRequested = false
            silenceDetected = false
            silenceStartTime = nil
            lastPreloadTrackId = nil
            switchingTrack = false

            if let file = newSlot.file {
                VisualizationEngine.shared.setAudioFile(file)
            }
            VisualizationEngine.shared.loadWaveformForTrack(track)
            return
        }

        // MARK: - FAST PATH 2: Running Engine Reuse
        // If the engine is already running and configured, reuse it without rebuilding nodes or restarting CoreAudio!
        if let engine = self.engine,
           engine.isRunning,
           slots.count == 2,
           currentEngineSpatial == settings.spatialAudioEnabled {

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

            let targetIdx = (activeSlot == 0) ? 1 : 0
            let oldIndex = activeSlot

            var targetSlot = slots[targetIdx]
            targetSlot.playerNode.stop()
            targetSlot.playerNode.reset()
            targetSlot.eqNode.reset()
            targetSlot.reverbNode.reset()
            targetSlot.delayNode.reset()

            targetSlot.track = track
            targetSlot.file = audioFile
            targetSlot.fileLength = audioFile.length
            targetSlot.sampleRate = format.sampleRate
            targetSlot.rgLinearGain = finalGain
            targetSlot.isPreloaded = true
            targetSlot.format = format
            targetSlot.cueSeekTime = 0
            targetSlot.cueBaseTime = 0

            setupEQBands(targetSlot.eqNode)
            setupEffects(&targetSlot)

            if let start = effectiveStartTime {
                let startFrame = AVAudioFramePosition(start * format.sampleRate)
                let maxFrame: AVAudioFramePosition
                if let dur = effectiveDuration, dur > 0, track.cueStartTime == nil {
                    maxFrame = min(startFrame + AVAudioFramePosition(dur * format.sampleRate), audioFile.length)
                } else {
                    maxFrame = audioFile.length
                }
                let remaining = maxFrame - startFrame
                if remaining > 0 {
                    targetSlot.playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
                    targetSlot.seekOffset = start
                } else {
                    targetSlot.playerNode.scheduleFile(audioFile, at: nil)
                    targetSlot.seekOffset = 0
                }
            } else {
                targetSlot.playerNode.scheduleFile(audioFile, at: nil)
                targetSlot.seekOffset = 0
            }

            targetSlot.playerNode.volume = 1.0
            targetSlot.mixerNode.outputVolume = finalGain
            slots[targetIdx] = targetSlot

            if autoplay {
                targetSlot.playerNode.play()
                isPlaying = true
                intendedPlaying = true
                startDisplayLink()
            } else {
                isPlaying = false
                intendedPlaying = false
            }

            // Smoothly mute & stop the old slot without click
            if oldIndex >= 0 && oldIndex < slots.count && oldIndex != targetIdx {
                slots[oldIndex].mixerNode.outputVolume = 0
                let savedOldTrackId = slots[oldIndex].track?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard oldIndex < self.slots.count else { return }
                        if let savedOldTrackId, self.slots[oldIndex].track?.id != savedOldTrackId { return }
                        self.slots[oldIndex].playerNode.stop()
                    }
                }
            }

            activeSlot = targetIdx
            preloadedSlot = nil
            currentTime = effectiveStartTime ?? 0
            lastPlayTime = Date()
            completionHandler = completion
            nextCompletion = nil
            isSeeking = false
            isFinishingNormally = false
            crossfadeStarted = false
            preloadRequested = false
            silenceDetected = false
            silenceStartTime = nil
            lastPreloadTrackId = nil
            switchingTrack = false

            VisualizationEngine.shared.setAudioFile(audioFile)
            VisualizationEngine.shared.loadWaveformForTrack(track)
            return
        }

        // MARK: - COLD START / GRAPH REBUILD PATH
        completionHandler = nil
        nextCompletion = nil
        switchingTrack = false

        for slot in slots { slot.playerNode.stop() }
        blendMixer?.removeTap(onBus: 0)
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        blendMixer = nil
        environmentNode = nil
        leftSpatialMixer = nil
        rightSpatialMixer = nil
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

        VisualizationEngine.shared.loadWaveformForTrack(track)

        let newEngine = AVAudioEngine()

        func makeSlot() -> PlayerSlot {
            let p = AVAudioPlayerNode()
            let e = AVAudioUnitEQ(numberOfBands: 10)
            let r = AVAudioUnitReverb()
            let d = AVAudioUnitDelay()
            let m = AVAudioMixerNode()
            newEngine.attach(p)
            newEngine.attach(e)
            newEngine.attach(r)
            newEngine.attach(d)
            newEngine.attach(m)
            newEngine.connect(p, to: e, format: nil)
            newEngine.connect(e, to: r, format: nil)
            newEngine.connect(r, to: d, format: nil)
            newEngine.connect(d, to: m, format: nil)
            return PlayerSlot(playerNode: p, eqNode: e, reverbNode: r, delayNode: d, mixerNode: m)
        }

        var slot = makeSlot()
        let slot2 = makeSlot()

        let blend = AVAudioMixerNode()
        newEngine.attach(blend)
        newEngine.connect(slot.mixerNode, to: blend, fromBus: 0, toBus: 0, format: nil)
        newEngine.connect(slot2.mixerNode, to: blend, fromBus: 0, toBus: 1, format: nil)
        self.blendMixer = blend

        let mainFormat = newEngine.mainMixerNode.outputFormat(forBus: 0)

        if settings.spatialAudioEnabled {
            let env = AVAudioEnvironmentNode()
            newEngine.attach(env)
            self.environmentNode = env

            env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            env.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)

            if settings.spatialStereoSpeakers {
                let leftMixer = AVAudioMixerNode()
                let rightMixer = AVAudioMixerNode()
                newEngine.attach(leftMixer)
                newEngine.attach(rightMixer)
                self.leftSpatialMixer = leftMixer
                self.rightSpatialMixer = rightMixer

                var leftLayout = AudioChannelLayout()
                leftLayout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
                leftLayout.mNumberChannelDescriptions = 1
                leftLayout.mChannelDescriptions = AudioChannelDescription(mChannelLabel: kAudioChannelLabel_Left, mChannelFlags: [], mCoordinates: (0,0,0))
                let leftFmt = AVAudioFormat(standardFormatWithSampleRate: mainFormat.sampleRate, channelLayout: AVAudioChannelLayout(layout: &leftLayout))

                var rightLayout = AudioChannelLayout()
                rightLayout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
                rightLayout.mNumberChannelDescriptions = 1
                rightLayout.mChannelDescriptions = AudioChannelDescription(mChannelLabel: kAudioChannelLabel_Right, mChannelFlags: [], mCoordinates: (0,0,0))
                let rightFmt = AVAudioFormat(standardFormatWithSampleRate: mainFormat.sampleRate, channelLayout: AVAudioChannelLayout(layout: &rightLayout))

                newEngine.connect(blend, to: [
                    AVAudioConnectionPoint(node: leftMixer, bus: 0),
                    AVAudioConnectionPoint(node: rightMixer, bus: 0)
                ], fromBus: 0, format: mainFormat)

                newEngine.connect(leftMixer, to: env, fromBus: 0, toBus: 0, format: leftFmt)
                newEngine.connect(rightMixer, to: env, fromBus: 0, toBus: 1, format: rightFmt)
            } else {
                self.leftSpatialMixer = nil
                self.rightSpatialMixer = nil
                let spatialFormat = AVAudioFormat(standardFormatWithSampleRate: mainFormat.sampleRate, channels: 1) ?? mainFormat
                newEngine.connect(blend, to: env, fromBus: 0, toBus: 0, format: spatialFormat)
            }

            applySpatialParameters(to: env, blend: blend)
            newEngine.connect(env, to: newEngine.mainMixerNode, format: mainFormat)
        } else {
            self.leftSpatialMixer = nil
            self.rightSpatialMixer = nil
            newEngine.connect(blend, to: newEngine.mainMixerNode, format: mainFormat)
        }
        newEngine.mainMixerNode.outputVolume = currentUserVolume
        currentEngineSpatial = settings.spatialAudioEnabled
        currentEngineSpatialStereo = settings.spatialStereoSpeakers
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
        slot.cueBaseTime = 0
        slots[0] = slot

        setupEQBands(slots[0].eqNode)
        setupEQBands(slots[1].eqNode)
        setupEffects(&slots[0])
        setupEffects(&slots[1])
        slots[1].mixerNode.outputVolume = 0

        if let start = effectiveStartTime {
            let startFrame = AVAudioFramePosition(start * format.sampleRate)
            let maxFrame: AVAudioFramePosition
            if let dur = effectiveDuration, dur > 0, track.cueStartTime == nil {
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

        slots[0].playerNode.volume = 1.0
        slots[0].mixerNode.outputVolume = finalGain

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
            lastPlayTime = Date()
            completionHandler = completion
            engine = newEngine

            installTapOnce()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                MainActor.assumeIsolated {
                    self?.applyVolume()
                }
            }
        } catch {
            for s in slots { s.playerNode.stop() }
            newEngine.stop()
            slots.removeAll()
            engine = nil
            completion()
            return
        }
    }

    private func installTapOnce() {
        guard let engine = engine, engine.isRunning else { return }
        guard let blend = blendMixer else { return }

        blend.removeTap(onBus: 0)
        engine.mainMixerNode.removeTap(onBus: 0)

        let needVis = VisualizationEngine.shared.mode != .off
        let needSil = settings.silenceSkipEnabled
        guard needVis || needSil else { return }

        let format = blend.outputFormat(forBus: 0)
        // Защита: частота дискретизации и количество каналов должны быть строго положительными,
        // иначе CoreAudio аварийно завершает приложение (NSException в installTap).
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        VisualizationEngine.shared.currentSampleRate = format.sampleRate

        // ⚠️ @Sendable — обязательно. Без него closure наследует @MainActor
        // от installTapOnce, и AVFAudio вызовет его на realtime-очереди → краш
        // "dispatch_assert_queue_fail" (проверено на macOS 26 / Swift 6).
        let isProcessing = OSAllocatedUnfairLock(initialState: false)
        blend.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format
        ) { @Sendable [weak self, isProcessing] buffer, _ in
            let acquired = isProcessing.withLock { busy -> Bool in
                if busy { return false }
                busy = true
                return true
            }
            guard acquired else { return }
            guard let samples = AudioPlayerService.extractMonoSamples(from: buffer) else {
                isProcessing.withLock { $0 = false }
                return
            }
            DispatchQueue.main.async { [weak self] in
                defer { isProcessing.withLock { $0 = false } }
                MainActor.assumeIsolated {
                    self?.handleAudioSamples(samples)
                }
            }
        }
    }
    private func applySpatialParameters(to env: AVAudioEnvironmentNode, blend: AVAudioMixerNode) {
        let algorithm: AVAudio3DMixingRenderingAlgorithm = {
            switch settings.spatialAlgorithm {
            case "equalPower": return .equalPowerPanning
            case "spherical":  return .sphericalHead
            case "hrtfHQ":     return .HRTFHQ
            case "soundField": return .soundField
            default:           return .HRTF
            }
        }()

        let halfSpread = max(0.2, settings.spatialSpeakerSpread / 2.0)
        let zPos = -max(0.1, settings.spatialDistance)

        if settings.spatialStereoSpeakers,
           let leftNode = leftSpatialMixer,
           let rightNode = rightSpatialMixer {
            if let destL = leftNode.destination(forMixer: env, bus: 0) {
                destL.renderingAlgorithm = algorithm
                destL.position = AVAudio3DPoint(
                    x: settings.spatialPan - halfSpread,
                    y: settings.spatialElevation,
                    z: zPos
                )
                destL.reverbBlend = settings.spatialReverbBlend / 100.0
                destL.obstruction = settings.spatialObstruction
                destL.occlusion = settings.spatialOcclusion
            }
            if let destR = rightNode.destination(forMixer: env, bus: 1) {
                destR.renderingAlgorithm = algorithm
                destR.position = AVAudio3DPoint(
                    x: settings.spatialPan + halfSpread,
                    y: settings.spatialElevation,
                    z: zPos
                )
                destR.reverbBlend = settings.spatialReverbBlend / 100.0
                destR.obstruction = settings.spatialObstruction
                destR.occlusion = settings.spatialOcclusion
            }
        } else if let dest = blend.destination(forMixer: env, bus: 0) {
            dest.renderingAlgorithm = algorithm
            dest.position = AVAudio3DPoint(
                x: settings.spatialPan,
                y: settings.spatialElevation,
                z: zPos
            )
            dest.reverbBlend = settings.spatialReverbBlend / 100.0
            dest.obstruction = settings.spatialObstruction
            dest.occlusion = settings.spatialOcclusion
        }

        env.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        env.distanceAttenuationParameters.referenceDistance = 1.0
        env.distanceAttenuationParameters.maximumDistance = 50.0
        env.distanceAttenuationParameters.rolloffFactor = settings.spatialRolloff

        if settings.spatialRoomPreset != "off", let preset = parseSpatialReverbPreset(settings.spatialRoomPreset) {
            env.reverbParameters.enable = true
            env.reverbParameters.loadFactoryReverbPreset(preset)
            env.reverbParameters.level = 0
        } else {
            env.reverbParameters.enable = false
        }
    }

    private func parseSpatialReverbPreset(_ name: String) -> AVAudioUnitReverbPreset? {
        switch name {
        case "smallRoom": return .smallRoom
        case "mediumRoom": return .mediumRoom
        case "largeRoom": return .largeRoom
        case "mediumHall": return .mediumHall
        case "largeHall": return .largeHall
        case "longHall": return .largeHall2
        case "cathedral": return .cathedral
        case "plate": return .plate
        default: return nil
        }
    }

    private func reapplySpatialSettings() {
        let spatialNeedsRebuild = settings.spatialAudioEnabled != currentEngineSpatial ||
            (currentEngineSpatial && settings.spatialStereoSpeakers != currentEngineSpatialStereo)

        if !spatialNeedsRebuild {
            if currentEngineSpatial,
               let blend = blendMixer,
               let env = environmentNode {
                applySpatialParameters(to: env, blend: blend)
            }
            return
        }

        guard !slots.isEmpty,
              activeSlot >= 0, activeSlot < slots.count,
              let track = slots[activeSlot].track else { return }

        let wasPlaying = isPlaying
        let pos = currentTime
        // Сохраняем текущий completionHandler — это то же замыкание, что было
        // установлено через PlayerViewModel.play(_:afterFinish:) для продолжения
        // воспроизведения после конца трека.
        let savedCompletion = completionHandler

        play(track, startTime: pos, autoplay: wasPlaying) {
            savedCompletion?()
        }
    }

    /// Извлекает моно-семплы из аудио-буфера. Вызывается на аудио-потоке,
    /// возвращает Sendable [Float] — можно безопасно передавать на main.
    nonisolated private static func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            var sum: Float = 0
            for ch in 0..<channelCount {
                sum += channelData[ch][i]
            }
            mono[i] = sum / Float(channelCount)
        }
        return mono
    }

    /// Обработка семплов на main — visualization + silence skip.
    private func handleAudioSamples(_ samples: [Float]) {
        if VisualizationEngine.shared.isRunning {
            VisualizationEngine.shared.processSamples(samples)
        }
        if settings.silenceSkipEnabled {
            analyzeSamples(samples)
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
        rgRampTask?.cancel()
        rgRampTask = nil
        stopCrossfade()
        stopDisplayLink()
        for slot in slots {
            slot.playerNode.stop()
            slot.playerNode.reset()
            slot.reverbNode.reset()
            slot.delayNode.reset()
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
        guard time.isFinite, time >= 0 else { return }
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
        if let cueStart = slot.track?.cueStartTime {
            effectiveTime = max(0, cueStart + time)
        } else {
            effectiveTime = max(0, time)
        }

        let frame = AVAudioFramePosition(max(0, effectiveTime * slot.sampleRate))
        let startFrame = max(0, min(frame, slot.fileLength))

        let maxFrame: AVAudioFramePosition
        if let t = slot.track, t.cueStartTime == nil, t.duration > 0 {
            let endFrame = AVAudioFramePosition(t.duration * slot.sampleRate)
            maxFrame = min(endFrame, slot.fileLength)
        } else {
            maxFrame = slot.fileLength
        }
        let remaining = maxFrame - startFrame

        guard remaining > 0 else {
            isSeeking = false
            handlePlaybackComplete()
            return
        }

        currentTime = time

        var updatedSlot = slots[activeSlot]
        updatedSlot.cueSeekTime = time
        updatedSlot.cueBaseTime = 0
        updatedSlot.seekOffset = effectiveTime
        slots[activeSlot] = updatedSlot

        silenceDetected = false
        silenceStartTime = nil
        lastPreloadTrackId = nil

        slot.playerNode.stop()
        slot.playerNode.reset()
        slot.reverbNode.reset()
        slot.delayNode.reset()
        slot.playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
        // [PATCH] raw + mixer
        slot.playerNode.volume = 1.0
        slot.mixerNode.outputVolume = slot.rgLinearGain

        if wasPlaying { slot.playerNode.play() }
        isFinishingNormally = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self = self, self.seekGeneration == myGen else { return }
                self.isSeeking = false
            }
        }
    }

    func setVolume(_ volume: Float) { currentUserVolume = volume; applyVolume() }

    private func applyVolume() {
        engine?.mainMixerNode.outputVolume = currentUserVolume
    }

    private func applySlotGain() {
        guard !slots.isEmpty,
              activeSlot >= 0,
              activeSlot < slots.count else { return }
        guard !crossfadeStarted else { return }
        slots[activeSlot].playerNode.volume = 1.0
        slots[activeSlot].mixerNode.outputVolume = slots[activeSlot].rgLinearGain
    }

    func applyCurrentRG() {
        guard !crossfadeStarted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    self?.applyCurrentRG()
                }
            }
            return
        }
        guard !slots.isEmpty, activeSlot >= 0, activeSlot < slots.count else { return }
        guard let track = slots[activeSlot].track else { return }
        let newGain = computeRGGain(for: track)
        slots[activeSlot].rgLinearGain = newGain
        applySlotGain()
        if let preIdx = preloadedSlot, preIdx < slots.count, let preTrack = slots[preIdx].track {
            slots[preIdx].rgLinearGain = computeRGGain(for: preTrack)
        }
        triggerAutoVolumeLevelingIfNeeded(for: track)
    }

    // MARK: - Preload

    func preloadNextTrack(_ track: Track, volume: Float? = nil, completion: @escaping () -> Void) {
        guard !crossfadeStarted,
              !isSeeking,
              !isFinishingNormally,
              !switchingTrack else { return }

        guard engine?.isRunning == true, slots.count == 2 else {
            completion()
            return
        }

        let nextIndex = activeSlot == 0 ? 1 : 0
        if let preIdx = preloadedSlot, preIdx == nextIndex, slots[nextIndex].isPreloaded, slots[nextIndex].track?.id == track.id {
            return
        }
        
        let now = Date()
        if lastPreloadTrackId == track.id && now.timeIntervalSince(lastPreloadTime) < 0.5 {
            return
        }
        lastPreloadTrackId = track.id
        lastPreloadTime = now
        
        let myPlayGen = playGeneration

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

        if settings.autoVolumeLevelingEnabled {
            let needsAuto: Bool
            if settings.rgMode == "off" {
                needsAuto = true
            } else {
                let hasRG = (settings.rgMode == "album" ? (track.replayGainAlbum ?? track.replayGain) : (track.replayGain ?? track.replayGainAlbum)) != nil
                needsAuto = !hasRG
            }

            if needsAuto && AutoVolumeLevelingService.shared.getCachedLoudness(for: track) == nil {
                let trackId = track.id
                AutoVolumeLevelingService.shared.requestLoudness(for: track) { [weak self] _ in
                    guard let self = self else { return }
                    if let preIdx = self.preloadedSlot, preIdx < self.slots.count, self.slots[preIdx].track?.id == trackId {
                        self.slots[preIdx].rgLinearGain = self.computeRGGain(for: track)
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            let boxed: SendableAudioFile? = await Task.detached(priority: .userInitiated) {
                guard let file = try? AVAudioFile(forReading: realURL) else { return nil }
                return SendableAudioFile(file: file)
            }.value

            guard let self = self, let boxed = boxed else {
                self?.preloadRequested = false
                return
            }

            self.applyPreload(
                audioFile: boxed.file,
                track: track,
                preloadStartTime: preloadStartTime,
                myPlayGen: myPlayGen,
                volume: volume,
                completion: completion
            )
        }
    }

    private func applyPreload(
        audioFile: AVAudioFile,
        track: Track,
        preloadStartTime: TimeInterval?,
        myPlayGen: Int,
        volume: Float?,
        completion: @escaping () -> Void
    ) {
        guard playGeneration == myPlayGen,
              let engine = self.engine,
              engine.isRunning,
              slots.count == 2,
              !crossfadeStarted,
              !switchingTrack,
              !isFinishingNormally else {
            preloadRequested = false
            return
        }

        let nextIndex = activeSlot == 0 ? 1 : 0
        if let preIdx = preloadedSlot, preIdx == nextIndex, slots[nextIndex].isPreloaded, slots[nextIndex].track?.id == track.id {
            preloadRequested = false
            return
        }
        let newFormat = audioFile.processingFormat
        
        var slot = slots[nextIndex]
        
        slot.playerNode.stop()
        slot.playerNode.reset()
        
        slot.eqNode.reset()
        slot.reverbNode.reset()
        slot.delayNode.reset()
        
        let finalGain = computeRGGain(for: track)
        
        slot.format = newFormat
        slot.track = track
        slot.file = audioFile
        slot.fileLength = audioFile.length
        slot.sampleRate = newFormat.sampleRate
        slot.rgLinearGain = finalGain
        slot.isPreloaded = true
        slot.cueSeekTime = 0
        setupEQBands(slot.eqNode)
        setupEffects(&slot)
        
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
                slot.playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: safeFrameCount, at: nil, completionHandler: nil)
                slot.seekOffset = start
            } else {
                slot.playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
                slot.seekOffset = 0
            }
        } else {
            slot.playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
            slot.seekOffset = 0
        }
        
        // [PATCH] raw + mixer, mixer в 0 до момента перехода
        slot.playerNode.volume = 1.0
        slot.mixerNode.outputVolume = 0
        
        slots[nextIndex] = slot
        
        preloadedSlot = nextIndex
        nextCompletion = completion
        preloadRequested = false
        if let vol = volume { currentUserVolume = vol; applyVolume() }
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

        let oldMaxTime: Double = {
            if let t = oldSlot.track, t.cueStartTime != nil, t.duration > 0 {
                return t.duration
            }
            return Double(oldSlot.fileLength) / oldSlot.sampleRate
        }()
        let remainingOld = oldMaxTime - currentTime

        guard remainingOld > 0.5,
              remainingOld <= settings.crossfadeDuration + 1.0,
              currentTime >= min(2.0, oldMaxTime * 0.2) else {
            slots[nextIndex].playerNode.stop()
            slots[nextIndex].mixerNode.outputVolume = 0
            slots[nextIndex].isPreloaded = false
            preloadedSlot = nil
            nextCompletion = nil
            preloadRequested = false
            return false
        }

        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeTimeoutWorkItem?.cancel()
        crossfadeTimeoutWorkItem = nil

        let nextMaxTime: Double = {
            if let t = newSlot.track, t.cueStartTime != nil, t.duration > 0 {
                return t.duration
            }
            return Double(newSlot.fileLength) / newSlot.sampleRate
        }()
        let maxByNext = max(0.3, nextMaxTime / 3)
        let duration = min(settings.crossfadeDuration, remainingOld, maxByNext)

        crossfadeStarted = true
        isFinishingNormally = true
        switchingTrack = true
        let savedNextIndex = nextIndex

        if let newTrack = newSlot.track {
            NotificationCenter.default.post(name: .crossfadeStarted, object: newTrack)
        }

        self.currentTime = 0

        newSlot.playerNode.volume = 1.0
        newSlot.mixerNode.outputVolume = 0
        newSlot.playerNode.play()

        let startTime = Date()
        crossfadeStartTime = startTime

        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.crossfadeStarted else {
                    self?.crossfadeTimer?.invalidate()
                    return
                }
                guard oldIndex < self.slots.count,
                      savedNextIndex < self.slots.count else {
                    self.crossfadeTimer?.invalidate()
                    return
                }

                let oldSlot = self.slots[oldIndex]
                let newSlot = self.slots[savedNextIndex]

                let oldTarget = oldSlot.rgLinearGain
                let newTarget = newSlot.rgLinearGain

                let elapsed = Date().timeIntervalSince(startTime)
                let progress = Float(min(elapsed / duration, 1.0))

                oldSlot.playerNode.volume = 1.0
                newSlot.playerNode.volume = 1.0
                oldSlot.mixerNode.outputVolume = oldTarget * (1.0 - progress)
                newSlot.mixerNode.outputVolume = newTarget * progress

                if progress >= 1.0 {
                    self.crossfadeTimer?.invalidate()
                    self.crossfadeTimer = nil
                    oldSlot.playerNode.stop()
                    oldSlot.mixerNode.outputVolume = 0

                    self.activeSlot = savedNextIndex
                    self.preloadedSlot = nil
                    self.crossfadeStarted = false
                    self.isFinishingNormally = false
                    self.switchingTrack = false
                    self.lastPlayTime = Date()
                    self.completionHandler = self.nextCompletion
                    self.nextCompletion = nil

                    if let newTrack = newSlot.track {
                        NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                    }

                    self.applyVolume()
                    if !self.slots[self.activeSlot].playerNode.isPlaying {
                        self.slots[self.activeSlot].playerNode.play()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer

        crossfadeTimeoutWorkItem?.cancel()
        let timeoutItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.crossfadeStarted,
                      self.isPlaying else { return }
                self.forceCompleteCrossfade(oldIndex: oldIndex, newIndex: savedNextIndex)
            }
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

        let newVolumeAtStart = newSlot.mixerNode.outputVolume
        let newTargetVolume = newSlot.rgLinearGain

        let remainingProgress = newTargetVolume > 0 ? 1.0 - (newVolumeAtStart / newTargetVolume) : 0
        let remainingDuration = savedCrossfadeRemaining > 0
            ? savedCrossfadeRemaining
            : max(0.1, settings.crossfadeDuration * Double(remainingProgress))

        let startTime = Date()
        crossfadeStartTime = startTime

        if newTargetVolume > 0 {
            let frac = newVolumeAtStart / newTargetVolume
            self.currentTime = max(0, settings.crossfadeDuration * Double(frac))
        } else {
            self.currentTime = 0
        }

        crossfadeTimer?.invalidate()

        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.crossfadeStarted else {
                    self?.crossfadeTimer?.invalidate()
                    return
                }
                guard oldIndex < self.slots.count,
                      newIndex < self.slots.count else {
                    self.crossfadeTimer?.invalidate()
                    return
                }

                let oldSlot = self.slots[oldIndex]
                let newSlot = self.slots[newIndex]

                let oldTarget = oldSlot.rgLinearGain
                let newTarget = newSlot.rgLinearGain

                let elapsed = Date().timeIntervalSince(startTime)
                let progress = Float(min(elapsed / remainingDuration, 1.0))

                oldSlot.playerNode.volume = 1.0
                newSlot.playerNode.volume = 1.0
                oldSlot.mixerNode.outputVolume = oldTarget * (1.0 - progress)
                newSlot.mixerNode.outputVolume = newVolumeAtStart + (newTarget - newVolumeAtStart) * progress

                if progress >= 1.0 {
                    self.crossfadeTimer?.invalidate()
                    self.crossfadeTimer = nil
                    oldSlot.playerNode.stop()
                    oldSlot.mixerNode.outputVolume = 0
                    self.activeSlot = newIndex
                    self.preloadedSlot = nil
                    self.crossfadeStarted = false
                    self.isFinishingNormally = false
                    self.switchingTrack = false
                    self.completionHandler = self.nextCompletion
                    self.nextCompletion = nil

                    self.lastPlayTime = Date()

                    if let newTrack = newSlot.track {
                        NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                    }

                    self.applyVolume()
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
            slots[nextIdx].mixerNode.outputVolume = slots[nextIdx].rgLinearGain
            if !slots[nextIdx].playerNode.isPlaying {
                slots[nextIdx].playerNode.play()
            }
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
        cancelActiveCrossfade()
    }

    func cancelActiveCrossfade() {
        rgRampTask?.cancel()
        rgRampTask = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeTimeoutWorkItem?.cancel()
        crossfadeTimeoutWorkItem = nil
        crossfadeStarted = false
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0
        switchingTrack = false
        isFinishingNormally = false

        // Ensure active slot is restored to full target volume
        if activeSlot >= 0, activeSlot < slots.count {
            let active = slots[activeSlot]
            active.playerNode.volume = 1.0
            active.mixerNode.outputVolume = active.rgLinearGain
        }

        // Clean up secondary slot if it was preloaded or crossfading
        if let nextIdx = preloadedSlot, nextIdx < slots.count, nextIdx != activeSlot {
            slots[nextIdx].playerNode.stop()
            slots[nextIdx].mixerNode.outputVolume = 0
            slots[nextIdx].isPreloaded = false
        }
        preloadedSlot = nil
        preloadRequested = false
        nextCompletion = nil
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
            slots[newIndex].mixerNode.outputVolume = slots[newIndex].rgLinearGain
        }

        activeSlot = newIndex
        currentTime = 0
        // [PATCH] installMainMixerTap() — УБРАНО
        preloadedSlot = nil
        crossfadeStarted = false
        isFinishingNormally = false
        switchingTrack = false
        lastPlayTime = Date()
        completionHandler = nextCompletion
        nextCompletion = nil
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0

        if newIndex >= 0, newIndex < slots.count, let newTrack = slots[newIndex].track {
            NotificationCenter.default.post(name: .trackChanged, object: newTrack)
        }
    }

    // MARK: - EQ
    private func setupEffects(_ slot: inout PlayerSlot) {
        let effects = AudioEffectsManager.shared

        // Reverb
        if effects.reverbPreset == "off" || effects.reverbWetDry <= 0 {
            slot.reverbNode.wetDryMix = 0
        } else {
            if let preset = Self.reverbPreset(from: effects.reverbPreset) {
                slot.reverbNode.loadFactoryPreset(preset)
            }
            slot.reverbNode.wetDryMix = effects.reverbWetDry
        }

        // Delay
        slot.delayNode.delayTime = TimeInterval(effects.delayTime)
        slot.delayNode.feedback = effects.delayFeedback
        slot.delayNode.lowPassCutoff = effects.delayLowPassCutoff
        slot.delayNode.wetDryMix = effects.delayEnabled ? effects.delayWetDry : 0
    }

    private func updateAllEffects() {
        for i in slots.indices {
            setupEffects(&slots[i])
        }
    }

    private static func reverbPreset(from id: String) -> AVAudioUnitReverbPreset? {
        switch id {
        case "smallRoom":   return .smallRoom
        case "mediumRoom":  return .mediumRoom
        case "largeRoom":   return .largeRoom
        case "mediumHall":  return .mediumHall
        case "largeHall":   return .largeHall
        case "plate":       return .plate
        case "cathedral":   return .cathedral
        default:            return nil
        }
    }

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
            MainActor.assumeIsolated {
                guard let self = self, self.engine?.isRunning == true, self.isPlaying else { return }

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
                        return (readingSlot.cueSeekTime ?? 0) + max(0, segmentTime - readingSlot.cueBaseTime)
                    }
                    return readingSlot.seekOffset + segmentTime
                }()

                guard let rawTime else { return }

                let timeSincePlay = Date().timeIntervalSince(self.lastPlayTime)
                let timeSinceSeek = Date().timeIntervalSince(self.lastSeekTime)
                let transitionGraceActive = timeSincePlay < 1.0 || timeSinceSeek < 1.2

                // Filter out stale CoreAudio render timestamps during rapid transitions
                if timeSincePlay < 0.6 && readingSlot.seekOffset == 0 && readingSlot.cueSeekTime == 0 && rawTime > 2.0 {
                    return
                }

                let maxTimeForSlot: Double = {
                    if let t = readingSlot.track, t.cueStartTime != nil, t.duration > 0 {
                        return t.duration
                    }
                    return Double(readingSlot.fileLength) / readingSlot.sampleRate
                }()

                let currentTimeValue = max(0, min(rawTime, maxTimeForSlot))
                self.currentTime = currentTimeValue

                if !self.crossfadeStarted && !self.isSeeking && self.isPlaying && !transitionGraceActive {
                    let activeSlot = self.slots[self.activeSlot]
                    let maxTime: Double
                    if let track = activeSlot.track, track.cueStartTime != nil, track.duration > 0 {
                        maxTime = track.duration
                    } else {
                        maxTime = Double(activeSlot.fileLength) / activeSlot.sampleRate
                    }
                    let remaining = maxTime - currentTimeValue

                    if self.settings.crossfadeEnabled && remaining <= (self.settings.crossfadeDuration + 5.0) && self.preloadedSlot == nil && !self.preloadRequested {
                        self.preloadRequested = true
                        NotificationCenter.default.post(name: .prepareNextTrack, object: nil)
                    }
                    if self.settings.gaplessEnabled && remaining <= 3.0 && self.preloadedSlot == nil && !self.preloadRequested {
                        self.preloadRequested = true
                        NotificationCenter.default.post(name: .prepareNextTrack, object: nil)
                    }
                    if self.settings.crossfadeEnabled &&
                       remaining <= self.settings.crossfadeDuration &&
                       currentTimeValue >= min(2.0, maxTime * 0.2) &&
                       self.preloadedSlot != nil {
                        self.startCrossfade()
                    }

                    if currentTimeValue >= maxTime - 0.02 && self.isPlaying && !self.isSeeking && !self.isFinishingNormally {
                        self.handlePlaybackComplete()
                    }
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


    private func isConsecutiveCUE(current: Track?, next: Track?) -> Bool {
        guard let current, let next else { return false }
        guard let curCue = current.cueStartTime, let nextCue = next.cueStartTime else { return false }
        let curPath = current.url.deletingPathExtension().path
        let nextPath = next.url.deletingPathExtension().path
        guard current.url.path == next.url.path || curPath == nextPath else { return false }
        return abs((curCue + current.duration) - nextCue) < 0.25
    }

    private func handlePlaybackComplete() {
        guard !isFinishingNormally else { return }
        isFinishingNormally = true

        if let nextIndex = preloadedSlot, nextIndex < slots.count, slots[nextIndex].isPreloaded {
            if settings.crossfadeEnabled {
                if startCrossfade() { return }
            } else {
                let oldIndex = activeSlot
                let oldSlot = slots[oldIndex]
                let newSlot = slots[nextIndex]
                guard let engine = engine, engine.isRunning else { return }

                if isConsecutiveCUE(current: oldSlot.track, next: newSlot.track) {
                    let currentSegmentTime: Double = {
                        if let nodeTime = engine.outputNode.lastRenderTime,
                           let playerTime = oldSlot.playerNode.playerTime(forNodeTime: nodeTime) {
                            let seg = Double(playerTime.sampleTime) / playerTime.sampleRate
                            if !seg.isNaN && !seg.isInfinite && seg >= 0 {
                                return seg
                            }
                        }
                        return oldSlot.cueBaseTime + (oldSlot.track?.duration ?? 0)
                    }()

                    var updatedOldSlot = oldSlot
                    guard let nextTrack = newSlot.track else { return }
                    updatedOldSlot.track = nextTrack
                    updatedOldSlot.cueBaseTime = currentSegmentTime
                    updatedOldSlot.cueSeekTime = 0
                    let finalGain = computeRGGain(for: nextTrack)
                    updatedOldSlot.rgLinearGain = finalGain
                    updatedOldSlot.mixerNode.outputVolume = finalGain
                    slots[oldIndex] = updatedOldSlot

                    slots[nextIndex].playerNode.stop()
                    slots[nextIndex].mixerNode.outputVolume = 0
                    slots[nextIndex].isPreloaded = false
                    preloadedSlot = nil
                    preloadRequested = false
                    lastPreloadTrackId = nil

                    currentTime = 0
                    isPlaying = true
                    intendedPlaying = true
                    isFinishingNormally = false
                    completionHandler = nextCompletion
                    nextCompletion = nil

                    NotificationCenter.default.post(name: .trackChanged, object: nextTrack)
                    return
                }

                // [PATCH] Настоящий gapless через play(at:) — без дырки
                newSlot.playerNode.volume = 1.0
                newSlot.mixerNode.outputVolume = newSlot.rgLinearGain
                newSlot.playerNode.play()

                // Старую ноду гасим через 20 мс — новая уже рендерится,
                // а на слух наложения нет.
                let savedOldTrackId = oldSlot.track?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard oldIndex >= 0, oldIndex < self.slots.count else { return }
                        if let savedOldTrackId, self.slots[oldIndex].track?.id != savedOldTrackId { return }
                        self.slots[oldIndex].playerNode.stop()
                        self.slots[oldIndex].mixerNode.outputVolume = 0
                    }
                }

                activeSlot = nextIndex
                preloadedSlot = nil
                preloadRequested = false
                lastPreloadTrackId = nil
                currentTime = 0
                lastPlayTime = Date()
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
                slots[activeSlot].reverbNode.reset()
                slots[activeSlot].delayNode.reset()
                slots[activeSlot].mixerNode.outputVolume = 0
            }
            isPlaying = false
            intendedPlaying = false
            currentTime = 0
            isFinishingNormally = false
        }
    }

    // MARK: - Silence Detection

    private func analyzeSamples(_ samples: [Float]) {
        guard settings.silenceSkipEnabled || VisualizationEngine.shared.isRunning else { return }
        guard settings.silenceSkipEnabled, isPlaying, !isSeeking, !crossfadeStarted, !settings.gaplessEnabled else { return }

        let count = samples.count
        guard count > 0 else { return }

        var sum: Float = 0
        for s in samples {
            sum += s * s
        }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.000001))
        let threshold = Float(settings.silenceSkipThreshold)

        // Уже на main (handleAudioSamples вызывается из MainActor Task) — не нужен async.
        if db < threshold {
            if !silenceDetected {
                silenceDetected = true
                silenceStartTime = Date()
            } else if let start = silenceStartTime {
                let duration = Date().timeIntervalSince(start)
                if duration >= silenceMinDuration { handleSilenceDetected() }
            }
        } else {
            if silenceDetected {
                silenceDetected = false
                silenceStartTime = nil
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
