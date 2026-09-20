// MelodicaApp.swift
import SwiftUI
import MediaPlayer

extension Notification.Name {
    static let toggleMiniPlayer = Notification.Name("toggleMiniPlayer")
    static let saveStateOnExit = Notification.Name("saveStateOnExit")
    static let enrichmentComplete = Notification.Name("enrichmentComplete")
    static let openSettingsSheet = Notification.Name("openSettingsSheet")
    static let trackRatingChanged = Notification.Name("trackRatingChanged")
    static let allFoldersLoaded = Notification.Name("allFoldersLoaded")
    static let mainWindowHidden = Notification.Name("mainWindowHidden")
    static let mainWindowShown = Notification.Name("mainWindowShown")
}

@main
struct MelodicaApp: App {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    @State private var isMiniPlayer = false
    @State private var isHiddenInTray = false
    @State private var hasRestored = false
    @State private var savedMainWindowSize = NSSize(width: 960, height: 640)

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Melodica", id: "main") {
            ZStack {
                if isHiddenInTray {
                    // Пустышка: дерево вью полностью отгружено, память освобождена.
                    // При возврате главный UI / MiniPlayer рождаются заново.
                    Color.clear
                        .frame(width: 100, height: 100)
                } else if isMiniPlayer {
                    if SettingsManager.shared.activeTheme == "liquid_glass" {
                        if #available(macOS 26.0, *) {
                            LiquidGlassMiniPlayerView(playerVM: playerVM, onExpand: {
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
                        }
                    } else {
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
                    .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) { isMiniPlayer = true }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                                window.delegate = AppDelegate.shared
                            }
                        }
                        // Чистим свою tmp-папку сразу (в фоне, не блокирует UI)
                        MetadataWriter.cleanupTmpFolder()
                    }
                    // Когда watched-папки загружены — чистим мусор и в них
                    // (важно для внешних томов, где temp-файлы кладутся рядом с оригиналами)
                    .onReceive(NotificationCenter.default.publisher(for: .allFoldersLoaded)) { _ in
                        let folders = libraryVM.watchedFolders.map { $0.url }
                        MetadataWriter.cleanupTmpFolder(extraFolders: folders)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isMiniPlayer)
            .environment(\.locale, Locale(identifier: SettingsManager.shared.language))
            // Реакция на скрытие/показ главного окна из AppDelegate.
            // Скрытие — сносим дерево вью и освобождаем память (обложки, таблицы).
            // Показ — заново строим.
            .onReceive(NotificationCenter.default.publisher(for: .mainWindowHidden)) { _ in
                isMiniPlayer = false
                isHiddenInTray = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .mainWindowShown)) { _ in
                isHiddenInTray = false
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
        }

        // MARK: - Menu bar extra (status item в системном трее)

        MenuBarExtra {
            MenuBarContent(playerVM: playerVM, libraryVM: libraryVM)
        } label: {
            Image(systemName: "music.pages")
                .font(.system(size: 14))
        }
        .menuBarExtraStyle(.window)
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
            hideMainWindow()
            return false
        }
        return true
    }

    // MARK: - Hide / Show main window

    /// Скрывает главное окно и переводит приложение в menu-bar-app.
    /// Дерево вью уничтожается (через `.mainWindowHidden`) — освобождает
    /// NSTableView, ячейки, NSImage-обложки и прочее.
    func hideMainWindow() {
        NotificationCenter.default.post(name: .saveStateOnExit, object: nil)

        // 1. Сообщаем SwiftUI выкинуть дерево (isHiddenInTray = true).
        NotificationCenter.default.post(name: .mainWindowHidden, object: nil)

        // 2. Ждём один run loop, чтобы SwiftUI успел применить state,
        //    только потом orderOut — иначе мелькнёт пустое окно.
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title == "Melodica" })?.orderOut(nil)
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // 3. Чистим кэш картинок — теперь его никто не держит.
        Task { @MainActor in
            await ImageCache.shared.clearMemory()
        }
    }

    /// Показывает главное окно и возвращает приложение в обычный режим.
    /// Дерево вью строится заново.
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
