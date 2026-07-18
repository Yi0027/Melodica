// Services,AudioPlayerService.swift
import AVFoundation
import Combine

extension Notification.Name {
    static let eqDidChange = Notification.Name("eqDidChange")
    static let progressIntervalChanged = Notification.Name("progressIntervalChanged")
    static let trackChanged = Notification.Name("trackChanged")
    static let prepareNextTrack = Notification.Name("prepareNextTrack")
}

final class AudioPlayerService: NSObject, ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    
    private var engine: AVAudioEngine?
    private var displayLink: DispatchSourceTimer?
    private var completionHandler: (() -> Void)?
    private var currentUserVolume: Float = 0.5
    private var seekOffset: TimeInterval = 0
    private var isSeeking = false
    private var isFinishingNormally = false
    private var crossfadeStarted = false
    private var crossfadeTimer: Timer?
    private var crossfadeStartTime: Date?       // ← добавить
    private var savedCrossfadeRemaining: TimeInterval = 0  // ← добавить
    
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
    
    // RG константы
    private let maxAllowedGain: Float = 4.0
    private let rgReferenceGain: Float = 1.0
    
    private struct PlayerSlot {
        let playerNode: AVAudioPlayerNode
        let eqNode: AVAudioUnitEQ
        var track: Track?
        var file: AVAudioFile?
        var fileLength: AVAudioFramePosition = 0
        var sampleRate: Double = 44100
        var rgLinearGain: Float = 1.0
        var isPreloaded = false
        var format: AVAudioFormat?
    }
    
    override init() {
        super.init()
        setupEngine()
        setupNotifications()
    }
    
    private func setupEngine() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }
        for _ in 0..<2 {
            let playerNode = AVAudioPlayerNode()
            let eqNode = AVAudioUnitEQ(numberOfBands: 10)
            engine.attach(playerNode)
            engine.attach(eqNode)
            let slot = PlayerSlot(playerNode: playerNode, eqNode: eqNode)
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
            guard let self = self else { return }
            self.recreateEngine()
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
        let finalGain = min(safeGain, maxAllowedGain) * rgReferenceGain
        
        return finalGain
    }
    
    // MARK: - Recreate Engine
    
    private func recreateEngine() {
        let currentTrack = slots[activeSlot].track
        let currentTime = self.currentTime
        let wasPlaying = isPlaying
        
        // Приглушаем громкость мгновенно
        let savedVolume = currentUserVolume
        currentUserVolume = 0
        applyVolume()
        
        stopCrossfade()
        stopDisplayLink()
        for slot in slots { slot.playerNode.stop() }
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        slots.removeAll()
        
        isPlaying = false
        silenceDetected = false
        silenceStartTime = nil
        
        guard let track = currentTrack else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.play(track, volume: savedVolume) {}
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if currentTime > 0 {
                    self.seek(to: currentTime)
                }
                if !wasPlaying {
                    self.pause()
                }
                // Возвращаем громкость
                self.currentUserVolume = savedVolume
                self.applyVolume()
            }
        }
    }
    
    func clearPreload() {
        if let idx = preloadedSlot {
            slots[idx].playerNode.stop()
            slots[idx].isPreloaded = false
            preloadedSlot = nil
            nextCompletion = nil
            preloadRequested = false
        }
        
        if isFinishingNormally && isPlaying {
            isFinishingNormally = false
            let slot = slots[activeSlot]
            let maxTime = Double(slot.fileLength) / slot.sampleRate
            if currentTime >= maxTime - 0.5 {
                handlePlaybackComplete()
            }
        }
    }
    func play(_ track: Track, volume: Float? = nil, startTime: TimeInterval? = nil, completion: @escaping () -> Void) {
        stopCrossfade()
        stopDisplayLink()
        completionHandler = nil
        nextCompletion = nil
        switchingTrack = false  // ← ВАЖНО: сбрасываем флаг переключения
        
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
        
        if let vol = volume { currentUserVolume = vol }
        
        let finalGain = computeRGGain(for: track)
        
        guard let audioFile = try? AVAudioFile(forReading: track.url) else { completion(); return }
        let format = audioFile.processingFormat
        
        let newEngine = AVAudioEngine()
        
        let playerNode = AVAudioPlayerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 10)
        newEngine.attach(playerNode)
        newEngine.attach(eqNode)
        newEngine.connect(playerNode, to: eqNode, format: format)
        newEngine.connect(eqNode, to: newEngine.mainMixerNode, format: format)
        
        let slot = PlayerSlot(playerNode: playerNode, eqNode: eqNode)
        slots.append(slot)
        activeSlot = 0
        
        let playerNode2 = AVAudioPlayerNode()
        let eqNode2 = AVAudioUnitEQ(numberOfBands: 10)
        newEngine.attach(playerNode2)
        newEngine.attach(eqNode2)
        newEngine.connect(playerNode2, to: eqNode2, format: format)
        newEngine.connect(eqNode2, to: newEngine.mainMixerNode, format: format)
        let slot2 = PlayerSlot(playerNode: playerNode2, eqNode: eqNode2)
        slots.append(slot2)
        
        slots[0].track = track
        slots[0].file = audioFile
        slots[0].fileLength = audioFile.length
        slots[0].sampleRate = format.sampleRate
        slots[0].rgLinearGain = finalGain
        slots[0].isPreloaded = true
        slots[0].format = format
        
        setupEQBands(slots[0].eqNode)
        setupEQBands(slots[1].eqNode)
        
        if let startTime = startTime, startTime > 0 {
            let startFrame = AVAudioFramePosition(startTime * format.sampleRate)
            let remaining = audioFile.length - startFrame
            if remaining > 0 {
                slots[0].playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
                seekOffset = startTime
            } else {
                slots[0].playerNode.scheduleFile(audioFile, at: nil)
                seekOffset = 0
            }
        } else {
            slots[0].playerNode.scheduleFile(audioFile, at: nil)
            seekOffset = 0
        }
        
        slots[0].playerNode.volume = currentUserVolume * finalGain
        
        do {
            try newEngine.start()
            slots[0].playerNode.play()
            isPlaying = true
            currentTime = startTime ?? 0
            completionHandler = completion
            engine = newEngine
            startDisplayLink()
            startSilenceDetection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in self?.applyVolume() }
        } catch {
            completion()
        }
    }
    
    func pause() {
        // Сначала останавливаем таймер
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        
        // Сохраняем состояние кроссфейда
        if crossfadeStarted {
            if let startTime = crossfadeStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                savedCrossfadeRemaining = max(0.1, settings.crossfadeDuration - elapsed)
            }
        }
        
        // Паузим все слоты
        for slot in slots {
            slot.playerNode.pause()
        }
        
        isPlaying = false
        stopDisplayLink()
    }

    func resume() {
        guard let engine = engine, engine.isRunning else { return }
        
        if crossfadeStarted {
            let oldIndex = activeSlot
            let newIndex = activeSlot == 0 ? 1 : 0
            
            let oldSlot = slots[oldIndex]
            let newSlot = slots[newIndex]
            
            // Запускаем оба слота
            oldSlot.playerNode.play()
            newSlot.playerNode.play()
            isPlaying = true
            startDisplayLink()
            
            let oldTargetVolume = currentUserVolume * oldSlot.rgLinearGain
            let newTargetVolume = currentUserVolume * newSlot.rgLinearGain
            
            // Берём текущие громкости (они сохранились с паузы)
            let currentOldVolume = oldSlot.playerNode.volume
            let currentNewVolume = newSlot.playerNode.volume
            
            // Сколько осталось для newSlot
            let newProgress = newTargetVolume > 0 ? currentNewVolume / newTargetVolume : 0
            let remainingDuration = savedCrossfadeRemaining
            
            let startTime = Date()
            var completed = false
            
            crossfadeTimer?.invalidate()
            crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self = self, self.crossfadeStarted && !completed else {
                    timer.invalidate()
                    return
                }
                
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = Float(min(elapsed / remainingDuration, 1.0))
                
                // Старый слот: от текущей громкости до 0
                oldSlot.playerNode.volume = currentOldVolume * (1.0 - progress)
                // Новый слот: от текущей громкости до целевой
                newSlot.playerNode.volume = currentNewVolume + (newTargetVolume - currentNewVolume) * progress
                
                if progress >= 1.0 {
                    completed = true
                    timer.invalidate()
                    self.crossfadeTimer = nil
                    oldSlot.playerNode.stop()
                    self.activeSlot = newIndex
                    self.preloadedSlot = nil
                    self.seekOffset = 0
                    self.crossfadeStarted = false
                    self.isFinishingNormally = false
                    self.switchingTrack = false
                    self.completionHandler = self.nextCompletion
                    self.nextCompletion = nil
                    self.crossfadeStartTime = nil
                    self.savedCrossfadeRemaining = 0
                }
            }
        } else {
            slots[activeSlot].playerNode.play()
            isPlaying = true
            startDisplayLink()
            applyVolume()
        }
    }
    func stop() {
        stopCrossfade()
        stopDisplayLink()
        for slot in slots { slot.playerNode.stop() }
        engine?.mainMixerNode.removeTap(onBus: 0)
        engine?.stop()
        isPlaying = false; currentTime = 0; seekOffset = 0
        silenceDetected = false; silenceStartTime = nil
    }
    
    func seek(to time: TimeInterval) {
        if crossfadeStarted {
            let newIndex = activeSlot == 0 ? 1 : 0
            
            stopCrossfade()
            
            slots[activeSlot].playerNode.volume = 0
            slots[activeSlot].playerNode.stop()
            slots[newIndex].playerNode.stop()
            slots[newIndex].playerNode.reset()
            
            activeSlot = newIndex
            preloadedSlot = nil
            seekOffset = 0
            crossfadeStarted = false
            isFinishingNormally = false
            switchingTrack = false
            completionHandler = nextCompletion
            nextCompletion = nil
            
            let slot = slots[activeSlot]
            guard let file = slot.file else { return }
            
            let wasPlaying = isPlaying
            isSeeking = true
            
            let frame = AVAudioFramePosition(time * slot.sampleRate)
            let startFrame = min(frame, slot.fileLength)
            let remaining = slot.fileLength - startFrame
            
            guard remaining > 0 else {
                isFinishingNormally = true
                handlePlaybackComplete()
                return
            }
            
            seekOffset = time
            currentTime = time
            silenceDetected = false
            silenceStartTime = nil
            preloadedSlot = nil
            preloadRequested = false
            
            // НЕ переподключаем — reset() уже всё очистил, слот в графе
            slot.playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
            slot.playerNode.volume = currentUserVolume * slot.rgLinearGain
            
            if wasPlaying {
                slot.playerNode.play()
            }
            
            isFinishingNormally = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isSeeking = false
            }
            return
        }
        
        // Обычная перемотка
        let slot = slots[activeSlot]
        
        guard let file = slot.file else { return }
        
        let wasPlaying = isPlaying
        isSeeking = true
        
        let frame = AVAudioFramePosition(time * slot.sampleRate)
        let startFrame = min(frame, slot.fileLength)
        let remaining = slot.fileLength - startFrame
        
        guard remaining > 0 else {
            isFinishingNormally = true
            handlePlaybackComplete()
            return
        }
        
        seekOffset = time
        currentTime = time
        silenceDetected = false
        silenceStartTime = nil
        preloadedSlot = nil
        preloadRequested = false
        
        // ✅ reset() + scheduleSegment — без переподключения к графу
        slot.playerNode.stop()
        slot.playerNode.reset()
        slot.playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
        slot.playerNode.volume = currentUserVolume * slot.rgLinearGain
        
        if wasPlaying {
            slot.playerNode.play()
        }
        
        isFinishingNormally = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isSeeking = false
        }
    }
    func setVolume(_ volume: Float) { currentUserVolume = volume; applyVolume() }
    
    private func applyVolume() {
        guard !crossfadeStarted else { return }
        slots[activeSlot].playerNode.volume = currentUserVolume * slots[activeSlot].rgLinearGain
    }
    
    func applyCurrentRG() {
        guard !crossfadeStarted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.applyCurrentRG()
            }
            return
        }
        
        guard let track = slots[activeSlot].track else { return }
        let newGain = computeRGGain(for: track)
        
        slots[activeSlot].rgLinearGain = newGain
        applyVolume()
        
        if let preIdx = preloadedSlot, let preTrack = slots[preIdx].track {
            slots[preIdx].rgLinearGain = computeRGGain(for: preTrack)
        }
    }
    
    // MARK: - Preload
    
    func preloadNextTrack(_ track: Track, volume: Float? = nil, completion: @escaping () -> Void) {
        guard !crossfadeStarted else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let engine = self.engine,
                  engine.isRunning else { return }
            
            let nextIndex = self.activeSlot == 0 ? 1 : 0
            
            guard let audioFile = try? AVAudioFile(forReading: track.url) else { return }
            let newFormat = audioFile.processingFormat
            
            // ✅ var вместо let
            var slot = self.slots[nextIndex]
            
            // Останавливаем и сбрасываем
            slot.playerNode.stop()
            slot.playerNode.reset()
            
            // НЕ переподключаем — AVAudioEngine сам смикширует разные форматы
            if let oldFormat = slot.format, oldFormat != newFormat {
            }
            
            let finalGain = self.computeRGGain(for: track)
            
            slot.format = newFormat
            slot.track = track
            slot.file = audioFile
            slot.fileLength = audioFile.length
            slot.sampleRate = newFormat.sampleRate
            slot.rgLinearGain = finalGain
            slot.isPreloaded = true
            self.setupEQBands(slot.eqNode)
            slot.playerNode.scheduleFile(audioFile, at: nil)
            
            // Записываем обратно в массив
            self.slots[nextIndex] = slot
            
            self.preloadedSlot = nextIndex
            self.nextCompletion = completion
            self.preloadRequested = false
            if let vol = volume { self.currentUserVolume = vol }
        }
    }
    
    // MARK: - Crossfade
    
    private func startCrossfade() {
        guard !crossfadeStarted,
              let nextIndex = preloadedSlot,
              let engine = engine,
              engine.isRunning else { return }
        stopCrossfade()
        
        let oldIndex = activeSlot
        let oldSlot = slots[oldIndex]
        let newSlot = slots[nextIndex]
        
        let oldMaxTime = Double(oldSlot.fileLength) / oldSlot.sampleRate
        let remainingOld = max(0.1, oldMaxTime - currentTime)
        
        let nextMaxTime = Double(newSlot.fileLength) / newSlot.sampleRate
        let maxByNext = max(0.3, nextMaxTime / 3)
        let duration = min(settings.crossfadeDuration, remainingOld, maxByNext)
        
        crossfadeStarted = true
        isFinishingNormally = true
        switchingTrack = true
        currentTime = 0
        let savedNextIndex = nextIndex
        let savedNextCompletion = nextCompletion
        
        if let newTrack = newSlot.track {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .trackChanged, object: newTrack)
            }
        }
        
        let oldTargetVolume = currentUserVolume * oldSlot.rgLinearGain
        let newTargetVolume = currentUserVolume * newSlot.rgLinearGain
        
        newSlot.playerNode.volume = 0
        newSlot.playerNode.play()
        
        let startTime = Date()
        var completed = false
        crossfadeStartTime = startTime
        
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, self.crossfadeStarted && !completed else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / duration, 1.0))
            
            oldSlot.playerNode.volume = oldTargetVolume * (1.0 - progress)
            newSlot.playerNode.volume = newTargetVolume * progress
            
            if progress >= 1.0 {
                completed = true
                timer.invalidate()
                self.crossfadeTimer = nil
                oldSlot.playerNode.stop()
                
                self.activeSlot = savedNextIndex
                self.preloadedSlot = nil
                self.seekOffset = 0
                self.crossfadeStarted = false
                self.isFinishingNormally = false
                self.switchingTrack = false
                self.completionHandler = savedNextCompletion
                self.nextCompletion = nil
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) { [weak self] in
            guard let self = self,
                  self.crossfadeStarted,
                  !completed,
                  self.isPlaying else { return }  // ← добавить проверку isPlaying
            self.forceCompleteCrossfade(oldIndex: oldIndex, newIndex: savedNextIndex)
        }
    }
    
    private func resumeCrossfade() {
        guard crossfadeStarted else { return }
        
        let oldIndex = activeSlot
        let newIndex = activeSlot == 0 ? 1 : 0
        
        let oldSlot = slots[oldIndex]
        let newSlot = slots[newIndex]
        
        oldSlot.playerNode.play()
        newSlot.playerNode.play()
        isPlaying = true
        startDisplayLink()
        
        let oldVolume = oldSlot.playerNode.volume
        let newVolume = newSlot.playerNode.volume
        let newTargetVolume = currentUserVolume * newSlot.rgLinearGain
        
        let remainingProgress = newTargetVolume > 0 ? 1.0 - (newVolume / newTargetVolume) : 0
        let remainingDuration = max(0.1, settings.crossfadeDuration * Double(remainingProgress))
        
        let startTime = Date()
        var completed = false
        
        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, self.crossfadeStarted && !completed else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = Float(min(elapsed / remainingDuration, 1.0))
            
            oldSlot.playerNode.volume = oldVolume * (1.0 - progress)
            newSlot.playerNode.volume = newVolume + (newTargetVolume - newVolume) * progress
            
            if progress >= 1.0 {
                completed = true
                timer.invalidate()
                self.crossfadeTimer = nil
                oldSlot.playerNode.stop()
                self.activeSlot = newIndex
                self.preloadedSlot = nil
                self.seekOffset = 0
                self.crossfadeStarted = false
                self.isFinishingNormally = false
                self.completionHandler = self.nextCompletion
                self.nextCompletion = nil
            }
        }
    }
    
    private func stopCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeStarted = false
        crossfadeStartTime = nil
        savedCrossfadeRemaining = 0
        switchingTrack = false
    }
    
    private func forceCompleteCrossfade(oldIndex: Int, newIndex: Int) {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        
        slots[oldIndex].playerNode.stop()
        slots[newIndex].playerNode.volume = currentUserVolume * slots[newIndex].rgLinearGain
        
        activeSlot = newIndex
        preloadedSlot = nil
        seekOffset = 0
        crossfadeStarted = false
        isFinishingNormally = false
        switchingTrack = false  // ← добавить
        completionHandler = nextCompletion
        nextCompletion = nil
        crossfadeStartTime = nil  // ← добавить
        savedCrossfadeRemaining = 0  // ← добавить
        
        if let newTrack = slots[newIndex].track {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .trackChanged, object: newTrack)
            }
        }
    }
    
    // MARK: - EQ
    
    private func setupEQBands(_ eq: AVAudioUnitEQ) {
        let bands = eqManager.bands
        for (index, band) in bands.enumerated() {
            guard index < eq.bands.count else { break }
            let p = eq.bands[index]
            p.filterType = .parametric; p.frequency = Float(band.frequency); p.bandwidth = 1.0
            p.gain = eqManager.isEnabled ? band.gain : 0; p.bypass = false
        }
    }
    
    private func updateAllEQs() { for slot in slots { setupEQBands(slot.eqNode) } }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        stopDisplayLink()
        let interval = Int(settings.progressUpdateInterval)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval))
        
        var crossfadeStartDate: Date?
        var crossfadeInitialOffset: TimeInterval = 0
        
        timer.setEventHandler { [weak self] in
            guard let self = self, self.engine?.isRunning == true, self.isPlaying else {
                return
            }
            
            let currentTimeValue: TimeInterval
            
            if self.switchingTrack {
                if crossfadeStartDate == nil {
                    crossfadeStartDate = Date()
                    crossfadeInitialOffset = self.currentTime
                }
                
                let newIndex = self.activeSlot == 0 ? 1 : 0
                let newSlot = self.slots[newIndex]
                let maxTime = Double(newSlot.fileLength) / newSlot.sampleRate
                let elapsed = Date().timeIntervalSince(crossfadeStartDate!)
                currentTimeValue = min(crossfadeInitialOffset + elapsed, maxTime)
            } else {
                crossfadeStartDate = nil
                crossfadeInitialOffset = 0
                
                let slot = self.slots[self.activeSlot]
                guard let nodeTime = slot.playerNode.lastRenderTime,
                      let playerTime = slot.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                
                let segmentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                currentTimeValue = self.seekOffset + segmentTime
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.currentTime = currentTimeValue
            }
            
            if !self.crossfadeStarted && !self.isSeeking && self.isPlaying {
                let slot = self.slots[self.activeSlot]
                let maxTime = Double(slot.fileLength) / slot.sampleRate
                let remaining = maxTime - currentTimeValue
                
                if self.settings.crossfadeEnabled && remaining <= self.settings.crossfadeDuration + 1.0 && self.preloadedSlot == nil && !self.preloadRequested {
                    self.preloadRequested = true
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .prepareNextTrack, object: nil) }
                }
                if self.settings.gaplessEnabled && remaining <= 3.0 && self.preloadedSlot == nil && !self.preloadRequested {
                    self.preloadRequested = true
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .prepareNextTrack, object: nil) }
                }
                if self.settings.crossfadeEnabled && remaining <= self.settings.crossfadeDuration && self.preloadedSlot != nil {
                    DispatchQueue.main.async { self.startCrossfade() }
                }
                if currentTimeValue >= maxTime - 0.1 && self.isPlaying && !self.isSeeking && !self.isFinishingNormally {
                    DispatchQueue.main.async { [weak self] in
                        self?.handlePlaybackComplete()
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
    private func restartDisplayLink() { guard isPlaying else { return }; stopDisplayLink(); startDisplayLink() }
    
    private func handlePlaybackComplete() {
        guard !isFinishingNormally else { return }
        isFinishingNormally = true

        // Gapless — переключаем на предзагруженный слот
        if let nextIndex = preloadedSlot, slots[nextIndex].isPreloaded {
            if settings.crossfadeEnabled {
                return
            } else {
                let newSlot = slots[nextIndex]
                newSlot.playerNode.volume = currentUserVolume * newSlot.rgLinearGain
                guard let engine = engine, engine.isRunning else { return }
                newSlot.playerNode.play()
                slots[activeSlot].playerNode.stop()
                activeSlot = nextIndex
                preloadedSlot = nil
                seekOffset = 0
                currentTime = 0
                isPlaying = true
                isFinishingNormally = false
                
                if let newTrack = newSlot.track {
                    NotificationCenter.default.post(name: .trackChanged, object: newTrack)
                }
                return
            }
        }
        
        // Обычное завершение — вызываем handler для следующего трека
        if let handler = completionHandler {
            completionHandler = nil
            currentTime = 0
            stopDisplayLink()
            handler()
        } else {
            slots[activeSlot].playerNode.stop()
            isPlaying = false
            currentTime = 0
        }
    }
    // MARK: - Silence Detection
    
    private func startSilenceDetection() {
        guard settings.silenceSkipEnabled, let engine = engine else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        silenceDetected = false
        silenceStartTime = nil
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.analyzeBuffer(buffer)
        }
    }
    
    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
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
                if self.silenceDetected { self.silenceDetected = false; self.silenceStartTime = nil }
            }
        }
    }
    
    private func handleSilenceDetected() {
        
        guard silenceDetected else { return }
        silenceDetected = false
        silenceStartTime = nil
        let slot = slots[activeSlot]
        let maxTime = Double(slot.fileLength) / slot.sampleRate
        let remaining = maxTime - currentTime
        guard remaining > 1.0 && remaining <= 10.0 else { return }
        slot.playerNode.volume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.seek(to: maxTime - 0.01)
            self?.handlePlaybackComplete()
        }
    }
}
