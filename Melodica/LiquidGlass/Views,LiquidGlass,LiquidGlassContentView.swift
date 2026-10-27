// Views,LiquidGlass,LiquidGlassContentView.swift
import SwiftUI

private enum LiquidGlassRootActiveSheet: Identifiable {
    case settings
    case tagEditor
    
    var id: String {
        switch self {
        case .settings: return "settings"
        case .tagEditor: return "tagEditor"
        }
    }
}


@available(macOS 26.0, *)
struct LiquidGlassContentView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var hasRestored: Bool

    @State private var selectedTrackID: UUID?
    @State private var selectedAlbum: String?
    @State private var selectedPlaylist: Int?
    @State private var selectedArtist: String?
    @State private var selectedGenre: String?
    @State private var selectedCUEAlbum: CUEAlbum?
    @State private var selectedRecommendationSectionID: UUID?
    @State private var showSettings = false
    @State private var showRightPanel = true
    @State private var showFavoritesOnly = false
    @State private var selectedSmartPlaylistID: UUID?
    @StateObject private var smartVM = SmartPlaylistViewModel()
    @State private var showEnrichDetails = false
    @State private var showEnrichmentComplete = false
    @ObservedObject private var tagEditorManager = TagEditorManager.shared
    
    @State private var detailHeaderHeight: CGFloat = 0

    @FocusState private var isSearchFocused: Bool
    @State private var pendingRestore = true

    private var maxVisiblePhases: Int {
        SettingsManager.shared.waveformCacheMode == "active" ? 3 : 2
    }
    private var isDetailOpen: Bool {
        selectedAlbum != nil ||
        selectedArtist != nil ||
        selectedGenre != nil ||
        selectedPlaylist != nil ||
        selectedCUEAlbum != nil ||
        selectedSmartPlaylistID != nil ||
        selectedRecommendationSectionID != nil
    }

    private var currentContextID: String {
        if let album = selectedAlbum { return "album:\(album)" }
        if let idx = selectedPlaylist, idx < libraryVM.playlists.count { return "playlist:\(libraryVM.playlists[idx].name)" }
        return libraryVM.searchText.isEmpty ? "tracks:\(libraryVM.sortField.rawValue)" : "tracks_search:\(libraryVM.searchText.lowercased())"
    }

    private var playerTracks: [Track] {
        if !playerVM.playerTracks.isEmpty && playerVM.currentTrack?.cueStartTime != nil {
            return playerVM.playerTracks
        }

        if let idx = selectedPlaylist, idx < libraryVM.playlists.count {
            return libraryVM.playlists[idx].tracks
        }

        if let album = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == album }) {
            return group.tracks
        }

        return libraryVM.filteredTracks
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            trackList
            if showRightPanel {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 1)
                    .transition(.opacity)

                LiquidGlassDetailView(
                    playerVM: playerVM,
                    selectedTrackID: $selectedTrackID
                )
                .frame(width: 350)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showRightPanel)
        .ignoresSafeArea()
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { playerBar }
        .onTapGesture {
            isSearchFocused = false
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTrackSelection)) { _ in
            selectedTrackID = nil
        }
        .onChange(of: libraryVM.searchText) {
            selectedTrackID = nil
        }
        .overlay(alignment: .top) {
            if showEnrichmentComplete {
                LiquidGlassEnrichmentBannerView()
            }
        }
        .sheet(item: Binding<LiquidGlassRootActiveSheet?>(
            get: {
                if showSettings { return .settings }
                if tagEditorManager.isPresented { return .tagEditor }
                return nil
            },
            set: { sheet in
                let wasSettings = showSettings
                showSettings = (sheet == .settings)
                tagEditorManager.isPresented = (sheet == .tagEditor)
                if wasSettings && !showSettings {
                    NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
                }
            }
        )) { sheet in
            switch sheet {
            case .settings:
                SettingsSheetView()
            case .tagEditor:
                TagEditorContainerView(
                    tracks: tagEditorManager.tracks,
                    libraryVM: libraryVM,
                    playerVM: playerVM
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLyricsPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showRightPanel.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSheet)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .enrichmentComplete)) { _ in
            showEnrichmentComplete = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showEnrichmentComplete = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartPlaylistsNeedRefresh)) { _ in
            smartVM.refreshAllCaches(
                library: libraryVM.tracks,
                favoriteURLs: Set(playerVM.favorites.map {
                    $0.url.standardizedFileURL.path
                })
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("allFoldersLoaded"))) { _ in
            tryRestore(tracks: libraryVM.tracks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .detailHeaderHeightChanged)) { notification in
            if let height = notification.userInfo?["height"] as? CGFloat {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        detailHeaderHeight = height
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Melodica" }) {
                    window.makeKeyAndOrderFront(nil)
                    window.makeMain()
                }

                if playerVM.playerTracks.isEmpty {
                    playerVM.playerTracks = self.playerTracks
                }

                MediaKeysHandler.shared.startMonitoring(
                    playerVM: playerVM,
                    tracks: { playerVM.playerTracks },
                    playTrack: { track, completion in
                        playerVM.play(track, afterFinish: completion)
                    },
                    stopPlayer: { playerVM.stop() }
                )
            }

            if !hasRestored {
                hasRestored = true
                restoreLastSession()
            }
        }
        .onChange(of: libraryVM.sortField) {
            selectedCUEAlbum = nil
            selectedSmartPlaylistID = nil
            selectedRecommendationSectionID = nil
        }
    }
}

