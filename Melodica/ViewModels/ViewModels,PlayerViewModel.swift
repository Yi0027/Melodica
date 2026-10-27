// ViewModels/PlayerViewModel.swift
import SwiftUI
import Combine
import MediaPlayer

@MainActor
final class PlayerViewModel: ObservableObject {
    static weak var shared: PlayerViewModel?
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    let volumeState = PlaybackVolume()

    var volume: Float {
        get { volumeState.volume }
        set { volumeState.volume = newValue }
    }

    var volumeBinding: Binding<Float> {
        Binding(
            get: { self.volumeState.volume },
            set: { self.volumeState.volume = $0 }
        )
    }

    let progress = PlaybackProgress()

    var currentTime: TimeInterval { progress.currentTime }
    var duration: TimeInterval { progress.duration }
    @Published var queue: [QueueItem] = []
    @Published var currentQueueItemID: UUID? = nil
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleMode: Bool = false
    @Published var favorites: [Track] = []
    @Published var playbackMode: PlaybackMode = .library
    @Published var activeContextID: String? = nil
    @Published var activeQueueContextID: String? = nil

    var canGoNext: Bool {
        if repeatMode == .one { return true }
        if !queue.isEmpty { return true }
        if !playerTracks.isEmpty, let current = currentTrack,
           let idx = playerTracks.firstIndex(where: { $0.id == current.id }) {
            return idx + 1 < playerTracks.count || repeatMode == .all
        }
        return false
    }

    var canGoPrevious: Bool {
        return currentTrack != nil
    }

    func isTrackCurrent(_ track: Track, inContext contextID: String) -> Bool {
        return activeContextID == contextID && currentTrack?.id == track.id
    }

    func startPlayback(track: Track, from tracks: [Track], contextID: String) {
        let now = Date()
        guard now.timeIntervalSince(lastTrackSwitchTime) >= trackSwitchCooldown else { return }
        lastTrackSwitchTime = now

        if let current = currentTrack, current.id != track.id, isPlaying, SettingsManager.shared.trackStatisticsEnabled {
            let listened = progress.currentTime
            let isNearEnd = current.duration > 0 && (listened / current.duration) >= 0.85
            let previousContext = playbackContextDescription
            Task {
                if isNearEnd {
                    await TrackStatisticsService.shared.recordPlay(
                        track: current,
                        context: previousContext,
                        listenedDuration: listened
                    )
                } else {
                    await TrackStatisticsService.shared.recordSkip(
                        track: current,
                        context: previousContext,
                        listenedDuration: listened
                    )
                }
            }
        }

        activeContextID = contextID
        activeQueueContextID = contextID
        playerTracks = tracks
        playbackMode = .album(tracks)
        play(track) { [weak self] in
            self?.playNextTrack()
        }
    }

