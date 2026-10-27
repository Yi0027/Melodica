// Views,LiquidGlass,LiquidGlassMiniPlayerView.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassMiniPlayerView: View {
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
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    Button(action: onExpand) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }

                VStack(spacing: 10) {
                    if let track = playerVM.currentTrack {
                        HStack(spacing: 8) {
                            if visEngine.mode == .spectrum && visEngine.isRunning {
                                LiquidGlassRotatedSpectrumView(mirrored: true, color: Color.accentColor)
                                    .frame(width: 20, height: 180)
                            }

                            ZStack {
                                if visEngine.mode == .circular && visEngine.isRunning {
                                    LiquidGlassCircularVisualizationView(
                                        color: Color.accentColor,
                                        artworkSize: 220,
                                        baseCornerRadius: 16
                                    )
                                    .frame(width: 270, height: 270)
                                    .allowsHitTesting(false)
                                }

                                CachedImage(url: track.albumArtURL, size: CGSize(width: 220, height: 220))
                                    .frame(width: 220, height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                            }
                            .frame(width: 240, height: 240)

                            if visEngine.mode == .spectrum && visEngine.isRunning {
                                LiquidGlassRotatedSpectrumView(mirrored: false, color: Color.accentColor)
                                    .frame(width: 20, height: 180)
                            }
                        }
                        .id(track.id)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 220, height: 220)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 50, weight: .thin))
                                    .foregroundColor(.secondary.opacity(0.5))
                            )
                    }

                    if let track = playerVM.currentTrack {
                        VStack(spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if track.hasKnownAlbum {
                                Text(track.album)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                            }

                            Button(action: { playerVM.toggleFavorite(track) }) {
                                Image(systemName: playerVM.isFavorite(track) ? "star.fill" : "star")
                                    .font(.system(size: 14))
                                    .foregroundColor(playerVM.isFavorite(track) ? Color.accentColor : .secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }

                    LiquidGlassProgressBar(
                        progress: playerVM.progress.duration > 0 ? (playerVM.progress.currentTime / playerVM.progress.duration) : 0,
                        currentTime: playerVM.progress.currentTime,
                        duration: playerVM.progress.duration,
                        onSeek: { fraction in
                            playerVM.seek(to: fraction)
                        }
                    )
                    .padding(.horizontal, 24)

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
                                .foregroundColor(playerVM.repeatMode.isActive ? .primary : .secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)

                        Button(action: { playPrevious() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { playerVM.togglePlayPause() }) {
                            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                                .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                        }
                        .buttonStyle(.plain)

                        Button(action: { playNext() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            playerVM.shuffleMode.toggle()
                            playerVM.service.clearPreload()
                            playerVM.saveState()
                        }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 12))
                                .foregroundColor(playerVM.shuffleMode ? .primary : .secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }

                    PlayerVolumeControl(
                        volumeState: playerVM.volumeState,
                        isFilled: true,
                        sliderWidth: 100,
                        iconSize: 9,
                        iconColor: .secondary,
                        tint: Color.accentColor
                    )
                }
                .padding(.bottom, 8)
                .padding(.horizontal, 12)

                HStack(spacing: 16) {
                    Button(action: { showLyrics.toggle(); showQueue = false }) {
                        HStack(spacing: 4) {
                            Text(showLyrics ? LocalizedStringKey("hide_lyrics") : LocalizedStringKey("show_lyrics"))
                                .font(.system(size: 10))
                            Image(systemName: showLyrics ? "chevron.down" : "chevron.up")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(showLyrics ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: { showQueue.toggle(); showLyrics = false }) {
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey("queue_btn"))
                                .font(.system(size: 10))
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(showQueue ? .primary : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: { showVisMenu.toggle() }) {
                        Image(systemName: visEngine.mode != .off ? "eye.fill" : "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(visEngine.mode != .off ? .primary : .secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVisMenu, arrowEdge: .bottom) {
                        LiquidGlassVisMenuView()
                    }
                }
                .padding(.vertical, 4)

                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)

                Group {
                    if showQueue { miniQueueView }
                    if showLyrics { lyricsView }
                }
                .clipped()
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showQueue)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showLyrics)
            }
        }
        .frame(minWidth: 400, minHeight: 520)
        .ignoresSafeArea()
        .onAppear {
            userScrolled = false
            updateLyrics(for: playerVM.currentTrack)
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

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsView: some View {
        if !currentLyrics.isEmpty {
            LiquidGlassLyricsView(
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
        } else if let unsynced = currentDisplayLyrics {
            ScrollView {
                Text(unsynced)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(LocalizedStringKey("no_lyrics"))
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 20)
        }
    }

    // MARK: - Queue

    private var miniQueueView: some View {
        VStack(spacing: 0) {
            ZStack {
                LiquidGlassQueueListRepresentable(
                    items: playerVM.queue,
                    currentQueueItemID: playerVM.currentQueueItemID,
                    rowHeight: 40,
                    onPlayNow: { item in playerVM.playNowFromQueue(item) },
                    onRemove: { item in playerVM.removeQueueItem(item) },
                    onMove: { source, dest in
                        playerVM.moveQueueItems(from: source, to: dest)
                    },
                    onInsertExternal: { ids, index in
                        playerVM.insertTracksIntoQueue(ids: ids, at: index)
                    },
                    configure: { cell, item, isCurrent in
                        cell.configure(
                            track: item.track,
                            isCurrent: isCurrent,
                            isPlaying: playerVM.isPlaying,
                            isEven: false,
                            isFavorite: playerVM.isFavorite(item.track),
                            showRating: false,
                            showRemoveButton: true,
                            onFavorite: { playerVM.toggleFavorite(item.track) },
                            onRemove: { playerVM.removeQueueItem(item) }
                        )
                    }
                )

                if playerVM.queue.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "list.bullet")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(LocalizedStringKey("queue_empty"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
    }

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
            currentLyrics = []
            currentDisplayLyrics = nil
            return
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
        currentLyrics = []
        currentDisplayLyrics = nil
    }
}

struct LiquidGlassProgressBar: View {
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
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: isHovering ? 5 : 3)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)), height: isHovering ? 5 : 3)
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
                Text(formatTime(currentTime)).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration)).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
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
