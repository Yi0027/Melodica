//Views,LiquidGlass,LiquidGlassSmartPlaylistsView
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct LiquidGlassSmartPlaylistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel

    @ObservedObject var vm: SmartPlaylistViewModel

    @Binding var selectedSmartPlaylistID: UUID?

    @State private var showingEditor = false
    @State private var editingPlaylist: SmartPlaylist?

    @ObservedObject private var settings = SettingsManager.shared
    @State private var gridRefreshID = UUID()

    @State private var gridPosition = ScrollPosition(idType: UUID.self)
    @State private var detailPosition = ScrollPosition(idType: UUID.self)
    @State private var lastSaveTime: Date?

    @Namespace private var smartAnimation

    var body: some View {
        Group {
            if let id = selectedSmartPlaylistID,
               let playlist = vm.playlists.first(where: { $0.id == id }) {
                smartPlaylistDetail(playlist)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                smartPlaylistGrid
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedSmartPlaylistID)
        .sheet(isPresented: $showingEditor) {
            LiquidGlassSmartPlaylistEditorView(
                vm: vm,
                playlist: editingPlaylist
            )
        }
        .onChange(of: settings.albumGridSize) { _ in
            gridRefreshID = UUID()
        }
    }

    private var smartPlaylistGrid: some View {
        GeometryReader { geometry in
            ScrollView {
                if vm.playlists.isEmpty {
                    emptyState
                } else {
                    let cellSize = settings.albumGridSize
                    let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                        spacing: 12
                    ) {
                        ForEach(vm.playlists) { playlist in
                            LiquidGlassSmartPlaylistCell(
                                playlist: playlist,
                                count: smartTracksCount(for: playlist),
                                tileSize: cellSize - 10
                            )
                            .matchedGeometryEffect(id: "smart_\(playlist.id)", in: smartAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedSmartPlaylistID = playlist.id
                                }
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
                            LiquidGlassSmartPlaylistCreateCell(tileSize: cellSize - 10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .scrollTargetLayout()
                    .animation(.easeInOut(duration: 0.3), value: columns)
                }
            }
            .id(gridRefreshID)
            .scrollPosition($gridPosition)
            .onAppear {
                if let saved = ScrollPositionManager.shared.getUUID(key: "liquid_smart_grid") {
                    gridPosition.scrollTo(id: saved, anchor: .top)
                }
            }
            .onChange(of: gridPosition.viewID(type: UUID.self)) { newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTime = now
                ScrollPositionManager.shared.saveUUID(key: "liquid_smart_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            Text(LocalizedStringKey("no_smart_playlists"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Button {
                editingPlaylist = nil
                showingEditor = true
            } label: {
                Label(LocalizedStringKey("create"), systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }

    private func smartPlaylistDetail(_ playlist: SmartPlaylist) -> some View {
        let tracks = smartTracks(for: playlist)

        return ScrollView {
            VStack(spacing: 4) {
                if tracks.isEmpty {
                    // Пустой контент с достаточной высотой
                    VStack {
                        Text(LocalizedStringKey("no_tracks"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)  // Минимальная высота
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        smartTrackRow(track, allTracks: tracks, index: index)
                    }
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($detailPosition)
        .onAppear {
            if let saved = ScrollPositionManager.shared.getUUID(key: "liquid_smart_detail") {
                detailPosition.scrollTo(id: saved, anchor: .top)
            }
        }
        .onChange(of: detailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            let now = Date()
            if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
            lastSaveTime = now
            ScrollPositionManager.shared.saveUUID(key: "liquid_smart_detail", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .ignoresSafeArea(edges: .top)
    }

    private func smartTrackRow(_ track: Track, allTracks: [Track], index: Int) -> some View {
        LiquidGlassTrackRow(
            track: track,
            isCurrent: playerVM.currentTrack?.id == track.id,
            isPlaying: playerVM.isPlaying,
            onPlay: {
                playerVM.playbackMode = .playlist(allTracks, name: "Smart")
                playerVM.playerTracks = allTracks
                playerVM.play(track) {
                    playerVM.playNextTrack()
                }
            },
            onAddToQueue: { playerVM.addToQueue(track) },
            onToggleFavorite: { playerVM.toggleFavorite(track) },
            isFavorite: playerVM.isFavorite(track),
            isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
            onShowInAlbum: nil,
            isEven: index % 2 == 0
        )
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

// MARK: - Ячейка

@available(macOS 26.0, *)
struct LiquidGlassSmartPlaylistCell: View {
    let playlist: SmartPlaylist
    let count: Int
    let tileSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.12))

                Image(systemName: playlist.icon)
                    .font(.system(size: tileSize * 0.22))
                    .foregroundColor(Color.accentColor.opacity(0.7))
            }
            .frame(width: tileSize, height: tileSize)

            Text(playlist.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(playlist.rules.count) \(NSLocalizedString("rules", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct LiquidGlassSmartPlaylistCreateCell: View {
    let tileSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.08))

                Image(systemName: "plus")
                    .font(.system(size: tileSize * 0.22, weight: .light))
                    .foregroundColor(Color.accentColor.opacity(0.7))
            }
            .frame(width: tileSize, height: tileSize)

            Text(LocalizedStringKey("create"))
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: tileSize, alignment: .leading)

            Text(LocalizedStringKey("smart_playlist"))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text(" ")
                .font(.system(size: 9))
        }
        .contentShape(Rectangle())
    }
}
