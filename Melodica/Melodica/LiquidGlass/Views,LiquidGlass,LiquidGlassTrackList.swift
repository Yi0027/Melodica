// Views,LiquidGlass,LiquidGlassTrackList.swift
import SwiftUI
import UniformTypeIdentifiers

struct DetailHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
extension Notification.Name {
    static let detailHeaderHeightChanged = Notification.Name("detailHeaderHeightChanged")
}

@available(macOS 26.0, *)
struct LiquidGlassTrackList: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?
    @Binding var selectedAlbum: String?
    @Binding var selectedPlaylist: Int?
    @Binding var selectedSmartPlaylistID: UUID?

    @Binding var selectedArtist: String?
    @Binding var selectedGenre: String?
    @Binding var selectedCUEAlbum: CUEAlbum?
    @Binding var showRightPanel: Bool
    @State private var cueTracks: [Track] = []
    @Binding var showFavoritesOnly: Bool
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject var smartVM: SmartPlaylistViewModel
    @State private var presetPickerType: UserArtworkManager.ArtworkType?
    @State private var artworkVersion = 0
    @State private var highlightedTrackID: UUID?
    @State private var highlightTimer: Timer?

    // MARK: - Позиции скролла

    var body: some View {
        VStack(spacing: 0) {
            if libraryVM.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.1)
                        .tint(Color.accentColor)
                    Text(LocalizedStringKey("scanning"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            if showDetailHeader {
                detailHeaderOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .ignoresSafeArea(edges: .top)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: DetailHeaderHeightKey.self,
                                    value: geometry.size.height
                                )
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .onPreferenceChange(DetailHeaderHeightKey.self) { height in
            NotificationCenter.default.post(
                name: .detailHeaderHeightChanged,
                object: nil,
                userInfo: ["height": height]
            )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showDetailHeader)

        .sheet(item: $presetPickerType) { type in
            LiquidGlassArtworkPresetPickerView(type: type)
                .onDisappear {
                    artworkVersion += 1
                }
        }
    }

    private var showDetailHeader: Bool {
        selectedAlbum != nil ||
        selectedArtist != nil ||
        selectedGenre != nil ||
        selectedPlaylist != nil ||
        selectedCUEAlbum != nil ||
        selectedSmartPlaylistID != nil
    }

    @ViewBuilder
    private var detailHeaderOverlay: some View {
        if let albumName = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
            detailHeaderView(title: group.album, subtitle: group.artist, artURL: group.tracks.first?.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedAlbum = nil }
            }
        } else if let artist = selectedArtist,
                  let group = libraryVM.artistGroups.first(where: { $0.artist == artist }) {
            detailHeaderView(title: group.artist, subtitle: nil, artURL: group.tracks.first?.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedArtist = nil }
            }
        } else if let genre = selectedGenre,
                  let group = libraryVM.genreGroups.first(where: { $0.genre == genre }) {
            detailHeaderView(title: group.genre, subtitle: nil, artURL: group.tracks.first?.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedGenre = nil }
            }
        } else if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
            let pl = libraryVM.playlists[idx]
            detailHeaderView(title: pl.name, subtitle: nil, artURL: pl.tracks.first?.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedPlaylist = nil }
            }
        } else if let album = selectedCUEAlbum {
            detailHeaderView(title: album.title, subtitle: album.performer, artURL: album.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedCUEAlbum = nil }
            }
        } else if let id = selectedSmartPlaylistID,
                  let playlist = smartVM.playlists.first(where: { $0.id == id }) {
            let count = smartVM.tracks(
                for: playlist,
                library: libraryVM.tracks,
                favoriteURLs: Set()
            ).count

            detailHeaderView(
                title: playlist.name,
                subtitle: "\(count) \(NSLocalizedString("tracks", comment: ""))",
                artURL: nil
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedSmartPlaylistID = nil }
            }
        }
    }

    private func detailHeaderView(title: String, subtitle: String?, artURL: URL?, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            if let artURL = artURL {
                CachedImage(url: artURL, size: CGSize(width: 36, height: 36))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 15))
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if showFavoritesOnly {
                favoritesView
            } else if libraryVM.sortField == .album {
                albumView
            } else if libraryVM.sortField == .artist {
                artistView
            } else if libraryVM.sortField == .genre {
                genreView
            } else if libraryVM.sortField == .playlists {
                playlistsView
            } else if libraryVM.sortField == .smart {
                LiquidGlassSmartPlaylistsView(
                    libraryVM: libraryVM,
                    playerVM: playerVM,
                    vm: smartVM,
                    selectedSmartPlaylistID: $selectedSmartPlaylistID
                )
                .transition(.opacity)
            } else if libraryVM.sortField == .cue {
                cueView
            } else if libraryVM.sortField == .recommendations {
                LiquidGlassRecommendationsView(
                    libraryVM: libraryVM,
                    playerVM: playerVM,
                    selectedTrackID: $selectedTrackID
                )
                .transition(.opacity)
            } else {
                trackListView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFavoritesOnly)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedAlbum != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedArtist != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedGenre != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlaylist != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedCUEAlbum != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedSmartPlaylistID != nil)
        .animation(.easeInOut(duration: 0.2), value: libraryVM.sortField)
    }

    // MARK: - Альбомы

    @ViewBuilder
    private var albumView: some View {
        if let albumName = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
            albumDetailView(group)
        } else {
            albumGridView
        }
    }

    private var albumGridView: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 52
        let maxPixel = cellSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.albumGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_albums_grid",
            identifier: { "\($0.album)|\($0.artist)" },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedAlbum = group.album
                }
            },
            configure: { cell, group in
                let art = group.tracks.first?.thumbURL(size: "400") ?? group.artURL
                cell.configure(
                    title: group.album,
                    subtitle: group.artist,
                    tertiary: "\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    placeholderSymbol: "music.note",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func albumDetailView(_ group: (album: String, artist: String, tracks: [Track], artURL: URL?)) -> some View {
        LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_album_detail_\(group.album)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: libraryVM.sortField == .rating,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                playerVM.playbackMode = .album(group.tracks)
                playerVM.playerTracks = group.tracks
                playerVM.play(track) { self.playNextTrack() }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    private func playNextTrack() {
        playerVM.playNextTrack()
    }

    // MARK: - Артисты

    @ViewBuilder
    private var artistView: some View {
        if let artist = selectedArtist,
           let group = libraryVM.artistGroups.first(where: { $0.artist == artist }) {
            artistDetailView(group)
        } else {
            artistGridView
        }
    }

    private var artistGridView: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 52
        let maxPixel = cellSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.artistGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_artists_grid",
            reloadToken: artworkVersion,
            identifier: { $0.artist },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedArtist = group.artist
                }
            },
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
                    tertiary: "\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    placeholderSymbol: "person.fill",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func artistDetailView(_ group: (artist: String, tracks: [Track], artURL: URL?)) -> some View {
        LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_artist_detail_\(group.artist)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: libraryVM.sortField == .rating,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                playerVM.playbackMode = .album(group.tracks)
                playerVM.playerTracks = group.tracks
                playerVM.play(track) { self.playNextTrack() }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Жанры

    @ViewBuilder
    private var genreView: some View {
        if let genre = selectedGenre,
           let group = libraryVM.genreGroups.first(where: { $0.genre == genre }) {
            genreDetailView(group)
        } else {
            genreGridView
        }
    }

    private var genreGridView: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 52
        let maxPixel = cellSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.genreGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_genres_grid",
            reloadToken: artworkVersion,
            identifier: { $0.genre },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedGenre = group.genre
                }
            },
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
                    tertiary: "\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    placeholderSymbol: "tag.fill",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func genreDetailView(_ group: (genre: String, tracks: [Track], artURL: URL?)) -> some View {
        LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_genre_detail_\(group.genre)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: libraryVM.sortField == .rating,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                playerVM.playbackMode = .album(group.tracks)
                playerVM.playerTracks = group.tracks
                playerVM.play(track) { self.playNextTrack() }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    private func chooseArtwork(for type: UserArtworkManager.ArtworkType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK,
               let url = panel.url,
               let image = NSImage(contentsOf: url) {
                UserArtworkManager.save(image, for: type)
                artworkVersion += 1
            }
        }
    }

    // MARK: - Плейлисты

    @ViewBuilder
    private var playlistsView: some View {
        if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
            playlistDetailView(libraryVM.playlists[idx], index: idx)
        } else {
            playlistGridView
        }
    }

    private var playlistGridView: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 52
        let maxPixel = cellSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.playlists,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_playlists_grid",
            reloadToken: artworkVersion,
            identifier: { $0.name },
            onSelect: { pl in
                if let idx = libraryVM.playlists.firstIndex(where: { $0.name == pl.name }) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedPlaylist = idx
                    }
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
                    tertiary: "\(pl.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    placeholderSymbol: "music.note.list",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
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

    private func playlistDetailView(_ playlist: (name: String, tracks: [Track]), index: Int) -> some View {
        LiquidGlassTrackListRepresentable(
            tracks: playlist.tracks,
            rowHeight: 44,
            scrollKey: "liquid_playlist_detail_\(playlist.name)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: libraryVM.sortField == .rating,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
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
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - CUE

    @ViewBuilder
    private var cueView: some View {
        if let album = selectedCUEAlbum {
            cueDetailView(album)
        } else {
            cueGridView
        }
    }

    private var cueGridView: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 52
        let maxPixel = cellSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.cueAlbums,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_cue_grid",
            identifier: { $0.title + "|" + $0.performer },
            onSelect: { album in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedCUEAlbum = album
                }
            },
            configure: { cell, album in
                cell.configure(
                    title: album.title,
                    subtitle: album.performer,
                    tertiary: "\(album.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    placeholderSymbol: "music.note.list",
                    artworkURL: album.albumArtURL,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func cueDetailView(_ album: CUEAlbum) -> some View {
        LiquidGlassTrackListRepresentable(
            tracks: cueTracks,
            rowHeight: 44,
            scrollKey: "liquid_cue_detail_\(album.title)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                playerVM.playbackMode = .album(cueTracks)
                playerVM.playerTracks = cueTracks
                selectedTrackID = track.id
                playerVM.play(track) { self.playNextTrack() }
            }
        )
        .ignoresSafeArea(edges: .top)
        .onAppear {
            cueTracks = album.makeTracks()
        }
    }


    // MARK: - Треки

    private var trackListView: some View {
        let key: String
        switch libraryVM.sortField {
        case .title: key = "liquid_tracks_title"
        case .year: key = "liquid_tracks_year"
        case .rating: key = "liquid_tracks_rating"
        case .duration: key = "liquid_tracks_duration"
        default: key = "liquid_tracks_title"
        }

        return LiquidGlassTrackListRepresentable(
            tracks: libraryVM.filteredTracks,
            rowHeight: 44,
            scrollKey: key,
            scrollToTopTrigger: libraryVM.searchText,
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: libraryVM.sortField == .rating,
            contentInsets: NSEdgeInsets(top: 60, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.play(track) { self.playNextTrack() }
            }
        )
    }

    // MARK: - Избранное

    private var favoritesView: some View {
        let hasMissing = !playerVM.missingFavorites.isEmpty
        // Если секция потерянного избранного уже занимает верх —
        // большой top-инсет не нужен, иначе пустая дыра между баннером и списком.
        let trackListTopInset: CGFloat = hasMissing ? 8 : 60

        return VStack(spacing: 0) {
            if hasMissing {
                LiquidGlassMissingFavoritesSection(
                    missingTracks: playerVM.missingFavorites,
                    onRemove: { track in playerVM.toggleFavorite(track) },
                    onClearAll: {
                        for track in playerVM.missingFavorites {
                            playerVM.toggleFavorite(track)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 60)
                .padding(.bottom, 8)
            }

            LiquidGlassTrackListRepresentable(
                tracks: playerVM.availableFavorites,
                rowHeight: 44,
                scrollKey: "liquid_favorites",
                scrollToID: highlightedTrackID,
                highlightedTrackID: highlightedTrackID,
                currentTrackID: playerVM.currentTrack?.id,
                isPlaying: playerVM.isPlaying,
                showRating: false,
                contentInsets: NSEdgeInsets(top: trackListTopInset, left: 0, bottom: 80, right: 0),
                menuProvider: { tracks in
                    self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                },
                onDoubleClick: { track in
                    selectedTrackID = track.id
                    playerVM.play(track) { self.playNextTrack() }
                }
            )
        }
    }

    // MARK: - Track context menu

    /// Обёртка для одиночного вызова (обратная совместимость).
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

    /// Единое меню для списка (одиночное и множественное выделение).
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

    // MARK: - Playlist menu

    private func buildPlaylistMenu(
        pl: (name: String, tracks: [Track]),
        index: Int
    ) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(closureItem(
            title: NSLocalizedString("choose_from_presets", comment: ""),
            systemImage: "photo.on.rectangle"
        ) {
            presetPickerType = .playlist(pl.name)
        })

        menu.addItem(closureItem(
            title: NSLocalizedString("add_artwork", comment: ""),
            systemImage: "photo"
        ) {
            chooseArtwork(for: .playlist(pl.name))
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
            action: nil,
            keyEquivalent: ""
        )
        let exportSub = NSMenu()

        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_absolute", comment: ""),
            systemImage: "arrow.up.doc"
        ) {
            exportPlaylist(pl, useAbsolutePaths: true)
        })

        exportSub.addItem(closureItem(
            title: NSLocalizedString("export_relative", comment: ""),
            systemImage: "arrow.up.doc"
        ) {
            exportPlaylist(pl, useAbsolutePaths: false)
        })

        exportRoot.submenu = exportSub
        menu.addItem(exportRoot)

        menu.addItem(.separator())

        if index >= 0 {
            menu.addItem(closureItem(
                title: NSLocalizedString("delete_playlist", comment: ""),
                systemImage: "trash"
            ) {
                libraryVM.removePlaylist(at: index)
            })
        }

        return menu
    }

    // MARK: - Artist / Genre menu

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
            presetPickerType = type
        })

        menu.addItem(closureItem(
            title: NSLocalizedString("add_artwork", comment: ""),
            systemImage: "photo"
        ) {
            chooseArtwork(for: type)
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

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    let ext = url.pathExtension.lowercased()
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        libraryVM.addFolder(url)
                    } else if ext == "m3u" || ext == "m3u8" {
                        libraryVM.importM3U(url)
                    } else if ["mp3", "flac", "m4a", "aac", "opus", "ogg"].contains(ext) {
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
}

// MARK: - MissingFavoritesSection
@available(macOS 26.0, *)
struct LiquidGlassMissingFavoritesSection: View {
    let missingTracks: [Track]
    let onRemove: (Track) -> Void
    let onClearAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.yellow.opacity(0.7))

                    Text(String(format: NSLocalizedString("missing_favorites_count", comment: ""), missingTracks.count))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if isExpanded {
                        Button(action: onClearAll) {
                            Text(LocalizedStringKey("clear"))
                                .font(.system(size: 10))
                                .foregroundColor(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.05))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.primary.opacity(0.1))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(missingTracks) { track in
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.square.dashed")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.4))
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text(track.artist)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(action: { onRemove(track) }) {
                                    Image(systemName: "star.slash.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
        }
    }
}
