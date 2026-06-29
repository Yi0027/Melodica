// Views,ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    @State private var selectedTrackID: UUID?
    @State private var lyrics: [LyricsLine] = []
    @State private var displayLyrics: String? = nil
    @State private var userScrolled: Bool = false
    @State private var leftWidth: CGFloat = 380
    @State private var pendingRestore = false
    @State private var selectedAlbum: String? = nil
    @State private var showSettings = false
    
    private var displayedTrack: Track? {
        playerVM.currentTrack
    }
    
    private var playerTracks: [Track] {
        if let album = selectedAlbum,
           let group = libraryVM.albumGroups.first(where: { $0.album == album }) {
            return group.tracks
        }
        return libraryVM.filteredTracks
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack {
                        SidebarView(
                            libraryVM: libraryVM,
                            selectedTrackID: $selectedTrackID,
                            playerVM: playerVM,
                            selectedAlbum: $selectedAlbum
                        )
                        
                        if libraryVM.isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.accent)
                                Text(LocalizedStringKey("scanning"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.textMuted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.darkBg.opacity(0.8))
                        }
                    }
                    .frame(minWidth: 280, maxWidth: .infinity)
                    .layoutPriority(1)
                    
                    Rectangle()
                        .fill(Color.accent.opacity(0.35))
                        .frame(width: 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newWidth = leftWidth + value.translation.width
                                    leftWidth = min(max(newWidth, 250), geo.size.width * 0.6)
                                }
                        )
                    
                    DetailView(
                        track: displayedTrack,
                        lyrics: lyrics,
                        displayLyrics: displayLyrics,
                        playerVM: playerVM,
                        userScrolled: $userScrolled,
                        onLyricTap: { time in
                            playerVM.seek(to: time / (playerVM.duration > 0 ? playerVM.duration : 1))
                        }
                    )
                    .frame(width: min(520, geo.size.width * 0.4))
                    .layoutPriority(-1)
                }
                .onAppear {
                    leftWidth = geo.size.width * 0.5
                }
                
                Rectangle()
                    .fill(Color.accent.opacity(0.35))
                    .frame(height: 2)
                
                PlayerBar(playerVM: playerVM, tracks: playerTracks, selectedTrackID: $selectedTrackID)
                    .frame(height: 72)
            }
        }
        .background(Color.darkBg)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: openFolder) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.accent)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.accent)
                }
                .popover(isPresented: $showSettings) {
                    SettingsView()
                }
            }
        }
        .onChange(of: playerVM.currentTrack) { newTrack in
            updateLyrics(for: newTrack)
        }
        .onChange(of: libraryVM.tracks) { tracks in
            if pendingRestore && !tracks.isEmpty {
                pendingRestore = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    restorePlayerState()
                }
            }
        }
        .onAppear {
            restoreLastSession()
        }
        .preferredColorScheme(.dark)
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
                                selectedTrackID = track.id
                                playerVM.play(track) {}
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Восстановление сессии
    
    private func restoreLastSession() {
        guard let state = PlayerStateManager.shared.load() else { return }
        guard let folderURL = libraryVM.restoreLastFolder() else { return }
        pendingRestore = true
        let needsSecurity = folderURL.startAccessingSecurityScopedResource()
        libraryVM.loadFolder(folderURL)
        _ = needsSecurity
    }
    
    private func restorePlayerState() {
        guard let state = PlayerStateManager.shared.load() else { return }
        playerVM.repeatMode = PlayerViewModel.RepeatMode(rawValue: state.repeatMode) ?? .off
        playerVM.shuffleMode = state.shuffleMode
        playerVM.restoreQueue(from: libraryVM.tracks)
        playerVM.restoreFavorites(from: libraryVM.tracks)
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
        playerVM.playPaused(track)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if state.currentTime > 0 && track.duration > 0 {
                playerVM.seek(to: state.currentTime / track.duration)
            }
            userScrolled = false
            NotificationCenter.default.post(name: NSNotification.Name("ForceResetLyricsView"), object: nil)
        }
    }
    
    private func updateLyrics(for track: Track?) {
        userScrolled = false
        guard let track = track else { lyrics = []; displayLyrics = nil; return }
        if let lrcURL = track.lyricsURL {
            let parsed = LyricsParser.parse(lrcURL)
            if !parsed.isEmpty {
                lyrics = parsed
                displayLyrics = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    userScrolled = false
                }
                return
            }
        }
        if let unsynced = track.unsyncedLyrics, !unsynced.isEmpty { lyrics = []; displayLyrics = unsynced; return }
        lyrics = []; displayLyrics = nil
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true  // ✅ Теперь можно выбирать файлы
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .plainText, .audio]
        panel.message = NSLocalizedString("choose_folder", comment: "")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let ext = url.pathExtension.lowercased()
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                
                if isDirectory.boolValue {
                    libraryVM.loadFolder(url)
                } else if ext == "m3u" || ext == "m3u8" {
                    libraryVM.importM3U(url)
                } else {
                    // Одиночный трек
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
