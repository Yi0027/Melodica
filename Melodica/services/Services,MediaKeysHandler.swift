// Services/MediaKeysHandler.swift
import Cocoa
import SwiftUI
import MediaPlayer

@MainActor
final class MediaKeysHandler {
    static let shared = MediaKeysHandler()
    
    private weak var playerVM: PlayerViewModel?
    private var tracksProvider: (() -> [Track])?
    private var isObserverRegistered = false
    
    func startMonitoring(
        playerVM: PlayerViewModel,
        tracks: @escaping () -> [Track],
        playTrack: @escaping (Track, @escaping () -> Void) -> Void,
        stopPlayer: @escaping () -> Void
    ) {
        self.playerVM = playerVM
        self.tracksProvider = tracks
        
        setupRemoteCommands()
        registerObservers()
    }
    
    private func registerObservers() {
        guard !isObserverRegistered else { return }
        isObserverRegistered = true
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserArtworkDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let playerVM = self.playerVM, let track = playerVM.currentTrack else { return }
                self.updateTrackInfo(track: track, isPlaying: playerVM.isPlaying, currentTime: playerVM.currentTime)
            }
        }
    }
    
    // MARK: - Headphones / Bluetooth / Touch Bar / System Menu Bar Controls
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
                
        // Clear previous commands
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        
        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.playerVM?.playFromRemote()
            }
            return .success
        }
        
        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.playerVM?.pauseFromRemote()
            }
            return .success
        }
        
        // Toggle Play/Pause
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleTogglePlayPause()
            }
            return .success
        }
        
        // Stop
        center.stopCommand.isEnabled = true
        center.stopCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.playerVM?.stop()
            }
            return .success
        }
        
        // Next Track
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleNext()
            }
            return .success
        }
        
        // Previous Track
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
                guard let playerVM = self?.playerVM, playerVM.duration > 0 else {
                    return
                }
                let fraction = event.positionTime / playerVM.duration
                playerVM.seek(to: fraction)
            }
            return .success
        }
        
        if let playerVM = playerVM {
            updateTrackInfo(track: playerVM.currentTrack, isPlaying: playerVM.isPlaying, currentTime: playerVM.currentTime)
        }
    }
    
    private func handleTogglePlayPause() {
        guard let playerVM = playerVM else { return }
        playerVM.togglePlayPause()
    }
    
    private func handleNext() {
        guard let playerVM = playerVM else { return }
        playerVM.skipToNextTrack()
    }

    private func handlePrevious() {
        guard let playerVM = playerVM else { return }
        playerVM.playPreviousTrack()
    }
    
    // MARK: - Now Playing Info Synchronization
    
    func updatePlaybackState(isPlaying: Bool, currentTime: TimeInterval) {
        guard let currentTrack = playerVM?.currentTrack else {
            clear()
            return
        }
        
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        if info[MPMediaItemPropertyTitle] == nil {
            info[MPMediaItemPropertyTitle] = currentTrack.title
            info[MPMediaItemPropertyArtist] = currentTrack.artist
            info[MPMediaItemPropertyAlbumTitle] = currentTrack.album
            info[MPMediaItemPropertyPlaybackDuration] = currentTrack.duration
        }
        
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    
    func updateTrackInfo(track: Track?, isPlaying: Bool, currentTime: TimeInterval) {
        guard let currentTrack = track else {
            clear()
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrack.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentTrack.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentTrack.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = currentTrack.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        // 1. Fast synchronous check for readily available image
        if let fastImage = getFastArtworkImage(for: currentTrack) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = Self.makeMediaItemArtwork(from: fastImage)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        } else {
            // Apply text metadata immediately
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
            
            // Asynchronously resolve and attach artwork (embedded tags, async download/read)
            let trackId = currentTrack.id
            Task { [weak self] in
                guard let image = await self?.resolveArtworkImage(for: currentTrack) else { return }
                guard let self = self,
                      let playingTrack = self.playerVM?.currentTrack,
                      playingTrack.id == trackId else { return }
                
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
                updated[MPMediaItemPropertyArtwork] = Self.makeMediaItemArtwork(from: image)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }
    
    // MARK: - Artwork Resolution
    
    private func getFastArtworkImage(for track: Track) -> NSImage? {
        // 1. Pre-rendered high-res thumbnail from cache directory
        if let thumbURL = track.thumbURL(size: "400"),
           FileManager.default.fileExists(atPath: thumbURL.path),
           let img = NSImage(contentsOf: thumbURL) {
            return img
        }
        
        // 2. Extracted albumArtURL (in memory cache or local file)
        if let artURL = track.albumArtURL {
            if let cached = ImageCache.shared.cachedImage(for: artURL, maxPixelSize: 512) {
                return cached
            }
            if FileManager.default.fileExists(atPath: artURL.path),
               let img = NSImage(contentsOf: artURL) {
                return img
            }
        }
        
        // 3. Folder image in audio file directory
        let folder = track.url.deletingLastPathComponent()
        let coverNames = [
            "cover.jpg", "cover.png", "cover.jpeg",
            "folder.jpg", "folder.png", "folder.jpeg",
            "front.jpg", "front.png", "front.jpeg",
            "artwork.jpg", "artwork.png", "artwork.jpeg",
            "AlbumArtSmall.jpg", "Folder.jpg"
        ]
        for name in coverNames {
            let coverURL = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: coverURL.path),
               let img = NSImage(contentsOf: coverURL) {
                return img
            }
        }
        
        // 4. Custom user artwork
        if let userArt = UserArtworkManager.load(for: .artist(track.artist)) {
            return userArt
        }
        
        return nil
    }
    
    private func resolveArtworkImage(for track: Track) async -> NSImage? {
        if let fast = getFastArtworkImage(for: track) {
            return fast
        }
        
        // Downsample albumArtURL if available
        if let artURL = track.albumArtURL {
            if let loaded = await ImageCache.shared.loadImage(for: artURL, maxPixelSize: 512) {
                return loaded
            }
        }
        
        // Extract embedded artwork on the fly
        if let extractedURL = await MetadataReader.enrichArtwork(for: track) {
            if let img = NSImage(contentsOf: extractedURL) {
                return img
            }
        }
        
        return nil
    }
    
    private nonisolated static func makeMediaItemArtwork(from image: NSImage) -> MPMediaItemArtwork {
        let repWidth = image.representations.first?.pixelsWide ?? 0
        let repHeight = image.representations.first?.pixelsHigh ?? 0
        let width = repWidth > 0 ? CGFloat(repWidth) : max(image.size.width, 512)
        let height = repHeight > 0 ? CGFloat(repHeight) : max(image.size.height, 512)
        let boundsSize = CGSize(width: max(width, 1), height: max(height, 1))
        
        // MPMediaItemArtwork requestHandler will be executed asynchronously by MediaPlayer
        // on its own background queue (`accessQueue`).
        // It MUST be nonisolated so Swift concurrency does not assert main actor isolation.
        return MPMediaItemArtwork(boundsSize: boundsSize) { (_: CGSize) -> NSImage in
            return image
        }
    }
    
    func updateElapsedPlaybackTime(_ time: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    
    func stopMonitoring() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        
        clear()
        
        playerVM = nil
        tracksProvider = nil
    }
}
