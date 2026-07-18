// Services/MediaKeysHandler.swift
import Cocoa
import SwiftUI
import MediaPlayer

class MediaKeysHandler {
    static let shared = MediaKeysHandler()
    
    private weak var playerVM: PlayerViewModel?
    private var tracksProvider: (() -> [Track])?
    
    func startMonitoring(
        playerVM: PlayerViewModel,
        tracks: @escaping () -> [Track],
        playTrack: @escaping (Track, @escaping () -> Void) -> Void,
        stopPlayer: @escaping () -> Void
    ) {
        self.playerVM = playerVM
        self.tracksProvider = tracks
        
        setupRemoteCommands()
    }
    
    // MARK: - Наушники / Bluetooth / Touch Bar
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        
        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleTogglePlayPause()
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleTogglePlayPause()
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Toggle Play/Pause (основная команда для большинства наушников)
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleTogglePlayPause()
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Next Track (двойное нажатие)
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleNext()
            }
            return .success
        }
        
        // Previous Track (тройное нажатие)
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePrevious()
            }
            return .success
        }
        
        // Change Playback Position
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                guard let playerVM = self?.playerVM, playerVM.duration > 0 else { return }
                let fraction = event.positionTime / playerVM.duration
                playerVM.seek(to: fraction)
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        
        updateNowPlayingInfo()
    }
    
    private func handleTogglePlayPause() {
        guard let playerVM = playerVM else { return }
        playerVM.togglePlayPause()
    }
    
    private func updateNowPlayingInfo() {
        guard let playerVM = playerVM else { return }
        
        var nowPlayingInfo = [String: Any]()
        
        if let currentTrack = playerVM.currentTrack {
            nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrack.title
            nowPlayingInfo[MPMediaItemPropertyArtist] = currentTrack.artist
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentTrack.album ?? ""
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = currentTrack.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playerVM.currentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playerVM.isPlaying ? 1.0 : 0.0
            
            // Пробуем загрузить обложку из папки трека
            let url = currentTrack.url
            let folder = url.deletingLastPathComponent()
            let coverNames = ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "artwork.jpg", "artwork.png"]
            for name in coverNames {
                let coverURL = folder.appendingPathComponent(name)
                if let image = NSImage(contentsOf: coverURL) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    break
                }
            }
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Melodica"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "Melodica Player"
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = playerVM.isPlaying ? .playing : .paused
    }
    
    private func handleNext() {
        guard let playerVM = playerVM else { return }
        playerVM.playNextTrack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }

    private func handlePrevious() {
        guard let playerVM = playerVM else { return }
        playerVM.playPreviousTrack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }
    
    func stopMonitoring() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        playerVM = nil
        tracksProvider = nil
    }
}
