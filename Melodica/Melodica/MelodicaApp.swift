// MelodicaApp.swift
import SwiftUI
import MediaPlayer

extension Notification.Name {
    static let toggleMiniPlayer = Notification.Name("toggleMiniPlayer")
    static let saveStateOnExit = Notification.Name("saveStateOnExit")
    static let enrichmentComplete = Notification.Name("enrichmentComplete")
}

@main
struct MelodicaApp: App {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    @State private var isMiniPlayer = false
    @State private var hasRestored = false
    @State private var savedMainWindowSize = NSSize(width: 960, height: 640)
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("Melodica", id: "main") {
            ZStack {
                if isMiniPlayer {
                    MiniPlayerView(playerVM: playerVM, onExpand: {
                        withAnimation(.easeInOut(duration: 0.3)) { isMiniPlayer = false }
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                                window.setContentSize(savedMainWindowSize)
                                window.minSize = NSSize(width: 960, height: 640)
                                window.maxSize = NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
                                window.level = .normal
                                window.delegate = AppDelegate.shared
                            }
                        }
                    }, tracks: libraryVM.filteredTracks)
                    .frame(minWidth: 400, minHeight: 520)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                                if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                                savedMainWindowSize = window.frame.size
                                window.setContentSize(NSSize(width: 400, height: 550))
                                window.minSize = NSSize(width: 400, height: 520)
                                window.maxSize = NSSize(width: 400, height: CGFloat.infinity)
                                window.titleVisibility = .hidden
                                window.titlebarSeparatorStyle = .none
                                window.titlebarAppearsTransparent = true
                                window.isOpaque = false
                                window.backgroundColor = NSColor.clear
                                window.delegate = MiniPlayerWindowDelegate.shared
                                window.level = .floating
                                window.collectionBehavior = [.canJoinAllSpaces, .stationary]
                            }
                        }
                    }
                } else {
                    ContentView(libraryVM: libraryVM, playerVM: playerVM, hasRestored: $hasRestored)
                        .frame(minWidth: 960, minHeight: 640)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)), removal: .opacity))
                        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
                            withAnimation(.easeInOut(duration: 0.3)) { isMiniPlayer = true }
                        }
                        .onAppear {
                            setupMediaControls()
                            DispatchQueue.main.async {
                                if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                                    window.delegate = AppDelegate.shared
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isMiniPlayer)
            .environment(\.locale, Locale(identifier: SettingsManager.shared.language))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
    
    private func setupMediaControls() {
        MediaKeysHandler.shared.startMonitoring(
            playerVM: playerVM,
            tracks: { [weak libraryVM] in
                return libraryVM?.filteredTracks ?? []
            },
            playTrack: { track, completion in
                playerVM.playerTracks = libraryVM.filteredTracks
                playerVM.play(track, afterFinish: completion)
            },
            stopPlayer: {
                playerVM.stop()
            }
        )
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let mainMenu = NSApp.mainMenu,
           let appMenu = mainMenu.item(at: 0)?.submenu {
            for item in appMenu.items {
                if item.action == #selector(NSApplication.terminate(_:)) {
                    item.action = #selector(handleQuit)
                    item.target = self
                    break
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        MediaKeysHandler.shared.stopMonitoring()
    }
    
    @objc private func handleQuit() {
        quitOrWarn()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.title == "Melodica" {
            quitOrWarn()
            return false
        }
        return true
    }
    
    private func quitOrWarn() {
        guard LibraryViewModel.shared?.isEnriching == true else {
            NotificationCenter.default.post(name: .saveStateOnExit, object: nil)
            NSApp.terminate(nil)
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
            window.makeKeyAndOrderFront(nil)
        }
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("scanning_in_progress", comment: "")
        alert.informativeText = NSLocalizedString("scanning_in_progress_hint", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("wait", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("exit_anyway", comment: ""))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NotificationCenter.default.post(name: .saveStateOnExit, object: nil)
            NSApp.terminate(nil)
        }
    }
}
