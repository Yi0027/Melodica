// Views/PlayerBar.swift
import SwiftUI
import Combine

struct PlayerBar: View {
    @ObservedObject var playerVM: PlayerViewModel
    let tracks: [Track]
    @Binding var selectedTrackID: UUID?
    var onShowInAlbum: (() -> Void)? = nil
    
    @State private var isHoveringCover = false
    @State private var isHoveringProgress = false
    @State private var showEQ = false
    @State private var showVisMenu = false
    @ObservedObject var eqManager = EqualizerManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var visualEngine = VisualizationEngine.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Прогресс-бар или волновая форма
            progressSection
                .padding(.horizontal, 14)
                .padding(.top, 6)
            
            // Основной контент плейбара
            HStack(spacing: 0) {
                // Левая часть: информация о треке
                trackInfo
                    .frame(width: 180, alignment: .leading)
                    .padding(.trailing, 50)
                
                // Спектрум между информацией и кнопками (если включен)
                // Спектрум (всегда занимает место, но невидим если выключен)
                SpectrumView(data: visualEngine.spectrumData)
                    .frame(width: 50, height: 24)
                    .padding(.horizontal, 8)
                    .opacity(visualEngine.mode == .spectrum && visualEngine.isRunning ? 1 : 0)
                    .allowsHitTesting(false)

                Spacer()

                // Центральные кнопки управления
                controlsSection

                Spacer()
                
                // Правая часть
                rightSection
                    .frame(width: 250, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
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
                    playerVM.play(first) { playerVM.playNextTrack() }
                }
            }) {
                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
            }
            
            Button(action: { playerVM.playNextTrack() }) {
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
            
            HStack(spacing: 6) {
                Image(systemName: playerVM.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted.opacity(0.5))
                    .frame(width: 14)
                Slider(value: $playerVM.volume, in: 0...1)
                    .frame(width: 80)
                    .tint(.accent)
            }
            
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
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textMain)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(track.artist)
                        .font(.system(size: 10.5))
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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
        guard playerVM.currentTrack != nil else { return false }
        if playerVM.repeatMode == .one { return true }
        if !playerVM.queue.isEmpty { return true }
        if !tracks.isEmpty, let current = playerVM.currentTrack,
           let idx = tracks.firstIndex(where: { $0.id == current.id }) {
            return idx + 1 < tracks.count || playerVM.repeatMode == .all
        }
        return false
    }
    
    private var canGoPrevious: Bool {
        return playerVM.currentTrack != nil
    }
    
    private func playPrevious() {
        guard let current = playerVM.currentTrack else { return }
        
        if playerVM.currentTime > 10 {
            playerVM.seek(to: 0)
            return
        }
        
        if playerVM.shuffleMode {
            playerVM.seek(to: 0)
            return
        }
        
        if !playerVM.queue.isEmpty {
            if let idx = playerVM.queue.firstIndex(where: { $0.id == current.id }), idx > 0 {
                playerVM.play(playerVM.queue[idx - 1]) { playerVM.playNextTrack() }
                return
            }
            playerVM.seek(to: 0)
            return
        }
        
        guard let idx = tracks.firstIndex(where: { $0.id == current.id }), idx > 0 else {
            playerVM.seek(to: 0)
            return
        }
        playerVM.play(tracks[idx - 1]) { playerVM.playNextTrack() }
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
                            let f = value.location.x / geo.size.width
                            playerVM.seek(to: Double(min(max(f, 0), 1)))
                        }
                )
            }
            .frame(height: 8)
            .offset(y: -3)
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
