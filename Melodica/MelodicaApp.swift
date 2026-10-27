// MelodicaApp.swift
import SwiftUI
import MediaPlayer
@preconcurrency import Translation

extension Notification.Name {
    static let toggleMiniPlayer = Notification.Name("toggleMiniPlayer")
    static let saveStateOnExit = Notification.Name("saveStateOnExit")
    static let enrichmentComplete = Notification.Name("enrichmentComplete")
    static let openSettingsSheet = Notification.Name("openSettingsSheet")
    static let trackRatingChanged = Notification.Name("trackRatingChanged")
    static let allFoldersLoaded = Notification.Name("allFoldersLoaded")
    static let mainWindowHidden = Notification.Name("mainWindowHidden")
    static let mainWindowShown = Notification.Name("mainWindowShown")
    static let detailHeaderHeightChanged = Notification.Name("detailHeaderHeightChanged")
    static let clearTrackSelection = Notification.Name("clearTrackSelection")
    static let focusSearch = Notification.Name("focusSearch")
    static let toggleLyricsPanel = Notification.Name("toggleLyricsPanel")
}

@main
struct MelodicaApp: App {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    @State private var isMiniPlayer = false
    @State private var hasRestored = false
    @State private var savedMainWindowSize = NSSize(width: 960, height: 640)
    @ObservedObject private var translationService = LyricsTranslationService.shared
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("Melodica", id: "main") {
            ZStack {
                if isMiniPlayer {
                    if SettingsManager.shared.activeTheme == "liquid_glass" {
                        if #available(macOS 26.0, *) {
                            LiquidGlassMiniPlayerView(playerVM: playerVM, onExpand: {
                                expandMiniPlayer()
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
                            MiniPlayerView(playerVM: playerVM, onExpand: {
                                expandMiniPlayer()
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
                        }
                    } else {
                        MiniPlayerView(playerVM: playerVM, onExpand: {
                            expandMiniPlayer()
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
                    }
                } else {
                    Group {
                        if SettingsManager.shared.activeTheme == "liquid_glass" {
                            if #available(macOS 26.0, *) {
                                LiquidGlassContentView(
                                    libraryVM: libraryVM,
                                    playerVM: playerVM,
                                    hasRestored: $hasRestored
                                )
                                .frame(minWidth: 960, minHeight: 640)
                                .toolbar {
                                    ToolbarItem(placement: .navigation) {
                                        Text("")
                                            .font(.system(size: 0.1))
                                            .opacity(0)
                                    }
                                }
                            } else {
                                ContentView(
                                    libraryVM: libraryVM,
                                    playerVM: playerVM,
                                    hasRestored: $hasRestored
                                )
                                .frame(minWidth: 960, minHeight: 640)
                            }
                        } else {
                            ContentView(
                                libraryVM: libraryVM,
                                playerVM: playerVM,
                                hasRestored: $hasRestored
                            )
                            .frame(minWidth: 960, minHeight: 640)
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)), removal: .opacity))
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                                window.delegate = AppDelegate.shared
                            }
                            LocalKeyboardShortcutManager.shared.startMonitoring(
                                playerVM: playerVM,
                                libraryVM: libraryVM
                            )
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isMiniPlayer)
            .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
                toggleMiniPlayer()
            }
            .environment(\.locale, Locale(identifier: SettingsManager.shared.language))
            .translationTask(translationService.translationConfiguration) { session in
                await LyricsTranslationService.shared.handleSession(session)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            
            CommandGroup(replacing: .appSettings) {
                Button(LocalizedStringKey("open_settings")) {
                    NotificationCenter.default.post(name: .openSettingsSheet, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Divider()
                
                Button(LocalizedStringKey("check_updates")) {
                    if let url = URL(string: "https://github.com/Yi0027/Melodica/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button(LocalizedStringKey("github_repo")) {
                    if let url = URL(string: "https://github.com/Yi0027/Melodica") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            CommandGroup(replacing: .help) {
                Button(LocalizedStringKey("report_issue")) {
                    if let url = URL(string: "https://github.com/Yi0027/Melodica/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            CommandMenu(Text(LocalizedStringKey("debug_menu_title"))) {
                Button(LocalizedStringKey("debug_menu_developer_diagnostics")) {
                    DeveloperDiagnosticsWindowController.shared.present(
                        libraryVM: libraryVM,
                        playerVM: playerVM
                    )
                }
                
                Button(LocalizedStringKey("debug_menu_recommendation_simulator")) {
                    RecommendationSimulatorWindowController.shared.present(
                        libraryVM: libraryVM
                    )
                }
                
                Divider()
                
                Button(LocalizedStringKey("debug_menu_clear_image_cache")) {
                    ImageCache.shared.clearMemory()
                }
                
                Divider()
                
                Button(LocalizedStringKey("debug_menu_reset_player_state")) {
                    showResetPlayerStateAlert()
                }
            }
        }
        
        MenuBarExtra {
            MenuBarContent(playerVM: playerVM, libraryVM: libraryVM)
        } label: {
            MenuBarStatusItemView(playerVM: playerVM)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func expandMiniPlayer() {
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
    }

    private func toggleMiniPlayer() {
        if isMiniPlayer {
            expandMiniPlayer()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { isMiniPlayer = true }
        }
    }

    private func showResetPlayerStateAlert() {
        AppResetService.shared.confirmAndResetApplication(
            playerVM: playerVM,
            libraryVM: libraryVM
        )
    }

    private func setupMediaControls() {
        MediaKeysHandler.shared.startMonitoring(
            playerVM: playerVM,
            tracks: {
                libraryVM.filteredTracks
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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        VisualizationEngine.shared.syncModeWithSettings()

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
        WaveformCache.shared.flushSync()
        TrackStatisticsService.shared.flushSync()
        PlayerViewModel.shared?.saveStateSync()
    }
    
    @objc private func handleQuit() {
        quitOrWarn()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.title == "Melodica" {
            hideMainWindow()
            return false
        }
        return true
    }

    // MARK: - Hide / Show main window

    func hideMainWindow() {
        NotificationCenter.default.post(name: .saveStateOnExit, object: nil)
        NotificationCenter.default.post(name: .mainWindowHidden, object: nil)

        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title == "Melodica" })?.orderOut(nil)
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        ImageCache.shared.clearMemory()
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .mainWindowShown, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Quit

    func quitOrWarn() {
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
