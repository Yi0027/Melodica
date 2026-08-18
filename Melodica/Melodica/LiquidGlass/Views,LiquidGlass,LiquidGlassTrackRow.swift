// Views,LiquidGlass,LiquidGlassTrackRow.swift
import SwiftUI
import UniformTypeIdentifiers

struct LiquidGlassTrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    var onAddToQueue: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var isFavorite: Bool = false
    var isInQueue: Bool = false
    var onShowInAlbum: (() -> Void)? = nil
    var showRating: Bool = false
    var isEven: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL, size: CGSize(width: 32, height: 32))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent && isPlaying ? Color.accentColor : .primary)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Text(track.artist)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let year = track.year {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(String(year))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }

            Spacer()

            if showRating, let rating = track.rating, rating > 0 {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: starName(for: index, rating: rating))
                            .font(.system(size: 8))
                            .foregroundColor(Color.accentColor.opacity(0.7))
                    }
                }
            }

            Text(formatDuration(track.duration))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isCurrent
                        ? Color.accentColor.opacity(0.08)
                        : (isEven ? Color.primary.opacity(0.03) : Color.clear)
                )
                .padding(.horizontal, 5)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if onShowInAlbum != nil {
                Button(action: { onShowInAlbum?() }) {
                    Label(LocalizedStringKey("show_in_album"), systemImage: "rectangle.stack")
                }
                Divider()
            }

            if let onFav = onToggleFavorite {
                Button(action: onFav) {
                    Label(
                        isFavorite ? LocalizedStringKey("remove_from_favorites") : LocalizedStringKey("add_to_favorites"),
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
            }

            if let onQueue = onAddToQueue, !isInQueue {
                Button(action: onQueue) {
                    Label(LocalizedStringKey("add_to_queue"), systemImage: "plus.circle")
                }
            }

            Divider()

            if let libraryVM = LibraryViewModel.shared {
                Menu(LocalizedStringKey("add_to_playlist")) {
                    Button(action: {
                        showNewPlaylistDialog(for: track)
                    }) {
                        Label(LocalizedStringKey("new_playlist"), systemImage: "plus")
                    }

                    if !libraryVM.playlists.isEmpty {
                        Divider()
                        ForEach(Array(libraryVM.playlists.enumerated()), id: \.offset) { idx, pl in
                            Button(action: {
                                libraryVM.playlists[idx].tracks.append(track)
                                libraryVM.savePlaylistsToCache()
                            }) {
                                Label(pl.name, systemImage: "music.note.list")
                            }
                        }
                    }
                }

                Divider()
            }

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
        .onTapGesture(count: 2) {
            onPlay()
        }
    }

    private func starName(for index: Int, rating: Int) -> String {
        let stars = max(0, min(rating / 51, 5))
        return index <= stars ? "star.fill" : "star"
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec.isFinite else { return "--:--" }
        let m = Int(sec) / 60, s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func showNewPlaylistDialog(for track: Track) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("new_playlist_title", comment: "")
        alert.informativeText = NSLocalizedString("new_playlist_desc", comment: "")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = NSLocalizedString("playlist_name_placeholder", comment: "")
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("create", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            var name = textField.stringValue.trimmingCharacters(in: .whitespaces)

            if name.isEmpty {
                name = "Playlist \(LibraryViewModel.shared?.playlists.count ?? 0 + 1)"
            }

            LibraryViewModel.shared?.playlists.append((name, [track]))
            LibraryViewModel.shared?.savePlaylistsToCache()
        }
    }
}