// MARK: - Layout Components
@available(macOS 26.0, *)
private extension LiquidGlassContentView {
    
    var sidebar: some View {
        LiquidGlassSidebarView(
            libraryVM: libraryVM,
            selectedTrackID: $selectedTrackID,
            playerVM: playerVM,
            selectedAlbum: $selectedAlbum,
            selectedPlaylist: $selectedPlaylist,
            selectedSmartPlaylistID: $selectedSmartPlaylistID,
            selectedArtist: $selectedArtist,
            selectedGenre: $selectedGenre,
            selectedCUEAlbum: $selectedCUEAlbum,
            selectedRecommendationSectionID: $selectedRecommendationSectionID,
            showFavoritesOnly: $showFavoritesOnly
        )
        .frame(width: 170)
        .padding(.leading, 10)
        .padding(.vertical, 10)
    }
    
    var trackList: some View {
        LiquidGlassTrackList(
            libraryVM: libraryVM,
            playerVM: playerVM,
            selectedTrackID: $selectedTrackID,
            selectedAlbum: $selectedAlbum,
            selectedPlaylist: $selectedPlaylist,
            selectedSmartPlaylistID: $selectedSmartPlaylistID,
            selectedArtist: $selectedArtist,
            selectedGenre: $selectedGenre,
            selectedCUEAlbum: $selectedCUEAlbum,
            selectedRecommendationSectionID: $selectedRecommendationSectionID,
            showRightPanel: $showRightPanel,
            showFavoritesOnly: $showFavoritesOnly,
            smartVM: smartVM
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.5), value: showRightPanel)
    }
}

// MARK: - Overlay Components
@available(macOS 26.0, *)
private extension LiquidGlassContentView {
    
