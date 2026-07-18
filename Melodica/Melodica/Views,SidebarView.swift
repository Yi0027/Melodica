// Views,SidebarView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @Binding var selectedTrackID: UUID?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedAlbum: String?
    @Binding var selectedPlaylist: Int?
    
    @State private var showFavoritesOnly: Bool = false
    @State private var showFolderManager = false
    @FocusState private var isSearchFocused: Bool
    
    @State private var trackPositionTitle = ScrollPosition(idType: UUID.self)
    @State private var trackPositionArtist = ScrollPosition(idType: UUID.self)
    @State private var trackPositionGenre = ScrollPosition(idType: UUID.self)
    @State private var trackPositionYear = ScrollPosition(idType: UUID.self)
    @State private var trackPositionDuration = ScrollPosition(idType: UUID.self)
    @State private var trackPositionFavorites = ScrollPosition(idType: UUID.self)
    @State private var lastSaveTimes: [String: Date] = [:]
    
    @State private var albumGridPosition = ScrollPosition(idType: String.self)
    @State private var albumDetailPosition = ScrollPosition(idType: UUID.self)
    @State private var playlistGridPosition = ScrollPosition(idType: String.self)
    @State private var playlistDetailPosition = ScrollPosition(idType: UUID.self)
    
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
        
        // Фильтруем треки из неотслеживаемых папок (только для отображения)
        let watchedPaths = libraryVM.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" }
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
    var onOpenFolder: (() -> Void)? = nil
    
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
                ForEach(Track.SortField.allCases, id: \.self) { field in
                    Button {
                        libraryVM.sortField = field
                        selectedAlbum = nil
                        selectedPlaylist = nil
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
                        .background(RoundedRectangle(cornerRadius: 6).fill(showFavoritesOnly ? Color.accent.opacity(0.2) : Color.white.opacity(0.03)))
                }.buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    libraryVM.sortAscending.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Сброс позиции треков
                        trackPositionTitle.scrollTo(y: 0)
                        trackPositionArtist.scrollTo(y: 0)
                        trackPositionGenre.scrollTo(y: 0)
                        trackPositionYear.scrollTo(y: 0)
                        trackPositionDuration.scrollTo(y: 0)
                        trackPositionFavorites.scrollTo(y: 0)
                        
                        // Сброс позиции альбомов и плейлистов
                        albumGridPosition.scrollTo(y: 0)
                        playlistGridPosition.scrollTo(y: 0)
                    }
                } label: {
                    Image(systemName: libraryVM.sortAscending ? "arrow.up" : "arrow.down").foregroundColor(.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            
            Group {
                if libraryVM.sortField == .album && !showFavoritesOnly {
                    albumView
                } else if libraryVM.sortField == .playlists && !showFavoritesOnly {
                    playlistsView
                } else if showFavoritesOnly && playerVM.favorites.isEmpty {
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
            if !loading {
                // Сканирование завершено — обновляем текущий вид
                if selectedPlaylist != nil {
                    let current = selectedPlaylist
                    selectedPlaylist = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        selectedPlaylist = current
                    }
                }
            }
        }
        .onTapGesture {
            isSearchFocused = false
        }
    }
    
    // MARK: - Альбомы
    
    private var albumView: some View {
        ZStack {
            if let albumName = selectedAlbum,
               let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
                albumDetailView(group)
                    .id(albumName)
            } else {
                albumGridView
                    .id("grid")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedAlbum != nil)
    }
    
    private var albumGridView: some View {
        let key = "albums_grid"
        
        if libraryVM.albumGroups.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(
                VStack(spacing: 12) {
                    Spacer()
                    Text(LocalizedStringKey("search_no_results"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        
        return AnyView(
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: SettingsManager.shared.albumGridSize, maximum: SettingsManager.shared.albumGridSize + 40), spacing: 16)], spacing: 16) {
                    ForEach(libraryVM.albumGroups, id: \.album) { group in
                        AlbumCell(group: group)
                            .onTapGesture { selectedAlbum = group.album }
                    }
                }
                .scrollTargetLayout()
                .padding(12)
            }
            .scrollPosition($albumGridPosition)
            .onAppear {
                if let savedID = ScrollPositionManager.shared.get(key: key) {
                    albumGridPosition.scrollTo(id: savedID)
                }
            }
            .onChange(of: albumGridPosition.viewID(type: String.self)) { _, newID in
                if let id = newID {
                    ScrollPositionManager.shared.save(key: key, id: id)
                }
            }
        )
    }
    private func displayTracksForPlaylist(_ pl: (name: String, tracks: [Track])) -> [Track] {
        var tracks = pl.tracks
        let watchedPaths = libraryVM.watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" }
        if !watchedPaths.isEmpty {
            tracks = tracks.filter { track in
                watchedPaths.contains { track.url.path.hasPrefix($0) }
            }
        }
        return filterPlaylistTracks(tracks)
    }
    
    private func albumDetailView(_ group: (album: String, artist: String, tracks: [Track], artURL: URL?)) -> some View {
        let key = currentScrollKey
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedAlbum = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                CachedImage(url: group.tracks.first?.thumbURL(size: "84") ?? group.artURL, size: CGSize(width: 42, height: 42)).cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.album).font(.system(size: 14, weight: .bold)).foregroundColor(.textMain).lineLimit(1)
                    Text(group.artist).font(.system(size: 11)).foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text(LocalizedStringKey("search_no_results"))
                            .font(.system(size: 13))
                            .foregroundColor(.textMuted.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(group.tracks) { track in
                            trackRowView(track, showNum: true) {
                                playerVM.playbackMode = .album(group.tracks)
                                playerVM.playerTracks = group.tracks
                                playerVM.play(track) { self.playNextTrack() }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 4)
                }
            
            }
            .scrollPosition($albumDetailPosition)
            .onAppear {
                if let savedID = ScrollPositionManager.shared.getUUID(key: key) {
                    albumDetailPosition.scrollTo(id: savedID)
                }
            }
            .onChange(of: albumDetailPosition.viewID(type: UUID.self)) { newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTimes[key], now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTimes[key] = now
                ScrollPositionManager.shared.saveUUID(key: key, id: id)
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
                    .id("grid")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedPlaylist)
    }
    
    private var playlistGridView: some View {
        let key = "playlists_grid"
        
        if filteredPlaylists.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(
                VStack(spacing: 12) {
                    Spacer()
                    Text(LocalizedStringKey("search_no_results"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        
        return AnyView(
            ScrollView {
                if libraryVM.playlists.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "music.note.list").font(.system(size: 32)).foregroundColor(.textMuted.opacity(0.3))
                        Text(LocalizedStringKey("no_playlists")).font(.system(size: 13)).foregroundColor(.textMuted.opacity(0.5))
                        Text(LocalizedStringKey("drop_m3u_hint")).font(.system(size: 11)).foregroundColor(.textMuted.opacity(0.35))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: SettingsManager.shared.albumGridSize, maximum: SettingsManager.shared.albumGridSize + 40), spacing: 16)], spacing: 16) {
                        ForEach(Array(filteredPlaylists.enumerated()), id: \.offset) { idx, pl in
                            PlaylistCell(playlist: pl, onDelete: { libraryVM.removePlaylist(at: idx) })
                                .onTapGesture { selectedPlaylist = idx; playerVM.playerTracks = pl.tracks }
                                .id("playlist_\(idx)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(12)
                }
            }
            .scrollPosition($playlistGridPosition)
            .onAppear {
                if let savedID = ScrollPositionManager.shared.get(key: key) {
                    playlistGridPosition.scrollTo(id: savedID)
                }
            }
            .onChange(of: playlistGridPosition.viewID(type: String.self)) { _, newID in
                if let id = newID {
                    ScrollPositionManager.shared.save(key: key, id: id)
                }
            }
        )
    }
    
    private func playlistDetailView(_ playlist: (name: String, tracks: [Track]), index: Int) -> some View {
        let key = currentScrollKey
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { selectedPlaylist = nil } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.system(size: 14, weight: .bold)).foregroundColor(.textMain).lineLimit(1)
                    let visibleCount = displayTracks.count
                    let totalCount = playlist.tracks.count
                    let countText: String = visibleCount == totalCount
                        ? String(format: NSLocalizedString("tracks_count", comment: ""), totalCount)
                        : "\(totalCount) (\(visibleCount)) \(NSLocalizedString("tracks_label", comment: ""))"

                    Text(countText)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text(LocalizedStringKey("search_no_results"))
                            .font(.system(size: 13))
                            .foregroundColor(.textMuted.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filterPlaylistTracks(displayTracks)) { track in
                            trackRowView(track, showNum: false) {
                                playerVM.playbackMode = .playlist(playlist.tracks, name: playlist.name)
                                playerVM.playerTracks = playlist.tracks
                                playerVM.play(track) { self.playNextTrack() }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 4)
                }
            }
            .scrollPosition($playlistDetailPosition)
            .onAppear {
                if let savedID = ScrollPositionManager.shared.getUUID(key: key) {
                    playlistDetailPosition.scrollTo(id: savedID)
                }
            }
            .onChange(of: playlistDetailPosition.viewID(type: UUID.self)) { newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTimes[key], now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTimes[key] = now
                ScrollPositionManager.shared.saveUUID(key: key, id: id)
            }
        }
        .background(Color.darkBg)
    }
    // MARK: - Избранное с ненайденными треками

    private var favoritesView: some View {
        VStack(spacing: 0) {
            if !playerVM.missingFavorites.isEmpty {
                MissingFavoritesSection(
                    missingTracks: playerVM.missingFavorites,
                    onRemove: { track in playerVM.toggleFavorite(track) },
                    onClearAll: {
                        for track in playerVM.missingFavorites {
                            playerVM.toggleFavorite(track)
                        }
                    }
                )
            }
            
            if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text(LocalizedStringKey("search_no_results"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                trackListView
            }
        }
    }
    
    // MARK: - Пустое избранное
    
    private var emptyFavoritesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star.slash").font(.system(size: 32)).foregroundColor(.textMuted.opacity(0.3))
            Text(LocalizedStringKey("no_favorites")).font(.system(size: 13)).foregroundColor(.textMuted.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Список треков (сохраняет позицию только при смене вкладки)
    
    private var trackListView: some View {
        let key = currentScrollKey
        
        let positionBinding: Binding<ScrollPosition> = {
            switch key {
            case "tracks_title":   return $trackPositionTitle
            case "tracks_artist":  return $trackPositionArtist
            case "tracks_genre":   return $trackPositionGenre
            case "tracks_year":    return $trackPositionYear
            case "tracks_duration": return $trackPositionDuration
            default:               return $trackPositionFavorites
            }
        }()
        
        if displayTracks.isEmpty && !libraryVM.searchText.isEmpty {
            return AnyView(
                VStack(spacing: 12) {
                    Spacer()
                    Text(LocalizedStringKey("search_no_results"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        
        return AnyView(
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayTracks) { track in
                        trackRowView(track, showNum: !showFavoritesOnly && libraryVM.sortField == .album) {
                            selectedTrackID = track.id
                            playerVM.play(track) { self.playNextTrack() }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollPosition(positionBinding, anchor: .top)
            .onAppear {
                if let savedID = ScrollPositionManager.shared.getUUID(key: key) {
                    positionBinding.wrappedValue.scrollTo(id: savedID, anchor: .top)
                }
            }
            .onChange(of: currentScrollKey) { newKey in
                if let id = positionBinding.wrappedValue.viewID(type: UUID.self) {
                    ScrollPositionManager.shared.saveUUID(key: key, id: id)
                }
                if let savedID = ScrollPositionManager.shared.getUUID(key: newKey) {
                    positionBinding.wrappedValue.scrollTo(id: savedID, anchor: .top)
                } else {
                    positionBinding.wrappedValue.scrollTo(y: 0)
                }
            }
            .onChange(of: libraryVM.searchText) { _ in
                ScrollPositionManager.shared.clear(key: key)
                positionBinding.wrappedValue.scrollTo(y: 0)
            }
        )
    }
    // MARK: - Вспомогательные
    
    private func trackRowView(_ track: Track, showNum: Bool, onDoubleClick: @escaping () -> Void) -> some View {
        TrackRowView(
            track: track,
            isCurrent: playerVM.currentTrack?.id == track.id,
            isPlaying: playerVM.isPlaying,
            onAddToQueue: { playerVM.addToQueue(track) },
            isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
            onToggleFavorite: { playerVM.toggleFavorite(track) },
            isFavorite: playerVM.isFavorite(track),
            showTrackNumber: showNum,
            onDoubleClick: onDoubleClick
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(playerVM.currentTrack?.id == track.id ? Color.accent.opacity(0.12) : Color.clear)
        )
        .padding(.horizontal, 4)
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
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
                            if let track = await MetadataReader.readTrack(from: url) { libraryVM.tracks.append(track) }
                        }
                    }
                }
            }
        }
    }
    
    private func playNextTrack() {
        playerVM.playNextTrack()
    }
}

// MARK: - Расширение SortField

extension Track.SortField {
    var localizedKey: String {
        switch self {
        case .title: return "sort_title"
        case .artist: return "sort_artist"
        case .album: return "sort_album"
        case .genre: return "sort_genre"
        case .year: return "sort_year"
        case .duration: return "sort_duration"
        case .playlists: return "sort_playlists"
        }
    }
}

// MARK: - Структуры ячеек

struct AlbumCell: View {
    let group: (album: String, artist: String, tracks: [Track], artURL: URL?)
    @ObservedObject var settings = SettingsManager.shared
    private var tileSize: CGFloat { settings.albumGridSize - 10 }
    private var genres: String {
        let allGenres = group.tracks.compactMap { $0.genre }.filter { !$0.isEmpty }
        return Array(Set(allGenres)).sorted().prefix(2).joined(separator: ", ")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            CachedImage(url: group.tracks.first?.thumbURL(size: "400") ?? group.artURL, size: CGSize(width: tileSize, height: tileSize))
                .frame(width: tileSize, height: tileSize).clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(spacing: 2) {
                Text(group.album).font(.system(size: 12, weight: .medium)).foregroundColor(.textMain).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: tileSize)
                Text(group.artist).font(.system(size: 10)).foregroundColor(.textMuted).lineLimit(1).frame(maxWidth: tileSize)
                if !genres.isEmpty { Text(genres).font(.system(size: 9)).foregroundColor(.textMuted.opacity(0.5)).lineLimit(1).frame(maxWidth: tileSize) }
                Text(String(format: NSLocalizedString("tracks_count", comment: ""), group.tracks.count)).font(.system(size: 9)).foregroundColor(.textMuted.opacity(0.6)).frame(maxWidth: tileSize)
            }
        }
        .padding(10).frame(minWidth: tileSize + 20, minHeight: tileSize + 80)
        .background(settings.darkSurface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(settings.accent.opacity(0.2), lineWidth: 1))
    }
}

