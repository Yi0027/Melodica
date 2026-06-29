// Services,AudioPlayerService.swift
import AVFoundation
import Combine

final class AudioPlayerService: NSObject, ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying = false
    
    private var player: AVAudioPlayer?
    private var displayLink: DispatchSourceTimer?
    private var completionHandler: (() -> Void)?
    private var currentUserVolume: Float = 0.5
    private var currentRGLinearGain: Float = 1.0  // RG gain
    
    func play(_ track: Track, volume: Float? = nil, completion: @escaping () -> Void) {
        stop()
        completionHandler = completion
        
        if let vol = volume {
            currentUserVolume = vol
        }
        
        // Сохраняем RG
        if let gain = track.replayGain {
            currentRGLinearGain = pow(10, gain / 20.0)
            currentRGLinearGain = min(max(currentRGLinearGain, 0.0), 1.0)
        } else {
            currentRGLinearGain = 1.0
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.delegate = self
            player?.prepareToPlay()
            
            applyVolume()
            
            player?.play()
            isPlaying = true
            startDisplayLink()
        } catch {
            print("Playback error: \(error)")
            completion()
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopDisplayLink()
    }
    
    func resume() {
        player?.play()
        isPlaying = true
        startDisplayLink()
        applyVolume()
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopDisplayLink()
    }
    
    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }
    
    func setVolume(_ volume: Float) {
        currentUserVolume = volume
        applyVolume()
    }
    
    private func applyVolume() {
        guard let player = player else { return }
        player.volume = currentUserVolume * currentRGLinearGain
    }
    
    private func startDisplayLink() {
        stopDisplayLink()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self, let player = self.player else { return }
            let time = player.currentTime
            DispatchQueue.main.async { [weak self] in self?.currentTime = time }
        }
        timer.resume()
        displayLink = timer
    }
    
    private func stopDisplayLink() {
        displayLink?.cancel()
        displayLink = nil
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.completionHandler?()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Decode error: \(String(describing: error))")
        DispatchQueue.main.async { [weak self] in
            self?.stop()
            self?.completionHandler?()
        }
    }
}
