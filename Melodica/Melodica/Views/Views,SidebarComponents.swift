// Views,SidebarComponents.swift
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Расширение SortField

extension Track.SortField {
    var localizedKey: String {
        switch self {
        case .recommendations: return "sort_recommendations"
        case .title: return "sort_title"
        case .artist: return "sort_artist"
        case .album: return "sort_album"
        case .genre: return "sort_genre"
        case .year: return "sort_year"
        case .rating: return "sort_rating"
        case .duration: return "sort_duration"
        case .playlists: return "sort_playlists"
        case .smart: return "sort_smart"
        case .cue: return "sort_cue"
        }
    }
}

// MARK: - Строка трека

struct TrackRowView: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    var onAddToQueue: (() -> Void)? = nil
    var isInQueue: Bool = false
    var onRemoveFromQueue: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var isFavorite: Bool = false
    var showTrackNumber: Bool = true
    var onDoubleClick: (() -> Void)? = nil
    var onShowInAlbum: (() -> Void)? = nil
    var onRemoveFromPlaylist: (() -> Void)? = nil
    var isHighlighted: Bool = false
    var showRating: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if let onAdd = onAddToQueue {
                Button(action: { if !isInQueue { onAdd() } }) {
                    ZStack {
                        Color.white.opacity(0.001).frame(width: 28, height: 28)
                        Image(systemName: isInQueue ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(isInQueue ? .textMuted.opacity(0.3) : .accent.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .disabled(isInQueue)
            }

            if showTrackNumber, let trackNum = track.trackNumber {
                Text("\(trackNum)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textMuted.opacity(0.5))
                    .frame(width: 18, alignment: .trailing)
            }

            CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL,
                       size: CGSize(width: 38, height: 38))
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(isCurrent && isPlaying ? .accent : .textMain)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(track.artist)
                        .font(.system(size: 10.5))
                        .foregroundColor(.textMuted)
                        .lineLimit(1)

                    if let genre = track.genre, !genre.isEmpty {
                        Text("•").foregroundColor(.textMuted.opacity(0.5))
                        Text(genre).font(.system(size: 9.5))
                            .foregroundColor(.textMuted.opacity(0.5)).lineLimit(1)
                    }
                    if let year = track.year {
                        Text("•").foregroundColor(.textMuted.opacity(0.5))
                        Text(String(year)).font(.system(size: 9.5))
                            .foregroundColor(.textMuted.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 8)

            if showRating, let rating = track.rating, rating > 0 {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= starRating(from: rating) ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundColor(.accent.opacity(0.7))
                    }
                }
            }

            Text(formatDuration(track.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textMuted)

            if let onFav = onToggleFavorite {
                Button(action: onFav) {
                    ZStack {
                        Color.white.opacity(0.001).frame(width: 28, height: 28)
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(isFavorite ? .accent : .textMuted.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accent.opacity(0.12) : Color.clear)
                .padding(.horizontal, -4)
        )
        .contentShape(Rectangle())
        .contextMenu {
            if onShowInAlbum != nil {
                Button(action: { onShowInAlbum?() }) {
                    Label(LocalizedStringKey("show_in_album"), systemImage: "rectangle.stack")
                }
            }

            Divider()

            if let onRemoveFromPlaylist {
                Button(role: .destructive, action: onRemoveFromPlaylist) {
                    Label(LocalizedStringKey("remove_from_playlist"), systemImage: "minus.circle")
                }
            }

            if let onFav = onToggleFavorite {
                Button(action: onFav) {
                    Label(
                        isFavorite ? LocalizedStringKey("remove_from_favorites") : LocalizedStringKey("add_to_favorites"),
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
            }

            TrackRatingMenu(track: track)

            if let onQueue = onAddToQueue, !isInQueue {
                Button(action: onQueue) {
                    Label(LocalizedStringKey("add_to_queue"), systemImage: "plus.circle")
                }
            }
            if isInQueue, let onRemove = onRemoveFromQueue {
                Button(action: onRemove) {
                    Label(LocalizedStringKey("remove_from_queue"), systemImage: "minus.circle")
                }
            }

            Divider()

            if let libraryVM = LibraryViewModel.shared {
                Menu(LocalizedStringKey("add_to_playlist")) {
                    Button(action: { showNewPlaylistDialog(for: track) }) {
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
        .onTapGesture(count: 2) { onDoubleClick?() }
    }

    private func starRating(from rating: Int) -> Int {
        switch rating {
        case 1...51: return 1
        case 52...102: return 2
        case 103...153: return 3
        case 154...204: return 4
        case 205...255: return 5
        default: return 0
        }
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec.isFinite else { return "--:--" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
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
            if name.isEmpty { name = "Playlist \(LibraryViewModel.shared?.playlists.count ?? 0 + 1)" }
            LibraryViewModel.shared?.playlists.append((name, [track]))
            LibraryViewModel.shared?.savePlaylistsToCache()
        }
    }
}

// MARK: - Секция отсутствующих избранных

struct MissingFavoritesSection: View {
    let missingTracks: [Track]
    let onRemove: (Track) -> Void
    let onClearAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11)).foregroundColor(.textMuted)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.7))
                    Text(String(format: NSLocalizedString("missing_favorites_count", comment: ""), missingTracks.count))
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.textMuted)
                    Spacer()
                    if isExpanded {
                        Button(action: onClearAll) {
                            Text(LocalizedStringKey("clear"))
                                .font(.system(size: 10)).foregroundColor(.accent)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.yellow.opacity(0.05))
            }.buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.white.opacity(0.1))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(missingTracks) { track in
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.square.dashed")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textMuted.opacity(0.4))
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title).font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.textMain).lineLimit(1)
                                    Text(track.artist).font(.system(size: 9))
                                        .foregroundColor(.textMuted).lineLimit(1)
                                }
                                Spacer()
                                Button(action: { onRemove(track) }) {
                                    Image(systemName: "star.slash.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textMuted.opacity(0.5))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                        }
                    }.padding(.vertical, 4)
                }.frame(maxHeight: 200)
            }
        }
    }
}
