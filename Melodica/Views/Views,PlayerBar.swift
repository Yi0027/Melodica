// Views/PlayerBar.swift
import SwiftUI
import Combine

struct PlayerBar: View {
    @ObservedObject var playerVM: PlayerViewModel
    let tracks: [Track]
    var currentContextID: String = "library"
    @Binding var selectedTrackID: UUID?
    var onShowInAlbum: (() -> Void)? = nil
    
    @State private var isHoveringCover = false
    @State private var isHoveringProgress = false
    @State private var showEQ = false
    @State private var showVisMenu = false
    @ObservedObject var eqManager = EqualizerManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var visualEngine = VisualizationEngine.shared
    @State private var controlsWidth: CGFloat = 220
    @State private var pureControlsWidth: CGFloat = 175
    
    var body: some View {
        VStack(spacing: 0) {
            // Прогресс-бар или волновая форма
            progressSection
                .padding(.horizontal, 14)
                .padding(.top, 6)
            
            // Основной контент плейбара
            GeometryReader { geo in
                let totalWidth = geo.size.width

                // Расчет доступного пространства для спектра справа от кнопок управления
                let availableCenterToRight = (totalWidth / 2) - 250
                let safeCenterToRight = availableCenterToRight - 12
                let controlsHalf = (pureControlsWidth > 0 ? pureControlsWidth : 175) / 2
                let availableForSpectrum = safeCenterToRight - controlsHalf

                let spectrumBands: Int = {
                    if availableForSpectrum >= 178 {
                        return 32
                    } else if availableForSpectrum >= 94 {
                        return 16
                    } else if availableForSpectrum >= 50 {
                        return 8
                    } else {
                        return 0
                    }
                }()

                let spectrumSpacerWidth: CGFloat = {
                    switch spectrumBands {
                    case 32: return 20
                    case 16: return 16
                    case 8: return 12
                    default: return 0
                    }
                }()

                let maxTrackWidth = max(120, (totalWidth - controlsWidth) / 2 - 16)

                ZStack {
                    // Левая и правая части
                    HStack(spacing: 0) {
                        trackInfo
                            .frame(maxWidth: maxTrackWidth, alignment: .leading)
                            .clipped()

                        Spacer(minLength: 0)

                        // Правая часть
                        rightSection
                            .frame(width: 250, alignment: .trailing)
                    }

                    // Центральная секция: Кнопки управления и спектрум
                    HStack(spacing: 0) {
                        // Симметричный невидимый спейсер слева, чтобы кнопки оставались абсолютно неподвижными
                        if visualEngine.mode == .spectrum && visualEngine.isRunning && spectrumBands > 0 {
                            SpectrumView(bands: spectrumBands)
                                .hidden()
                                .allowsHitTesting(false)
                            Color.clear
                                .frame(width: spectrumSpacerWidth, height: 1)
                        }

                        controlsSection

                        // Спектрум справа от кнопок, отделенный невидимым спейсером от кнопки repeat
                        if visualEngine.mode == .spectrum && visualEngine.isRunning && spectrumBands > 0 {
                            Color.clear
                                .frame(width: spectrumSpacerWidth, height: 1)
                            SpectrumView(bands: spectrumBands)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .background(
                        GeometryReader { cGeo in
                            Color.clear.preference(
                                key: PlayerBarControlsWidthKey.self,
                                value: cGeo.size.width
                            )
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: totalWidth, height: geo.size.height)
            }
            .onPreferenceChange(PlayerBarControlsWidthKey.self) { newWidth in
                if newWidth > 0 && abs(self.controlsWidth - newWidth) > 1 {
                    self.controlsWidth = newWidth
                }
            }
            .onPreferenceChange(PlayerBarPureControlsWidthKey.self) { newWidth in
                if newWidth > 0 && abs(self.pureControlsWidth - newWidth) > 1 {
                    self.pureControlsWidth = newWidth
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.2), value: visualEngine.isRunning)
            .animation(.easeInOut(duration: 0.2), value: visualEngine.mode)
        }
        .frame(height: 64)
        .contentShape(Rectangle())
        .contextMenu {
            PlayerContextMenu(playerVM: playerVM, onShowInAlbum: onShowInAlbum)
        }
        .background(Color.darkSurface.opacity(0.92))
    }
    
    // MARK: - Progress Section
    
    @ViewBuilder
    private var progressSection: some View {
        PlayerBarProgressSection(
            playerVM: playerVM,
            visualEngine: visualEngine,
            isHoveringProgress: $isHoveringProgress
        )
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        HStack(spacing: 20) {
            Button(action: { playPrevious() }) {
                Image(systemName: "backward.fill").font(.system(size: 16))
            }
            .disabled(!canGoPrevious)
            
            Button(action: {
                if let current = playerVM.currentTrack {
                    if playerVM.isPlaying { playerVM.togglePlayPause() }
                    else if playerVM.currentTime > 0 { playerVM.togglePlayPause() }
                    else { playerVM.play(current) { playerVM.playNextTrack() } }
                } else if let first = tracks.first {
                    selectedTrackID = first.id
                    playerVM.startPlayback(track: first, from: tracks, contextID: currentContextID)
                }
            }) {
                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
            }
            
            Button(action: { playerVM.skipToNextTrack() }) {
                Image(systemName: "forward.fill").font(.system(size: 16))
            }
            .disabled(!canGoNext)
            
            Button(action: {
                playerVM.shuffleMode.toggle()
                playerVM.service.clearPreload()
                playerVM.saveState()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(playerVM.shuffleMode ? .accent : settings.playerControlsColor.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            Button(action: {
                switch playerVM.repeatMode {
                case .off: playerVM.repeatMode = .all
                case .all: playerVM.repeatMode = .one
                case .one: playerVM.repeatMode = .off
                }
                playerVM.saveState()
            }) {
                Image(systemName: playerVM.repeatMode.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(playerVM.repeatMode.isActive ? .accent : settings.playerControlsColor.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .background(
            GeometryReader { pGeo in
                Color.clear.preference(
                    key: PlayerBarPureControlsWidthKey.self,
                    value: pGeo.size.width
                )
            }
        )
        .buttonStyle(.plain)
        .foregroundColor(settings.playerControlsColor)
        .id(settings.theme.playerControlsR)
    }
    
    // MARK: - Right Section
    
    private var rightSection: some View {
        HStack(spacing: 12) {
            // Кнопка визуализации
            Button(action: { showVisMenu.toggle() }) {
                Image(systemName: visualEngine.mode != .off ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(visualEngine.mode != .off ? .accent : settings.playerControlsColor.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showVisMenu, arrowEdge: .bottom) {
                VisMenuView()
                    .background(settings.darkBg)
            }
            
            Button(action: { showEQ.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(eqManager.isEnabled ? .accent : settings.playerControlsColor.opacity(0.4))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showEQ) { EqualizerView() }
            
            PlayerVolumeControl(
                volumeState: playerVM.volumeState,
                isFilled: true,
                sliderWidth: 80,
                iconSize: 10,
                iconColor: .textMuted.opacity(0.5),
                tint: .accent
            )
            
            timeDisplay
        }
    }
    
    // MARK: - Track Info
    
    private var trackInfo: some View {
        HStack(spacing: 10) {
            if let track = playerVM.currentTrack {
                ZStack {
                    CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL, size: CGSize(width: 42, height: 42))
                        .id(track.id)
                        .frame(width: 42, height: 42)
                        .cornerRadius(5)
                    
                    if isHoveringCover {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(5)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isHoveringCover = hovering }
                }
                .onTapGesture {
                    NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
                }
                
                SynchronizedScrollingTrackInfo(
                    title: track.title,
                    artist: track.artist,
                    titleFont: .system(size: 12, weight: .medium),
                    titleColor: .textMain,
                    artistFont: .system(size: 10.5),
                    artistColor: .textMuted,
                    spacing: 2
                )
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(.textMuted))
                Text(LocalizedStringKey("nothing_playing"))
                    .font(.system(size: 12))
                    .foregroundColor(.textMuted)
            }
        }
    }
    
    // MARK: - Time Display
    
    private var timeDisplay: some View {
        PlayerBarTimeDisplay(progress: playerVM.progress)
    }
    
    // MARK: - Navigation
    
    private var canGoNext: Bool {
        playerVM.canGoNext
    }
    
    private var canGoPrevious: Bool {
        playerVM.canGoPrevious
    }
    
    private func playPrevious() {
        playerVM.playPreviousTrack()
    }
    
    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
// MARK: - Subviews for PlaybackProgress isolation

private struct PlayerBarProgressSection: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var visualEngine: VisualizationEngine
    @ObservedObject var progress: PlaybackProgress
    @Binding var isHoveringProgress: Bool

    init(playerVM: PlayerViewModel, visualEngine: VisualizationEngine,
         isHoveringProgress: Binding<Bool>) {
        self.playerVM = playerVM
        self.visualEngine = visualEngine
        self.progress = playerVM.progress
        self._isHoveringProgress = isHoveringProgress
    }

    private var fraction: Double {
        guard progress.duration > 0 else { return 0 }
        return progress.currentTime / progress.duration
    }

    var body: some View {
        Group {
            if visualEngine.mode == .waveform && visualEngine.isRunning {
                WaveformProgressView(
                    data: visualEngine.waveformData,
                    progress: fraction,
                    currentTime: progress.currentTime,
                    duration: progress.duration,
                    onSeek: { playerVM.seek(to: $0) }
                )
                .frame(height: 12)
                .offset(y: 5)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: isHoveringProgress ? 5 : 3)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accent)
                            .frame(
                                width: max(0, geo.size.width * CGFloat(fraction)),
                                height: isHoveringProgress ? 5 : 3
                            )
                    }
                    .frame(height: isHoveringProgress ? 10 : 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { isHoveringProgress = hovering }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard geo.size.width > 0 else { return }
                                let f = value.location.x / geo.size.width
                                guard f.isFinite else { return }
                                playerVM.seek(to: Double(min(max(f, 0), 1)))
                            }
                    )
                }
                .frame(height: 8)
                .offset(y: -3)
            }
        }
        .onAppear {
            ensureWaveformLoaded()
        }
        .onChange(of: visualEngine.mode) { _, _ in
            ensureWaveformLoaded()
        }
        .onChange(of: playerVM.currentTrack) { _, _ in
            ensureWaveformLoaded()
        }
    }

    private func ensureWaveformLoaded() {
        guard visualEngine.mode == .waveform else { return }
        if let track = playerVM.currentTrack {
            if visualEngine.currentTrack?.id != track.id || visualEngine.waveformData.allSatisfy({ $0 == 0 }) {
                visualEngine.loadWaveformForTrack(track)
            }
        }
    }
}

private struct PlayerBarTimeDisplay: View {
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        HStack(spacing: 4) {
            Text(format(progress.currentTime))
            Text("/").foregroundColor(.textMuted.opacity(0.5))
            Text(format(progress.duration))
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.textMuted)
    }

    private func format(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
private struct PlayerBarControlsWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct PlayerBarPureControlsWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 175
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}


