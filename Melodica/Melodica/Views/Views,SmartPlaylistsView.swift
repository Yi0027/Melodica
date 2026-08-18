import SwiftUI
import UniformTypeIdentifiers

struct SmartPlaylistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel

    @StateObject private var vm = SmartPlaylistViewModel()

    @Binding var selectedSmartPlaylistID: UUID?

    @State private var showingEditor = false
    @State private var editingPlaylist: SmartPlaylist?

    @State private var gridPosition = ScrollPosition(idType: UUID.self)
    @State private var detailPosition = ScrollPosition(idType: UUID.self)
    @State private var lastSaveTime: Date?

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

    private var smartPlaylistGrid: some View {
        ScrollView {
            VStack(spacing: 8) {
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
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(vm.playlists) { playlist in
                        SmartPlaylistRow(
                            playlist: playlist,
                            count: smartTracksCount(for: playlist)
                        )
                        .onTapGesture {
                            selectedSmartPlaylistID = playlist.id
                        }
                        .contextMenu {
                            Button {
                                editingPlaylist = playlist
                                showingEditor = true
                            } label: {
                                Label(LocalizedStringKey("edit"), systemImage: "pencil")
                            }

                            Menu(LocalizedStringKey("export_playlist")) {
                                Button(LocalizedStringKey("export_absolute")) {
                                    exportSmartPlaylist(playlist, useAbsolutePaths: true)
                                }
                                Button(LocalizedStringKey("export_relative")) {
                                    exportSmartPlaylist(playlist, useAbsolutePaths: false)
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                vm.delete(playlist)
                            } label: {
                                Label(LocalizedStringKey("delete_playlist"), systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        editingPlaylist = nil
                        showingEditor = true
                    } label: {
                        Label(LocalizedStringKey("create_smart_playlist"), systemImage: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)
                    .padding(.top, 6)
                }
            }
            .padding(12)
            .scrollTargetLayout()
        }
        .scrollPosition($gridPosition)
        .onAppear {
            if let saved = ScrollPositionManager.shared.getUUID(key: "smart_grid") {
                gridPosition.scrollTo(id: saved, anchor: .top)
            }
        }
        .onChange(of: gridPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            let now = Date()
            if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
            lastSaveTime = now
            ScrollPositionManager.shared.saveUUID(key: "smart_grid", id: id)
        }
    }

    private func smartPlaylistDetail(_ playlist: SmartPlaylist) -> some View {
        let tracks = smartTracks(for: playlist)

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

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        smartTrackRow(track, allTracks: tracks)
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollPosition($detailPosition)
            .onAppear {
                if let saved = ScrollPositionManager.shared.getUUID(key: "smart_detail") {
                    detailPosition.scrollTo(id: saved, anchor: .top)
                }
            }
            .onChange(of: detailPosition.viewID(type: UUID.self)) { newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTime = now
                ScrollPositionManager.shared.saveUUID(key: "smart_detail", id: id)
            }
        }
        .background(Color.darkBg)
    }

    private func smartTrackRow(_ track: Track, allTracks: [Track]) -> some View {
        TrackRowView(
            track: track,
            isCurrent: playerVM.currentTrack?.id == track.id,
            isPlaying: playerVM.isPlaying,
            onAddToQueue: { playerVM.addToQueue(track) },
            isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
            onRemoveFromQueue: { playerVM.removeFromQueue(track) },
            onToggleFavorite: { playerVM.toggleFavorite(track) },
            isFavorite: playerVM.isFavorite(track),
            showTrackNumber: false,
            onDoubleClick: {
                playerVM.playbackMode = .playlist(allTracks, name: "Smart")
                playerVM.playerTracks = allTracks
                playerVM.play(track) {
                    playerVM.playNextTrack()
                }
            },
            onShowInAlbum: nil,
            isHighlighted: false
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

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
