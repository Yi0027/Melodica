// Views,LiquidGlass,LiquidGlassContentView.swift
import SwiftUI

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
    @State private var showSettings = false
    @State private var showRightPanel = true
    @State private var showFavoritesOnly = false
    @State private var selectedSmartPlaylistID: UUID?
    @StateObject private var smartVM = SmartPlaylistViewModel()
    @State private var showEnrichDetails = false
    @State private var showEnrichmentComplete = false
    
    @State private var detailHeaderHeight: CGFloat = 0

    @FocusState private var isSearchFocused: Bool

    private var maxVisiblePhases: Int {
        SettingsManager.shared.waveformCacheMode == "active" ? 3 : 2
    }
    private var isDetailOpen: Bool {
        selectedAlbum != nil ||
        selectedArtist != nil ||
        selectedGenre != nil ||
        selectedPlaylist != nil ||
        selectedCUEAlbum != nil ||
        selectedSmartPlaylistID != nil
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
            // Убрали makeFirstResponder — вместо неё просто снимаем focus через SwiftUI.
            // Если каретка мигает после этого — оставь только isSearchFocused = false,
            // либо вызывай makeFirstResponder через DispatchQueue.main.async:
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .overlay(alignment: .top) {
            if showEnrichmentComplete {
                LiquidGlassEnrichmentBannerView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSheet)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .prepareNextTrack)) { _ in
            playerVM.prepareNextTrack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enrichmentComplete)) { _ in
            showEnrichmentComplete = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showEnrichmentComplete = true
            }
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

                playerVM.playerTracks = self.playerTracks

                MediaKeysHandler.shared.startMonitoring(
                    playerVM: playerVM,
                    tracks: { self.playerTracks },
                    playTrack: { track, completion in
                        playerVM.playerTracks = self.playerTracks
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
        .onChange(of: playerVM.currentTrack) { newTrack in
            if newTrack?.cueStartTime == nil {
                playerVM.playerTracks = playerTracks
            }
        }
        .onChange(of: libraryVM.tracks) { _ in
            if playerVM.currentTrack?.cueStartTime == nil {
                playerVM.playerTracks = playerTracks
            }
        }
        .onChange(of: selectedPlaylist) { _ in
            if playerVM.currentTrack?.cueStartTime == nil {
                playerVM.playerTracks = playerTracks
            }
        }
        .onChange(of: selectedAlbum) { _ in
            if playerVM.currentTrack?.cueStartTime == nil {
                playerVM.playerTracks = playerTracks
            }
        }
        .onChange(of: libraryVM.sortField) { _ in
            selectedCUEAlbum = nil
            selectedSmartPlaylistID = nil
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
        .padding(.top, isDetailOpen ? max(12, detailHeaderHeight - 8) : 12)
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
            playerVM.restoreFavorites(from: [])
            libraryVM.loadPlaylistsFromCache()
            return
        }

        if libraryVM.loadTracksFromCache() {
            libraryVM.loadPlaylistsFromCache()
            libraryVM.loadCUEAlbumsFromCache()
            playerVM.restoreQueue(from: libraryVM.tracks)
            playerVM.restoreFavorites(from: libraryVM.tracks)

            restorePlayerState()
        }
    }

    func restorePlayerState() {
        guard let state = PlayerStateManager.shared.loadPlayer() else { return }
        playerVM.repeatMode = PlayerViewModel.RepeatMode(rawValue: state.repeatMode) ?? .off
        playerVM.shuffleMode = state.shuffleMode

        guard let trackPath = state.currentTrackPath else { return }

        // CUE-треки живут в cueAlbums, не в libraryVM.tracks.
        // Ищем по smartHash среди makeTracks() — они детерминированные.
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
            // Legacy-сессии: cueStart сохранён, а path — старый (не хеш).
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
