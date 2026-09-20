// Views,SidebarView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @Binding var selectedTrackID: UUID?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedAlbum: String?
    @Binding var selectedPlaylist: Int?

    @State private var selectedCUEAlbum: CUEAlbum?
    @State private var showFavoritesOnly: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var artworkVersion = 0

    @State private var selectedArtist: String?
    @State private var selectedGenre: String?
    @State private var highlightedTrackID: UUID?
    @State private var highlightTimer: Timer?
    @State private var cueTracks: [Track] = []

    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var smartVM = SmartPlaylistViewModel()
    @State private var selectedSmartPlaylistID: UUID?
    @State private var presetPickerType: UserArtworkManager.ArtworkType?

    var onOpenFolder: (() -> Void)? = nil

    // MARK: - Computed

    private var filteredPlaylists: [(name: String, tracks: [Track])] {
        if libraryVM.searchText.isEmpty { return libraryVM.playlists }
        let query = libraryVM.searchText.lowercased()
        return libraryVM.playlists.filter { pl in
            pl.name.lowercased().contains(query) ||
            pl.tracks.contains { track in
                track.title.lowercased().contains(query) ||
                track.artist.lowercased().contains(query) ||
                track.album.lowercased().contains(query)
            }
        }
    }

    private var visibleSortFields: [Track.SortField] {
        Track.SortField.allCases.filter { field in
            switch field {
            case .recommendations:
                return SettingsManager.shared.trackStatisticsEnabled
            case .cue:
                return !libraryVM.cueAlbums.isEmpty
            case .playlists:
                return !libraryVM.playlists.isEmpty
            case .smart:
                return true
            case .rating:
                return libraryVM.tracks.contains { ($0.rating ?? 0) > 0 }
            default:
                return true
            }
        }
    }

    private func filterPlaylistTracks(_ tracks: [Track]) -> [Track] {
        if libraryVM.searchText.isEmpty { return tracks }
        let query = libraryVM.searchText.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query) ||
            $0.album.lowercased().contains(query) ||
            ($0.albumArtist ?? "").lowercased().contains(query) ||
            ($0.genre ?? "").lowercased().contains(query) ||
            ($0.year.map { String($0) } ?? "").contains(query)
        }
    }

    private var displayTracks: [Track] {
        var tracks: [Track]
        if showFavoritesOnly {
            tracks = playerVM.availableFavorites
        } else if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
            tracks = libraryVM.playlists[idx].tracks
        } else if let album = selectedAlbum,
                  let group = libraryVM.albumGroups.first(where: { $0.album == album }) {
            tracks = group.tracks
        } else {
            tracks = libraryVM.filteredTracks
        }

        if !libraryVM.searchText.isEmpty {
            let query = libraryVM.searchText.lowercased()
            tracks = tracks.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query) ||
                ($0.albumArtist ?? "").lowercased().contains(query) ||
                ($0.genre ?? "").lowercased().contains(query) ||
                ($0.year.map { String($0) } ?? "").contains(query)
            }
        }

        let watchedPaths = libraryVM.watchedFolders.map {
            $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/"
        }
        if !watchedPaths.isEmpty {
            tracks = tracks.filter { track in
                watchedPaths.contains { track.url.path.hasPrefix($0) }
            }
        }
        return tracks
    }

    private var currentScrollKey: String {
        if showFavoritesOnly { return "favorites" }
        if let album = selectedAlbum { return "album_\(album)" }
        if let idx = selectedPlaylist { return "playlist_\(idx)" }
        if libraryVM.sortField == .album { return "albums_grid" }
        if libraryVM.sortField == .playlists { return "playlists_grid" }
        return "tracks_\(libraryVM.sortField.rawValue)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.textMuted)
                TextField(LocalizedStringKey("search_placeholder"), text: $libraryVM.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.textMain)
                    .focused($isSearchFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = false
                        }
                    }
            }
            .padding(10).background(Color.darkSurface).cornerRadius(8)
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: 4) {
                ForEach(visibleSortFields, id: \.self) { field in
                    Button {
                        
                        libraryVM.sortField = field
                        selectedAlbum = nil
                        selectedArtist = nil
                        selectedGenre = nil
                        selectedPlaylist = nil
                        selectedCUEAlbum = nil
                        showFavoritesOnly = false
                    } label: {
                        Text(LocalizedStringKey(field.localizedKey))
                            .font(.system(size: 11, weight: libraryVM.sortField == field && !showFavoritesOnly ? .semibold : .regular))
                            .foregroundColor(libraryVM.sortField == field && !showFavoritesOnly ? .textMain : .textMuted.opacity(0.7))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(libraryVM.sortField == field && !showFavoritesOnly ? Color.accent.opacity(0.2) : Color.white.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    
                    showFavoritesOnly.toggle()
                    if showFavoritesOnly { selectedAlbum = nil; selectedPlaylist = nil }
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(showFavoritesOnly ? .accent : .textMuted.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(showFavoritesOnly ? Color.accent.opacity(0.2) : Color.white.opacity(0.03)))
                }.buttonStyle(.plain)

                Spacer()

                Button {
                    libraryVM.sortAscending.toggle()
                } label: {
                    Image(systemName: libraryVM.sortAscending ? "arrow.up" : "arrow.down")
                        .foregroundColor(.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            Group {
                if libraryVM.sortField == .recommendations && !showFavoritesOnly {
                    recommendationsView
                } else if libraryVM.sortField == .album && !showFavoritesOnly {
                    albumView
                } else if libraryVM.sortField == .playlists && !showFavoritesOnly {
                    playlistsView
                } else if libraryVM.sortField == .smart && !showFavoritesOnly {
                    SmartPlaylistsView(
                        libraryVM: libraryVM,
                        playerVM: playerVM,
                        selectedSmartPlaylistID: $selectedSmartPlaylistID,
                        menuProvider: { tracks in
                            self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                        },
                        cellConfigurator: { cell, track in
                            cell.configure(
                                with: track,
                                state: self.buildCellState(track: track, showNum: false)
                            )
                        }
                    )
                } else if libraryVM.sortField == .artist && !showFavoritesOnly {
                    artistView
                } else if libraryVM.sortField == .genre && !showFavoritesOnly {
                    genreView
                } else if libraryVM.sortField == .cue && !showFavoritesOnly {
                    cueView
                } else if showFavoritesOnly && playerVM.favorites.isEmpty && playerVM.missingFavorites.isEmpty {
                    emptyFavoritesView
                } else if showFavoritesOnly {
                    favoritesView
                } else {
                    trackListView
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)).animation(.easeInOut(duration: 0.2)),
                removal: .opacity.animation(.easeInOut(duration: 0.15))
            ))
            .animation(.easeInOut(duration: 0.2), value: libraryVM.sortField)
            .animation(.easeInOut(duration: 0.2), value: showFavoritesOnly)
            .animation(.easeInOut(duration: 0.2), value: selectedAlbum != nil)
            .animation(.easeInOut(duration: 0.2), value: selectedPlaylist != nil)
            .background(Color.darkBg)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
                return true
            }
        }
        .onChange(of: libraryVM.isLoading) { loading in
            if !loading, selectedPlaylist != nil {
                let current = selectedPlaylist
                selectedPlaylist = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    selectedPlaylist = current
                }
            }
        }
        .onTapGesture { isSearchFocused = false }
        .onReceive(NotificationCenter.default.publisher(for: .chooseArtistArtwork)) { note in
            if let artist = note.object as? String { chooseArtwork(for: .artist(artist)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chooseGenreArtwork)) { note in
            if let genre = note.object as? String { chooseArtwork(for: .genre(genre)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .choosePlaylistArtwork)) { note in
            if let name = note.object as? String { chooseArtwork(for: .playlist(name)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPresetPicker)) { note in
            if let type = note.object as? UserArtworkManager.ArtworkType {
                presetPickerType = type
            }
        }
        .sheet(item: $presetPickerType) { type in
            ArtworkPresetPickerView(type: type)
                .onDisappear { artworkVersion += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HighlightTrack"))) { notification in
            if let trackID = notification.object as? UUID {
                highlightedTrackID = trackID
                highlightTimer?.invalidate()
                highlightTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    highlightedTrackID = nil
                }
            }
        }
    }

    private var recommendationsView: some View {
        RecommendationsView(libraryVM: libraryVM, playerVM: playerVM, selectedTrackID: $selectedTrackID)
    }

    // MARK: - Альбомы

    private var albumView: some View {
        ZStack {
            if let albumName = selectedAlbum,
               let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
                albumDetailView(group).id(albumName)
            } else {
                albumGridView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedAlbum != nil)
    }

    private var albumGridView: some View {
        if libraryVM.albumGroups.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(noResultsView)
        }
        let cellW = settings.albumGridSize + 10
        let cellH = settings.albumGridSize + 90
        let maxPixel = settings.albumGridSize * 2

        return AnyView(
            AppKitGridView(
                items: libraryVM.albumGroups,
                itemSize: CGSize(width: cellW, height: cellH),
                scrollKey: "albums_grid",
                identifier: { "\($0.album)|\($0.artist)" },
                onSelect: { selectedAlbum = $0.album },
                configure: { cell, group in
                    let allGenres = group.tracks.compactMap { $0.genre }.filter { !$0.isEmpty }
                    let genres = Array(Set(allGenres)).sorted().prefix(2).joined(separator: ", ")
                    let art = group.tracks.first?.thumbURL(size: "400") ?? group.artURL
                    cell.configure(
                        title: group.album,
                        subtitle: group.artist,
                        tertiary: genres,
                        count: group.tracks.count,
                        placeholderSymbol: "music.note",
                        placeholderLabel: "",
                        artworkURL: art,
                        maxPixel: maxPixel
                    )
                }
            )
        )
    }

    private func albumDetailView(_ group: (album: String, artist: String, tracks: [Track], artURL: URL?)) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedAlbum = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001)).frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                CachedImage(url: group.tracks.first?.thumbURL(size: "84") ?? group.artURL,
                           size: CGSize(width: 42, height: 42)).cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.album).font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain).lineLimit(1)
                    Text(group.artist).font(.system(size: 11)).foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))

            if group.tracks.isEmpty {
                noResultsView
            } else {
                TrackListRepresentable(
                    tracks: group.tracks,
                    rowHeight: 52,
                    scrollKey: currentScrollKey,
                    scrollToID: highlightedTrackID,
                    highlightedTrackID: highlightedTrackID,
                    currentTrackID: playerVM.currentTrack?.id,
                    menuProvider: { tracks in
                        self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                    },
                    onDoubleClick: { track in
                        playerVM.playbackMode = .album(group.tracks)
                        playerVM.playerTracks = group.tracks
                        playerVM.play(track) { self.playNextTrack() }
                    },
                    configure: { cell, track in
                        cell.configure(
                            with: track,
                            state: self.buildCellState(track: track, showNum: true)
                        )
                    }
                )
            }
        }
        .background(Color.darkBg)
    }

    // MARK: - Плейлисты

    private var playlistsView: some View {
        ZStack {
            if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
                playlistDetailView(libraryVM.playlists[idx], index: idx)
                    .id("playlist_\(idx)")
            } else {
                playlistGridView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlaylist)
    }

    private var playlistGridView: some View {
        if filteredPlaylists.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(noResultsView)
        }
        let cellW = settings.albumGridSize + 10
        let cellH = settings.albumGridSize + 90
        let maxPixel = settings.albumGridSize * 2

        return AnyView(
            AppKitGridView(
                items: filteredPlaylists,
                itemSize: CGSize(width: cellW, height: cellH),
                scrollKey: "playlists_grid",
                reloadToken: artworkVersion,
                identifier: { $0.name },
                onSelect: { pl in
                    if let idx = libraryVM.playlists.firstIndex(where: { $0.name == pl.name }) {
                        selectedPlaylist = idx
                        playerVM.playerTracks = pl.tracks
                    }
                },
                contextMenu: { pl in
                    let idx = libraryVM.playlists.firstIndex(where: { $0.name == pl.name }) ?? -1
                    return buildPlaylistMenu(pl: pl, index: idx)
                },
                configure: { cell, pl in
                    let art = UserArtworkManager.imageURL(for: .playlist(pl.name))
                        ?? pl.tracks.first.flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                    cell.configure(
                        title: pl.name,
                        subtitle: "",
                        tertiary: "",
                        count: pl.tracks.count,
                        placeholderSymbol: "music.note.list",
                        placeholderLabel: "",
                        artworkURL: art,
                        maxPixel: maxPixel
                    )
                }
            )
        )
    }

    private func buildPlaylistMenu(
        pl: (name: String, tracks: [Track]),
        index: Int
    ) -> NSMenu {
        let menu = NSMenu()
        let vm = libraryVM

        menu.addItem(closureItem(
            title: NSLocalizedString("choose_from_presets", comment: ""),
            systemImage: "photo.on.rectangle"
        ) {
            NotificationCenter.default.post(
                name: .showPresetPicker,
                object: UserArtworkManager.ArtworkType.playlist(pl.name)
            )
        })

        menu.addItem(closureItem(
            title: NSLocalizedString("add_artwork", comment: ""),
            systemImage: "photo"
        ) {
            NotificationCenter.default.post(name: .choosePlaylistArtwork, object: pl.name)
        })

        if UserArtworkManager.load(for: .playlist(pl.name)) != nil {
            menu.addItem(closureItem(
                title: NSLocalizedString("remove_custom_artwork", comment: ""),
                systemImage: "trash"
            ) {
                UserArtworkManager.delete(for: .playlist(pl.name))
                artworkVersion += 1
            })
        }

        menu.addItem(.separator())

        let exportRoot = NSMenuItem(
            title: NSLocalizedString("export_playlist", comment: ""),
            action: nil, keyEquivalent: ""
        )
        let exportSub = NSMenu()
        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_absolute", comment: ""),
            systemImage: "arrow.up.doc"
        ) { exportPlaylist(pl, useAbsolutePaths: true) })
        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_relative", comment: ""),
            systemImage: "arrow.up.doc"
        ) { exportPlaylist(pl, useAbsolutePaths: false) })
        exportRoot.submenu = exportSub
        menu.addItem(exportRoot)

        menu.addItem(.separator())

        if index >= 0 {
            menu.addItem(closureItem(
                title: NSLocalizedString("delete_playlist", comment: ""),
                systemImage: "trash"
            ) {
                vm.removePlaylist(at: index)
            })
        }

        return menu
    }

    private func playlistDetailView(_ playlist: (name: String, tracks: [Track]), index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedPlaylist = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001)).frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain).lineLimit(1)
                    let visibleCount = displayTracks.count
                    let totalCount = playlist.tracks.count
                    let countText: String = visibleCount == totalCount
                        ? String(format: NSLocalizedString("tracks_count", comment: ""), totalCount)
                        : "\(totalCount) (\(visibleCount)) \(NSLocalizedString("tracks_label", comment: ""))"
                    Text(countText).font(.system(size: 11)).foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))

            let visible = filterPlaylistTracks(displayTracks)
            if visible.isEmpty && !libraryVM.searchText.isEmpty {
                noResultsView
            } else {
                TrackListRepresentable(
                    tracks: visible,
                    rowHeight: 52,
                    scrollKey: currentScrollKey,
                    scrollToID: highlightedTrackID,
                    highlightedTrackID: highlightedTrackID,
                    currentTrackID: playerVM.currentTrack?.id,
                    menuProvider: { tracks in
                        self.buildTrackMenu(
                            tracks: tracks,
                            onRemoveFromPlaylist: { tracksToRemove in
                                let ids = Set(tracksToRemove.map(\.id))
                                libraryVM.playlists[index].tracks.removeAll { ids.contains($0.id) }
                                libraryVM.savePlaylistsToCache()
                            }
                        )
                    },
                    onDoubleClick: { track in
                        playerVM.playbackMode = .playlist(playlist.tracks, name: playlist.name)
                        playerVM.playerTracks = playlist.tracks
                        playerVM.play(track) { self.playNextTrack() }
                    },
                    configure: { cell, track in
                        cell.configure(
                            with: track,
                            state: self.buildCellState(track: track, showNum: false)
                        )
                    }
                )
            }
        }
        .background(Color.darkBg)
    }

    private func exportPlaylist(_ playlist: (name: String, tracks: [Track]), useAbsolutePaths: Bool) {
        let savePanel = NSSavePanel()
        savePanel.title = NSLocalizedString("export_playlist_title", comment: "")
        savePanel.nameFieldStringValue = "\(playlist.name).m3u"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText]
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            M3UParser.export(playlist: playlist, to: url, useAbsolutePaths: useAbsolutePaths)
        }
    }

    // MARK: - Избранное

    private var favoritesView: some View {
        VStack(spacing: 0) {
            if !playerVM.missingFavorites.isEmpty {
                MissingFavoritesSection(
                    missingTracks: playerVM.missingFavorites,
                    onRemove: { track in playerVM.toggleFavorite(track) },
                    onClearAll: {
                        for track in playerVM.missingFavorites { playerVM.toggleFavorite(track) }
                    }
                )
            }
            if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
                noResultsView
            } else {
                trackListView
            }
        }
    }

    // MARK: - CUE

    private var cueView: some View {
        ZStack {
            if let album = selectedCUEAlbum {
                cueDetailView(album)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                cueGridView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedCUEAlbum != nil)
    }

    private var cueGridView: some View {
        if libraryVM.cueAlbums.isEmpty {
            return AnyView(
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32)).foregroundColor(.textMuted.opacity(0.3))
                    Text(LocalizedStringKey("no_cue_files"))
                        .font(.system(size: 13)).foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        let cellW = settings.albumGridSize + 10
        let cellH = settings.albumGridSize + 90
        let maxPixel = settings.albumGridSize * 2

        return AnyView(
            AppKitGridView(
                items: libraryVM.cueAlbums,
                itemSize: CGSize(width: cellW, height: cellH),
                scrollKey: "cue_grid",
                reloadToken: artworkVersion,
                identifier: { "\($0.title)|\($0.performer)" },
                onSelect: { selectedCUEAlbum = $0 },
                configure: { cell, album in
                    cell.configure(
                        title: album.title,
                        subtitle: album.performer,
                        tertiary: "",
                        count: album.tracks.count,
                        placeholderSymbol: "music.note.list",
                        placeholderLabel: "CUE",
                        artworkURL: album.albumArtURL,
                        maxPixel: maxPixel
                    )
                }
            )
        )
    }

    private func cueDetailView(_ album: CUEAlbum) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedCUEAlbum = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001)).frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                if let artURL = cueTracks.first?.albumArtURL {
                    CachedImage(url: artURL, size: CGSize(width: 42, height: 42)).cornerRadius(6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title).font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain).lineLimit(1)
                    Text(album.performer).font(.system(size: 11)).foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))

            if cueTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView().scaleEffect(1.2).tint(.accent)
                    Text(LocalizedStringKey("loading"))
                        .font(.system(size: 12)).foregroundColor(.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackListRepresentable(
                    tracks: cueTracks,
                    rowHeight: 52,
                    scrollKey: "cue_detail_\(album.title)",
                    scrollToID: highlightedTrackID,
                    highlightedTrackID: highlightedTrackID,
                    currentTrackID: playerVM.currentTrack?.id,
                    menuProvider: { tracks in
                        self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                    },
                    onDoubleClick: { track in
                        playerVM.playbackMode = .album(cueTracks)
                        playerVM.playerTracks = cueTracks
                        selectedTrackID = track.id
                        playerVM.play(track) { self.playNextTrack() }
                    },
                    configure: { cell, track in
                        cell.configure(
                            with: track,
                            state: self.buildCellState(track: track, showNum: true)
                        )
                    }
                )
            }
        }
        .background(Color.darkBg)
        .onAppear {
            cueTracks = album.makeTracks()
        }
    }


    // MARK: - Артисты

    private var artistView: some View {
        ZStack {
            if let artist = selectedArtist,
               let group = libraryVM.artistGroups.first(where: { $0.artist == artist }) {
                artistDetailView(group)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                artistGridView.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedArtist != nil)
    }

    private var artistGridView: some View {
        let cellW = settings.albumGridSize + 10
        let cellH = settings.albumGridSize + 90
        let maxPixel = settings.albumGridSize * 2

        return AppKitGridView(
            items: libraryVM.artistGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            scrollKey: "artist_grid",
            reloadToken: artworkVersion,
            identifier: { $0.artist },
            onSelect: { selectedArtist = $0.artist },
            contextMenu: { group in
                buildArtistGenreMenu(
                    type: .artist(group.artist),
                    name: group.artist,
                    chooseNotification: .chooseArtistArtwork
                )
            },
            configure: { cell, group in
                let art = UserArtworkManager.imageURL(for: .artist(group.artist))
                    ?? group.tracks.first(where: { $0.albumArtURL != nil })
                        .flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                cell.configure(
                    title: group.artist,
                    subtitle: "",
                    tertiary: "",
                    count: group.tracks.count,
                    placeholderSymbol: "person.fill",
                    placeholderLabel: "",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func artistDetailView(_ group: (artist: String, tracks: [Track], artURL: URL?)) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedArtist = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001)).frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                Text(group.artist).font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textMain).lineLimit(1)
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))

            TrackListRepresentable(
                tracks: group.tracks,
                rowHeight: 52,
                scrollKey: "artist_detail_\(group.artist)",
                scrollToID: highlightedTrackID,
                highlightedTrackID: highlightedTrackID,
                currentTrackID: playerVM.currentTrack?.id,
                menuProvider: { tracks in
                    self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                },
                onDoubleClick: { track in
                    playerVM.playbackMode = .album(group.tracks)
                    playerVM.playerTracks = group.tracks
                    playerVM.play(track) { self.playNextTrack() }
                },
                configure: { cell, track in
                    cell.configure(
                        with: track,
                        state: self.buildCellState(track: track, showNum: true)
                    )
                }
            )
        }
        .background(Color.darkBg)
    }

    // MARK: - Жанры

    private var genreView: some View {
        ZStack {
            if let genre = selectedGenre,
               let group = libraryVM.genreGroups.first(where: { $0.genre == genre }) {
                genreDetailView(group)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                genreGridView.transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedGenre != nil)
    }

    private var genreGridView: some View {
        let cellW = settings.albumGridSize + 10
        let cellH = settings.albumGridSize + 90
        let maxPixel = settings.albumGridSize * 2

        return AppKitGridView(
            items: libraryVM.genreGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            scrollKey: "genre_grid",
            reloadToken: artworkVersion,
            identifier: { $0.genre },
            onSelect: { selectedGenre = $0.genre },
            contextMenu: { group in
                buildArtistGenreMenu(
                    type: .genre(group.genre),
                    name: group.genre,
                    chooseNotification: .chooseGenreArtwork
                )
            },
            configure: { cell, group in
                let art = UserArtworkManager.imageURL(for: .genre(group.genre))
                    ?? group.tracks.first(where: { $0.albumArtURL != nil })
                        .flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                cell.configure(
                    title: group.genre,
                    subtitle: "",
                    tertiary: "",
                    count: group.tracks.count,
                    placeholderSymbol: "tag.fill",
                    placeholderLabel: "",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func genreDetailView(_ group: (genre: String, tracks: [Track], artURL: URL?)) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedGenre = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001)).frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                Text(group.genre).font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textMain).lineLimit(1)
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))

            TrackListRepresentable(
                tracks: group.tracks,
                rowHeight: 52,
                scrollKey: "genre_detail_\(group.genre)",
                scrollToID: highlightedTrackID,
                highlightedTrackID: highlightedTrackID,
                currentTrackID: playerVM.currentTrack?.id,
                menuProvider: { tracks in
                    self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                },
                onDoubleClick: { track in
                    playerVM.playbackMode = .album(group.tracks)
                    playerVM.playerTracks = group.tracks
                    playerVM.play(track) { self.playNextTrack() }
                },
                configure: { cell, track in
                    cell.configure(
                        with: track,
                        state: self.buildCellState(track: track, showNum: true)
                    )
                }
            )
        }
        .background(Color.darkBg)
    }

    private func buildArtistGenreMenu(
        type: UserArtworkManager.ArtworkType,
        name: String,
        chooseNotification: Notification.Name
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureItem(
            title: NSLocalizedString("choose_from_presets", comment: ""),
            systemImage: "photo.on.rectangle"
        ) {
            NotificationCenter.default.post(name: .showPresetPicker, object: type)
        })
        menu.addItem(closureItem(
            title: NSLocalizedString("add_artwork", comment: ""),
            systemImage: "photo"
        ) {
            NotificationCenter.default.post(name: chooseNotification, object: name)
        })
        if UserArtworkManager.load(for: type) != nil {
            menu.addItem(closureItem(
                title: NSLocalizedString("remove_custom_artwork", comment: ""),
                systemImage: "trash"
            ) {
                UserArtworkManager.delete(for: type)
                artworkVersion += 1
            })
        }
        return menu
    }

    // MARK: - Общие

    private var emptyFavoritesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star.slash")
                .font(.system(size: 32)).foregroundColor(.textMuted.opacity(0.3))
            Text(LocalizedStringKey("no_favorites"))
                .font(.system(size: 13)).foregroundColor(.textMuted.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(LocalizedStringKey("search_no_results"))
                .font(.system(size: 13)).foregroundColor(.textMuted.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Список треков

    private var trackListView: some View {
        let key = currentScrollKey
        if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(noResultsView)
        }
        return AnyView(
            TrackListRepresentable(
                tracks: displayTracks,
                rowHeight: 52,
                scrollKey: key,
                scrollToTopTrigger: libraryVM.searchText,
                scrollToID: highlightedTrackID,
                highlightedTrackID: highlightedTrackID,
                currentTrackID: playerVM.currentTrack?.id,
                menuProvider: { tracks in
                    self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                },
                onDoubleClick: { track in
                    selectedTrackID = track.id
                    playerVM.play(track) { self.playNextTrack() }
                },
                configure: { cell, track in
                    cell.configure(
                        with: track,
                        state: self.buildCellState(
                            track: track,
                            showNum: !self.showFavoritesOnly && self.libraryVM.sortField == .album
                        )
                    )
                }
            )
        )
    }

    // MARK: - Cell state + menu

    private func buildCellState(
        track: Track,
        showNum: Bool,
        showAddButton: Bool = true,
        showFavoriteButton: Bool = true
    ) -> TrackCellState {
        var state = TrackCellState()
        state.showTrackNumber = showNum
        state.showRating = libraryVM.sortField == .rating
        state.isCurrent = playerVM.currentTrack?.id == track.id
        state.isPlaying = playerVM.isPlaying
        state.isFavorite = playerVM.isFavorite(track)
        state.isInQueue = playerVM.queue.contains(where: { $0.id == track.id })
        state.isHighlighted = highlightedTrackID == track.id
        state.showAddButton = showAddButton
        state.showFavoriteButton = showFavoriteButton
        state.onAdd = showAddButton ? { playerVM.addToQueue(track) } : nil
        state.onFavorite = showFavoriteButton ? { playerVM.toggleFavorite(track) } : nil
        return state
    }

    // MARK: - Track context menu

    /// Одиночный вызов (обратная совместимость для вызовов, где на входе один трек).
    private func buildTrackMenu(
        track: Track,
        onRemoveFromPlaylist: (() -> Void)? = nil
    ) -> NSMenu {
        buildTrackMenu(
            tracks: [track],
            onRemoveFromPlaylist: onRemoveFromPlaylist.map { cb in
                { _ in cb() }
            }
        )
    }

    /// Множественное выделение.
    private func buildTrackMenu(
        tracks: [Track],
        onRemoveFromPlaylist: (([Track]) -> Void)? = nil
    ) -> NSMenu {
        TrackContextMenuBuilder.build(
            tracks: tracks,
            libraryVM: libraryVM,
            playerVM: playerVM,
            onRemoveFromPlaylist: onRemoveFromPlaylist,
            onShowInAlbum: { track in
                selectedArtist = nil
                selectedGenre = nil
                selectedPlaylist = nil
                selectedCUEAlbum = nil
                selectedSmartPlaylistID = nil

                // Сброс подсветки, чтобы повторный Show in album на тот же трек сработал
                highlightedTrackID = nil
                highlightTimer?.invalidate()

                libraryVM.sortField = .album
                selectedAlbum = track.album

                DispatchQueue.main.async {
                    highlightedTrackID = track.id
                    highlightTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        highlightedTrackID = nil
                    }
                }
            }
        )
    }

    // MARK: - DnD + misc

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    let ext = url.pathExtension.lowercased()
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue { libraryVM.addFolder(url) }
                    else if ext == "m3u" || ext == "m3u8" { libraryVM.importM3U(url) }
                    else if ["mp3", "flac", "m4a", "aac", "opus", "ogg"].contains(ext) {
                        Task {
                            if let track = await MetadataReader.readTrack(from: url) {
                                libraryVM.tracks.append(track)
                            }
                        }
                    }
                }
            }
        }
    }

    private func playNextTrack() { playerVM.playNextTrack() }

    private func chooseArtwork(for type: UserArtworkManager.ArtworkType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url,
               let image = NSImage(contentsOf: url) {
                UserArtworkManager.save(image, for: type)
                artworkVersion += 1
            }
        }
    }
}



extension Notification.Name {
    static let chooseArtistArtwork = Notification.Name("chooseArtistArtwork")
    static let chooseGenreArtwork = Notification.Name("chooseGenreArtwork")
    static let choosePlaylistArtwork = Notification.Name("choosePlaylistArtwork")
    static let showPresetPicker = Notification.Name("showPresetPicker")
}
