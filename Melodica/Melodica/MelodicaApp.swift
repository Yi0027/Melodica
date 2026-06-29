// MelodicaApp.swift
import SwiftUI

@main
struct MelodicaApp: App {
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    
    var body: some Scene {
        Window("Melodica", id: "main") {
            ContentView(libraryVM: libraryVM, playerVM: playerVM)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    MediaKeysHandler.shared.startMonitoring(
                        playerVM: playerVM,
                        tracks: { libraryVM.filteredTracks },
                        playTrack: { track, completion in
                            playerVM.play(track, afterFinish: completion)
                        },
                        stopPlayer: {
                            playerVM.stop()
                        }
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    playerVM.saveState()
                    MediaKeysHandler.shared.stopMonitoring()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
