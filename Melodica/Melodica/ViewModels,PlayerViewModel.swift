// ViewModels,PlayerViewModel.swift
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
        
        var name: String {
            switch self {
            case .library: return "Library"
            case .album: return "Album"
            case .playlist(_, let name): return name
            case .queue: return "Queue"
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
    
    private let service = AudioPlayerService()
    private var cancellables = Set<AnyCancellable>()
    private var autoSaveTimer: Timer?
    private var lastSavedVolume: Float = 0.5
    private var lastPlayedTrackPath: String?
    private var lastPlayedTime: TimeInterval = 0
    private var pendingQueuePaths: [String] = []
    private var pendingFavoritePaths: [String] = []
    
    init() {
        service.$currentTime
            .receive(on: RunLoop.main)
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)
        service.$isPlaying
            .receive(on: RunLoop.main)
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        $currentTrack.dropFirst().sink { [weak self] track in
            if let track = track { self?.lastPlayedTrackPath = track.url.path; self?.saveState() }
        }.store(in: &cancellables)
        $volume.sink { [weak self] v in
            self?.service.setVolume(v)
            if self?.lastSavedVolume != v { self?.lastSavedVolume = v; self?.saveState() }
        }.store(in: &cancellables)
        $queue.dropFirst().sink { [weak self] _ in self?.saveState() }.store(in: &cancellables)
        $repeatMode.dropFirst().sink { [weak self] _ in self?.saveState() }.store(in: &cancellables)
        $shuffleMode.dropFirst().sink { [weak self] _ in self?.saveState() }.store(in: &cancellables)
        $favorites.dropFirst().sink { [weak self] _ in self?.saveState() }.store(in: &cancellables)
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.saveState() }
        
        if let state = PlayerStateManager.shared.load() {
            volume = state.volume; lastSavedVolume = state.volume
            lastPlayedTrackPath = state.currentTrackPath; lastPlayedTime = state.currentTime
            shuffleMode = state.shuffleMode
            repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
            pendingQueuePaths = state.queuePaths
            pendingFavoritePaths = state.favoritePaths
        }
        service.setVolume(volume)
    }
    
    var progress: Double { guard duration > 0 else { return 0 }; return currentTime / duration }
    
    func play(_ track: Track, afterFinish: @escaping () -> Void) {
        currentTrack = track; lastPlayedTrackPath = track.url.path; duration = track.duration
        service.play(track, volume: volume) { [weak self] in DispatchQueue.main.async { afterFinish() } }
        saveState()
    }
    
    func playPaused(_ track: Track) {
        currentTrack = track
        lastPlayedTrackPath = track.url.path
        duration = track.duration
        service.play(track, volume: volume) { [weak self] in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.service.pause()
        }
        saveState()
    }
    
    func playNextInQueue() -> Track? { guard !queue.isEmpty else { return nil }; let next = queue.removeFirst(); saveState(); return next }
    func addToQueue(_ track: Track) { guard !queue.contains(where: { $0.id == track.id }) else { return }; queue.append(track); saveState() }
    func removeFromQueue(_ track: Track) { queue.removeAll { $0.id == track.id }; saveState() }
    func clearQueue() { queue.removeAll(); saveState() }
    func togglePlayPause() { isPlaying ? service.pause() : service.resume(); saveState() }
    func stop() { lastPlayedTime = currentTime; service.stop(); currentTrack = nil; currentTime = 0; duration = 0; saveState() }
    func seek(to fraction: Double) { service.seek(to: fraction * duration) }
    
    func toggleFavorite(_ track: Track) {
        if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(track)
        }
        saveState()
    }
    func isFavorite(_ track: Track) -> Bool { favorites.contains(where: { $0.id == track.id }) }
    
    func restoreQueue(from tracks: [Track]) {
        guard !pendingQueuePaths.isEmpty else { return }
        queue = pendingQueuePaths.compactMap { path in tracks.first { $0.url.path == path } }
        pendingQueuePaths = []
    }
    func restoreFavorites(from tracks: [Track]) {
        guard !pendingFavoritePaths.isEmpty else { return }
        favorites = pendingFavoritePaths.compactMap { path in tracks.first { $0.url.path == path } }
        pendingFavoritePaths = []
    }
    
    func saveState() {
        var state = PlayerStateManager.shared.load() ?? PlayerState(
            lastFolderBookmark: nil, currentTrackPath: nil, currentTime: 0, volume: 0.5,
            repeatMode: "off", shuffleMode: false, queuePaths: [], favoritePaths: [], timestamp: Date()
        )
        state.currentTrackPath = lastPlayedTrackPath ?? currentTrack?.url.path
        state.currentTime = currentTime > 0 ? currentTime : lastPlayedTime
        state.volume = volume; state.repeatMode = repeatMode.rawValue
        state.shuffleMode = shuffleMode; state.queuePaths = queue.map { $0.url.path }
        state.favoritePaths = favorites.map { $0.url.path }; state.timestamp = Date()
        PlayerStateManager.shared.save(state: state)
    }
    
    func restoreState(tracks: [Track]) -> (track: Track?, time: TimeInterval)? {
        guard let state = PlayerStateManager.shared.load() else { return nil }
        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off; shuffleMode = state.shuffleMode
        guard let p = state.currentTrackPath, let t = tracks.first(where: { $0.url.path == p }) else { return nil }
        return (t, state.currentTime)
    }
}
