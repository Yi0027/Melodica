// services/Services,LocalKeyboardShortcutManager.swift
import AppKit
import SwiftUI

@MainActor
final class LocalKeyboardShortcutManager {
    static let shared = LocalKeyboardShortcutManager()

    private weak var playerVM: PlayerViewModel?
    private weak var libraryVM: LibraryViewModel?
    private var localMonitor: Any?

    private init() {}

    func startMonitoring(playerVM: PlayerViewModel, libraryVM: LibraryViewModel) {
        self.playerVM = playerVM
        self.libraryVM = libraryVM

        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyDown(event) {
                return nil // Event handled, prevent further propagation and system beeps
            }
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Must be the frontmost active app with a key window in focus
        guard NSApp.isActive, let keyWindow = NSApp.keyWindow, keyWindow.isKeyWindow else {
            return false
        }

        let isEditing = isEditingText(in: keyWindow)
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let flags = event.modifierFlags.intersection(relevantModifiers)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyCode = event.keyCode

        // 1. Cmd + F -> Focus Search (works anytime, even if already editing another field)
        if flags == .command && (chars == "f" || keyCode == 3) {
            NotificationCenter.default.post(name: .focusSearch, object: nil)
            return true
        }

        // 2. Escape -> Clear search / dismiss focus
        if flags.isEmpty && keyCode == 53 { // 53 = Escape
            if let lib = libraryVM, !lib.searchText.isEmpty {
                lib.searchText = ""
                keyWindow.makeFirstResponder(nil)
                return true
            } else if isEditing {
                keyWindow.makeFirstResponder(nil)
                return true
            }
            return false
        }

        // If the user is actively typing in a text field, do not intercept regular typing keys
        if isEditing {
            return false
        }

        // ==========================================
        // Shortcuts below only apply when NOT editing
        // ==========================================

        // 3. Space -> Play / Pause
        if flags.isEmpty && (keyCode == 49 || chars == " ") { // 49 = Space
            handlePlayPause()
            return true
        }

        // 4. Cmd + Shift + Right Arrow -> Next Track
        if flags == [.command, .shift] && keyCode == 124 { // 124 = Right Arrow
            playerVM?.skipToNextTrack()
            return true
        }

        // 5. Cmd + Shift + Left Arrow -> Previous Track
        if flags == [.command, .shift] && keyCode == 123 { // 123 = Left Arrow
            handlePreviousTrack()
            return true
        }

        // 6. Cmd + Shift + Up Arrow -> Volume Up (+5%)
        if flags == [.command, .shift] && keyCode == 126 { // 126 = Up Arrow
            adjustVolume(by: 0.05)
            return true
        }

        // 7. Cmd + Shift + Down Arrow -> Volume Down (-5%)
        if flags == [.command, .shift] && keyCode == 125 { // 125 = Down Arrow
            adjustVolume(by: -0.05)
            return true
        }

        // 8. Cmd + S -> Toggle Shuffle
        if flags == .command && (chars == "s" || keyCode == 1) { // 1 = 'S'
            guard let player = playerVM else { return false }
            player.shuffleMode.toggle()
            player.service.clearPreload()
            player.saveState()
            return true
        }

        // 9. Cmd + R -> Toggle Repeat Mode
        if flags == .command && (chars == "r" || keyCode == 15) { // 15 = 'R'
            guard let player = playerVM else { return false }
            switch player.repeatMode {
            case .off: player.repeatMode = .all
            case .all: player.repeatMode = .one
            case .one: player.repeatMode = .off
            }
            player.saveState()
            return true
        }

        // 10. Cmd + L -> Toggle Lyrics / Right Panel
        if flags == .command && (chars == "l" || keyCode == 37) { // 37 = 'L'
            NotificationCenter.default.post(name: .toggleLyricsPanel, object: nil)
            return true
        }

        // 11. Cmd + U -> Toggle Queue
        if flags == .command && (chars == "u" || keyCode == 32) { // 32 = 'U'
            NotificationCenter.default.post(name: NSNotification.Name("ToggleQueue"), object: nil)
            return true
        }

        // 12. Cmd + Shift + M -> Toggle Mini Player
        if flags == [.command, .shift] && (chars == "m" || keyCode == 46) { // 46 = 'M'
            NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
            return true
        }

        return false
    }

    private func handlePlayPause() {
        guard let player = playerVM else { return }
        if let current = player.currentTrack {
            if player.isPlaying {
                player.togglePlayPause()
            } else if player.currentTime > 0 {
                player.togglePlayPause()
            } else {
                player.play(current) { [weak player] in
                    player?.playNextTrack()
                }
            }
        } else if let first = libraryVM?.filteredTracks.first {
            let tracks = libraryVM?.filteredTracks ?? []
            player.startPlayback(track: first, from: tracks, contextID: "library")
        }
    }

    private func handlePreviousTrack() {
        guard let player = playerVM else { return }
        if player.currentTime > 5 {
            player.seek(to: 0)
        } else {
            player.playPreviousTrack()
        }
    }

    private func adjustVolume(by delta: Float) {
        guard let player = playerVM else { return }
        let current = player.volume
        let updated = max(0.0, min(1.0, current + delta))
        player.volume = (updated * 100).rounded() / 100
    }

    private func isEditingText(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        var current: NSResponder? = responder
        while let resp = current {
            if resp is NSTextView || resp is NSTextField || resp is NSTextInputClient {
                return true
            }
            current = resp.nextResponder
        }
        return false
    }
}
