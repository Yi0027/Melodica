// Views,SidebarView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @Binding var selectedTrackID: UUID?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedAlbum: String?
    
    @State private var showFavoritesOnly: Bool = false
    @State private var selectedPlaylist: Int? = nil
    
    private var displayTracks: [Track] {
        if showFavoritesOnly {
            return playerVM.favorites
        }
        return libraryVM.filteredTracks
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.textMuted)
                TextField(LocalizedStringKey("search_placeholder"), text: $libraryVM.searchText)
                    .textFieldStyle(.plain).foregroundColor(.textMain)
            }
            .padding(10).background(Color.darkSurface).cornerRadius(8)
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            
            HStack(spacing: 4) {
                ForEach(Track.SortField.allCases, id: \.self) { field in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            libraryVM.sortField = field
                            selectedAlbum = nil
                            selectedPlaylist = nil
                            showFavoritesOnly = false
                        }
                    }) {
                        Text(LocalizedStringKey(field.localizedKey))
                            .font(.system(size: 11, weight: libraryVM.sortField == field && !showFavoritesOnly ? .semibold : .regular))
                            .foregroundColor(libraryVM.sortField == field && !showFavoritesOnly ? .textMain : .textMuted.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(libraryVM.sortField == field && !showFavoritesOnly ? Color.accent.opacity(0.2) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(libraryVM.sortField == field && !showFavoritesOnly ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFavoritesOnly.toggle()
                        if showFavoritesOnly {
                            selectedAlbum = nil
                            selectedPlaylist = nil
                        }
                    }
                }) {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(showFavoritesOnly ? .accent : .textMuted.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showFavoritesOnly ? Color.accent.opacity(0.2) : Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(showFavoritesOnly ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button { libraryVM.sortAscending.toggle() } label: {
                    Image(systemName: libraryVM.sortAscending ? "arrow.up" : "arrow.down")
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            
            // Основной контент
            if libraryVM.sortField == .album && !showFavoritesOnly {
                albumView
            } else if libraryVM.sortField == .playlists && !showFavoritesOnly {
                playlistsView
            } else if showFavoritesOnly && displayTracks.isEmpty {
                emptyFavoritesView
            } else {
                trackListView
            }
        }
        .background(Color.darkBg)
    }
    
    // MARK: - Альбомы
    private var albumView: some View {
        Group {
            if let albumName = selectedAlbum,
               let group = libraryVM.albumGroups.first(where: { $0.album == albumName }) {
                AlbumDetailView(
                    group: group,
                    playerVM: playerVM,
                    selectedTrackID: $selectedTrackID,
                    onBack: { selectedAlbum = nil },
                    onPlayNext: { playNextTrack() }
                )
            } else {
                AlbumGridView(
                    groups: libraryVM.albumGroups,
                    onTap: { album in selectedAlbum = album }
                )
            }
        }
    }
    
    // MARK: - Плейлисты
    private var playlistsView: some View {
        Group {
            if let idx = selectedPlaylist,
               idx < libraryVM.playlists.count {
                let playlist = libraryVM.playlists[idx]
                PlaylistDetailView(
                    playlist: playlist,
                    playerVM: playerVM,
                    selectedTrackID: $selectedTrackID,
                    onBack: { selectedPlaylist = nil },
                    onPlayNext: { playNextTrack() }
                )
            } else {
                PlaylistGridView(
                    playlists: libraryVM.playlists,
                    onTap: { idx in selectedPlaylist = idx }
                )
            }
        }
    }
    
    // MARK: - Пустое избранное
    private var emptyFavoritesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star.slash")
                .font(.system(size: 32))
                .foregroundColor(.textMuted.opacity(0.3))
            Text(LocalizedStringKey("no_favorites"))
                .font(.system(size: 13))
                .foregroundColor(.textMuted.opacity(0.5))
            Text(LocalizedStringKey("add_to_favorites_hint"))
                .font(.system(size: 11))
                .foregroundColor(.textMuted.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Список треков
    private var trackListView: some View {
        List(selection: $selectedTrackID) {
            ForEach(displayTracks) { track in
                TrackRowView(
                    track: track,
                    isCurrent: playerVM.currentTrack?.id == track.id,
                    isPlaying: playerVM.isPlaying,
                    onAddToQueue: { playerVM.addToQueue(track) },
                    isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
                    onToggleFavorite: { playerVM.toggleFavorite(track) },
                    isFavorite: playerVM.isFavorite(track),
                    showTrackNumber: !showFavoritesOnly && libraryVM.sortField == .album,
                    onDoubleClick: {
                        selectedTrackID = track.id
                        playerVM.play(track) { self.playNextTrack() }
                    }
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - Drag & Drop
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                DispatchQueue.main.async {
                    let ext = url.pathExtension.lowercased()
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    
                    if isDirectory.boolValue {
                        libraryVM.loadFolder(url)
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
    
    private func playNextTrack() {
        guard let current = playerVM.currentTrack else { return }
        let list = displayTracks
        guard let idx = list.firstIndex(where: { $0.id == current.id }) else { return }
        if idx + 1 < list.count {
            let next = list[idx + 1]
            selectedTrackID = next.id
            playerVM.play(next) { self.playNextTrack() }
        }
    }
}

// MARK: - Расширение SortField для локализации
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

// MARK: - Сетка плейлистов
struct PlaylistGridView: View {
    let playlists: [(name: String, tracks: [Track])]
    let onTap: (Int) -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)]
    
    var body: some View {
        ScrollView {
            if playlists.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundColor(.textMuted.opacity(0.3))
                    Text(LocalizedStringKey("no_playlists"))
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Text(LocalizedStringKey("drop_m3u_hint"))
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted.opacity(0.35))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(playlists.enumerated()), id: \.offset) { idx, playlist in
                        PlaylistCell(playlist: playlist)
                            .onTapGesture { onTap(idx) }
                    }
                }
                .padding(12)
            }
        }
        .background(Color.darkBg)
    }
}

struct PlaylistCell: View {
    let playlist: (name: String, tracks: [Track])
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.darkSurface)
                    .frame(width: 140, height: 140)
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundColor(settings.textMuted.opacity(0.4))
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            
            VStack(spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(settings.textMain)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 140)
                
                Text("\(playlist.tracks.count) треков")
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.6))
                    .frame(maxWidth: 140)
            }
        }
        .padding(10)
        .frame(minWidth: 160, minHeight: 220)
        .background(settings.darkSurface.opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Внутри плейлиста
struct PlaylistDetailView: View {
    let playlist: (name: String, tracks: [Track])
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?
    let onBack: () -> Void
    let onPlayNext: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textMain)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain)
                        .lineLimit(1)
                    Text("\(playlist.tracks.count) треков")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.darkSurface.opacity(0.8))
            
            Divider().background(Color.white.opacity(0.1))
            
            List(selection: $selectedTrackID) {
                ForEach(playlist.tracks) { track in
                    TrackRowView(
                        track: track,
                        isCurrent: playerVM.currentTrack?.id == track.id,
                        isPlaying: playerVM.isPlaying,
                        onAddToQueue: { playerVM.addToQueue(track) },
                        isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
                        onToggleFavorite: { playerVM.toggleFavorite(track) },
                        isFavorite: playerVM.isFavorite(track),
                        showTrackNumber: false,
                        onDoubleClick: {
                            selectedTrackID = track.id
                            playerVM.play(track) { onPlayNext() }
                        }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.darkBg)
    }
}

