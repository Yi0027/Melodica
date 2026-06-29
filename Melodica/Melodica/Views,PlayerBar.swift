// Views,PlayerBar.swift
import SwiftUI

struct PlayerBar: View {
    @ObservedObject var playerVM: PlayerViewModel
    let tracks: [Track]
    @Binding var selectedTrackID: UUID?
    @ObservedObject var eqManager = EqualizerManager.shared
    
    @State private var showEQ = false
    @State private var isHoveringProgress = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Прогресс-бар
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: isHoveringProgress ? 6 : 3)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accent)
                        .frame(width: max(0, geo.size.width * CGFloat(playerVM.progress)), height: isHoveringProgress ? 6 : 3)
                        .animation(.easeOut(duration: 0.15), value: isHoveringProgress)
                }
                .frame(height: isHoveringProgress ? 14 : 8)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHoveringProgress = hovering
                    }
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
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
            .padding(.horizontal, 14)
            .padding(.top, 6)
            
            // Кнопки и информация
            HStack(spacing: 0) {
                trackInfo.frame(width: 180, alignment: .leading)
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: playPrevious) {
                        Image(systemName: "backward.fill").font(.system(size: 16))
                    }
                    .disabled(currentIndex == nil || (currentIndex == 0 && !playerVM.shuffleMode))
                    
                    Button(action: {
                        if let current = playerVM.currentTrack {
                            if playerVM.isPlaying { playerVM.togglePlayPause() }
                            else if playerVM.currentTime > 0 { playerVM.togglePlayPause() }
                            else { playerVM.play(current) { self.playNext() } }
                        } else if let first = tracks.first {
                            selectedTrackID = first.id
                            playerVM.play(first) { self.playNext() }
                        }
                    }) {
                        Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                    }
                    
                    Button(action: playNext) {
                        Image(systemName: "forward.fill").font(.system(size: 16))
                    }
                    .disabled(currentIndex == nil || (playerVM.repeatMode == .off && !playerVM.shuffleMode && currentIndex == tracks.count - 1 && playerVM.queue.isEmpty))
                    
                    Button(action: {
                        playerVM.shuffleMode.toggle()
                        playerVM.saveState()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(playerVM.shuffleMode ? .accent : .textMuted)
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
                            .foregroundColor(playerVM.repeatMode.isActive ? .accent : .textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .buttonStyle(.plain).foregroundColor(.textMain)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { showEQ.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(eqManager.isEnabled ? .accent : .textMuted)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showEQ) {
                        EqualizerView()
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: playerVM.volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 10)).foregroundColor(.textMuted.opacity(0.5)).frame(width: 14)
                        Slider(value: $playerVM.volume, in: 0...1).frame(width: 80).tint(.accent)
                    }
                    timeDisplay
                }
                .frame(width: 250, alignment: .trailing)
            }
            .padding(.horizontal, 18).padding(.bottom, 10)
        }
        .background(Color.darkSurface.opacity(0.92))
    }
    
    private var trackInfo: some View {
        HStack(spacing: 10) {
            if let track = playerVM.currentTrack {
                CachedImage(url: track.albumArtURL, size: CGSize(width: 42, height: 42))
                    .frame(width: 42, height: 42).cornerRadius(5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 12, weight: .medium)).foregroundColor(.textMain).lineLimit(1)
                    Text(track.artist).font(.system(size: 10.5)).foregroundColor(.textMuted).lineLimit(1)
                }
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)).frame(width: 42, height: 42)
                    .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(.textMuted))
                Text(LocalizedStringKey("nothing_playing")).font(.system(size: 12)).foregroundColor(.textMuted)
            }
        }
    }
    
    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Text(formatTime(playerVM.currentTime))
            Text("/").foregroundColor(.textMuted.opacity(0.5))
            Text(formatTime(playerVM.duration))
        }
        .font(.system(size: 11, design: .monospaced)).foregroundColor(.textMuted)
    }
    
    private var currentIndex: Int? {
        guard let track = playerVM.currentTrack else { return nil }
        return tracks.firstIndex(where: { $0.id == track.id })
    }
    
    private func playPrevious() {
        if playerVM.shuffleMode {
            let other = tracks.filter { $0.id != playerVM.currentTrack?.id }
            if let random = other.randomElement() {
                selectedTrackID = random.id
                playerVM.play(random) { self.playNext() }
            }
            return
        }
        guard let idx = currentIndex, idx > 0 else { return }
        let prev = tracks[idx - 1]
        selectedTrackID = prev.id
        playerVM.play(prev) { self.playNext() }
    }
    
    private func playNext() {
        if let queued = playerVM.playNextInQueue() {
            selectedTrackID = queued.id
            playerVM.play(queued) { self.playNext() }
            return
        }
        if playerVM.shuffleMode {
            let other = tracks.filter { $0.id != playerVM.currentTrack?.id }
            if let random = other.randomElement() {
                selectedTrackID = random.id
                playerVM.play(random) { self.playNext() }
            }
            return
        }
        guard let idx = currentIndex else { return }
        if playerVM.repeatMode == .one, let track = playerVM.currentTrack {
            playerVM.play(track) { self.playNext() }
            return
        }
        if idx + 1 < tracks.count {
            let next = tracks[idx + 1]
            selectedTrackID = next.id
            playerVM.play(next) { self.playNext() }
        } else if playerVM.repeatMode == .all, let first = tracks.first {
            selectedTrackID = first.id
            playerVM.play(first) { self.playNext() }
        } else {
            playerVM.stop()
        }
    }
    
    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "--:--" }
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
