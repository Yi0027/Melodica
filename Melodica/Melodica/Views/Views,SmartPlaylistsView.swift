// Views,SmartPlaylistsView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SmartPlaylistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel

    @StateObject private var vm = SmartPlaylistViewModel()

    @Binding var selectedSmartPlaylistID: UUID?

    @State private var showingEditor = false
    @State private var editingPlaylist: SmartPlaylist?

    // Прокидываем из SidebarView
    let menuProvider: ([Track]) -> NSMenu?
    let cellConfigurator: (AppKitTrackRowCell, Track) -> Void

    var body: some View {
        ZStack {
            if let id = selectedSmartPlaylistID,
               let playlist = vm.playlists.first(where: { $0.id == id }) {
                smartPlaylistDetail(playlist)
            } else {
                smartPlaylistGrid
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedSmartPlaylistID)
        .sheet(isPresented: $showingEditor) {
            SmartPlaylistEditorView(
                vm: vm,
                playlist: editingPlaylist
            )
        }
    }

    // MARK: - Grid (AppKit)

    private var smartPlaylistGrid: some View {
        VStack(spacing: 0) {
            if vm.playlists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.textMuted.opacity(0.3))

                    Text(LocalizedStringKey("no_smart_playlists"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))

                    Button {
                        editingPlaylist = nil
                        showingEditor = true
                    } label: {
                        Label(LocalizedStringKey("create"), systemImage: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SmartPlaylistListRepresentable(
                    items: vm.playlists,
                    countProvider: { smartTracksCount(for: $0) },
                    scrollKey: "smart_grid",
                    onSelect: { playlist in
                        selectedSmartPlaylistID = playlist.id
                    },
                    menuProvider: { playlist in
                        buildSmartPlaylistMenu(playlist)
                    }
                )

                Divider().background(Color.white.opacity(0.1))

                Button {
                    editingPlaylist = nil
                    showingEditor = true
                } label: {
                    Label(LocalizedStringKey("create_smart_playlist"), systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .tint(.accent)
                .padding(12)
            }
        }
    }

    // MARK: - Detail (AppKit)

    private func smartPlaylistDetail(_ playlist: SmartPlaylist) -> some View {
        let tracks = smartTracks(for: playlist)
        let scrollKey = "smart_detail_\(playlist.id.uuidString)"

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    selectedSmartPlaylistID = nil
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 32, height: 28)

                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                }
                .buttonStyle(.plain)

                Image(systemName: playlist.icon)
                    .foregroundColor(.accent)

                Text(playlist.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textMain)
                    .lineLimit(1)

                Spacer()

                Button {
                    editingPlaylist = playlist
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.darkSurface.opacity(0.8))

            Divider().background(Color.white.opacity(0.1))

            if tracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundColor(.textMuted.opacity(0.3))
                    Text(LocalizedStringKey("no_tracks"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackListRepresentable(
                    tracks: tracks,
                    rowHeight: 52,
                    scrollKey: scrollKey,
                    currentTrackID: playerVM.currentTrack?.id,
                    menuProvider: menuProvider,
                    onDoubleClick: { track in
                        playerVM.playbackMode = .playlist(tracks, name: playlist.name)
                        playerVM.playerTracks = tracks
                        playerVM.play(track) {
                            playerVM.playNextTrack()
                        }
                    },
                    configure: { cell, track in
                        cellConfigurator(cell, track)
                    }
                )
            }
        }
        .background(Color.darkBg)
    }

    // MARK: - Menu

    private func buildSmartPlaylistMenu(_ playlist: SmartPlaylist) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(closureItem(
            title: NSLocalizedString("edit", comment: ""),
            systemImage: "pencil"
        ) {
            editingPlaylist = playlist
            showingEditor = true
        })

        let exportRoot = NSMenuItem(
            title: NSLocalizedString("export_playlist", comment: ""),
            action: nil, keyEquivalent: ""
        )
        let exportSub = NSMenu()
        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_absolute", comment: ""),
            systemImage: "arrow.up.doc"
        ) {
            exportSmartPlaylist(playlist, useAbsolutePaths: true)
        })
        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_relative", comment: ""),
            systemImage: "arrow.up.doc"
        ) {
            exportSmartPlaylist(playlist, useAbsolutePaths: false)
        })
        exportRoot.submenu = exportSub
        menu.addItem(exportRoot)

        menu.addItem(.separator())

        menu.addItem(closureItem(
            title: NSLocalizedString("delete_playlist", comment: ""),
            systemImage: "trash"
        ) {
            vm.delete(playlist)
        })

        return menu
    }

    private func closureItem(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        if let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }

    // MARK: - Helpers

    private func favoriteURLs() -> Set<String> {
        Set(playerVM.favorites.map { $0.url.standardizedFileURL.path })
    }

    private func smartTracks(for playlist: SmartPlaylist) -> [Track] {
        vm.tracks(
            for: playlist,
            library: libraryVM.tracks,
            favoriteURLs: favoriteURLs()
        )
    }

    private func smartTracksCount(for playlist: SmartPlaylist) -> Int {
        smartTracks(for: playlist).count
    }

    private func exportSmartPlaylist(_ playlist: SmartPlaylist, useAbsolutePaths: Bool) {
        let tracks = smartTracks(for: playlist)

        let savePanel = NSSavePanel()
        savePanel.title = NSLocalizedString("export_playlist_title", comment: "")
        savePanel.nameFieldStringValue = "\(playlist.name).m3u"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText]

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            M3UParser.export(
                playlist: (name: playlist.name, tracks: tracks),
                to: url,
                useAbsolutePaths: useAbsolutePaths
            )
        }
    }
}
