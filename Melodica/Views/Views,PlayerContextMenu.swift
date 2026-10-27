// Views,PlayerContextMenu.swift
import SwiftUI

struct PlayerContextMenu: View {
    @ObservedObject var playerVM: PlayerViewModel
    var onShowInAlbum: (() -> Void)? = nil

    var body: some View {
        Menu(LocalizedStringKey("repeat_mode")) {
            Button(action: { playerVM.repeatMode = .off }) {
                Label(LocalizedStringKey("repeat_off"),
                      systemImage: playerVM.repeatMode == .off ? "checkmark" : "repeat")
            }
            Button(action: { playerVM.repeatMode = .all }) {
                Label(LocalizedStringKey("repeat_all"),
                      systemImage: playerVM.repeatMode == .all ? "checkmark" : "repeat")
            }
            Button(action: { playerVM.repeatMode = .one }) {
                Label(LocalizedStringKey("repeat_one"),
                      systemImage: playerVM.repeatMode == .one ? "checkmark" : "repeat.1")
            }
        }

        Divider()

        Button(action: {
            playerVM.shuffleMode.toggle()
            playerVM.saveState()          // ← всегда сохраняем
        }) {
            Label(
                playerVM.shuffleMode ? LocalizedStringKey("shuffle_off") : LocalizedStringKey("shuffle_on"),
                systemImage: "shuffle"
            )
        }

        Divider()

        if let track = playerVM.currentTrack {
            if let onShowInAlbum = onShowInAlbum {
                Button(action: onShowInAlbum) {
                    Label(LocalizedStringKey("show_in_album"), systemImage: "rectangle.stack")
                }
            }

            TrackRatingMenu(track: track)

            Divider()

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            }) {
                Label(LocalizedStringKey("show_in_finder"), systemImage: "folder")
            }
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.title, forType: .string)
            }) {
                Label(LocalizedStringKey("copy_title"), systemImage: "doc.on.doc")
            }
        }
    }
}
