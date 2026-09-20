// ViewModels/PlayerViewModel.swift
import SwiftUI
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var volume: Float = 0.5

    /// Живой прогресс воспроизведения — в отдельном ObservableObject.
    /// Подписываются только те вьюхи, что реально отображают время/полоску.
    /// Благодаря этому PlayerBar и остальные родители не перерисовываются на каждом тике.
    let progress = PlaybackProgress()

    /// Обратная совместимость: обработчики кнопок читают значение в момент клика,
    /// им подписка на изменения не нужна. Для отображения — используй `progress` напрямую.
    var currentTime: TimeInterval { progress.currentTime }
    var duration: TimeInterval { progress.duration }
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
    private var playbackContextDescription: String {
        switch playbackMode {
        case .library:
            return "library"
        case .album:
            return "album"
        case .playlist(_, let name):
            return "playlist:\(name)"
        case .queue:
            return "queue"
        }
    }
    
    init() {
        if let state = PlayerStateManager.shared.loadPlayer() {
            volume = state.volume; lastSavedVolume = state.volume
            lastPlayedTrackPath = state.currentTrackPath; lastPlayedTime = state.currentTime
            shuffleMode = state.shuffleMode
            repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
            pendingQueuePaths = state.queuePaths
            pendingFavoriteInfos = state.favoriteInfos ?? []
        }
        
        service.$currentTime
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.progress.currentTime = $0 }
            .store(in: &cancellables)

        service.$isPlaying
            .sink { [weak self] in self?.isPlaying = $0 }
            .store(in: &cancellables)
        
        $currentTrack.dropFirst().sink { [weak self] track in
            guard let self = self, !self.isRestoringState else { return }
            if let track = track { self.lastPlayedTrackPath = track.url.path; self.scheduleSave() }
        }.store(in: &cancellables)
        
        $currentTrack
            .sink { track in
                EQPresetManager.shared.autoApplyIfNeeded(for: track?.genre)
            }
            .store(in: &cancellables)
        
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
        NotificationCenter.default.addObserver(forName: .crossfadeStarted, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let track = notification.object as? Track else { return }
            self.currentTrack = track
            self.progress.duration = track.duration
            self.progress.currentTime = 0
        }
        
        NotificationCenter.default.addObserver(forName: .trackRatingChanged, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let track = notification.object as? Track else { return }
            if let idx = self.favorites.firstIndex(where: { $0.id == track.id }) {
                self.favorites[idx].rating = track.rating
                self.saveState()
            }
            if self.currentTrack?.id == track.id {
                self.currentTrack?.rating = track.rating
            }
        }
        NotificationCenter.default.addObserver(forName: .trackChanged, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            
            if let track = notification.object as? Track {
                if self.currentTrack?.id != track.id {
                    self.currentTrack = track
                    self.progress.duration = track.duration
                    self.progress.currentTime = track.cueStartTime ?? 0
                }
                self.lastPlayedTrackPath = track.url.path
                
                if self.repeatMode == .off, !self.queue.isEmpty {
                    self.queue.removeFirst()
                    self.saveState()
                }
            } else {
                self.stop()
            }
        }
        NotificationCenter.default.addObserver(forName: .prepareNextTrack, object: nil, queue: .main) { [weak self] _ in
            self?.prepareNextTrack()
            if let next = self?.getNextTrackForPreload() {
                VisualizationEngine.shared.preloadWaveform(for: next)
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
        let cueAlbums = LibraryViewModel.shared?.cueAlbums ?? []
        guard !allTracks.isEmpty || !cueAlbums.isEmpty else { return }

        var updatedFavorites = favorites

        for i in 0..<updatedFavorites.count {
            let oldPath = updatedFavorites[i].url.path
            let oldHash = updatedFavorites[i].smartHash
            let fileName = URL(fileURLWithPath: oldPath).lastPathComponent
            let oldDuration = updatedFavorites[i].duration

            // 0. Cue-трек
            if let hash = oldHash, let cueTrack = Self.findCUETrack(hash: hash, in: cueAlbums) {
                updatedFavorites[i] = cueTrack
                continue
            }

            // 1. По smartHash
            if let smartHash = oldHash,
               let match = allTracks.first(where: { $0.smartHash == smartHash }) {
                updatedFavorites[i] = match
                continue
            }

            // 2. По точному пути
            if let match = allTracks.first(where: { $0.url.path == oldPath }) {
                updatedFavorites[i] = match
                continue
            }

            // 3. По имени файла + длительности
            if let match = allTracks.first(where: {
                $0.url.lastPathComponent == fileName && abs($0.duration - oldDuration) < 1.0
            }) {
                updatedFavorites[i] = match
                continue
            }

            // 4. По имени файла
            if let match = allTracks.first(where: { $0.url.lastPathComponent == fileName }) {
                updatedFavorites[i] = match
            }
        }

        favorites = updatedFavorites
        saveState()
    }
    func finishRestoringState() {
        isRestoringState = false
    }
    
    var progressFraction: Double { guard duration > 0 else { return 0 }; return currentTime / duration }
    
    func play(_ track: Track, afterFinish: @escaping () -> Void) {
        VisualizationEngine.shared.cancelWaveformGeneration()
        
        // Сбрасываем позицию сразу, чтобы прогрессбар не мигнул
        // между обновлением duration и приходом currentTime из сервиса.
        progress.currentTime = track.cueStartTime ?? 0
        currentTrack = track
        lastPlayedTrackPath = track.smartHash ?? track.url.path
        progress.duration = track.duration
        
        updatePlayerTracksForCurrentMode()

        service.play(
            track,
            volume: volume,
            startTime: track.cueStartTime,
            duration: track.cueStartTime != nil ? track.duration : nil
        ) { [weak self] in
            DispatchQueue.main.async {
                afterFinish()
            }
        }

        TrackStatisticsService.shared.recordPlay(
            track: track,
            context: playbackContextDescription,
            listenedDuration: track.duration
        )

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
        currentTrack = track; lastPlayedTrackPath = track.smartHash ?? track.url.path; progress.duration = track.duration
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
    func playFromRemote() {
        guard currentTrack != nil, !isPlaying else { return }
        togglePlayPause()
    }

    func pauseFromRemote() {
        guard currentTrack != nil, isPlaying else { return }
        togglePlayPause()
    }
    func togglePlayPause() {
        guard currentTrack != nil else { return }
        isPlaying ? service.pause() : service.resume()
        saveState()
    }
    
    func stop() {
        lastPlayedTime = progress.currentTime
        VisualizationEngine.shared.cancelWaveformGeneration()
        service.stop()
        currentTrack = nil
        progress.currentTime = 0
        progress.duration = 0
        saveState()
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.objectWillChange.send()
        }
    }
    
    func seek(to fraction: Double) {
        let time = fraction * duration
        service.seek(to: time)
    }
    
    func toggleFavorite(_ track: Track) {
        if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(track)
        }
        saveState()
    }
    func isFavorite(_ track: Track) -> Bool { favorites.contains(where: { $0.id == track.id }) }
    
    func playPreviousTrack() {
        guard let current = currentTrack else { return }

        if currentTime > 10 {
            seek(to: 0)
            return
        }

        TrackStatisticsService.shared.recordSkip(
            track: current,
            context: playbackContextDescription
        )

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

        if let current = currentTrack {
            TrackStatisticsService.shared.recordSkip(
                track: current,
                context: playbackContextDescription
            )
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
        service.preloadNextTrack(next, volume: volume) { [weak self] in
            self?.playNextTrack()
        }
        VisualizationEngine.shared.preloadWaveform(for: next)
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

        let cueAlbums = LibraryViewModel.shared?.cueAlbums ?? []

        queue = pendingQueuePaths.compactMap { path in
            if let track = tracks.first(where: { $0.smartHash == path }) {
                return track
            }

            if let track = tracks.first(where: { $0.url.path == path }) {
                return track
            }

            if let track = tracks.first(where: {
                $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent
            }) {
                return track
            }

            if let cueTrack = Self.findCUETrack(hash: path, in: cueAlbums) {
                return cueTrack
            }

            return nil
        }

        pendingQueuePaths = []
    }
    
    func restoreFavorites(from tracks: [Track]) {
        guard !pendingFavoriteInfos.isEmpty else { return }

        let cueAlbums = LibraryViewModel.shared?.cueAlbums ?? []
        var restored: [Track] = []

        for info in pendingFavoriteInfos {
            // 0. Cue-трек — ищем по детерминированному hash в cueAlbums
            if let cueTrack = Self.findCUETrack(hash: info.path, in: cueAlbums) {
                restored.append(cueTrack)
                continue
            }

            if let track = tracks.first(where: { $0.smartHash == info.path }) {
                restored.append(track)
                continue
            }

            if let track = tracks.first(where: { $0.url.path == info.path }) {
                restored.append(track)
                continue
            }

            if let track = tracks.first(where: {
                $0.url.lastPathComponent == URL(fileURLWithPath: info.path).lastPathComponent
            }) {
                restored.append(track)
                continue
            }

            let placeholder = Track(
                url: URL(fileURLWithPath: info.path),
                fileName: URL(fileURLWithPath: info.path).lastPathComponent,
                title: info.title,
                artist: info.artist,
                album: NSLocalizedString("unknown_album", comment: ""),
                year: nil,
                duration: 0,
                trackNumber: nil,
                genre: nil,
                albumArtURL: nil,
                replayGain: nil,
                replayGainPeak: nil,
                replayGainAlbum: nil,
                replayGainAlbumPeak: nil,
                lyricsURL: nil,
                unsyncedLyrics: nil
            )
            restored.append(placeholder)
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
            queuePaths: queue.map { $0.smartHash ?? $0.url.path },
            favoriteInfos: favorites.map {
                FavoriteInfo(
                    path: $0.smartHash ?? $0.url.path,
                    title: $0.title,
                    artist: $0.artist
                )
            },
            timestamp: Date(),
            currentCueStartTime: currentTrack?.cueStartTime
        )
        do {
            let data = try JSONEncoder().encode(state)
            PlayerStateManager.shared.savePlayer(state)
        } catch {
        }
    }
    func restoreState(tracks: [Track]) -> (track: Track?, time: TimeInterval)? {
        guard let state = PlayerStateManager.shared.loadPlayer() else { return nil }

        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
        shuffleMode = state.shuffleMode

        guard let p = state.currentTrackPath else { return nil }

        let track: Track?

        if let match = tracks.first(where: { $0.smartHash == p }) {
            track = match
        } else if let match = tracks.first(where: { $0.url.path == p }) {
            track = match
        } else if let match = tracks.first(where: {
            $0.url.lastPathComponent == URL(fileURLWithPath: p).lastPathComponent
        }) {
            track = match
        } else {
            track = nil
        }

        guard let resolved = track else { return nil }
        return (resolved, state.currentTime)
    }
    func setVolumeWithoutUI(_ volume: Float) {
        isRestoringState = true
        self.volume = volume
        service.setVolume(volume)
        isRestoringState = false
    }
    /// Ищет cue-трек по детерминированному hash среди всех cue-альбомов.
    private static func findCUETrack(hash: String, in cueAlbums: [CUEAlbum]) -> Track? {
        for album in cueAlbums {
            if let match = album.makeTracks().first(where: { $0.smartHash == hash }) {
                return match
            }
        }
        return nil
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
        autoSaveTimer?.invalidate()
        saveDebouncer?.invalidate()
    }
}
