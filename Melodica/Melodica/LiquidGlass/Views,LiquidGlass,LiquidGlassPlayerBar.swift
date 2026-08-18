// Views,LiquidGlass,LiquidGlassPlayerBar.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassPlayerBar: View {
    @ObservedObject var playerVM: PlayerViewModel
    let tracks: [Track]
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
                            playerVM.play(first) { playNext() }
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

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                if visualEngine.mode == .spectrum && visualEngine.isRunning {
                    Color.clear
                        .frame(width: 15, height: 1)

                    LiquidGlassSpectrumView(data: visualEngine.spectrumData)
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

                    HStack(spacing: 4) {
                        Image(systemName: playerVM.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                        Slider(value: $playerVM.volume, in: 0...1)
                            .frame(width: 60)
                            .tint(nil)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: visualEngine.isRunning)
        }
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            if playerVM.currentTrack != nil {
                ZStack(alignment: .bottom) {
                    if isHoveringProgressBar {
                        Rectangle()
                            .fill(.regularMaterial)
                            .frame(height: 64)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: .white, location: 0.06),
                                            .init(color: .white, location: 0.94),
                                            .init(color: .clear, location: 1)
                                        ]
                                    ),
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
                                    Text(formatTime(playerVM.currentTime))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("-" + formatTime(max(0, playerVM.duration - playerVM.currentTime)))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .transition(.opacity)
                            }

                            ZStack(alignment: .leading) {
                                if visualEngine.mode == .waveform && visualEngine.isRunning && isHoveringProgressBar {
                                    LiquidGlassWaveformProgressView(
                                        data: visualEngine.waveformData,
                                        progress: playerVM.progress,
                                        currentTime: playerVM.currentTime,
                                        duration: playerVM.duration,
                                        onSeek: { fraction in playerVM.seek(to: fraction) },
                                        accentColor: Color.accentColor
                                    )
                                    .frame(height: 24)
                                } else {
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: isHoveringProgressBar ? 6 : 1)
                                            .fill(Color.secondary.opacity(isHoveringProgressBar ? 0.2 : 0.35))
                                            .frame(height: isHoveringProgressBar ? 8 : 2)
                                            .frame(maxHeight: .infinity, alignment: .center)
                                            .glassEffect(isHoveringProgressBar ? .clear : .identity)

                                        RoundedRectangle(cornerRadius: isHoveringProgressBar ? 6 : 1)
                                            .fill(Color.accentColor)
                                            .frame(
                                                width: max(0, geo.size.width * CGFloat(playerVM.progress)),
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
                                    let fraction = value.location.x / geo.size.width
                                    playerVM.seek(to: min(max(fraction, 0), 1))
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
        }
        .glassEffect()
        .contentShape(Rectangle())
        .contextMenu {
            Menu(LocalizedStringKey("repeat_mode")) {
                Button(action: { playerVM.repeatMode = .off }) {
                    Label(LocalizedStringKey("repeat_off"), systemImage: playerVM.repeatMode == .off ? "checkmark" : "repeat")
                }
                Button(action: { playerVM.repeatMode = .all }) {
                    Label(LocalizedStringKey("repeat_all"), systemImage: playerVM.repeatMode == .all ? "checkmark" : "repeat")
                }
                Button(action: { playerVM.repeatMode = .one }) {
                    Label(LocalizedStringKey("repeat_one"), systemImage: playerVM.repeatMode == .one ? "checkmark" : "repeat.1")
                }
            }
            Divider()
            Button(action: {
                playerVM.shuffleMode.toggle()
                playerVM.saveState()
            }) {
                Label(
                    playerVM.shuffleMode ? LocalizedStringKey("shuffle_off") : LocalizedStringKey("shuffle_on"),
                    systemImage: "shuffle"
                )
            }
            Divider()
            if let track = playerVM.currentTrack {
                Button(action: { onShowInAlbum?() }) {
                    Label(LocalizedStringKey("show_in_album"), systemImage: "rectangle.stack")
                }
                Button(action: { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }) {
                    Label(LocalizedStringKey("show_in_finder"), systemImage: "folder")
                }
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(track.title, forType: .string)
                }) {
                    Label(LocalizedStringKey("copy_title"), systemImage: "doc.on.doc")
                }
            }
        }
    }
    
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
    
    private func playNext() {
        guard let current = playerVM.currentTrack else { return }
        
        if playerVM.repeatMode == .one {
            playerVM.play(current) { playNext() }
            return
        }
        
        if !playerVM.queue.isEmpty {
            playerVM.playNextTrack()
            return
        }
        
        if playerVM.shuffleMode {
            let other = tracks.filter { $0.id != current.id }
            if let random = other.randomElement() {
                playerVM.play(random) { playNext() }
            }
            return
        }
        
        guard let idx = tracks.firstIndex(where: { $0.id == current.id }) else {
            playerVM.stop()
            return
        }
        
        if idx + 1 < tracks.count {
            playerVM.play(tracks[idx + 1]) { playNext() }
        } else if playerVM.repeatMode == .all, let first = tracks.first {
            playerVM.play(first) { playNext() }
        } else {
            playerVM.stop()
        }
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
                playerVM.play(playerVM.queue[idx - 1]) { playNext() }
                return
            }
            playerVM.seek(to: 0)
            return
        }
        
        guard let idx = tracks.firstIndex(where: { $0.id == current.id }), idx > 0 else {
            playerVM.seek(to: 0)
            return
        }
        playerVM.play(tracks[idx - 1]) { playNext() }
    }
    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
