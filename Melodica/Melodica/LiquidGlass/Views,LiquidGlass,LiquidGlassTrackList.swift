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
    @Namespace private var gridAnimation
    @ObservedObject private var settings = SettingsManager.shared
    @State private var gridRefreshID = UUID()
    @ObservedObject var smartVM: SmartPlaylistViewModel

    // MARK: - Позиции скролла
    @State private var albumGridPosition = ScrollPosition(idType: String.self)
    @State private var albumDetailPosition = ScrollPosition(idType: UUID.self)

    @State private var artistGridPosition = ScrollPosition(idType: String.self)
    @State private var artistDetailPosition = ScrollPosition(idType: UUID.self)

    @State private var genreGridPosition = ScrollPosition(idType: String.self)
    @State private var genreDetailPosition = ScrollPosition(idType: UUID.self)

    @State private var playlistGridPosition = ScrollPosition(idType: String.self)
    @State private var playlistDetailPosition = ScrollPosition(idType: UUID.self)

    @State private var cueGridPosition = ScrollPosition(idType: String.self)
    @State private var cueDetailPosition = ScrollPosition(idType: UUID.self)

    @State private var titlePosition = ScrollPosition(idType: UUID.self)
    @State private var yearPosition = ScrollPosition(idType: UUID.self)
    @State private var ratingPosition = ScrollPosition(idType: UUID.self)
    @State private var durationPosition = ScrollPosition(idType: UUID.self)
    @State private var favoritesPosition = ScrollPosition(idType: UUID.self)

    @State private var lastSaveTimes: [String: Date] = [:]
    
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
        .onChange(of: settings.albumGridSize) { _ in
            gridRefreshID = UUID()
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
        GeometryReader { geometry in
            ScrollView {
                let cellSize = settings.albumGridSize
                let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(libraryVM.albumGroups, id: \.album) { group in
                        LiquidGlassAlbumCell(group: group)
                            .frame(height: cellSize + 50)
                            .matchedGeometryEffect(id: "album_\(group.album)", in: gridAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedAlbum = group.album
                                }
                            }
                    }
                }
                .padding(12)
                .scrollTargetLayout()
                .animation(.easeInOut(duration: 0.3), value: columns)
            }
        }
        .id(gridRefreshID)
        .scrollPosition($albumGridPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.get(key: "liquid_albums_grid") {
                albumGridPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: albumGridPosition.viewID(type: String.self)) { _, newID in
            if let id = newID {
                ScrollPositionManager.shared.save(key: "liquid_albums_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)
    }

    private func albumDetailView(_ group: (album: String, artist: String, tracks: [Track], artURL: URL?)) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: true, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($albumDetailPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_album_detail_\(group.album)") {
                albumDetailPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: albumDetailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            ScrollPositionManager.shared.saveUUID(key: "liquid_album_detail_\(group.album)", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .ignoresSafeArea(edges: .top)
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
        GeometryReader { geometry in
            ScrollView {
                let cellSize = settings.albumGridSize
                let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(libraryVM.artistGroups, id: \.artist) { group in
                        LiquidGlassArtistCell(group: group)
                            .frame(height: cellSize + 50)
                            .matchedGeometryEffect(id: "artist_\(group.artist)", in: gridAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedArtist = group.artist
                                }
                            }
                    }
                }
                .padding(12)
                .scrollTargetLayout()
                .animation(.easeInOut(duration: 0.3), value: columns)
            }
        }
        .id(gridRefreshID)
        .scrollPosition($artistGridPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.get(key: "liquid_artists_grid") {
                artistGridPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: artistGridPosition.viewID(type: String.self)) { _, newID in
            if let id = newID {
                ScrollPositionManager.shared.save(key: "liquid_artists_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)
    }

    private func artistDetailView(_ group: (artist: String, tracks: [Track], artURL: URL?)) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: true, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($artistDetailPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_artist_detail_\(group.artist)") {
                artistDetailPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: artistDetailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            ScrollPositionManager.shared.saveUUID(key: "liquid_artist_detail_\(group.artist)", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
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
        GeometryReader { geometry in
            ScrollView {
                let cellSize = settings.albumGridSize
                let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(libraryVM.genreGroups, id: \.genre) { group in
                        LiquidGlassGenreCell(group: group)
                            .frame(height: cellSize + 50)
                            .matchedGeometryEffect(id: "genre_\(group.genre)", in: gridAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedGenre = group.genre
                                }
                            }
                    }
                }
                .padding(12)
                .scrollTargetLayout()
                .animation(.easeInOut(duration: 0.3), value: columns)
            }
        }
        .id(gridRefreshID)
        .scrollPosition($genreGridPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.get(key: "liquid_genres_grid") {
                genreGridPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: genreGridPosition.viewID(type: String.self)) { _, newID in
            if let id = newID {
                ScrollPositionManager.shared.save(key: "liquid_genres_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)
    }

    private func genreDetailView(_ group: (genre: String, tracks: [Track], artURL: URL?)) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: true, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($genreDetailPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_genre_detail_\(group.genre)") {
                genreDetailPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: genreDetailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            ScrollPositionManager.shared.saveUUID(key: "liquid_genre_detail_\(group.genre)", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .ignoresSafeArea(edges: .top)
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
        GeometryReader { geometry in
            ScrollView {
                let cellSize = settings.albumGridSize
                let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(Array(libraryVM.playlists.enumerated()), id: \.offset) { idx, pl in
                        LiquidGlassPlaylistCell(playlist: pl)
                            .frame(height: cellSize + 50)
                            .matchedGeometryEffect(id: "playlist_\(idx)", in: gridAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedPlaylist = idx
                                    playerVM.playerTracks = pl.tracks
                                }
                            }
                            .contextMenu {
                                Menu(LocalizedStringKey("export_playlist")) {
                                    Button(action: { exportPlaylist(pl, useAbsolutePaths: true) }) {
                                        Label(LocalizedStringKey("export_absolute"), systemImage: "arrow.up.doc")
                                    }
                                    Button(action: { exportPlaylist(pl, useAbsolutePaths: false) }) {
                                        Label(LocalizedStringKey("export_relative"), systemImage: "arrow.up.doc")
                                    }
                                }
                                Divider()
                                Button(role: .destructive, action: { libraryVM.removePlaylist(at: idx) }) {
                                    Label(LocalizedStringKey("delete_playlist"), systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(12)
                .scrollTargetLayout()
                .animation(.easeInOut(duration: 0.3), value: columns)
            }
        }
        .id(gridRefreshID)
        .scrollPosition($playlistGridPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.get(key: "liquid_playlists_grid") {
                playlistGridPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: playlistGridPosition.viewID(type: String.self)) { _, newID in
            if let id = newID {
                ScrollPositionManager.shared.save(key: "liquid_playlists_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)    }

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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: false, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($playlistDetailPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_playlist_detail_\(playlist.name)") {
                playlistDetailPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: playlistDetailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            ScrollPositionManager.shared.saveUUID(key: "liquid_playlist_detail_\(playlist.name)", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
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
        GeometryReader { geometry in
            ScrollView {
                if libraryVM.cueAlbums.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(LocalizedStringKey("no_cue_files"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    let cellSize = settings.albumGridSize
                    let columns = max(1, Int(geometry.size.width / (cellSize + 12)))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                        ForEach(libraryVM.cueAlbums, id: \.title) { album in
                            LiquidGlassCUECell(album: album)
                            .frame(height: cellSize + 50)
                            .matchedGeometryEffect(id: "cue_\(album.title)", in: gridAnimation)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedCUEAlbum = album
                                }
                            }
                        }
                    }
                    .padding(12)
                    .scrollTargetLayout()
                    .animation(.easeInOut(duration: 0.3), value: columns)
                }
            }
        }
        .id(gridRefreshID)
        .scrollPosition($cueGridPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.get(key: "liquid_cue_grid") {
                cueGridPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: cueGridPosition.viewID(type: String.self)) { _, newID in
            if let id = newID {
                ScrollPositionManager.shared.save(key: "liquid_cue_grid", id: id)
            }
        }
        .contentMargins(.vertical, 80, for: .scrollContent)
    }

    private func cueDetailView(_ album: CUEAlbum) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(cueTracks.enumerated()), id: \.element.id) { index, track in
                    cueTrackRow(track, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($cueDetailPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_cue_detail_\(album.title)") {
                cueDetailPosition.scrollTo(id: savedID)
            }

            cueTracks = []

            Task {
                let tracks = album.tracks.map { cue in
                    let cueURL = URL(string: album.file.absoluteString + "#cue_\(String(format: "%.3f", cue.startTime))") ?? album.file

                    return Track(
                        url: cueURL,
                        fileName: "\(cue.trackNumber). \(cue.title)",
                        title: cue.title,
                        artist: cue.performer,
                        album: album.title,
                        year: album.year,
                        duration: cue.duration ?? max(0, 0),
                        trackNumber: cue.trackNumber,
                        genre: album.genre,
                        albumArtURL: album.albumArtURL,
                        replayGain: album.replayGain,
                        replayGainPeak: album.replayGainPeak,
                        replayGainAlbum: album.replayGainAlbum,
                        replayGainAlbumPeak: album.replayGainAlbumPeak,
                        lyricsURL: findLyricsForCUETrack(cue, album: album),
                        unsyncedLyrics: album.unsyncedLyrics,
                        cueStartTime: cue.startTime
                    )
                }

                await MainActor.run {
                    cueTracks = tracks
                }
            }
        }
        .onChange(of: cueDetailPosition.viewID(type: UUID.self)) { newID in
            guard let id = newID else { return }
            ScrollPositionManager.shared.saveUUID(key: "liquid_cue_detail_\(album.title)", id: id)
        }
        .contentMargins(.top, 80, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .ignoresSafeArea(edges: .top)
    }

    private func findLyricsForCUETrack(_ cue: CUETrack, album: CUEAlbum) -> URL? {
        let baseDir = album.file.deletingLastPathComponent()

        let names = [
            "\(cue.performer) - \(cue.title).lrc",
            "\(cue.title).lrc"
        ]

        for name in names {
            let url = baseDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        return nil
    }

    // MARK: - Треки

    private var trackListView: some View {
        let key: String
        let positionBinding: Binding<ScrollPosition>

        switch libraryVM.sortField {
        case .title:
            key = "liquid_tracks_title"
            positionBinding = $titlePosition
        case .year:
            key = "liquid_tracks_year"
            positionBinding = $yearPosition
        case .rating:
            key = "liquid_tracks_rating"
            positionBinding = $ratingPosition
        case .duration:
            key = "liquid_tracks_duration"
            positionBinding = $durationPosition
        default:
            key = "liquid_tracks_title"
            positionBinding = $titlePosition
        }

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(libraryVM.filteredTracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: false, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition(positionBinding)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: key) {
                positionBinding.wrappedValue.scrollTo(id: savedID)
            }
        }
        .onChange(of: libraryVM.sortField) { newField in
            guard !showFavoritesOnly else { return }

            let newKey: String
            switch newField {
            case .title: newKey = "liquid_tracks_title"
            case .year: newKey = "liquid_tracks_year"
            case .rating: newKey = "liquid_tracks_rating"
            case .duration: newKey = "liquid_tracks_duration"
            default: return
            }

            if let id = positionBinding.wrappedValue.viewID(type: UUID.self) {
                ScrollPositionManager.shared.saveUUID(key: key, id: id)
            }

            if let savedID = ScrollPositionManager.shared.getUUID(key: newKey) {
                positionBinding.wrappedValue.scrollTo(id: savedID)
            } else {
                positionBinding.wrappedValue.scrollTo(y: 0)
            }
        }
        .contentMargins(.top, 60, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    // MARK: - Избранное

    private var favoritesView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playerVM.availableFavorites.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, showNum: false, index: index)
                }
            }
            .padding(.vertical, 4)
            .scrollTargetLayout()
        }
        .scrollPosition($favoritesPosition)
        .onAppear {
            if let savedID = ScrollPositionManager.shared.getUUID(key: "liquid_favorites") {
                favoritesPosition.scrollTo(id: savedID)
            }
        }
        .onChange(of: showFavoritesOnly) { newValue in
            guard !newValue else { return }

            if let id = favoritesPosition.viewID(type: UUID.self) {
                ScrollPositionManager.shared.saveUUID(key: "liquid_favorites", id: id)
            }
        }
        .contentMargins(.top, 60, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }
    
    // MARK: - Строка трека

    private func trackRow(_ track: Track, showNum: Bool, index: Int) -> some View {
        LiquidGlassTrackRow(
            track: track,
            isCurrent: playerVM.currentTrack?.id == track.id,
            isPlaying: playerVM.isPlaying,
            onPlay: {
                selectedTrackID = track.id
                playerVM.play(track) {
                    playerVM.playNextTrack()
                }
            },
            onAddToQueue: { playerVM.addToQueue(track) },
            onToggleFavorite: { playerVM.toggleFavorite(track) },
            isFavorite: playerVM.isFavorite(track),
            isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
            onShowInAlbum: {
                selectedArtist = nil
                selectedGenre = nil
                selectedPlaylist = nil
                selectedCUEAlbum = nil
                selectedSmartPlaylistID = nil

                libraryVM.sortField = .album
                selectedAlbum = track.album
            },
            showRating: libraryVM.sortField == .rating,
            isEven: index % 2 == 0
        )
    }
    private func cueTrackRow(_ track: Track, index: Int) -> some View {
        LiquidGlassTrackRow(
            track: track,
            isCurrent: playerVM.currentTrack?.id == track.id,
            isPlaying: playerVM.isPlaying,
            onPlay: {
                selectedTrackID = track.id
                playerVM.playbackMode = .album(cueTracks)
                playerVM.playerTracks = cueTracks
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

// MARK: - Ячейки

struct LiquidGlassArtistCell: View {
    let group: (artist: String, tracks: [Track], artURL: URL?)
    @ObservedObject private var settings = SettingsManager.shared

    private var tileSize: CGFloat { settings.albumGridSize - 10 }

    var body: some View {
        VStack(spacing: 4) {
            if let artURL = group.tracks.first(where: { $0.albumArtURL != nil })?.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: tileSize, height: tileSize))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: tileSize, height: tileSize)
                    Image(systemName: "person.fill")
                        .font(.system(size: tileSize * 0.25))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Text(group.artist)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct LiquidGlassGenreCell: View {
    let group: (genre: String, tracks: [Track], artURL: URL?)
    @ObservedObject private var settings = SettingsManager.shared

    private var tileSize: CGFloat { settings.albumGridSize - 10 }

    var body: some View {
        VStack(spacing: 4) {
            if let artURL = group.tracks.first(where: { $0.albumArtURL != nil })?.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: tileSize, height: tileSize))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: tileSize, height: tileSize)
                    Image(systemName: "tag.fill")
                        .font(.system(size: tileSize * 0.25))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Text(group.genre)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct LiquidGlassPlaylistCell: View {
    let playlist: (name: String, tracks: [Track])
    @ObservedObject private var settings = SettingsManager.shared

    private var tileSize: CGFloat { settings.albumGridSize - 10 }

    var body: some View {
        VStack(spacing: 4) {
            if let firstTrack = playlist.tracks.first {
                CachedImage(url: firstTrack.thumbURL(size: "400") ?? firstTrack.albumArtURL,
                           size: CGSize(width: tileSize, height: tileSize))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: tileSize, height: tileSize)
                    Image(systemName: "music.note.list")
                        .font(.system(size: tileSize * 0.25))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Text(playlist.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(playlist.tracks.count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
