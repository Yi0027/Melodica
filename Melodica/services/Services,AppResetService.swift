// Services,AppResetService.swift
import Foundation
import AppKit

@MainActor
final class AppResetService {
    static let shared = AppResetService()
    
    private init() {}
    
    func confirmAndResetApplication(playerVM: PlayerViewModel? = nil, libraryVM: LibraryViewModel? = nil) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("debug_reset_player_alert_title", comment: "")
        alert.informativeText = NSLocalizedString("debug_reset_player_alert_message", comment: "")
        alert.alertStyle = .critical
        let confirmBtn = alert.addButton(withTitle: NSLocalizedString("debug_reset_player_alert_confirm", comment: ""))
        confirmBtn.hasDestructiveAction = true
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        
        if alert.runModal() == .alertFirstButtonReturn {
            executeFullReset(playerVM: playerVM, libraryVM: libraryVM)
        }
    }
    
    func executeFullReset(playerVM: PlayerViewModel? = nil, libraryVM: LibraryViewModel? = nil) {
        let pVM = playerVM ?? PlayerViewModel.shared
        let lVM = libraryVM ?? LibraryViewModel.shared

        // 1. Immediately stop playback, reset player state, and stop media keys
        pVM?.resetToBlankState()
        MediaKeysHandler.shared.stopMonitoring()
        
        // 2. Stop all folder watchers
        FolderWatcherService.shared.stopAll()
        
        // 3. Clear in-memory library and view models
        lVM?.tracks.removeAll()
        lVM?.filteredTracks.removeAll()
        lVM?.albumGroups.removeAll()
        lVM?.artistGroups.removeAll()
        lVM?.genreGroups.removeAll()
        lVM?.playlists.removeAll()
        lVM?.watchedFolders.removeAll()
        lVM?.cueAlbums.removeAll()
        lVM?.searchText = ""
        
        // 4. Invalidate memory caches and audio presets
        ImageCache.shared.clearMemory()
        EQPresetManager.shared.resetAll()
        
        // 5. Invalidate on-disk application data directories
        let fileManager = FileManager.default
        var targetPaths: [URL] = []
        
        // Home Application Support/Melodica
        let homeAppSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        targetPaths.append(homeAppSupport)
        
        // Standard user Application Support/Melodica
        if let stdAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Melodica") {
            targetPaths.append(stdAppSupport)
        }
        
        // Caches directories
        if let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            targetPaths.append(cachesDir.appendingPathComponent("Melodica"))
            if let bundleID = Bundle.main.bundleIdentifier {
                targetPaths.append(cachesDir.appendingPathComponent(bundleID))
            }
        }
        
        // Delete all targeted directories and files
        for path in targetPaths {
            try? fileManager.removeItem(at: path)
        }
        
        // 6. Reset UserDefaults completely
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.removePersistentDomain(forName: "Melodica")
        UserDefaults.standard.removePersistentDomain(forName: "-23.Melodica")
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        
        // 7. Relaunch application fresh
        relaunchApplication()
    }
    
    private func relaunchApplication() {
        let windows = NSApp.windows
        for window in windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .cancel)
            }
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        exit(0)
    }
}
