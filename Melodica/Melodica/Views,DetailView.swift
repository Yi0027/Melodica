// Views,DetailView.swift
import SwiftUI

struct DetailView: View {
    let track: Track?
    let lyrics: [LyricsLine]
    let displayLyrics: String?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var userScrolled: Bool
    let onLyricTap: ((TimeInterval) -> Void)?
    
    @State private var showQueue: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let track = track {
                if !lyrics.isEmpty && !showQueue {
                    VStack(spacing: 0) {
                        // Кнопка очереди — зафиксирована сверху
                        HStack {
                            Spacer()
                            Button(action: { showQueue.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showQueue ? "music.note.list" : "list.bullet")
                                        .font(.system(size: 11))
                                    Text(showQueue ? LocalizedStringKey("track") : LocalizedStringKey("queue"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(showQueue ? .accent : .textMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.darkSurface)
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        
                        // Сплиттер
                        SplitView(
                            topView: trackInfoView(track: track, artSize: 260, compact: true)
                                .padding(.horizontal, 24),
                            bottomView: LyricsView(
                                lyrics: lyrics,
                                currentTime: playerVM.currentTime,
                                userScrolled: $userScrolled,
                                trackId: track.id,
                                onTapLine: onLyricTap
                            )
                        )
                    }
                } else if showQueue {
                    queueView
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button(action: { showQueue.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showQueue ? "music.note.list" : "list.bullet")
                                        .font(.system(size: 11))
                                    Text(showQueue ? LocalizedStringKey("track") : LocalizedStringKey("queue"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(showQueue ? .accent : .textMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.darkSurface)
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        
                        SplitView(
                            topView: trackInfoView(track: track, artSize: 260, compact: false)
                                .padding(.horizontal, 24),
                            bottomView: Group {
                                if let unsynced = displayLyrics, !unsynced.isEmpty {
                                    unsyncedLyricsView(unsynced)
                                } else {
                                    noLyricsPlaceholder
                                }
                            }
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color.darkBg)
    }
    
    private func trackInfoView(track: Track, artSize: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 24) {
            Spacer()
            
            CachedImage(url: track.albumArtURL, size: CGSize(width: artSize, height: artSize))
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
            
            VStack(spacing: compact ? 3 : 6) {
                Text(track.title)
                    .font(.system(size: compact ? 18 : 20, weight: .bold))
                    .foregroundColor(.textMain)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(track.artist)
                    .font(.system(size: compact ? 14 : 15))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                
                if !track.album.isEmpty, track.album != "Неизвестный альбом" {
                    Text(track.album)
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundColor(.textMuted.opacity(0.7))
                }
                
                tagsRow(track: track)
            }
            Spacer()
        }
    }
    
    private var queueView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { showQueue = false }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textMain)
                }
                .buttonStyle(.plain)
                
                Text(LocalizedStringKey("queue"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textMain)
                
                Spacer()
                
                if !playerVM.queue.isEmpty {
                    Button(LocalizedStringKey("clear")) {
                        playerVM.clearQueue()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            
            Divider().background(Color.white.opacity(0.1))
            
            if playerVM.queue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet")
                        .font(.system(size: 32))
                        .foregroundColor(.textMuted.opacity(0.3))
                    Text(LocalizedStringKey("queue_empty"))
                        .font(.system(size: 14))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Text(LocalizedStringKey("add_to_queue_hint"))
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted.opacity(0.35))
                    Spacer()
                }
            } else {
                List {
                    ForEach(playerVM.queue) { track in
                        HStack(spacing: 10) {
                            CachedImage(url: track.albumArtURL, size: CGSize(width: 32, height: 32))
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textMain)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textMuted)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: { playerVM.removeFromQueue(track) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textMuted.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.darkBg)
    }
    
    private func tagsRow(track: Track) -> some View {
        HStack(spacing: 8) {
            if let genre = track.genre, !genre.isEmpty {
                Text(genre)
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.darkSurface).cornerRadius(10)
            }
            if let year = track.year {
                Text(String(year))
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.darkSurface).cornerRadius(10)
            }
            if let rg = track.replayGain {
                Text("RG: \(String(format: "%.1f", rg)) dB")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted.opacity(0.5))
            }
        }
    }
    
    private func unsyncedLyricsView(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey("lyrics"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted.opacity(0.5))
                    .padding(.bottom, 8)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.textMuted)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
    }
    
    private var noLyricsPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundColor(.textMuted.opacity(0.4))
            Text(LocalizedStringKey("no_lyrics"))
                .font(.system(size: 13))
                .foregroundColor(.textMuted.opacity(0.5))
            Spacer()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(.textMuted.opacity(0.35))
            Text(LocalizedStringKey("melodica"))
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.textMuted.opacity(0.5))
            Text(LocalizedStringKey("select_track"))
                .font(.system(size: 13))
                .foregroundColor(.textMuted.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Кастомный сплиттер с accent цветом и перетаскиванием

struct SplitView<Top: View, Bottom: View>: View {
    let topView: Top
    let bottomView: Bottom
    @State private var topFraction: CGFloat = 0.45
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topView
                    .frame(height: geo.size.height * topFraction)
                    .clipped()
                
                ZStack {
                    Rectangle()
                        .fill(Color.darkBg)
                        .frame(height: 7)
                    
                    Rectangle()
                        .fill(Color.accent.opacity(0.5))
                        .frame(height: 3)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeUpDown.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newFraction = topFraction + value.translation.height / geo.size.height
                            topFraction = min(max(newFraction, 0.05), 0.9)
                        }
                )
                
                bottomView
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
    }
}