    private func isTrackAvailable(_ track: Track, watchedPaths: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            return false
        }
        if watchedPaths.isEmpty {
            return true
        }
        return watchedPaths.contains { track.url.path.hasPrefix($0) }
    }

    var missingFavorites: [Track] {
        let watchedPaths = LibraryViewModel.shared?.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" } ?? []
        return favorites.filter { !isTrackAvailable($0, watchedPaths: watchedPaths) }
    }

    var availableFavorites: [Track] {
        let watchedPaths = LibraryViewModel.shared?.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" } ?? []
        return favorites.filter { isTrackAvailable($0, watchedPaths: watchedPaths) }
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
    nonisolated(unsafe) private var autoSaveTimer: Timer?
    nonisolated(unsafe) private var saveDebouncer: Timer?
    nonisolated(unsafe) private var observerTokens: [any NSObjectProtocol] = []
    private var preloadedTrack: Track?
    private var preloadedQueueItem: QueueItem?
    private var lastSavedVolume: Float = 0.5
    private var lastPlayedTrackPath: String?
    private var lastPlayedTime: TimeInterval = 0
    private var pendingQueuePaths: [String] = []
    private var pendingFavoriteInfos: [FavoriteInfo] = []
    private var isRestoringState = true
    private var pendingQueueItemID: UUID? = nil
    private var lastTrackSwitchTime: Date = .distantPast
    private let trackSwitchCooldown: TimeInterval = 0.20

    var playerTracks: [Track] = []
    private var playbackContextDescription: String {
        if let active = activeContextID, !active.isEmpty {
            if active.starts(with: "rec_") {
                return "recommendations"
            }
            if active == "queue" {
                return "queue"
            }
            if active == "favorites" {
                return "favorites"
            }
            if active.starts(with: "playlist:") {
                return active
            }
            if active.starts(with: "album:") {
                return "album"
            }
            if active.starts(with: "tracks") {
                return "library"
            }
            return active
        }
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
        PlayerViewModel.shared = self
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
            .sink { [weak self] time in
                guard let self = self else { return }
                if self.progress.duration > 0 {
                    self.progress.currentTime = min(max(0, time), self.progress.duration)
                } else {
                    self.progress.currentTime = max(0, time)
                }
            }
            .store(in: &cancellables)

        service.$isPlaying
            .sink { [weak self] playing in
                guard let self = self else { return }
                self.isPlaying = playing
                MediaKeysHandler.shared.updatePlaybackState(isPlaying: playing, currentTime: self.currentTime)
            }
            .store(in: &cancellables)

        $currentTrack.dropFirst().sink { [weak self] track in
            guard let self = self, !self.isRestoringState else { return }
            if let track = track { self.lastPlayedTrackPath = track.url.path; self.scheduleSave() }
        }.store(in: &cancellables)

        $currentTrack
            .sink { [weak self] track in
                guard let self = self else { return }
                EQPresetManager.shared.autoApplyIfNeeded(for: track?.genre)
                MediaKeysHandler.shared.updateTrackInfo(track: track, isPlaying: self.isPlaying, currentTime: self.currentTime)
            }
            .store(in: &cancellables)

        volumeState.$volume.sink { [weak self] v in
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
            MainActor.assumeIsolated {
                guard let self = self, !self.isRestoringState else { return }
                self.saveState()
            }
        }

        service.setVolume(volume)

        let t1 = NotificationCenter.default.addObserver(forName: NSNotification.Name("allFoldersLoaded"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFavorites()
            }
        }
        observerTokens.append(t1)

        let t2 = NotificationCenter.default.addObserver(forName: .enrichmentComplete, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isRestoringState = false
                self?.refreshFavorites()
            }
        }
        observerTokens.append(t2)

        let t3 = NotificationCenter.default.addObserver(forName: .saveStateOnExit, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveState()
            }
        }
        observerTokens.append(t3)

        let t4 = NotificationCenter.default.addObserver(forName: .crossfadeStarted, object: nil, queue: .main) { [weak self] notification in
            let track = notification.object as? Track
            MainActor.assumeIsolated {
                guard let self = self, let track else { return }

                if let oldTrack = self.currentTrack, SettingsManager.shared.trackStatisticsEnabled {
                    let oldContext = self.playbackContextDescription
                    Task {
                        await TrackStatisticsService.shared.recordPlay(
                            track: oldTrack,
                            context: oldContext,
                            listenedDuration: oldTrack.duration
                        )
                    }
                }

                self.currentTrack = track
                self.lastPlayedTrackPath = track.smartHash ?? track.url.path
                self.progress.duration = track.duration
                self.progress.currentTime = 0

                if let item = self.queue.first(where: { $0.track.id == track.id }) {
                    self.currentQueueItemID = item.id
                } else {
                    self.currentQueueItemID = nil
                }
                self.scheduleSave()
            }
        }
        observerTokens.append(t4)

        let t5 = NotificationCenter.default.addObserver(forName: .trackRatingChanged, object: nil, queue: .main) { [weak self] notification in
            let track = notification.object as? Track
            MainActor.assumeIsolated {
                guard let self = self, let track else { return }
                if let idx = self.favorites.firstIndex(where: { $0.id == track.id }) {
                    self.favorites[idx].rating = track.rating
                    self.saveState()
                }
                if self.currentTrack?.id == track.id {
                    self.currentTrack?.rating = track.rating
                }
            }
        }
        observerTokens.append(t5)

        let t6 = NotificationCenter.default.addObserver(forName: .trackChanged, object: nil, queue: .main) { [weak self] notification in
            let track = notification.object as? Track
            MainActor.assumeIsolated {
                guard let self = self else { return }

                if let track {
                    if self.currentTrack?.id != track.id {
                        if let oldTrack = self.currentTrack, SettingsManager.shared.trackStatisticsEnabled {
                            let oldContext = self.playbackContextDescription
                            Task {
                                await TrackStatisticsService.shared.recordPlay(
                                    track: oldTrack,
                                    context: oldContext,
                                    listenedDuration: oldTrack.duration
                                )
                            }
                        }

                        self.currentTrack = track
                        self.progress.duration = track.duration
                        self.progress.currentTime = 0
                    }
                    self.lastPlayedTrackPath = track.smartHash ?? track.url.path

                    if self.repeatMode == .off {
                        if let pending = self.pendingQueueItemID,
                           let idx = self.queue.firstIndex(where: { $0.id == pending }) {
                            self.queue.remove(at: idx)
                        } else if let idx = self.queue.firstIndex(where: { $0.track.id == track.id }) {
                            self.queue.remove(at: idx)
                        }
                    }

                    if let pending = self.pendingQueueItemID {
                        self.currentQueueItemID = pending
                        self.pendingQueueItemID = nil
                    } else if let item = self.queue.first(where: { $0.track.id == track.id }) {
                        self.currentQueueItemID = item.id
                    } else {
                        self.currentQueueItemID = nil
                    }
                    self.scheduleSave()
                } else {
                    self.stop()
                }
            }
        }
        observerTokens.append(t6)

        let t7 = NotificationCenter.default.addObserver(forName: .prepareNextTrack, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareNextTrack()
            }
        }
        observerTokens.append(t7)
    }

    private func scheduleSave() {
        saveDebouncer?.invalidate()
        saveDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveState()
            }
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

            if let hash = oldHash, let cueTrack = Self.findCUETrack(hash: hash, in: cueAlbums) {
                updatedFavorites[i] = cueTrack
                continue
            }

            if let smartHash = oldHash,
               let match = allTracks.first(where: { $0.smartHash == smartHash }) {
                updatedFavorites[i] = match
                continue
            }

            if let match = allTracks.first(where: { $0.url.path == oldPath }) {
                updatedFavorites[i] = match
                continue
            }

            if let match = allTracks.first(where: {
                $0.url.lastPathComponent == fileName && abs($0.duration - oldDuration) < 1.0
            }) {
                updatedFavorites[i] = match
                continue
            }

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
        lastTrackSwitchTime = Date()
        currentQueueItemID = pendingQueueItemID
        pendingQueueItemID = nil

        progress.currentTime = 0
        currentTrack = track
        lastPlayedTrackPath = track.smartHash ?? track.url.path
        progress.duration = track.duration

        updatePlayerTracksForCurrentMode()

        service.cancelActiveCrossfade()

        service.play(
            track,
            volume: volume,
            startTime: track.cueStartTime,
            duration: track.cueStartTime != nil ? track.duration : nil
        ) { [weak self] in
            Task { @MainActor in
                _ = self
                afterFinish()
            }
        }

        scheduleSave()
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
        service.play(track, volume: volume, autoplay: false) { [weak self] in
            Task { @MainActor in
                self?.playNextTrack()
            }
        }
        saveState()
    }

    // MARK: - Queue

    func playNowFromQueue(_ item: QueueItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        let copy = item
        queue.remove(at: idx)
        scheduleSave()
        pendingQueueItemID = copy.id
        activeContextID = "queue"
        play(copy.track) { [weak self] in
            self?.playNextTrack()
        }
    }

    func addToQueue(_ track: Track) {
        queue.append(QueueItem(track: track))
        saveState()
    }

    func removeFromQueue(_ track: Track) {
        queue.removeAll { $0.track.id == track.id }
        service.clearPreload()
        saveState()
    }

    func removeQueueItem(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
        if currentQueueItemID == item.id {
            currentQueueItemID = nil
        }
        service.clearPreload()
        saveState()
    }

    func clearQueue() {
        queue.removeAll()
        currentQueueItemID = nil
        saveState()
    }

    // MARK: - Queue reorder / external insert

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        saveState()
    }

    func insertTracksIntoQueue(ids: [UUID], at index: Int) {
        let resolved = resolveTracksByIDs(ids)
        guard !resolved.isEmpty else { return }
        let items = resolved.map { QueueItem(track: $0) }
        let safeIndex = max(0, min(index, queue.count))
        queue.insert(contentsOf: items, at: safeIndex)
        saveState()
    }

    private func resolveTracksByIDs(_ ids: [UUID]) -> [Track] {
        var found: [UUID: Track] = [:]
        let remaining = Set(ids)

        func harvest(_ source: [Track]) {
            for t in source where remaining.contains(t.id) && found[t.id] == nil {
                found[t.id] = t
            }
        }

        harvest(LibraryViewModel.shared?.tracks ?? [])
        harvest(playerTracks)
        harvest(queue.map(\.track))
        harvest(favorites)

        if found.count < ids.count, let cueAlbums = LibraryViewModel.shared?.cueAlbums {
            for album in cueAlbums {
                harvest(album.makeTracks())
                if found.count == ids.count { break }
            }
        }

        return ids.compactMap { found[$0] }
    }

    func playNextInQueue() -> Track? {
        guard !queue.isEmpty else { return nil }

        if repeatMode == .all {
            if shuffleMode {
                let other = queue.filter { $0.id != currentQueueItemID }
                if let random = other.randomElement() {
                    pendingQueueItemID = random.id
                    return random.track
                }
                pendingQueueItemID = queue.first?.id
                return queue.first?.track
            }

            guard let currentID = currentQueueItemID,
                  let idx = queue.firstIndex(where: { $0.id == currentID }) else {
                pendingQueueItemID = queue.first?.id
                return queue.first?.track
            }

            if idx + 1 < queue.count {
                pendingQueueItemID = queue[idx + 1].id
                return queue[idx + 1].track
            } else {
                pendingQueueItemID = queue.first?.id
                return queue.first?.track
            }
        }

        if shuffleMode {
            let other = queue.filter { $0.id != currentQueueItemID }
            if let random = other.randomElement() {
                pendingQueueItemID = random.id
                queue.removeAll { $0.id == random.id }
                saveState()
                return random.track
            }
            return nil
        }

        let next = queue.removeFirst()
        pendingQueueItemID = next.id
        saveState()
        return next.track
    }

    func playFromRemote() {
        guard currentTrack != nil else { return }
        if !isPlaying {
            service.resume()
            saveState()
        }
    }

    func pauseFromRemote() {
        guard currentTrack != nil else { return }
        if isPlaying {
            service.pause()
            saveState()
        }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        isPlaying ? service.pause() : service.resume()
        saveState()
    }

    func stop() {
        lastPlayedTime = progress.currentTime
        service.stop()
        currentTrack = nil
        progress.currentTime = 0
        progress.duration = 0
        saveState()

        // Already on MainActor — update directly without DispatchQueue.main.async
        self.isPlaying = false
        MediaKeysHandler.shared.clear()
        self.objectWillChange.send()
    }

    // MARK: - Full Reset to Blank State

    func resetToBlankState() {
        saveDebouncer?.invalidate()
        saveDebouncer = nil

        service.stop()
        service.clearPreload()

        currentTrack = nil
        isPlaying = false
        progress.currentTime = 0
        progress.duration = 0
        lastPlayedTime = 0
        lastPlayedTrackPath = nil

        volume = 0.5
        service.setVolume(0.5)
        lastSavedVolume = 0.5
        repeatMode = .off
        shuffleMode = false
        playbackMode = .library
        activeContextID = nil
        activeQueueContextID = nil
        playerTracks.removeAll()

        queue.removeAll()
        currentQueueItemID = nil
        pendingQueuePaths.removeAll()
        pendingQueueItemID = nil

        favorites.removeAll()
        pendingFavoriteInfos.removeAll()

        AudioEffectsManager.shared.reset()
        EqualizerManager.shared.reset()

        MediaKeysHandler.shared.clear()

        PlayerStateManager.shared.clearPlayer()
        objectWillChange.send()
    }

    func seek(to fraction: Double) {
        guard fraction.isFinite, duration > 0, duration.isFinite else { return }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let time = clampedFraction * duration
        service.seek(to: time)
        MediaKeysHandler.shared.updateElapsedPlaybackTime(time)
    }

    func toggleFavorite(_ track: Track) {
        if let idx = favorites.firstIndex(where: {
            $0.id == track.id ||
            (track.smartHash != nil && $0.smartHash == track.smartHash) ||
            $0.url.path == track.url.path
        }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(track)
        }
        saveState()
        NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)
    }

    func isFavorite(_ track: Track) -> Bool {
        favorites.contains { fav in
            fav.id == track.id ||
            (track.smartHash != nil && fav.smartHash == track.smartHash) ||
            fav.url.path == track.url.path
        }
    }

    func playPreviousTrack() {
        let now = Date()
        guard now.timeIntervalSince(lastTrackSwitchTime) >= trackSwitchCooldown else { return }
        lastTrackSwitchTime = now

        guard let current = currentTrack else { return }

        if currentTime > 10 {
            seek(to: 0)
            return
        }

        if SettingsManager.shared.trackStatisticsEnabled {
            let listened = progress.currentTime
            Task {
                await TrackStatisticsService.shared.recordSkip(
                    track: current,
                    context: playbackContextDescription,
                    listenedDuration: listened
                )
            }
        }

        if !queue.isEmpty {
            if let idx = queue.firstIndex(where: { $0.track.id == current.id }), idx > 0 {
                activeContextID = "queue"
                play(queue[idx - 1].track) { [weak self] in self?.playNextTrack() }
                return
            }
            seek(to: 0)
            return
        }

        if !playerTracks.isEmpty {
            if shuffleMode {
                let other = playerTracks.filter { $0.id != current.id }
                if let random = other.randomElement() {
                    activeContextID = activeQueueContextID
                    play(random) { [weak self] in self?.playNextTrack() }
                }
                return
            }
            guard let idx = playerTracks.firstIndex(where: { $0.id == current.id }), idx > 0 else {
                seek(to: 0)
                return
            }
            activeContextID = activeQueueContextID
            play(playerTracks[idx - 1]) { [weak self] in self?.playNextTrack() }
            return
        }

        seek(to: 0)
    }

    func skipToNextTrack() {
        let now = Date()
        guard now.timeIntervalSince(lastTrackSwitchTime) >= trackSwitchCooldown else { return }
        lastTrackSwitchTime = now

        if let current = currentTrack, SettingsManager.shared.trackStatisticsEnabled {
            let listened = progress.currentTime
            Task {
                await TrackStatisticsService.shared.recordSkip(
                    track: current,
                    context: playbackContextDescription,
                    listenedDuration: listened
                )
            }
        }

        if !queue.isEmpty {
            if let queued = playNextInQueue() {
                activeContextID = "queue"
                play(queued) { [weak self] in self?.playNextTrack() }
                return
            }
        }

        if !playerTracks.isEmpty, let current = currentTrack {
            if shuffleMode {
                if let preloaded = preloadedTrack, playerTracks.contains(where: { $0.id == preloaded.id }) {
                    let trackToPlay = preloaded
                    preloadedTrack = nil
                    preloadedQueueItem = nil
                    activeContextID = activeQueueContextID
                    play(trackToPlay) { [weak self] in self?.playNextTrack() }
                    return
                }
                let other = playerTracks.filter { $0.id != current.id }
                if let random = other.randomElement() {
                    activeContextID = activeQueueContextID
                    play(random) { [weak self] in self?.playNextTrack() }
                    return
                }
            } else {
                guard let idx = playerTracks.firstIndex(where: { $0.id == current.id }) else {
                    stop()
                    return
                }
                if idx + 1 < playerTracks.count {
                    activeContextID = activeQueueContextID
                    play(playerTracks[idx + 1]) { [weak self] in self?.playNextTrack() }
                } else if repeatMode == .all, let first = playerTracks.first {
                    activeContextID = activeQueueContextID
                    play(first) { [weak self] in self?.playNextTrack() }
                } else {
                    stop()
                }
                return
            }
        }

        stop()
    }

    func playNextTrack() {
        if repeatMode == .one, let current = currentTrack {
            pendingQueueItemID = currentQueueItemID
            play(current) { [weak self] in self?.playNextTrack() }
            return
        }

        if let current = currentTrack, SettingsManager.shared.trackStatisticsEnabled {
            Task {
                await TrackStatisticsService.shared.recordPlay(
                    track: current,
                    context: playbackContextDescription,
                    listenedDuration: current.duration
                )
            }
        }

        if !queue.isEmpty {
            if let preloaded = preloadedQueueItem, let idx = queue.firstIndex(where: { $0.id == preloaded.id }) {
                let item = queue.remove(at: idx)
                preloadedQueueItem = nil
                preloadedTrack = nil
                currentQueueItemID = item.id
                activeContextID = "queue"
                play(item.track) { [weak self] in self?.playNextTrack() }
                return
            } else if let queued = playNextInQueue() {
                preloadedQueueItem = nil
                preloadedTrack = nil
                activeContextID = "queue"
                play(queued) { [weak self] in self?.playNextTrack() }
                return
            }
        }

        if !playerTracks.isEmpty, let current = currentTrack {
            if shuffleMode {
                if let preloaded = preloadedTrack, playerTracks.contains(where: { $0.id == preloaded.id }) {
                    let trackToPlay = preloaded
                    preloadedTrack = nil
                    preloadedQueueItem = nil
                    activeContextID = activeQueueContextID
                    play(trackToPlay) { [weak self] in self?.playNextTrack() }
                    return
                }
                let other = playerTracks.filter { $0.id != current.id }
                if let random = other.randomElement() {
                    activeContextID = activeQueueContextID
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
                    activeContextID = activeQueueContextID
                    play(next) { [weak self] in self?.playNextTrack() }
                } else if repeatMode == .all, let first = playerTracks.first {
                    activeContextID = activeQueueContextID
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
        if let nextItem = getNextQueueItemForPreload() {
            pendingQueueItemID = nextItem.id
            preloadedQueueItem = nextItem
            preloadedTrack = nextItem.track
            service.preloadNextTrack(nextItem.track, volume: volume) { [weak self] in
                self?.playNextTrack()
            }
            VisualizationEngine.shared.preloadWaveform(for: nextItem.track)
            return
        }

        guard let next = getNextPlayerTrackForPreload() else {
            preloadedTrack = nil
            preloadedQueueItem = nil
            return
        }
        pendingQueueItemID = nil
        preloadedQueueItem = nil
        preloadedTrack = next
        service.preloadNextTrack(next, volume: volume) { [weak self] in
            self?.playNextTrack()
        }
        VisualizationEngine.shared.preloadWaveform(for: next)
    }

    private func getNextQueueItemForPreload() -> QueueItem? {
        guard !queue.isEmpty else { return nil }

        if shuffleMode {
            let other = queue.filter { $0.id != currentQueueItemID }
            return other.randomElement() ?? queue.first
        }

        if repeatMode == .all,
           let currentID = currentQueueItemID,
           let idx = queue.firstIndex(where: { $0.id == currentID }) {
            if idx + 1 < queue.count { return queue[idx + 1] }
            else { return queue.first }
        }

        if repeatMode == .one {
            if let currentID = currentQueueItemID,
               let item = queue.first(where: { $0.id == currentID }) {
                return item
            }
            return nil
        }

        return queue.first
    }

    private func getNextPlayerTrackForPreload() -> Track? {
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

        queue = pendingQueuePaths.compactMap { path -> QueueItem? in
            if let track = tracks.first(where: { $0.smartHash == path }) {
                return QueueItem(track: track)
            }
            if let track = tracks.first(where: { $0.url.path == path }) {
                return QueueItem(track: track)
            }
            if let track = tracks.first(where: {
                $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent
            }) {
                return QueueItem(track: track)
            }
            if let cueTrack = Self.findCUETrack(hash: path, in: cueAlbums) {
                return QueueItem(track: cueTrack)
            }
            return nil
        }

        pendingQueuePaths = []
        currentQueueItemID = nil
    }

    func restoreFavorites(from tracks: [Track]) {
        guard !pendingFavoriteInfos.isEmpty else { return }

        let cueAlbums = LibraryViewModel.shared?.cueAlbums ?? []
        var restored: [Track] = []

        for info in pendingFavoriteInfos {
            let hashToCheck = info.smartHash ?? (info.path.count == 64 && info.path.allSatisfy { $0.isHexDigit } ? info.path : nil)

            if let hash = hashToCheck, let cueTrack = Self.findCUETrack(hash: hash, in: cueAlbums) {
                restored.append(cueTrack)
                continue
            }

            if let hash = hashToCheck, let track = tracks.first(where: { $0.smartHash == hash }) {
                restored.append(track)
                continue
            }

            if let track = tracks.first(where: { $0.url.path == info.path }) {
                restored.append(track)
                continue
            }

            let fileName = URL(fileURLWithPath: info.path).lastPathComponent
            if let track = tracks.first(where: {
                $0.url.lastPathComponent == fileName
            }) {
                restored.append(track)
                continue
            }

            let isHash = hashToCheck != nil && hashToCheck == info.path
            let placeholder = Track(
                url: URL(fileURLWithPath: info.path),
                fileName: isHash ? info.title : fileName,
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
                unsyncedLyrics: nil,
                cueStartTime: nil,
                smartHash: hashToCheck
            )
            restored.append(placeholder)
        }

        favorites = restored
        pendingFavoriteInfos = []
        refreshFavorites()
    }

    func saveState() {
        let hasContent = (lastPlayedTrackPath != nil || currentTrack != nil) || !queue.isEmpty || !favorites.isEmpty
        guard hasContent else {
            PlayerStateManager.shared.clearPlayer()
            return
        }

        let state = PlayerState(
            currentTrackPath: lastPlayedTrackPath ?? currentTrack?.url.path,
            currentTime: currentTime > 0 ? currentTime : lastPlayedTime,
            volume: volume,
            repeatMode: repeatMode.rawValue,
            shuffleMode: shuffleMode,
            queuePaths: queue.map { $0.track.smartHash ?? $0.track.url.path },
            favoriteInfos: favorites.map {
                FavoriteInfo(
                    path: $0.url.path,
                    title: $0.title,
                    artist: $0.artist,
                    smartHash: $0.smartHash
                )
            },
            timestamp: Date(),
            currentCueStartTime: currentTrack?.cueStartTime,
            activeContextID: activeQueueContextID ?? activeContextID,
            playbackQueuePaths: playerTracks.map { $0.smartHash ?? $0.url.path }
        )
        PlayerStateManager.shared.savePlayer(state)
    }

    func saveStateSync() {
        let state = PlayerState(
            currentTrackPath: currentTrack?.smartHash ?? currentTrack?.url.path,
            currentTime: currentTime,
            volume: volume,
            repeatMode: repeatMode.rawValue,
            shuffleMode: shuffleMode,
            queuePaths: queue.map { $0.track.smartHash ?? $0.track.url.path },
            favoriteInfos: favorites.map {
                FavoriteInfo(
                    path: $0.url.path,
                    title: $0.title,
                    artist: $0.artist,
                    smartHash: $0.smartHash
                )
            },
            timestamp: Date(),
            currentCueStartTime: currentTrack?.cueStartTime,
            activeContextID: activeQueueContextID ?? activeContextID,
            playbackQueuePaths: playerTracks.map { $0.smartHash ?? $0.url.path }
        )
        PlayerStateManager.shared.savePlayerSync(state)
    }

    func restoreState(tracks: [Track]) -> (track: Track?, time: TimeInterval)? {
        guard let state = PlayerStateManager.shared.loadPlayer() else { return nil }

        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
        shuffleMode = state.shuffleMode

        if let savedContextID = state.activeContextID {
            activeContextID = savedContextID
            activeQueueContextID = savedContextID
        }

        if let savedQueuePaths = state.playbackQueuePaths, !savedQueuePaths.isEmpty {
            let cueAlbums = LibraryViewModel.shared?.cueAlbums ?? []
            let restoredTracks = savedQueuePaths.compactMap { path -> Track? in
                if let track = tracks.first(where: { $0.smartHash == path || $0.url.path == path || $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent }) {
                    return track
                }
                if let cueTrack = Self.findCUETrack(hash: path, in: cueAlbums) {
                    return cueTrack
                }
                return nil
            }
            if !restoredTracks.isEmpty {
                playerTracks = restoredTracks
            }
        }

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

    private static func findCUETrack(hash: String, in cueAlbums: [CUEAlbum]) -> Track? {
        for album in cueAlbums {
            if let match = album.makeTracks().first(where: { $0.smartHash == hash }) {
                return match
            }
        }
        return nil
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
        autoSaveTimer?.invalidate()
        saveDebouncer?.invalidate()
    }
}
