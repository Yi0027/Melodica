// Views,LiquidGlass,LiquidGlassTrackList.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers


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
    @Binding var selectedRecommendationSectionID: UUID?
    @Binding var showRightPanel: Bool
    @Binding var showFavoritesOnly: Bool
    @ObservedObject var smartVM: SmartPlaylistViewModel

    @State private var cueTracks: [Track] = []
    @State private var artworkVersion = 0
    @State private var presetPickerType: UserArtworkManager.ArtworkType?
    @State private var highlightedTrackID: UUID?
    @State private var highlightTimer: Timer?
    @ObservedObject private var settings = SettingsManager.shared

    private var isDetailOpen: Bool {
        selectedAlbum != nil ||
        selectedArtist != nil ||
        selectedGenre != nil ||
        selectedPlaylist != nil ||
        selectedCUEAlbum != nil ||
        selectedSmartPlaylistID != nil ||
        selectedRecommendationSectionID != nil
    }

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
                mainContent
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .overlay(alignment: .top) {
            if isDetailOpen {
                detailHeaderOverlay
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .sheet(item: $presetPickerType) { type in
            LiquidGlassArtworkPresetPickerView(type: type)
                .onDisappear {
                    artworkVersion += 1
                }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDetailOpen)
        .onChange(of: isDetailOpen) { _, isOpen in
            if !isOpen {
                NotificationCenter.default.post(
                    name: .detailHeaderHeightChanged,
                    object: nil,
                    userInfo: ["height": CGFloat(0)]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserArtworkDidChange"))) { _ in
            artworkVersion += 1
        }
    }

    // MARK: - Main Content Switcher

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if libraryVM.sortField == .recommendations && !showFavoritesOnly {
                LiquidGlassRecommendationsView(
                    libraryVM: libraryVM,
                    playerVM: playerVM,
                    selectedTrackID: $selectedTrackID,
                    selectedSectionID: $selectedRecommendationSectionID
                )
            } else if libraryVM.sortField == .album && !showFavoritesOnly {
                albumView
            } else if libraryVM.sortField == .playlists && !showFavoritesOnly {
                playlistsView
            } else if libraryVM.sortField == .smart && !showFavoritesOnly {
                LiquidGlassSmartPlaylistsView(
                    libraryVM: libraryVM,
                    playerVM: playerVM,
                    vm: smartVM,
                    selectedSmartPlaylistID: $selectedSmartPlaylistID
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
    }

    // MARK: - Detail Header Overlay

    @ViewBuilder
    private var detailHeaderOverlay: some View {
        if let albumName = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
            let artURL = group.tracks.first(where: { $0.albumArtURL != nil })?.thumbURL(size: "84")
                ?? group.tracks.first(where: { $0.albumArtURL != nil })?.albumArtURL
                ?? group.artURL
            detailHeaderView(title: group.album, subtitle: group.artist, artURL: artURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedAlbum = nil
                }
            }
        } else if let artist = selectedArtist,
                  let group = libraryVM.artistGroups.first(where: { $0.artist == artist }) {
            let artURL = UserArtworkManager.imageURL(for: .artist(group.artist))
                ?? group.tracks.first(where: { $0.albumArtURL != nil })?.thumbURL(size: "84")
                ?? group.tracks.first?.albumArtURL
            detailHeaderView(title: group.artist, subtitle: nil, artURL: artURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedArtist = nil
                }
            }
        } else if let genre = selectedGenre,
                  let group = libraryVM.genreGroups.first(where: { $0.genre == genre }) {
            let artURL = UserArtworkManager.imageURL(for: .genre(group.genre))
                ?? group.tracks.first(where: { $0.albumArtURL != nil })?.thumbURL(size: "84")
                ?? group.tracks.first?.albumArtURL
            detailHeaderView(title: group.genre, subtitle: nil, artURL: artURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedGenre = nil
                }
            }
        } else if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
            let pl = libraryVM.playlists[idx]
            let artURL = UserArtworkManager.imageURL(for: .playlist(pl.name))
                ?? pl.tracks.first(where: { $0.albumArtURL != nil })?.thumbURL(size: "84")
                ?? pl.tracks.first?.albumArtURL
            detailHeaderView(title: pl.name, subtitle: nil, artURL: artURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedPlaylist = nil
                }
            }
        } else if let album = selectedCUEAlbum {
            detailHeaderView(title: album.title, subtitle: album.performer, artURL: album.albumArtURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedCUEAlbum = nil
                }
            }
        } else if let id = selectedSmartPlaylistID,
                  let pl = smartVM.playlists.first(where: { $0.id == id }) {
            let favs = Set(playerVM.favorites.map { $0.url.standardizedFileURL.path })
            let smartTracks = smartVM.tracks(for: pl, library: libraryVM.tracks, favoriteURLs: favs)
            let count = smartTracks.count
            let countText = String(format: NSLocalizedString("tracks_count", comment: ""), count)
            let artURL = UserArtworkManager.imageURL(for: .smartPlaylist(pl.id))
                ?? smartTracks.first(where: { $0.albumArtURL != nil })?.thumbURL(size: "84")
                ?? smartTracks.first?.albumArtURL
            detailHeaderView(title: pl.name, subtitle: countText, artURL: artURL) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedSmartPlaylistID = nil
                }
            }
        }
    }

    private func detailHeaderView(title: String, subtitle: String?, artURL: URL?, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            if let artURL = artURL {
                CachedImage(url: artURL, size: CGSize(width: 36, height: 36))
                    .id("\(artURL.path)_\(artworkVersion)")
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
                }
            }
            Spacer()
        }
        .frame(minHeight: 36)
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 15))
        .padding(.bottom, 16)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        NotificationCenter.default.post(
                            name: .detailHeaderHeightChanged,
                            object: nil,
                            userInfo: ["height": geo.size.height]
                        )
                    }
                    .onChange(of: geo.size.height) { _, newH in
                        NotificationCenter.default.post(
                            name: .detailHeaderHeightChanged,
                            object: nil,
                            userInfo: ["height": newH]
                        )
                    }
            }
        )
    }

    // MARK: - Albums

    private var albumView: some View {
        ZStack {
            if let albumName = selectedAlbum,
               let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
                albumDetailView(group)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                albumGridView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedAlbum != nil)
    }

    private var albumGridView: some View {
        let cellW = settings.albumGridSize
        let cellH = settings.albumGridSize + 62
        let maxPixel = settings.albumGridSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.albumGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 80, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_albums_grid",
            reloadToken: artworkVersion,
            identifier: { $0.album },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedAlbum = group.album
                }
            },
            onPlay: { group in
                let tracks = group.tracks
                guard !tracks.isEmpty else { return }
                let trackToPlay = (playerVM.shuffleMode ? tracks.randomElement() : nil) ?? tracks[0]
                let contextID = "album:\(group.album)"
                playerVM.startPlayback(track: trackToPlay, from: tracks, contextID: contextID)
            },
            contextMenu: nil,
            configure: { cell, group in
                let allGenres = group.tracks.compactMap { $0.genre }.filter { !$0.isEmpty }
                let genres = Array(Set(allGenres)).sorted().prefix(2).joined(separator: ", ")
                let art = group.tracks.first.flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                    ?? group.artURL
                cell.configure(
                    title: group.album,
                    subtitle: group.artist,
                    tertiary: genres,
                    placeholderSymbol: "music.note",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func albumDetailView(_ group: (album: String, artist: String, tracks: [Track], artURL: URL?)) -> some View {
        let contextID = "album:\(group.album)"
        return LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_album_\(group.album)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: group.tracks, contextID: contextID)
            }
        )
    }

    // MARK: - Artists

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
                artistGridView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedArtist != nil)
    }

    private var artistGridView: some View {
        let cellW = settings.albumGridSize
        let cellH = settings.albumGridSize + 62
        let maxPixel = settings.albumGridSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.artistGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 80, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_artists_grid",
            reloadToken: artworkVersion,
            identifier: { $0.artist },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedArtist = group.artist
                }
            },
            onPlay: { group in
                let tracks = group.tracks
                guard !tracks.isEmpty else { return }
                let trackToPlay = (playerVM.shuffleMode ? tracks.randomElement() : nil) ?? tracks[0]
                let contextID = "artist:\(group.artist)"
                playerVM.startPlayback(track: trackToPlay, from: tracks, contextID: contextID)
            },
            contextMenu: { group in
                buildArtistGenreMenu(type: .artist(group.artist), name: group.artist)
            },
            configure: { cell, group in
                let art = UserArtworkManager.imageURL(for: .artist(group.artist))
                    ?? group.tracks.first.flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                    ?? group.artURL
                cell.configure(
                    title: group.artist,
                    subtitle: "\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    tertiary: "",
                    placeholderSymbol: "person.fill",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func artistDetailView(_ group: (artist: String, tracks: [Track], artURL: URL?)) -> some View {
        let contextID = "artist:\(group.artist)"
        return LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_artist_\(group.artist)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: group.tracks, contextID: contextID)
            }
        )
    }

    // MARK: - Genres

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
                genreGridView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedGenre != nil)
    }

    private var genreGridView: some View {
        let cellW = settings.albumGridSize
        let cellH = settings.albumGridSize + 62
        let maxPixel = settings.albumGridSize * 2

        return LiquidGlassAppKitGridView(
            items: libraryVM.genreGroups,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 80, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_genres_grid",
            reloadToken: artworkVersion,
            identifier: { $0.genre },
            onSelect: { group in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedGenre = group.genre
                }
            },
            onPlay: { group in
                let tracks = group.tracks
                guard !tracks.isEmpty else { return }
                let trackToPlay = (playerVM.shuffleMode ? tracks.randomElement() : nil) ?? tracks[0]
                let contextID = "genre:\(group.genre)"
                playerVM.startPlayback(track: trackToPlay, from: tracks, contextID: contextID)
            },
            contextMenu: { group in
                buildArtistGenreMenu(type: .genre(group.genre), name: group.genre)
            },
            configure: { cell, group in
                let art = UserArtworkManager.imageURL(for: .genre(group.genre))
                    ?? group.tracks.first.flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                    ?? group.artURL
                cell.configure(
                    title: group.genre,
                    subtitle: "\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    tertiary: "",
                    placeholderSymbol: "tag.fill",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func genreDetailView(_ group: (genre: String, tracks: [Track], artURL: URL?)) -> some View {
        let contextID = "genre:\(group.genre)"
        return LiquidGlassTrackListRepresentable(
            tracks: group.tracks,
            rowHeight: 44,
            scrollKey: "liquid_genre_\(group.genre)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: group.tracks, contextID: contextID)
            }
        )
    }

    // MARK: - Playlists

    private var playlistsView: some View {
        ZStack {
            if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
                playlistDetailView(libraryVM.playlists[idx], index: idx)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                playlistGridView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlaylist != nil)
    }

    private var playlistGridView: some View {
        let cellW = settings.albumGridSize
        let cellH = settings.albumGridSize + 62
        let maxPixel = settings.albumGridSize * 2

        return LiquidGlassAppKitGridView(
            items: Array(libraryVM.playlists.enumerated()),
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 80, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_playlists_grid",
            reloadToken: artworkVersion,
            identifier: { "\($0.offset)_\($0.element.name)" },
            onSelect: { idx, pl in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedPlaylist = idx
                    playerVM.playerTracks = pl.tracks
                }
            },
            onPlay: { idx, pl in
                let tracks = pl.tracks
                guard !tracks.isEmpty else { return }
                let trackToPlay = (playerVM.shuffleMode ? tracks.randomElement() : nil) ?? tracks[0]
                let contextID = "playlist:\(pl.name)"
                playerVM.startPlayback(track: trackToPlay, from: tracks, contextID: contextID)
            },
            contextMenu: { idx, pl in
                buildPlaylistMenu(pl: pl, index: idx)
            },
            configure: { cell, pair in
                let (_, pl) = pair
                let art = UserArtworkManager.imageURL(for: .playlist(pl.name))
                    ?? pl.tracks.first.flatMap { $0.thumbURL(size: "400") ?? $0.albumArtURL }
                cell.configure(
                    title: pl.name,
                    subtitle: "\(pl.tracks.count) \(NSLocalizedString("tracks", comment: ""))",
                    tertiary: "",
                    placeholderSymbol: "music.note.list",
                    artworkURL: art,
                    maxPixel: maxPixel
                )
            }
        )
    }

    private func playlistDetailView(_ playlist: (name: String, tracks: [Track]), index: Int) -> some View {
        let contextID = "playlist:\(playlist.name)"
        return LiquidGlassTrackListRepresentable(
            tracks: playlist.tracks,
            rowHeight: 44,
            scrollKey: "liquid_playlist_\(playlist.name)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { tracks in
                self.buildTrackMenu(
                    tracks: tracks,
                    onRemoveFromPlaylist: { tracksToRemove in
                        let ids = Set(tracksToRemove.map(\.id))
                        guard index < libraryVM.playlists.count else { return }
                        libraryVM.playlists[index].tracks.removeAll { ids.contains($0.id) }
                        libraryVM.savePlaylistsToCache()
                    }
                )
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: playlist.tracks, contextID: contextID)
            }
        )
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
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(LocalizedStringKey("no_cue_files"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            )
        }

        let cellW = settings.albumGridSize
        let cellH = settings.albumGridSize + 62
        let maxPixel = settings.albumGridSize * 2

        return AnyView(
            LiquidGlassAppKitGridView(
                items: libraryVM.cueAlbums,
                itemSize: CGSize(width: cellW, height: cellH),
                itemSpacing: 12,
                sectionInset: NSEdgeInsets(top: 80, left: 12, bottom: 80, right: 12),
                scrollKey: "liquid_cue_grid",
                reloadToken: artworkVersion,
                identifier: { "\($0.title)|\($0.performer)" },
                onSelect: { album in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedCUEAlbum = album
                    }
                },
                onPlay: { album in
                    let tracks = album.makeTracks()
                    guard !tracks.isEmpty else { return }
                    let trackToPlay = (playerVM.shuffleMode ? tracks.randomElement() : nil) ?? tracks[0]
                    let contextID = "cue:\(album.title)"
                    playerVM.startPlayback(track: trackToPlay, from: tracks, contextID: contextID)
                },
                configure: { cell, album in
                    cell.configure(
                        title: album.title,
                        subtitle: album.performer,
                        tertiary: "",
                        placeholderSymbol: "music.note.list",
                        artworkURL: album.albumArtURL,
                        maxPixel: maxPixel
                    )
                }
            )
        )
    }

    private func cueDetailView(_ album: CUEAlbum) -> some View {
        let tracks = album.makeTracks()
        let contextID = "cue:\(album.title)"
        return LiquidGlassTrackListRepresentable(
            tracks: tracks,
            rowHeight: 44,
            scrollKey: "liquid_cue_detail_\(album.title)",
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: tracks, contextID: contextID)
            }
        )
    }

    // MARK: - Favorites

    private var emptyFavoritesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text(LocalizedStringKey("no_favorites"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

@available(macOS 26.0, *)
private struct LiquidGlassMissingFavoritesSection: View {
    let missingTracks: [Track]
    let onRemove: (Track) -> Void
    let onClearAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)

                        Text(String(format: NSLocalizedString("missing_favorites_count", comment: ""), missingTracks.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded {
                    Button(action: onClearAll) {
                        Text(LocalizedStringKey("clear"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            if isExpanded {
                Divider()
                    .opacity(0.2)
                    .padding(.vertical, 6)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(missingTracks) { track in
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.square.dashed")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text(track.artist)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(action: { onRemove(track) }) {
                                    Image(systemName: "star.slash.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.accentColor.opacity(0.85))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}

    private var favoritesView: some View {
        VStack(spacing: 0) {
            if !playerVM.missingFavorites.isEmpty {
                LiquidGlassMissingFavoritesSection(
                    missingTracks: playerVM.missingFavorites,
                    onRemove: { track in playerVM.toggleFavorite(track) },
                    onClearAll: {
                        for track in playerVM.missingFavorites { playerVM.toggleFavorite(track) }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 58)
                .padding(.bottom, 8)
            }

            LiquidGlassTrackListRepresentable(
                tracks: playerVM.availableFavorites,
                rowHeight: 44,
                scrollKey: "liquid_favorites",
                scrollToTopTrigger: libraryVM.searchText,
                scrollToID: highlightedTrackID,
                highlightedTrackID: highlightedTrackID,
                currentTrackID: playerVM.activeContextID == "favorites" ? playerVM.currentTrack?.id : nil,
                isPlaying: playerVM.isPlaying,
                showRating: true,
                isFavorite: { playerVM.isFavorite($0) },
                onToggleFavorite: { playerVM.toggleFavorite($0) },
                contentInsets: NSEdgeInsets(
                    top: playerVM.missingFavorites.isEmpty ? 80 : 8,
                    left: 0,
                    bottom: 80,
                    right: 0
                ),
                menuProvider: { tracks in
                    self.buildTrackMenu(tracks: tracks, onRemoveFromPlaylist: nil)
                },
                onDoubleClick: { track in
                    selectedTrackID = track.id
                    playerVM.startPlayback(track: track, from: playerVM.availableFavorites, contextID: "favorites")
                }
            )
        }
    }

    // MARK: - All Tracks List

    private var trackListView: some View {
        let tracks = libraryVM.filteredTracks
        let contextID = libraryVM.searchText.isEmpty ? "tracks:\(libraryVM.sortField.rawValue)" : "tracks_search:\(libraryVM.searchText.lowercased())"

        return LiquidGlassTrackListRepresentable(
            tracks: tracks,
            rowHeight: 44,
            scrollKey: "liquid_tracks_\(libraryVM.sortField.rawValue)",
            scrollToTopTrigger: libraryVM.searchText,
            scrollToID: highlightedTrackID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: playerVM.activeContextID == contextID ? playerVM.currentTrack?.id : nil,
            isPlaying: playerVM.isPlaying,
            showRating: true,
            isFavorite: { playerVM.isFavorite($0) },
            onToggleFavorite: { playerVM.toggleFavorite($0) },
            menuProvider: { selectedTracks in
                self.buildTrackMenu(tracks: selectedTracks, onRemoveFromPlaylist: nil)
            },
            onDoubleClick: { track in
                selectedTrackID = track.id
                playerVM.startPlayback(track: track, from: tracks, contextID: contextID)
            }
        )
    }

    // MARK: - Menus

    private func buildArtistGenreMenu(type: UserArtworkManager.ArtworkType, name: String) -> NSMenu {
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

    private func buildPlaylistMenu(pl: (name: String, tracks: [Track]), index: Int) -> NSMenu {
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

        if index >= 0 && index < libraryVM.playlists.count {
            menu.addItem(closureItem(
                title: NSLocalizedString("delete_playlist", comment: ""),
                systemImage: "trash"
            ) {
                libraryVM.removePlaylist(at: index)
            })
        }

        return menu
    }

    private func chooseArtwork(for type: UserArtworkManager.ArtworkType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            UserArtworkManager.save(image, for: type)
            artworkVersion += 1
        }
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
                    highlightTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            withAnimation(.easeOut(duration: 0.5)) {
                                highlightedTrackID = nil
                            }
                        }
                    }
                }
            }
        )
    }

    // MARK: - Drag & Drop

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
