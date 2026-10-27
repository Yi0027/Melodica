// Views,MiniPlayerView.swift
import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var visEngine = VisualizationEngine.shared
    let onExpand: () -> Void
    let tracks: [Track]
    
    @State private var showLyrics = true
    @State private var showQueue = false
    @State private var showVisMenu = false
    @State private var userScrolled = false
    @State private var currentLyrics: [LyricsLine] = []
    @State private var currentDisplayLyrics: String?
    
    var body: some View {
        ZStack {
            GeometryReader { geo in
                if let track = playerVM.currentTrack {
                    CachedImage(url: track.albumArtURL, size: CGSize(width: geo.size.width, height: geo.size.height))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 40)
                        .opacity(0.9)
                        .clipped()
                        .id(track.id)
                } else {
                    settings.darkBg
                }
            }
            .animation(.easeInOut(duration: 0.5), value: playerVM.currentTrack?.id)
            
            Color.black.opacity(0.5)
            
            VStack(spacing: 0) {
                Color.clear.frame(height: 28)
                
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button(action: onExpand) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    
                    // Обложка с визуализацией
                    if let track = playerVM.currentTrack {
                        HStack(spacing: 8) {
                            // Левый спектр (повёрнут на 90°)
                            if visEngine.mode == .spectrum && visEngine.isRunning {
                                RotatedSpectrumView(mirrored: true)
                                    .frame(width: 20, height: 180)
                            }
                            // Обложка с кольцами
                            ZStack {
                                // Кольца вокруг обложки
                                if visEngine.mode == .circular && visEngine.isRunning {
                                    CircularVisualizationView(
                                        color: .white,
                                        artworkSize: 220,
                                        baseCornerRadius: 10
                                    )
                                    .frame(width: 270, height: 270)
                                    .allowsHitTesting(false)
                                }
                                
                                CachedImage(url: track.albumArtURL, size: CGSize(width: 220, height: 220))
                                    .frame(width: 220, height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .frame(width: 240, height: 240)
                            
                            // Правый спектр (повёрнут на -90°)
                            if visEngine.mode == .spectrum && visEngine.isRunning {
                                RotatedSpectrumView(mirrored: false)
                                    .frame(width: 180, height: 180)
                            }
                        }
                        .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
                        .id(track.id)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 220, height: 220)
                            .overlay(Image(systemName: "music.note").font(.system(size: 50)).foregroundColor(.white.opacity(0.3)))
                    }
                    
                    if let track = playerVM.currentTrack {
                        VStack(spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                            if track.hasKnownAlbum {
                                Text(track.album)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            
                            Button(action: { playerVM.toggleFavorite(track) }) {
                                Image(systemName: playerVM.isFavorite(track) ? "star.fill" : "star")
                                    .font(.system(size: 14))
                                    .foregroundColor(playerVM.isFavorite(track) ? .white : .white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Прогресс-бар
                    ProgressBarView(
                        progress: playerVM.progress.duration > 0 ? (playerVM.progress.currentTime / playerVM.progress.duration) : 0,
                        currentTime: playerVM.progress.currentTime,
                        duration: playerVM.progress.duration,
                        onSeek: { fraction in
                            playerVM.seek(to: fraction)
                        }
                    )
                    .padding(.horizontal, 24)
                    
                    // Кнопки управления
                    HStack(spacing: 22) {
                        Button(action: {
                            switch playerVM.repeatMode {
                            case .off: playerVM.repeatMode = .all
                            case .all: playerVM.repeatMode = .one
                            case .one: playerVM.repeatMode = .off
                            }
                            playerVM.saveState()
                        }) {
                            Image(systemName: playerVM.repeatMode.icon)
                                .font(.system(size: 12))
                                .foregroundColor(playerVM.repeatMode.isActive ? .white : .white.opacity(0.4))
                        }.buttonStyle(.plain)
                        
                        Button(action: { playPrevious() }) {
                            Image(systemName: "backward.fill").font(.system(size: 16)).foregroundColor(.white)
                        }.buttonStyle(.plain)
                        
                        Button(action: { playerVM.togglePlayPause() }) {
                            Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38)).foregroundColor(.white)
                        }.buttonStyle(.plain)
                        
                        Button(action: { playNext() }) {
                            Image(systemName: "forward.fill").font(.system(size: 16)).foregroundColor(.white)
                        }.buttonStyle(.plain)
                        
                        Button(action: {
                            playerVM.shuffleMode.toggle()
                            playerVM.service.clearPreload()
                            playerVM.saveState()
                        }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 12))
                                .foregroundColor(playerVM.shuffleMode ? .white : .white.opacity(0.4))
                        }.buttonStyle(.plain)
                    }
                    
                    PlayerVolumeControl(
                        volumeState: playerVM.volumeState,
                        isFilled: true,
                        sliderWidth: 100,
                        iconSize: 9,
                        iconColor: .white.opacity(0.6),
                        tint: .white
                    )
                }
                .padding(.bottom, 8)
                
                // Кнопки Lyrics / Queue / Vis
                HStack(spacing: 16) {
                    Button(action: { showLyrics.toggle(); showQueue = false }) {
                        HStack(spacing: 4) {
                            Text(showLyrics ? LocalizedStringKey("hide_lyrics") : LocalizedStringKey("show_lyrics")).font(.system(size: 10))
                            Image(systemName: showLyrics ? "chevron.down" : "chevron.up").font(.system(size: 9))
                        }
                        .foregroundColor(showLyrics ? .white : .white.opacity(0.5))
                    }.buttonStyle(.plain)
                    
                    Button(action: { showQueue.toggle(); showLyrics = false }) {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey("queue_btn")).font(.system(size: 10))
                            Image(systemName: "list.bullet").font(.system(size: 10))
                        }
                        .foregroundColor(showQueue ? .white : .white.opacity(0.5))
                    }.buttonStyle(.plain)
                    
                    // Кнопка визуализации
                    Button(action: { showVisMenu.toggle() }) {
                        Image(systemName: visEngine.mode != .off ? "eye.fill" : "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(visEngine.mode != .off ? .white : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVisMenu, arrowEdge: .bottom) {
                        VisMenuView()
                            .background(settings.darkBg)
                    }
                }
                .padding(.vertical, 4)
                
                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)

                Group {
                    if showQueue {
                        miniQueueView
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                    
                    if showLyrics {
                        if !currentLyrics.isEmpty {
                            LyricsView(
                                lyrics: currentLyrics,
                                progress: playerVM.progress,
                                userScrolled: $userScrolled,
                                trackId: playerVM.currentTrack?.id,
                                onTapLine: { time in
                                    let fraction = time / (playerVM.duration > 0 ? playerVM.duration : 1)
                                    playerVM.seek(to: fraction)
                                }
                            )
                            .id(playerVM.currentTrack?.id)
                            .frame(maxHeight: .infinity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        } else if let unsynced = currentDisplayLyrics {
                            ScrollView {
                                Text(unsynced)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        } else {
                            Text(LocalizedStringKey("no_lyrics"))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, 20)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                ))
                        }
                    }
                }
                .clipped()
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showQueue)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showLyrics)
            }
            .animation(.easeInOut(duration: 0.4), value: playerVM.currentTrack?.id)
        }
        .frame(minWidth: 400, minHeight: 520)
        .ignoresSafeArea()
        .onAppear {
            userScrolled = false
            updateLyrics(for: playerVM.currentTrack)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: NSNotification.Name("ForceResetLyricsView"), object: nil)
            }
        }
        .onChange(of: playerVM.currentTrack) { _, newTrack in
            updateLyrics(for: newTrack)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lyricsDidAutoTranslate)) { notif in
            if let notifTrack = notif.userInfo?["track"] as? Track,
               let newLyrics = notif.userInfo?["lyrics"] as? [LyricsLine],
               isTrackMatching(current: playerVM.currentTrack, notifTrack: notifTrack) {
                self.currentLyrics = newLyrics
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unsyncedLyricsDidAutoTranslate)) { notif in
            if let notifTrack = notif.userInfo?["track"] as? Track,
               let newText = notif.userInfo?["unsyncedLyrics"] as? String,
               isTrackMatching(current: playerVM.currentTrack, notifTrack: notifTrack) {
                self.currentDisplayLyrics = newText
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("lrcSettingsChanged"))) { _ in
            updateLyrics(for: playerVM.currentTrack)
        }
    }
    
    // MARK: - Navigation
    
    private func playPrevious() {
        guard playerVM.currentTrack != nil else { return }
        
        if playerVM.currentTime > 10 {
            playerVM.seek(to: 0)
            return
        }
        
        playerVM.playPreviousTrack()
    }

    private func playNext() {
        playerVM.skipToNextTrack()
    }
    
    // MARK: - Queue

    private var miniQueueView: some View {
        VStack(spacing: 0) {
            ZStack {
                QueueListRepresentable(
                    items: playerVM.queue,
                    currentQueueItemID: playerVM.currentQueueItemID,
                    rowHeight: 32,
                    onPlayNow: { item in playerVM.playNowFromQueue(item) },
                    onRemove: { item in playerVM.removeQueueItem(item) },
                    onMove: { source, dest in
                        playerVM.moveQueueItems(from: source, to: dest)
                    },
                    onInsertExternal: { ids, index in
                        playerVM.insertTracksIntoQueue(ids: ids, at: index)
                    },
                    configure: { cell, item, isCurrent in
                        var state = TrackCellState()
                        state.showTrackNumber = false
                        state.showRating = false
                        state.isCurrent = isCurrent
                        state.isPlaying = playerVM.isPlaying
                        state.isInQueue = true
                        state.showAddButton = true
                        state.addButtonStyle = .remove
                        state.showFavoriteButton = false
                        state.onAdd = { playerVM.removeQueueItem(item) }
                        state.onFavorite = nil
                        cell.configure(with: item.track, state: state)
                    }
                )

                if playerVM.queue.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "list.bullet")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.3))
                        Text(LocalizedStringKey("queue_empty"))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - Lyrics
    
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

    private func updateLyrics(for track: Track?) {
        guard let track = track else {
            currentLyrics = []; currentDisplayLyrics = nil; return
        }
        if let lrcURL = track.lyricsURL {
            let parsed = LyricsParser.parse(lrcURL)
            if !parsed.isEmpty {
                currentLyrics = LyricsTranslationService.shared.prepareLyrics(for: track, parsed: parsed)
                currentDisplayLyrics = nil
                return
            }
        }
        if let unsynced = track.unsyncedLyrics, !unsynced.isEmpty {
            currentLyrics = []
            currentDisplayLyrics = LyricsTranslationService.shared.prepareUnsynced(for: track, text: unsynced)
            return
        }
        currentLyrics = []; currentDisplayLyrics = nil
    }
}

// MARK: - ProgressBarView

struct ProgressBarView: View {
    let progress: Double
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (Double) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.2))
                        .frame(height: isHovering ? 5 : 3)
                        .animation(.easeOut(duration: 0.15), value: isHovering)
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)), height: isHovering ? 5 : 3)
                        .animation(.easeOut(duration: 0.15), value: isHovering)
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    onSeek(value.location.x / geo.size.width)
                })
            }
            .frame(height: 10)
            
            HStack {
                Text(formatTime(currentTime)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(formatTime(duration)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let totalSeconds = Int(t)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