// MARK: - Сетка альбомов
struct AlbumGridView: View {
    let groups: [(album: String, artist: String, tracks: [Track], artURL: URL?)]
    let onTap: (String) -> Void
    
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(groups, id: \.album) { group in
                    AlbumCell(group: group)
                        .onTapGesture { onTap(group.album) }
                }
            }
            .padding(12)
        }
        .background(Color.darkBg)
    }
}

struct AlbumCell: View {
    let group: (album: String, artist: String, tracks: [Track], artURL: URL?)
    @ObservedObject var settings = SettingsManager.shared
    
    private var genres: String {
        let allGenres = group.tracks.compactMap { $0.genre }.filter { !$0.isEmpty }
        let unique = Array(Set(allGenres)).sorted()
        return unique.prefix(2).joined(separator: ", ")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            CachedImage(url: group.artURL, size: CGSize(width: 140, height: 140))
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            
            VStack(spacing: 2) {
                Text(group.album)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textMain)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 140)
                
                Text(group.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 140)
                
                if !genres.isEmpty {
                    Text(genres)
                        .font(.system(size: 9))
                        .foregroundColor(.textMuted.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                }
                
                Text(String(format: NSLocalizedString("tracks_count", comment: ""), group.tracks.count))
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted.opacity(0.6))
                    .frame(maxWidth: 140)
            }
        }
        .padding(10)
        .frame(minWidth: 160, minHeight: 220)
        .background(settings.darkSurface.opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.accent.opacity(0.2), lineWidth: 1)
        )
    }
}
// MARK: - Внутри альбома
struct AlbumDetailView: View {
    let group: (album: String, artist: String, tracks: [Track], artURL: URL?)
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?
    let onBack: () -> Void
    let onPlayNext: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .medium)).foregroundColor(.textMain) }.buttonStyle(.plain)
                CachedImage(url: group.artURL, size: CGSize(width: 40, height: 40)).frame(width: 40, height: 40).cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.album).font(.system(size: 14, weight: .bold)).foregroundColor(.textMain).lineLimit(1)
                    Text(group.artist).font(.system(size: 11)).foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(12).background(Color.darkSurface.opacity(0.8))
            Divider().background(Color.white.opacity(0.1))
            List(selection: $selectedTrackID) {
                ForEach(group.tracks) { track in
                    TrackRowView(
                        track: track,
                        isCurrent: playerVM.currentTrack?.id == track.id,
                        isPlaying: playerVM.isPlaying,
                        onAddToQueue: { playerVM.addToQueue(track) },
                        isInQueue: playerVM.queue.contains(where: { $0.id == track.id }),
                        onToggleFavorite: { playerVM.toggleFavorite(track) },
                        isFavorite: playerVM.isFavorite(track),
                        showTrackNumber: true,
                        onDoubleClick: {
                            selectedTrackID = track.id
                            playerVM.play(track) { onPlayNext() }
                        }
                    )
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .background(Color.darkBg)
    }
}

// MARK: - TrackRowView
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
                    Image(systemName: isInQueue ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 14)).foregroundColor(isInQueue ? .textMuted.opacity(0.3) : .accent.opacity(0.7))
                }.buttonStyle(.plain).frame(width: 18).disabled(isInQueue)
            }
            if showTrackNumber, let trackNum = track.trackNumber {
                Text("\(trackNum)").font(.system(size: 10, design: .monospaced)).foregroundColor(.textMuted.opacity(0.5)).frame(width: 18, alignment: .trailing)
            }
            CachedImage(url: track.albumArtURL, size: CGSize(width: 38, height: 38)).frame(width: 38, height: 38).cornerRadius(5)
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
                Button(action: onFav) { Image(systemName: isFavorite ? "star.fill" : "star").font(.system(size: 12)).foregroundColor(isFavorite ? .accent : .textMuted.opacity(0.3)) }.buttonStyle(.plain).frame(width: 20)
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
