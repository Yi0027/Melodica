// Services,AudioPlayerService.swift
import AVFoundation
import Combine

final class AudioPlayerService: NSObject, ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eqNode: AVAudioUnitEQ?
    private var displayLink: DispatchSourceTimer?
    private var completionHandler: (() -> Void)?
    private var currentUserVolume: Float = 0.5
    private var currentRGLinearGain: Float = 1.0
    private var currentFile: AVAudioFile?
    private var currentSampleRate: Double = 44100
    private var currentFileLength: AVAudioFramePosition = 0
    private var isFinishingNormally = false
    private var seekOffset: TimeInterval = 0
    private var isSeeking = false
    
    private let eqManager = EqualizerManager.shared
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .eqDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateEQ()
        }
    }
    
    func play(_ track: Track, volume: Float? = nil, completion: @escaping () -> Void) {
        stop()
        completionHandler = completion
        isFinishingNormally = false
        seekOffset = 0
        
        if let vol = volume {
            currentUserVolume = vol
        }
        
        if let gain = track.replayGain {
            currentRGLinearGain = pow(10, gain / 20.0)
            currentRGLinearGain = min(max(currentRGLinearGain, 0.0), 3.0)
        } else {
            currentRGLinearGain = 1.0
        }
        
        guard let audioFile = try? AVAudioFile(forReading: track.url) else {
            completion()
            return
        }
        
        currentFile = audioFile
        currentSampleRate = audioFile.processingFormat.sampleRate
        currentFileLength = audioFile.length
        
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 10)
        
        engine.attach(playerNode)
        engine.attach(eqNode)
        
        setupEQBands(eqNode)
        
        engine.connect(playerNode, to: eqNode, format: audioFile.processingFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: audioFile.processingFormat)
        
        playerNode.scheduleFile(audioFile, at: nil)
        
        do {
            try engine.start()
            
            // Слой 1: громкость до play
            playerNode.volume = currentUserVolume * currentRGLinearGain
            
            playerNode.play()
            isPlaying = true
            startDisplayLink()
        } catch {
            print("Engine start error: \(error)")
            completion()
        }
        
        self.engine = engine
        self.playerNode = playerNode
        self.eqNode = eqNode
    }
    
    private func setupEQBands(_ eq: AVAudioUnitEQ) {
        let bands = eqManager.bands
        for (index, band) in bands.enumerated() {
            guard index < eq.bands.count else { break }
            let filterParams = eq.bands[index]
            filterParams.filterType = .parametric
            filterParams.frequency = Float(band.frequency)
            filterParams.bandwidth = 1.0
            filterParams.gain = eqManager.isEnabled ? band.gain : 0
            filterParams.bypass = false
        }
    }
    
    func updateEQ() {
        guard let eq = eqNode else { return }
        let bands = eqManager.bands
        for (index, band) in bands.enumerated() {
            guard index < eq.bands.count else { break }
            eq.bands[index].gain = eqManager.isEnabled ? band.gain : 0
        }
    }
    
    func pause() {
        playerNode?.pause()
        isPlaying = false
        stopDisplayLink()
    }
    
    func resume() {
        playerNode?.play()
        isPlaying = true
        startDisplayLink()
        applyVolume()
    }
    
    func stop() {
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        eqNode = nil
        currentFile = nil
        isPlaying = false
        currentTime = 0
        seekOffset = 0
        stopDisplayLink()
    }
    
    func seek(to time: TimeInterval) {
        guard let playerNode = playerNode,
              let engine = engine,
              engine.isRunning,
              let file = currentFile else { return }
        
        let wasPlaying = isPlaying
        
        let frame = AVAudioFramePosition(time * currentSampleRate)
        let startFrame = min(frame, currentFileLength)
        let remainingFrames = currentFileLength - startFrame
        
        guard remainingFrames > 0 else {
            handlePlaybackComplete()
            return
        }
        
        seekOffset = time
        currentTime = time
        isSeeking = true
        
        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        )
        
        if wasPlaying {
            playerNode.play()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isSeeking = false
        }
    }
    
    func setVolume(_ volume: Float) {
        currentUserVolume = volume
        applyVolume()
    }
    
    private func applyVolume() {
        guard let playerNode = playerNode else { return }
        playerNode.volume = currentUserVolume * currentRGLinearGain
    }
    
    private func handlePlaybackComplete() {
        guard !isFinishingNormally else { return }
        isFinishingNormally = true
        
        let handler = completionHandler
        completionHandler = nil
        stop()
        handler?()
    }
    
    private func startDisplayLink() {
        stopDisplayLink()
        
        // Слой 2: громкость при первом обновлении
        applyVolume()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self,
                  let playerNode = self.playerNode,
                  let engine = self.engine,
                  engine.isRunning else { return }
            
            if let nodeTime = playerNode.lastRenderTime,
               let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                let segmentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                let totalTime = self.seekOffset + segmentTime
                let maxTime = Double(self.currentFileLength) / self.currentSampleRate
                let clampedTime = min(totalTime, maxTime)
                
                DispatchQueue.main.async { [weak self] in
                    self?.currentTime = clampedTime
                }
                
                // Проверка окончания трека
                if clampedTime >= maxTime - 0.1 && self.isPlaying && !self.isSeeking {
                    DispatchQueue.main.async { [weak self] in
                        self?.isPlaying = false
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
}
