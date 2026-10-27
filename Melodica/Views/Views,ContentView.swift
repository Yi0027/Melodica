// Views/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

private enum RootActiveSheet: Identifiable {
    case settings
    case tagEditor
    
    var id: String {
        switch self {
        case .settings: return "settings"
        case .tagEditor: return "tagEditor"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ContentView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var hasRestored: Bool
    
    @State private var showLRCSettings = false
    @State private var showEnrichDetails = false
    @State private var showEnrichmentComplete = false
    @State private var selectedTrackID: UUID?
    @State private var lyrics: [LyricsLine] = []
    @State private var displayLyrics: String? = nil
    @State private var userScrolled: Bool = false
    @State private var leftWidth: CGFloat = 380
    @State private var rightPanelWidth: CGFloat = 430
    @State private var lastRightWidth: CGFloat = 520
    @State private var pendingRestore = false
    @State private var selectedAlbum: String? = nil
    @State private var selectedPlaylist: Int? = nil
    @State private var showSettings = false
    @State private var restoreTimeoutStarted = false
    @State private var showFolderManager = false
    @State private var smartVM = SmartPlaylistViewModel()
    @ObservedObject private var theme = SettingsManager.shared
    @ObservedObject private var tagEditorManager = TagEditorManager.shared
    @ObservedObject private var translationService = LyricsTranslationService.shared
    
    private var displayedTrack: Track? { playerVM.currentTrack }
    
    private var currentContextID: String {
        if let album = selectedAlbum { return "album:\(album)" }
        if let idx = selectedPlaylist, idx < libraryVM.playlists.count { return "playlist:\(libraryVM.playlists[idx].name)" }
        return libraryVM.searchText.isEmpty ? "tracks:\(libraryVM.sortField.rawValue)" : "tracks_search:\(libraryVM.searchText.lowercased())"
    }
    
    private var playerTracks: [Track] {
        if !playerVM.playerTracks.isEmpty && playerVM.currentTrack?.cueStartTime != nil {
            return playerVM.playerTracks
        }
        if let album = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == album }) { return group.tracks }
        if let idx = selectedPlaylist,
           idx < libraryVM.playlists.count { return libraryVM.playlists[idx].tracks }
        return libraryVM.filteredTracks
    }
    private var maxVisiblePhases: Int {
        return SettingsManager.shared.waveformCacheMode == "active" ? 3 : 2
    }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    leftPanel
                    dividerView(geo: geo)
                    if rightPanelWidth > 0 {
                        rightPanel
                    }
                }
                .onAppear { leftWidth = geo.size.width * 0.5 }
                
                Rectangle().fill(Color.accent.opacity(0.35)).frame(height: 2)
                PlayerBar(
                    playerVM: playerVM,
                    tracks: playerTracks,
                    currentContextID: currentContextID,
                    selectedTrackID: $selectedTrackID,
                    onShowInAlbum: {
                        libraryVM.sortField = .album
                        if let album = playerVM.currentTrack?.album {
                            selectedAlbum = album
                        }
                        if let trackID = playerVM.currentTrack?.id {
                            NotificationCenter.default.post(name: NSNotification.Name("HighlightTrack"), object: trackID)
                        }
                    }
                ).frame(height: 72)
            }
        }
        .background(Color.darkBg)
        .onTapGesture {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if libraryVM.isEnriching || showEnrichDetails {
                    Button(action: { showEnrichDetails = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: libraryVM.enrichPhase == 1
                                  ? "doc.text.magnifyingglass"
                                  : libraryVM.enrichPhase == 2
                                  ? "photo.stack.fill"
                                  : "waveform.path")
                                .font(.system(size: 10))
                                .foregroundColor(.accent)

                            ProgressView(
                                value: Double(libraryVM.enrichProgress.current),
                                total: Double(max(libraryVM.enrichProgress.total, 1))
                            )
                            .scaleEffect(0.6)
                            .frame(width: 50)
                            .tint(.accent)

                            Text("\(libraryVM.enrichPhase)/\(maxVisiblePhases)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(libraryVM.isEnriching ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: libraryVM.isEnriching)
                    .popover(isPresented: $showEnrichDetails, arrowEdge: .bottom) {
                        EnrichDetailsView(libraryVM: libraryVM)
                    }
                }
            }
        }
        .onChange(of: playerVM.currentTrack) { _, newTrack in
            updateLyrics(for: newTrack)
        }
        .onChange(of: libraryVM.tracks) { _, tracks in
            if pendingRestore {
                tryRestore(tracks: tracks)
            }
        }
        .onChange(of: libraryVM.playlists.count) {
            if pendingRestore {
                tryRestore(tracks: libraryVM.tracks)
            }
        }
        .onAppear {
            guard !hasRestored else {
                updateLyrics(for: playerVM.currentTrack)
                return
            }
            hasRestored = true
            if playerVM.playerTracks.isEmpty {
                playerVM.playerTracks = playerTracks
            }
            
            MediaKeysHandler.shared.startMonitoring(
                playerVM: playerVM,
                tracks: { playerVM.playerTracks },
                playTrack: { track, completion in playerVM.play(track, afterFinish: completion) },
                stopPlayer: { playerVM.stop() }
            )
            
            restoreLastSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("allFoldersLoaded"))) { _ in
            tryRestore(tracks: libraryVM.tracks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartPlaylistsNeedRefresh)) { _ in
            smartVM.refreshAllCaches(
                library: libraryVM.tracks,
                favoriteURLs: Set(playerVM.favorites.map {
                    $0.url.standardizedFileURL.path
                })
            )
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if showEnrichmentComplete {
                EnrichmentBannerView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .enrichmentComplete)) { _ in
            showEnrichmentComplete = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showEnrichmentComplete = true
            }
        }
        .sheet(item: Binding<RootActiveSheet?>(
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
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSheet)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyricsDidAutoTranslate), perform: handleLyricsDidAutoTranslate)
        .onReceive(NotificationCenter.default.publisher(for: .unsyncedLyricsDidAutoTranslate), perform: handleUnsyncedLyricsDidAutoTranslate)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("lrcSettingsChanged"))) { _ in
            updateLyrics(for: displayedTrack)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTrackSelection)) { _ in
            selectedTrackID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLyricsPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                if rightPanelWidth > 50 {
                    lastRightWidth = rightPanelWidth
                    rightPanelWidth = 0
                } else {
                    rightPanelWidth = lastRightWidth > 50 ? lastRightWidth : 400
                }
            }
        }
        .onChange(of: libraryVM.searchText) {
            selectedTrackID = nil
        }
    }
    
    // MARK: - Subviews
    
    private var leftPanel: some View {
        ZStack {
            SidebarView(
                libraryVM: libraryVM,
                selectedTrackID: $selectedTrackID,
                playerVM: playerVM,
                selectedAlbum: $selectedAlbum,
                selectedPlaylist: $selectedPlaylist,
                onOpenFolder: { openFolder() }
            )
            if libraryVM.isLoading {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.2).tint(.accent)
                    Text(LocalizedStringKey("scanning")).font(.system(size: 12)).foregroundColor(.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.darkBg.opacity(0.8))
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity).layoutPriority(1)
    }
    
    private func dividerView(geo: GeometryProxy) -> some View {
        ZStack {
            Rectangle().fill(Color.accent.opacity(0.35)).frame(width: 2)
            Button(action: { toggleRightPanel() }) {
                Image(systemName: rightPanelWidth > 50 ? "chevron.right" : "chevron.left")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.textMuted)
                    .frame(width: 14, height: 28).background(Color.darkBg.opacity(0.9)).cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .gesture(DragGesture().onChanged { value in
            let newWidth = leftWidth + value.translation.width
            leftWidth = min(max(newWidth, 250), geo.size.width * 0.6)
        })
    }
    
    private var rightPanel: some View {
        DetailView(track: displayedTrack, lyrics: lyrics, displayLyrics: displayLyrics, playerVM: playerVM, userScrolled: $userScrolled,
                   onLyricTap: { time in playerVM.seek(to: time / (playerVM.duration > 0 ? playerVM.duration : 1)) } )
        .frame(width: rightPanelWidth).layoutPriority(-1)
    }
    
    private func toggleRightPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if rightPanelWidth > 50 {
                lastRightWidth = rightPanelWidth
                rightPanelWidth = 0
            } else {
                rightPanelWidth = lastRightWidth > 50 ? lastRightWidth : 400
            }
        }
    }
    
    // MARK: - Restore
    
    private func restoreLastSession() {
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

                pendingRestore = true
                tryRestore(tracks: libraryVM.tracks)
            } else {
                pendingRestore = false
            }

            if let libraryState = PlayerStateManager.shared.loadLibrary() {
                let cachedNames = Set(libraryVM.playlists.map { $0.name })

                for path in libraryState.playlistPaths {
                    let playlistName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    if !cachedNames.contains(playlistName) {
                        let url = URL(fileURLWithPath: path)
                        if FileManager.default.fileExists(atPath: path) {
                            let vm = libraryVM
                            vm.importM3U(url)
                        }
                    }
                }

                for saved in libraryState.savedPlaylists {
                    if !cachedNames.contains(saved.name) {
                        let baseDir = watchedFolders.first ?? URL(fileURLWithPath: "/")
                        let (name, trackURLs) = M3UParser.parseContent(
                            saved.m3uContent, baseDir: baseDir, defaultName: saved.name
                        )

                        Task.detached(priority: .userInitiated) {
                            var loaded: [Track] = []
                            for url in trackURLs {
                                if let track = await MetadataReader.readTrack(from: url) { loaded.append(track) }
                            }
                            await MainActor.run {
                                for track in loaded {
                                    if !self.libraryVM.tracks.contains(where: { $0.url.path == track.url.path }) {
                                        self.libraryVM.tracks.append(track)
                                    }
                                }
                                if !self.libraryVM.playlists.contains(where: { $0.name == name }) {
                                    self.libraryVM.playlists.append((name, loaded))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func tryRestore(tracks: [Track]) {
        guard pendingRestore else { return }
        
        if tracks.isEmpty {
            finishRestore(tracks: tracks)
            return
        }
        
        let playerState = PlayerStateManager.shared.loadPlayer()
        
        if let trackPath = playerState?.currentTrackPath {
            let found = tracks.first { $0.smartHash == trackPath } ??
                         tracks.first { $0.url.path == trackPath } ??
                         tracks.first { $0.url.lastPathComponent == URL(fileURLWithPath: trackPath).lastPathComponent }
            if found == nil {
                finishRestore(tracks: tracks)
                return
            }
        }
        
        finishRestore(tracks: tracks)
    }
    
    private func finishRestore(tracks: [Track]) {
        guard pendingRestore else { return }
        pendingRestore = false
        playerVM.restoreQueue(from: tracks)
        playerVM.restoreFavorites(from: tracks)
        restorePlayerState()
        playerVM.finishRestoringState()
    }
    
    private func restorePlayerState() {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.userScrolled = false
                NotificationCenter.default.post(name: NSNotification.Name("ScrollToCurrentTime"), object: playerVM.currentTime)
            }
        }
    }
    
    // MARK: - Lyrics
    
    private func updateLyrics(for track: Track?) {
        userScrolled = false
        if LyricsTranslationService.shared.unresolvedRequest?.track.id != track?.id {
            LyricsTranslationService.shared.dismissUnresolved()
        }
        guard let track = track else { lyrics = []; displayLyrics = nil; return }
        if let lrcURL = track.lyricsURL {
            let parsed = LyricsParser.parse(lrcURL)
            if !parsed.isEmpty {
                lyrics = LyricsTranslationService.shared.prepareLyrics(for: track, parsed: parsed)
                displayLyrics = nil
                return
            }
        }
        if let unsynced = track.unsyncedLyrics, !unsynced.isEmpty {
            lyrics = []
            displayLyrics = LyricsTranslationService.shared.prepareUnsynced(for: track, text: unsynced)
            return
        }
        lyrics = []; displayLyrics = nil
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .plainText, .audio]
        panel.message = NSLocalizedString("choose_folder", comment: "")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let ext = url.pathExtension.lowercased()
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    libraryVM.addFolder(url)
                }
                else if ext == "m3u" || ext == "m3u8" {
                    let vm = libraryVM
                    vm.importM3U(url)
                }
                else {
                    Task {
                        if let track = await MetadataReader.readTrack(from: url) {
                            libraryVM.tracks.append(track)
                            selectedTrackID = track.id
                            playerVM.startPlayback(track: track, from: [track], contextID: "external")
                        }
                    }
                }
            }
        }
    }
    
    private func isTrackMatching(current: Track?, notifTrack: Track) -> Bool {
        guard let current = current else { return false }
        if current.id == notifTrack.id { return true }
        if current.url == notifTrack.url {
            if current.cueStartTime != nil || notifTrack.cueStartTime != nil {
                return current.cueStartTime == notifTrack.cueStartTime
            }
            return true
        }
        return false
    }

    private func handleLyricsDidAutoTranslate(_ notif: Notification) {
        guard let notifTrack = notif.userInfo?["track"] as? Track,
              let newLyrics = notif.userInfo?["lyrics"] as? [LyricsLine] else { return }
        if isTrackMatching(current: displayedTrack, notifTrack: notifTrack) {
            self.lyrics = newLyrics
        }
    }
    
    private func handleUnsyncedLyricsDidAutoTranslate(_ notif: Notification) {
        guard let notifTrack = notif.userInfo?["track"] as? Track,
              let newText = notif.userInfo?["unsyncedLyrics"] as? String else { return }
        if isTrackMatching(current: displayedTrack, notifTrack: notifTrack) {
            self.displayLyrics = newText
        }
    }
}

extension Notification.Name {
    static let smartPlaylistsNeedRefresh = Notification.Name("smartPlaylistsNeedRefresh")
}