    var topBar: some View {
        HStack(spacing: 10) {
            Spacer()

            if libraryVM.isEnriching || showEnrichDetails {
                Button(action: { showEnrichDetails = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: libraryVM.enrichPhase == 1
                              ? "doc.text.magnifyingglass"
                              : libraryVM.enrichPhase == 2
                              ? "photo.stack.fill"
                              : "waveform.path")
                            .font(.system(size: 10))
                            .foregroundColor(Color.accentColor)

                        ProgressView(
                            value: Double(libraryVM.enrichProgress.current),
                            total: Double(max(libraryVM.enrichProgress.total, 1))
                        )
                        .scaleEffect(0.6)
                        .frame(width: 50)
                        .tint(Color.accentColor)

                        Text("\(libraryVM.enrichPhase)/\(maxVisiblePhases)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(in: .rect(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEnrichDetails, arrowEdge: .bottom) {
                    LiquidGlassEnrichDetailsView(libraryVM: libraryVM)
                }
            }

            searchBar

            if showRightPanel {
                Spacer()
                    .frame(width: 350)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, isDetailOpen ? 26 : 12)
        .ignoresSafeArea(edges: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDetailOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showRightPanel)
    }
    
    var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField(LocalizedStringKey("search_placeholder"), text: $libraryVM.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .focused($isSearchFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFocused = false
                    }
                }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    libraryVM.sortAscending.toggle()
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(libraryVM.sortAscending ? 0 : 180))
                    .animation(.easeInOut(duration: 0.3), value: libraryVM.sortAscending)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isDetailOpen ? 6 : 10)
        .frame(width: 280)
        .background(Color.clear)
        .glassEffect(in: .rect(cornerRadius: isDetailOpen ? 0 : 15))
        .padding(.trailing, isDetailOpen ? 15 : 0)
    }
    
    var playerBar: some View {
        HStack {
            Spacer()
                .frame(width: 170 + 10)

            LiquidGlassPlayerBar(
                playerVM: playerVM,
                tracks: playerTracks,
                currentContextID: currentContextID,
                selectedTrackID: $selectedTrackID,
                showRightPanel: $showRightPanel,
                onShowInAlbum: {
                    libraryVM.sortField = .album
                    if let album = playerVM.currentTrack?.album {
                        selectedAlbum = album
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if showRightPanel {
                Spacer()
                    .frame(width: 350)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showRightPanel)
    }
}

// MARK: - Session Restoration
@available(macOS 26.0, *)
private extension LiquidGlassContentView {
    
    func restoreLastSession() {
        guard PlayerStateManager.shared.loadPlayer() != nil else { return }

        let watchedFolders = libraryVM.loadWatchedFolders()

        if watchedFolders.isEmpty {
            pendingRestore = false
            playerVM.restoreFavorites(from: [])
            libraryVM.loadPlaylistsFromCache()
            return
        }

        Task { @MainActor in
            if await libraryVM.loadTracksFromCache() {
                libraryVM.loadPlaylistsFromCache()
                libraryVM.loadCUEAlbumsFromCache()
                if pendingRestore {
                    pendingRestore = false
                    playerVM.restoreQueue(from: libraryVM.tracks)
                    playerVM.restoreFavorites(from: libraryVM.tracks)
                    restorePlayerState()
                    playerVM.finishRestoringState()
                }
            }
        }
    }

    private func tryRestore(tracks: [Track]) {
        guard pendingRestore else { return }
        pendingRestore = false
        playerVM.restoreQueue(from: tracks)
        playerVM.restoreFavorites(from: tracks)
        restorePlayerState()
        playerVM.finishRestoringState()
    }

    func restorePlayerState() {
        guard let state = PlayerStateManager.shared.loadPlayer() else { return }
        playerVM.repeatMode = PlayerViewModel.RepeatMode(rawValue: state.repeatMode) ?? .off
        playerVM.shuffleMode = state.shuffleMode

        guard let trackPath = state.currentTrackPath else { return }

        let cueTrackByHash = libraryVM.cueAlbums
            .flatMap { $0.makeTracks() }
            .first { $0.smartHash == trackPath }

        let foundTrack = cueTrackByHash
            ?? libraryVM.tracks.first { $0.smartHash == trackPath }
            ?? libraryVM.tracks.first { $0.url.path == trackPath }
        let track: Track

        if let ft = foundTrack {
            track = ft
        } else if let cueStart = state.currentCueStartTime {
            let allCueTracks = libraryVM.cueAlbums.flatMap { $0.makeTracks() }
            if let match = allCueTracks.first(where: {
                $0.cueStartTime == cueStart && $0.url.path == trackPath
            }) ?? allCueTracks.first(where: { $0.cueStartTime == cueStart }) {
                track = match
            } else {
                return
            }
        } else {
            let fileName = URL(fileURLWithPath: trackPath).lastPathComponent
            guard let match = libraryVM.tracks.first(where: { $0.url.lastPathComponent == fileName }) else { return }
            track = match
        }

        selectedTrackID = track.id

        playerVM.setVolumeWithoutUI(0)
        playerVM.playPaused(track)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if state.currentTime > 0 && track.duration > 0 {
                playerVM.seek(to: state.currentTime / track.duration)
            }
            playerVM.setVolumeWithoutUI(state.volume)
        }
    }
}