struct PlaylistCell: View {
    let playlist: (name: String, tracks: [Track])
    let onDelete: () -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    private var tileSize: CGFloat { settings.albumGridSize - 10 }
    
    private var countText: String {
        return String(format: NSLocalizedString("tracks_count", comment: ""), playlist.tracks.count)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if let firstTrack = playlist.tracks.first, firstTrack.duration > 0 {
                    CachedImage(url: firstTrack.thumbURL(size: "400") ?? firstTrack.albumArtURL, size: CGSize(width: tileSize, height: tileSize))
                        .frame(width: tileSize, height: tileSize).clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(settings.darkSurface).frame(width: tileSize, height: tileSize)
                        Image(systemName: "music.note.list").font(.system(size: tileSize * 0.28)).foregroundColor(settings.textMuted.opacity(0.4))
                    }
                }
                VStack(spacing: 2) {
                    Text(playlist.name).font(.system(size: 12, weight: .medium)).foregroundColor(settings.textMain).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: tileSize)
                    Text(countText)
                        .font(.system(size: 9))
                        .foregroundColor(settings.textMuted.opacity(0.6))
                        .frame(maxWidth: tileSize)
                }
            }
            .padding(10).frame(minWidth: tileSize + 20, minHeight: tileSize + 80)
            .background(settings.darkSurface).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(settings.accent.opacity(0.2), lineWidth: 1))
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(settings.textMuted.opacity(0.5))
            }.buttonStyle(.plain).padding(4)
        }
    }
}
struct TrackRowView: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    var onAddToQueue: (() -> Void)? = nil
    var isInQueue: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    var isFavorite: Bool = false
    var showTrackNumber: Bool = true
    var onDoubleClick: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            if let onAdd = onAddToQueue {
                Button(action: { if !isInQueue { onAdd() } }) {
                    ZStack {
                        Color.white.opacity(0.001)
                            .frame(width: 28, height: 28)
                        Image(systemName: isInQueue ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14)).foregroundColor(isInQueue ? .textMuted.opacity(0.3) : .accent.opacity(0.7))
                    }
                }.buttonStyle(.plain).frame(width: 28, height: 28).disabled(isInQueue)            }
            if showTrackNumber, let trackNum = track.trackNumber {
                Text("\(trackNum)").font(.system(size: 10, design: .monospaced)).foregroundColor(.textMuted.opacity(0.5)).frame(width: 18, alignment: .trailing)
            }
            CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL, size: CGSize(width: 38, height: 38)).cornerRadius(5)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 12.5, weight: .medium)).foregroundColor(isCurrent && isPlaying ? .accent : .textMain).lineLimit(1)
                HStack(spacing: 4) {
                    Text(track.artist).font(.system(size: 10.5)).foregroundColor(.textMuted).lineLimit(1)
                    if let genre = track.genre, !genre.isEmpty {
                        Text("•").foregroundColor(.textMuted.opacity(0.5)).font(.system(size: 8))
                        Text(genre).font(.system(size: 9.5)).foregroundColor(.textMuted.opacity(0.5)).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(formatDuration(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundColor(.textMuted)
            if let onFav = onToggleFavorite {
                Button(action: onFav) {
                    ZStack {
                        Color.white.opacity(0.001)
                            .frame(width: 28, height: 28)
                        Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 12)).foregroundColor(isFavorite ? .accent : .textMuted.opacity(0.3))
                    }
                }.buttonStyle(.plain).frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.accent.opacity(0.12) : Color.clear).padding(.horizontal, -4))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick?() }
    }
    
    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec.isFinite else { return "--:--" }
        let m = Int(sec) / 60, s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
struct MissingFavoritesSection: View {
    let missingTracks: [Track]
    let onRemove: (Track) -> Void
    let onClearAll: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow.opacity(0.7))
                    
                    Text(String(format: NSLocalizedString("missing_favorites_count", comment: ""), missingTracks.count))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textMuted)
                    
                    Spacer()
                    
                    if isExpanded {
                        Button(action: onClearAll) {
                            Text(LocalizedStringKey("clear_all"))
                                .font(.system(size: 10))
                                .foregroundColor(.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.05))
            }
            .buttonStyle(.plain)
            
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
                                    Text(track.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.textMain)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 9))
                                        .foregroundColor(.textMuted)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button(action: { onRemove(track) }) {
                                    Image(systemName: "star.slash.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textMuted.opacity(0.5))
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
