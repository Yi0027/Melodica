// Services,MediaKeysHandler.swift
import Cocoa
import SwiftUI

class MediaKeysHandler {
    static let shared = MediaKeysHandler()
    
    private var eventMonitor: Any?
    private weak var playerVM: PlayerViewModel?
    private var tracksProvider: (() -> [Track])?
    private var selectedTrackIDProvider: (() -> Binding<UUID?>?)?
    
    func startMonitoring(
        playerVM: PlayerViewModel,
        tracks: @escaping () -> [Track],
        playTrack: @escaping (Track, @escaping () -> Void) -> Void,
        stopPlayer: @escaping () -> Void
    ) {
        self.playerVM = playerVM
        self.tracksProvider = tracks
        self.playTrack = playTrack
        self.stopPlayer = stopPlayer
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self = self,
                  let playerVM = self.playerVM else { return event }
            
            guard event.type == .systemDefined,
                  event.subtype.rawValue == 8 else { return event }
            
            let keyCode = (event.data1 & 0xFFFF0000) >> 16
            let keyFlags = (event.data1 & 0x0000FFFF)
            let keyState = (keyFlags & 0xFF00) >> 8
            
            guard keyState == 0xA else { return event }
            
            switch Int32(keyCode) {
            case NX_KEYTYPE_PLAY:
                DispatchQueue.main.async {
                    if playerVM.currentTrack != nil {
                        playerVM.togglePlayPause()
                    }
                }
                return nil
                
            case NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST:
                DispatchQueue.main.async { [weak self] in
                    self?.handleNext()
                }
                return nil
                
            case NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND:
                DispatchQueue.main.async { [weak self] in
                    self?.handlePrevious()
                }
                return nil
                
            default:
                break
            }
            
            return event
        }
    }
    
    private var playTrack: ((Track, @escaping () -> Void) -> Void)?
    private var stopPlayer: (() -> Void)?
    
    private func handleNext() {
        guard let playerVM = playerVM,
              let tracks = tracksProvider?() else { return }
        
        // Сначала проверяем очередь
        if let queued = playerVM.playNextInQueue() {
            playTrack?(queued) { self.handleNext() }
            return
        }
        
        // Shuffle
        if playerVM.shuffleMode {
            let other = tracks.filter { $0.id != playerVM.currentTrack?.id }
            if let random = other.randomElement() {
                playTrack?(random) { self.handleNext() }
            }
            return
        }
        
        guard let current = playerVM.currentTrack,
              let idx = tracks.firstIndex(where: { $0.id == current.id }) else { return }
        
        // Repeat one
        if playerVM.repeatMode == .one {
            playTrack?(current) { self.handleNext() }
            return
        }
        
        // Next track
        if idx + 1 < tracks.count {
            let next = tracks[idx + 1]
            playTrack?(next) { self.handleNext() }
        } else if playerVM.repeatMode == .all, let first = tracks.first {
            playTrack?(first) { self.handleNext() }
        } else {
            stopPlayer?()
        }
    }
    
    private func handlePrevious() {
        guard let playerVM = playerVM,
              let tracks = tracksProvider?() else { return }
        
        // Shuffle
        if playerVM.shuffleMode {
            let other = tracks.filter { $0.id != playerVM.currentTrack?.id }
            if let random = other.randomElement() {
                playTrack?(random) { self.handleNext() }
            }
            return
        }
        
        guard let current = playerVM.currentTrack,
              let idx = tracks.firstIndex(where: { $0.id == current.id }),
              idx > 0 else { return }
        
        let prev = tracks[idx - 1]
        playTrack?(prev) { self.handleNext() }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        playerVM = nil
        tracksProvider = nil
        playTrack = nil
        stopPlayer = nil
    }
}
