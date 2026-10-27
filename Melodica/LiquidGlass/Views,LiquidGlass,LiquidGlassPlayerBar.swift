// Views,LiquidGlass,LiquidGlassPlayerBar.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassPlayerBar: View {
    @ObservedObject var playerVM: PlayerViewModel
    let tracks: [Track]
    var currentContextID: String = "library"
    @Binding var selectedTrackID: UUID?
    @Binding var showRightPanel: Bool
    var onShowInAlbum: (() -> Void)? = nil
    
    @State private var showEQ = false
    @State private var showVisMenu = false
    @State private var isHoveringProgressBar = false
    @ObservedObject var eqManager = EqualizerManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var visualEngine = VisualizationEngine.shared
    @State private var isHoveringCover = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 12) {
                    Button(action: {
                        playerVM.shuffleMode.toggle()
                        playerVM.service.clearPreload()
                        playerVM.saveState()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 12))
                            .foregroundColor(playerVM.shuffleMode ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { playPrevious() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoPrevious)

                    Button(action: {
                        if let current = playerVM.currentTrack {
                            if playerVM.isPlaying {
                                playerVM.togglePlayPause()
                            } else if playerVM.currentTime > 0 {
                                playerVM.togglePlayPause()
                            } else {
                                playerVM.play(current) { playNext() }
                            }
                        } else if let first = tracks.first {
                            selectedTrackID = first.id
                            playerVM.startPlayback(track: first, from: tracks, contextID: currentContextID)
                        }
                    }) {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                    }
                    .buttonStyle(.plain)

                    Button(action: { playNext() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoNext)

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
                            .foregroundColor(playerVM.repeatMode.isActive ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let track = playerVM.currentTrack {
                    ZStack {
                        CachedImage(
                            url: track.thumbURL(size: "84") ?? track.albumArtURL,
                            size: CGSize(width: 42, height: 42)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        if isHoveringCover {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringCover = hovering
                        }
                    }
                    .onTapGesture {
                        NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
                    }

                    SynchronizedScrollingTrackInfo(
                        title: track.title,
                        artist: track.artist,
                        titleFont: .system(size: 10.5, weight: .medium),
                        titleColor: .primary,
                        artistFont: .system(size: 9.5),
                        artistColor: .secondary,
                        spacing: 1
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                if visualEngine.mode == .spectrum && visualEngine.isRunning {
                    Color.clear
                        .frame(width: 15, height: 1)

                    LiquidGlassSpectrumView()
                        .frame(width: 50, height: 20)
                        .allowsHitTesting(false)
                        .padding(.trailing, 50)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleQueue"), object: nil)
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { showRightPanel.toggle() }) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 12))
                            .foregroundColor(showRightPanel ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { showVisMenu.toggle() }) {
                        Image(systemName: visualEngine.mode != .off ? "eye.fill" : "eye.slash")
                            .font(.system(size: 12))
                            .foregroundColor(visualEngine.mode != .off ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVisMenu, arrowEdge: .top) {
                        LiquidGlassVisMenuView()
                    }

                    Button(action: { showEQ.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundColor(eqManager.isEnabled ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showEQ) {
                        LiquidGlassEqualizerView()
                    }

                    PlayerVolumeControl(
                        volumeState: playerVM.volumeState,
                        isFilled: false,
                        sliderWidth: 60,
                        iconSize: 10,
                        iconColor: .secondary
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: visualEngine.isRunning)
            .animation(.easeInOut(duration: 0.2), value: visualEngine.mode)
        }
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            if playerVM.currentTrack != nil {
                LiquidGlassPlayerBarProgressArea(
                    playerVM: playerVM,
                    visualEngine: visualEngine,
                    isHoveringProgressBar: $isHoveringProgressBar
                )
            }
        }
        .glassEffect()
        .contentShape(Rectangle())
        .contextMenu {
            PlayerContextMenu(playerVM: playerVM, onShowInAlbum: onShowInAlbum)
        }
    }
    
    private var canGoNext: Bool {
        playerVM.canGoNext
    }
    
    private var canGoPrevious: Bool {
        playerVM.canGoPrevious
    }
    
    private func playNext() {
        playerVM.skipToNextTrack()
    }
    
    private func playPrevious() {
        playerVM.playPreviousTrack()
    }
    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
@available(macOS 26.0, *)
private struct LiquidGlassPlayerBarProgressArea: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var visualEngine: VisualizationEngine
    @ObservedObject var progress: PlaybackProgress
    @Binding var isHoveringProgressBar: Bool

    init(playerVM: PlayerViewModel, visualEngine: VisualizationEngine,
         isHoveringProgressBar: Binding<Bool>) {
        self.playerVM = playerVM
        self.visualEngine = visualEngine
        self.progress = playerVM.progress
        self._isHoveringProgressBar = isHoveringProgressBar
    }

    private var fraction: Double {
        guard progress.duration > 0 else { return 0 }
        return progress.currentTime / progress.duration
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isHoveringProgressBar {
                Rectangle()
                    .fill(.regularMaterial)
                    .frame(height: 64)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.06),
                                .init(color: .white, location: 0.94),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 110)
                    .allowsHitTesting(false)
            }

            GeometryReader { geo in
                VStack(spacing: 4) {
                    if isHoveringProgressBar {
                        HStack {
                            Text(formatTime(progress.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)

                            Spacer()

                            Text("-" + formatTime(max(0, progress.duration - progress.currentTime)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    }

                    ZStack(alignment: .leading) {
                        if visualEngine.mode == .waveform && visualEngine.isRunning && isHoveringProgressBar {
                            LiquidGlassWaveformProgressView(
                                data: visualEngine.waveformData,
                                progress: fraction,
                                currentTime: progress.currentTime,
                                duration: progress.duration,
                                onSeek: { playerVM.seek(to: $0) },
                                accentColor: Color.accentColor
                            )
                            .frame(height: 24)
                        } else {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: isHoveringProgressBar ? 6 : 1)
                                    .fill(Color.secondary.opacity(isHoveringProgressBar ? 0.45 : 0.35))
                                    .frame(height: isHoveringProgressBar ? 8 : 2)
                                    .frame(maxHeight: .infinity, alignment: .center)

                                RoundedRectangle(cornerRadius: isHoveringProgressBar ? 6 : 1)
                                    .fill(Color.accentColor)
                                    .frame(
                                        width: max(0, geo.size.width * CGFloat(fraction)),
                                        height: isHoveringProgressBar ? 8 : 2
                                    )
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: isHoveringProgressBar ? 8 : 2)
                        }
                    }
                    .frame(height: isHoveringProgressBar ? 8 : 2)
                }
                .frame(height: isHoveringProgressBar ? 38 : 2)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHoveringProgressBar = hovering
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = value.location.x / geo.size.width
                            playerVM.seek(to: min(max(f, 0), 1))
                        }
                )
            }
            .frame(height: isHoveringProgressBar ? 38 : 2)
            .padding(.horizontal, 165)
            .padding(.bottom, 6)
            .allowsHitTesting(true)
        }
        .allowsHitTesting(true)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
