// Views/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers


extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct ContentView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var hasRestored: Bool
    
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
    
    private var displayedTrack: Track? { playerVM.currentTrack }
    
    private var playerTracks: [Track] {
        if let album = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == album }) { return group.tracks }
        if let idx = selectedPlaylist,
           idx < libraryVM.playlists.count { return libraryVM.playlists[idx].tracks }
        return libraryVM.filteredTracks
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
                PlayerBar(playerVM: playerVM, tracks: playerTracks, selectedTrackID: $selectedTrackID).frame(height: 72)
            }
        }
        .background(Color.darkBg)
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .toolbar {
            // Кнопки папки и настроек в одном стекле
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { showFolderManager.toggle() }) {
                    Image(systemName: "folder.badge.gear")
                        .foregroundColor(.accent)
                }
                .popover(isPresented: $showFolderManager) {
                    FolderManagerView(
                        folders: libraryVM.watchedFolders,
                        onRemove: { libraryVM.removeWatchedFolder($0) },
                        onToggle: { libraryVM.toggleFolderVisibility($0) },
                        onAdd: { openFolder() },
                        onRescan: { libraryVM.rescanAllFolders() }
                    )
                    .frame(width: 300, height: 300)
                }
                
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.accent)
                }
                .popover(isPresented: $showSettings) {
                    SettingsView()
                }
            }
            
            // Индикатор сканирования — отдельное стекло
            ToolbarItem(placement: .automatic) {
                if libraryVM.isEnriching || showEnrichDetails {
                    Button(action: { showEnrichDetails = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: libraryVM.enrichPhase == 1 ? "tag.fill" : libraryVM.enrichPhase == 2 ? "photo.fill" : "photo.stack.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accent)
                            
                            ProgressView(value: Double(libraryVM.enrichProgress.current), total: Double(max(libraryVM.enrichProgress.total, 1)))
                                .scaleEffect(0.6)
                                .frame(width: 50)
                                .tint(.accent)
                            
                            Text("\(libraryVM.enrichPhase)/\(libraryVM.folderQueueCount == 0 ? 3 : 2)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())  // Невидимый, но кликабельный
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
        .onChange(of: playerVM.currentTrack) { newTrack in
            updateLyrics(for: newTrack)
            playerVM.playerTracks = playerTracks
        }
        .onChange(of: libraryVM.tracks) { tracks in
            playerVM.playerTracks = playerTracks
            if pendingRestore {
                tryRestore(tracks: tracks)
            }
        }
        .onChange(of: libraryVM.playlists.count) { _ in
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
            playerVM.playerTracks = playerTracks
            
            MediaKeysHandler.shared.startMonitoring(
                playerVM: playerVM,
                tracks: { self.playerTracks },
                playTrack: { track, completion in playerVM.play(track, afterFinish: completion) },
                stopPlayer: { playerVM.stop() }
            )
            
            restoreLastSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .prepareNextTrack)) { _ in playerVM.prepareNextTrack() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("allFoldersLoaded"))) { _ in
            tryRestore(tracks: libraryVM.tracks)
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
                   onLyricTap: { time in playerVM.seek(to: time / (playerVM.duration > 0 ? playerVM.duration : 1)) })
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
            // Всё равно восстанавливаем избранное (треки будут заглушками)
            playerVM.restoreFavorites(from: [])
            // Восстанавливаем плейлисты из кеша (треки будут заглушками)
            libraryVM.loadPlaylistsFromCache()
            return
        }
        
        // Загружаем треки из кеша
        if libraryVM.loadTracksFromCache() {
            
            // Загружаем плейлисты из кеша (треки уже есть в tracks)
            libraryVM.loadPlaylistsFromCache()
            
            // Проверяем что получилось
            for pl in libraryVM.playlists {
            }
            
            pendingRestore = true
            tryRestore(tracks: libraryVM.tracks)
        } else {
            pendingRestore = false
        }
        
        // Восстанавливаем m3u-файлы, которых нет в кеше
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
    
    private func tryRestore(tracks: [Track]) {
        guard pendingRestore else { return }
        
        // Если tracks пуст, всё равно восстанавливаем избранное
        if tracks.isEmpty {
            finishRestore(tracks: tracks)
            return
        }
        
        let playerState = PlayerStateManager.shared.loadPlayer()
        
        if let trackPath = playerState?.currentTrackPath {
            let found = tracks.first { $0.url.path == trackPath } ??
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
        let foundTrack = libraryVM.tracks.first { $0.url.path == trackPath }
        let track: Track
        if let ft = foundTrack { track = ft }
        else {
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
        guard let track = track else { lyrics = []; displayLyrics = nil; return }
        if let lrcURL = track.lyricsURL {
            let parsed = LyricsParser.parse(lrcURL)
            if !parsed.isEmpty { lyrics = parsed; displayLyrics = nil; return }
        }
        if let unsynced = track.unsyncedLyrics, !unsynced.isEmpty { lyrics = []; displayLyrics = unsynced; return }
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
                            playerVM.play(track) {}
                        }
                    }
                }
            }
        }
    }
}
