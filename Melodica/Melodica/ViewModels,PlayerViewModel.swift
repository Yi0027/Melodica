// ViewModels/PlayerViewModel.swift
import SwiftUI
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.5
    @Published var queue: [Track] = []
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleMode: Bool = false
    @Published var favorites: [Track] = []
    @Published var playbackMode: PlaybackMode = .library

    var missingFavorites: [Track] {
        let watchedPaths = LibraryViewModel.shared?.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" } ?? []
        if watchedPaths.isEmpty {
            // Все треки считаются missing когда папок нет
            return favorites
        }
        return favorites.filter { track in
            !watchedPaths.contains { track.url.path.hasPrefix($0) }
        }
    }

    var availableFavorites: [Track] {
        let watchedPaths = LibraryViewModel.shared?.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" } ?? []
        guard !watchedPaths.isEmpty else { return [] }
        return favorites.filter { track in
            watchedPaths.contains { track.url.path.hasPrefix($0) }
        }
    }

    enum PlaybackMode: Equatable {
        case library
        case album([Track])
        case playlist([Track], name: String)
        case queue
        var tracks: [Track] {
            switch self {
            case .library: return []
            case .album(let tracks): return tracks
            case .playlist(let tracks, _): return tracks
            case .queue: return []
            }
        }
    }
    
    enum RepeatMode: String, Codable {
        case off, one, all
        var icon: String { switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }}
        var isActive: Bool { self != .off }
    }
    
    let service = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()
    private var autoSaveTimer: Timer?
    private var saveDebouncer: Timer?
    private var lastSavedVolume: Float = 0.5
    private var lastPlayedTrackPath: String?
    private var lastPlayedTime: TimeInterval = 0
    private var pendingQueuePaths: [String] = []
    private var pendingFavoriteInfos: [FavoriteInfo] = []
    private var isRestoringState = true
    
    var playerTracks: [Track] = []
    
    init() {
        if let state = PlayerStateManager.shared.loadPlayer() {
            volume = state.volume; lastSavedVolume = state.volume
            lastPlayedTrackPath = state.currentTrackPath; lastPlayedTime = state.currentTime
            shuffleMode = state.shuffleMode
            repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
            pendingQueuePaths = state.queuePaths
            pendingFavoriteInfos = state.favoriteInfos ?? []
        }
        
        service.$currentTime.receive(on: RunLoop.main).assign(to: \.currentTime, on: self).store(in: &cancellables)
        service.$isPlaying.receive(on: RunLoop.main).assign(to: \.isPlaying, on: self).store(in: &cancellables)
        
        $currentTrack.dropFirst().sink { [weak self] track in
            guard let self = self, !self.isRestoringState else { return }
            if let track = track { self.lastPlayedTrackPath = track.url.path; self.scheduleSave() }
        }.store(in: &cancellables)
        
        $volume.sink { [weak self] v in
            self?.service.setVolume(v)
            guard let self = self, !self.isRestoringState else { return }
            if self.lastSavedVolume != v { self.lastSavedVolume = v; self.scheduleSave() }
        }.store(in: &cancellables)
        
        $shuffleMode.dropFirst().sink { [weak self] _ in
            guard let self = self, !self.isRestoringState else { return }
            self.scheduleSave()
        }.store(in: &cancellables)
        
        $favorites.dropFirst().sink { [weak self] _ in
            guard let self = self, !self.isRestoringState else { return }
            self.scheduleSave()
        }.store(in: &cancellables)
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isRestoringState else { return }
            self.saveState()
        }
        
        service.setVolume(volume)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("allFoldersLoaded"), object: nil, queue: .main) { [weak self] _ in
            self?.refreshFavorites()
        }

        NotificationCenter.default.addObserver(forName: .enrichmentComplete, object: nil, queue: .main) { [weak self] _ in
            self?.isRestoringState = false
            self?.refreshFavorites()
        }
        
        NotificationCenter.default.addObserver(forName: .saveStateOnExit, object: nil, queue: .main) { [weak self] _ in
            self?.saveState()
        }
        
        NotificationCenter.default.addObserver(forName: .trackChanged, object: nil, queue: .main) { [weak self] notification in
            if let track = notification.object as? Track {
                self?.currentTrack = track
                self?.duration = track.duration
                self?.lastPlayedTrackPath = track.url.path
                
                if self?.repeatMode == .off, let self = self {
                    if !self.queue.isEmpty {
                        self.queue.removeFirst()
                        self.saveState()
                    }
                }
            } else {
                // Треков нет — останавливаем плеер
                self?.stop()
            }
        }
    }
    
    private func scheduleSave() {
        saveDebouncer?.invalidate()
        saveDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.saveState()
        }
    }
    func refreshFavorites() {
        guard !isRestoringState else { return }
        let allTracks = LibraryViewModel.shared?.tracks ?? []
        guard !allTracks.isEmpty else { return }
        
        var updatedFavorites = favorites
        for i in 0..<updatedFavorites.count {
            let oldPath = updatedFavorites[i].url.path
            let fileName = URL(fileURLWithPath: oldPath).lastPathComponent
            let oldDuration = updatedFavorites[i].duration
            
            // Ищем по точному пути
            if let match = allTracks.first(where: { $0.url.path == oldPath }) {
                updatedFavorites[i] = match
            }
            // Ищем по имени файла + длительности
            else if let match = allTracks.first(where: { $0.url.lastPathComponent == fileName && abs($0.duration - oldDuration) < 1.0 }) {
                updatedFavorites[i] = match
            }
            // Ищем только по имени файла
            else if let match = allTracks.first(where: { $0.url.lastPathComponent == fileName }) {
                updatedFavorites[i] = match
            }
            // Не нашли — оставляем как есть (попадёт в missing)
        }
        favorites = updatedFavorites
           saveState()
       }
    func finishRestoringState() {
        isRestoringState = false
    }
    
    var progress: Double { guard duration > 0 else { return 0 }; return currentTime / duration }
    
    func play(_ track: Track, afterFinish: @escaping () -> Void) {

        currentTrack = track; lastPlayedTrackPath = track.url.path; duration = track.duration
        updatePlayerTracksForCurrentMode()
        service.play(track, volume: volume) { [weak self] in
            DispatchQueue.main.async { afterFinish() }
        }
        saveState()
    }
    private func updatePlayerTracksForCurrentMode() {
        switch playbackMode {
        case .album(let tracks): playerTracks = tracks
        case .playlist(let tracks, _): playerTracks = tracks
        default: break
        }
    }
    
    func playPaused(_ track: Track) {
        currentTrack = track; lastPlayedTrackPath = track.url.path; duration = track.duration
        service.play(track, volume: volume) { [weak self] in
            DispatchQueue.main.async {
                self?.playNextTrack()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.service.pause() }
        saveState()
    }
    
    func playNextInQueue() -> Track? {
        guard !queue.isEmpty else {
            return nil
        }
        
        if repeatMode == .one {
            if let current = currentTrack, queue.contains(where: { $0.id == current.id }) {
                return current
            }
            return nil
        }
        
        if repeatMode == .all {
            if shuffleMode {
                let other = queue.filter { $0.id != currentTrack?.id }
                if let random = other.randomElement() {
                    return random
                }
                return queue.first
            }
            
            guard let current = currentTrack,
                  let idx = queue.firstIndex(where: { $0.id == current.id }) else {
                return queue.first
            }
            
            if idx + 1 < queue.count {
                let next = queue[idx + 1]
                return next
            } else {
                let first = queue[0]
                return first
            }
        }
        
        if shuffleMode {
                let other = queue.filter { $0.id != currentTrack?.id }
                if let random = other.randomElement() {
                    queue.removeAll { $0.id == random.id }
                    saveState()
                    return random
                }
                return nil
            }
            
            // Всегда берём первый трек из очереди
            let next = queue.removeFirst()
            saveState()
            return next
        }
    func playNowFromQueue(_ track: Track) {
        guard let idx = queue.firstIndex(where: { $0.id == track.id }) else { return }
        queue.remove(at: idx)
        saveState()
        play(track) { [weak self] in
            self?.playNextTrack()
        }
    }
    func addToQueue(_ track: Track) { guard !queue.contains(where: { $0.id == track.id }) else { return }; queue.append(track); saveState() }
    func removeFromQueue(_ track: Track) {
        queue.removeAll { $0.id == track.id }
        service.clearPreload()
        saveState()
    }
    func clearQueue() { queue.removeAll(); saveState() }
    func togglePlayPause() {
        guard currentTrack != nil else { return }
        isPlaying ? service.pause() : service.resume()
        saveState()
    }
    
    func stop() {
        lastPlayedTime = currentTime
        service.stop()
        currentTrack = nil
        currentTime = 0
        duration = 0
        saveState()
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.objectWillChange.send()
        }
    }
    
    func seek(to fraction: Double) { service.seek(to: fraction * duration) }
    
    func toggleFavorite(_ track: Track) {
        if let idx = favorites.firstIndex(where: { $0.id == track.id }) { favorites.remove(at: idx) }
        else { favorites.append(track) }
        saveState()
    }
    func isFavorite(_ track: Track) -> Bool { favorites.contains(where: { $0.id == track.id }) }
    
    func playPreviousTrack() {
        guard let current = currentTrack else { return }
        
        if currentTime > 10 {
            seek(to: 0)
            return
        }
        
        if !queue.isEmpty {
            if let idx = queue.firstIndex(where: { $0.id == current.id }), idx > 0 {
                play(queue[idx - 1]) { [weak self] in self?.playNextTrack() }
                return
            }
            seek(to: 0)
            return
        }
        
        if !playerTracks.isEmpty {
            if shuffleMode {
                let other = playerTracks.filter { $0.id != current.id }
                if let random = other.randomElement() {
                    play(random) { [weak self] in self?.playNextTrack() }
                }
                return
            }
            guard let idx = playerTracks.firstIndex(where: { $0.id == current.id }), idx > 0 else {
                seek(to: 0)
                return
            }
            play(playerTracks[idx - 1]) { [weak self] in self?.playNextTrack() }
            return
        }
        
        seek(to: 0)
    }
    
    func playNextTrack() {
        if repeatMode == .one, let current = currentTrack {
            play(current) { [weak self] in self?.playNextTrack() }
            return
        }
        
        if !queue.isEmpty {
            if let queued = playNextInQueue() {
                play(queued) { [weak self] in self?.playNextTrack() }
                return
            }
        }
        
        if !playerTracks.isEmpty, let current = currentTrack {
            if shuffleMode {
                let other = playerTracks.filter { $0.id != current.id }
                if let random = other.randomElement() {
                    play(random) { [weak self] in self?.playNextTrack() }
                    return
                }
            } else {
                guard let idx = playerTracks.firstIndex(where: { $0.id == current.id }) else {
                    stop()
                    return
                }
                
                if idx + 1 < playerTracks.count {
                    let next = playerTracks[idx + 1]
                    play(next) { [weak self] in self?.playNextTrack() }
                } else if repeatMode == .all, let first = playerTracks.first {
                    play(first) { [weak self] in self?.playNextTrack() }
                } else {
                    stop()

                }
                return
            }
        }
        
        stop()
    }
    
    func prepareNextTrack() {
        guard let next = getNextTrackForPreload() else { return }
        service.preloadNextTrack(next, volume: volume) {}
    }
    
    private func getNextTrackForPreload() -> Track? {
        // Очередь — всегда приоритет
        if !queue.isEmpty {
            if shuffleMode {
                let other = queue.filter { $0.id != currentTrack?.id }
                return other.randomElement() ?? queue.first
            }
            
            if repeatMode == .all, let current = currentTrack,
               let idx = queue.firstIndex(where: { $0.id == current.id }) {
                if idx + 1 < queue.count { return queue[idx + 1] }
                else { return queue.first }
            }
            if repeatMode == .one, let current = currentTrack { return current }
            return queue.first
        }
        
        // PlayerTracks
        let tracks = playerTracks
        guard !tracks.isEmpty, let current = currentTrack else { return nil }
        
        if shuffleMode {
            let other = tracks.filter { $0.id != current.id }
            return other.randomElement()
        }
        
        guard let idx = tracks.firstIndex(where: { $0.id == current.id }) else { return nil }
        if repeatMode == .one { return current }
        if idx + 1 < tracks.count { return tracks[idx + 1] }
        else if repeatMode == .all { return tracks.first }
        return nil
    }
    
    func restoreQueue(from tracks: [Track]) {
        guard !pendingQueuePaths.isEmpty else { return }
        queue = pendingQueuePaths.compactMap { path in
            tracks.first { $0.url.path == path } ?? tracks.first { $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent }
        }
        pendingQueuePaths = []
    }
    
    func restoreFavorites(from tracks: [Track]) {
        guard !pendingFavoriteInfos.isEmpty else {
            return
        }
        
        var restored: [Track] = []
        for info in pendingFavoriteInfos {
            if let track = tracks.first(where: { $0.url.path == info.path }) {
                restored.append(track)
            } else if let track = tracks.first(where: { $0.url.lastPathComponent == URL(fileURLWithPath: info.path).lastPathComponent }) {
                restored.append(track)
            } else {
                let placeholder = Track(
                    url: URL(fileURLWithPath: info.path),
                    fileName: URL(fileURLWithPath: info.path).lastPathComponent,
                    title: info.title,
                    artist: info.artist,
                    album: NSLocalizedString("unknown_album", comment: ""),
                    year: nil, duration: 0, trackNumber: nil,
                    genre: nil, albumArtURL: nil,
                    replayGain: nil, replayGainPeak: nil,
                    replayGainAlbum: nil, replayGainAlbumPeak: nil,
                    lyricsURL: nil, unsyncedLyrics: nil
                )
                restored.append(placeholder)
            }
        }
        favorites = restored
        pendingFavoriteInfos = []
        refreshFavorites()
    }
    
    func saveState() {
        let state = PlayerState(
            currentTrackPath: lastPlayedTrackPath ?? currentTrack?.url.path,
            currentTime: currentTime > 0 ? currentTime : lastPlayedTime,
            volume: volume,
            repeatMode: repeatMode.rawValue,
            shuffleMode: shuffleMode,
            queuePaths: queue.map { $0.url.path },
            favoriteInfos: favorites.map { FavoriteInfo(path: $0.url.path, title: $0.title, artist: $0.artist) },
            timestamp: Date()
        )
        do {
            let data = try JSONEncoder().encode(state)
            PlayerStateManager.shared.savePlayer(state)
        } catch {
        }
    }
    func restoreState(tracks: [Track]) -> (track: Track?, time: TimeInterval)? {
        guard let state = PlayerStateManager.shared.loadPlayer() else { return nil }
        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off; shuffleMode = state.shuffleMode
        guard let p = state.currentTrackPath, let t = tracks.first(where: { $0.url.path == p }) else { return nil }
        return (t, state.currentTime)
    }
    func setVolumeWithoutUI(_ volume: Float) {
        isRestoringState = true
        self.volume = volume
        service.setVolume(volume)
        isRestoringState = false
    }
}
