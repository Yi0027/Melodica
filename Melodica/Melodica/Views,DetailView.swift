// Views/DetailView.swift
import SwiftUI

struct DetailView: View {
    let track: Track?
    let lyrics: [LyricsLine]
    let displayLyrics: String?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var userScrolled: Bool
    let onLyricTap: ((TimeInterval) -> Void)?
    
    @State private var showQueue: Bool = false
    @State private var artworkCache: [URL: Image] = [:]
    @State private var previousArtwork: Image?
    @State private var currentArtwork: Image?
    @State private var loadingTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            if let track = track {
                if !lyrics.isEmpty && !showQueue {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showQueue.toggle() } }) {
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
                            topView: trackInfoView(track: track, compact: true)
                                .frame(minHeight: 300)
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
                    .transition(.opacity)
                } else if showQueue {
                    queueView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showQueue.toggle() } }) {
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
                            topView: trackInfoView(track: track, compact: true)
                                .frame(minHeight: 300)
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
                    .transition(.opacity)
                }
            } else {
                emptyState
            }
        }
        .background(Color.darkBg)
        .animation(.easeInOut(duration: 0.25), value: showQueue)
        .animation(.easeInOut(duration: 0.3), value: track?.id)
    }
    
    private func trackInfoView(track: Track, compact: Bool) -> some View {
        GeometryReader { geo in
            let dynamicSize = min(geo.size.width * 0.9, geo.size.height * 0.7, 1000)
            
            VStack(spacing: compact ? 10 : 24) {
                Spacer()
                
                artworkView(url: track.albumArtURL, size: dynamicSize)
                    .id(track.id)
                
                VStack(spacing: compact ? 6 : 10) {
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
                        .padding(.top, 2)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // Загружаем изображение с возможностью отмены
    private func loadArtwork(for url: URL?) {
        loadingTask?.cancel()
        previousArtwork = currentArtwork
        
        // Очищаем кеш если больше 10 обложек
        if artworkCache.count > 10 {
            artworkCache.removeAll()
        }
        
        guard let url = url else {
            withAnimation(.easeInOut(duration: 0.4)) {
                currentArtwork = nil
            }
            return
        }
        
        if let cachedImage = artworkCache[url] {
            withAnimation(.easeInOut(duration: 0.4)) {
                currentArtwork = cachedImage
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.previousArtwork = nil
            }
            return
        }
        
        loadingTask = Task {
            if let nsImage = NSImage(contentsOf: url) {
                let image = Image(nsImage: nsImage)
                await MainActor.run {
                    self.artworkCache[url] = image
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.currentArtwork = image
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.previousArtwork = nil
                    }
                }
            } else {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.currentArtwork = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.previousArtwork = nil
                    }
                }
            }
        }
    }
    
    // Отдельная вьюха для обложки с кешированием
    private func artworkView(url: URL?, size: CGFloat) -> some View {
        ZStack {
            // Предыдущая обложка
            if let prevArt = previousArtwork {
                prevArt
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            }
            
            // Новая обложка
            if let currArt = currentArtwork {
                currArt
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else if previousArtwork == nil {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.darkSurface)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundColor(.textMuted.opacity(0.3))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))  // ← обрезает всё что выходит за рамки
        .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
        .onAppear { loadArtwork(for: url) }
        .onChange(of: url?.absoluteString ?? "") { _ in loadArtwork(for: url) }
    }
    
    private var queueView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showQueue = false } }) {
                    ZStack {
                        Color.white.opacity(0.001)
                            .frame(width: 32, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textMain)
                    }
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
                            CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL, size: CGSize(width: 28, height: 28))
                                .frame(width: 28, height: 28).cornerRadius(4)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(playerVM.currentTrack?.id == track.id ? .accent : .textMain)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textMuted)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: { playerVM.removeFromQueue(track) }) {
                                ZStack {
                                    Color.white.opacity(0.001)
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(playerVM.currentTrack?.id == track.id ? Color.accent.opacity(0.12) : Color.clear)
                                .padding(.horizontal, -4)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            playerVM.playNowFromQueue(track)
                        }
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
        let hasRG = track.replayGain != nil || track.replayGainAlbum != nil
        
        let rgInfo: (label: String, value: Float)? = {
            guard hasRG else { return nil }
            guard SettingsManager.shared.rgMode != "off" else { return ("RG", 0) }
            
            switch SettingsManager.shared.rgMode {
            case "track":
                if let rg = track.replayGain { return ("RG", rg) }
                if let rg = track.replayGainAlbum { return ("RG", rg) }
            case "album":
                if let rg = track.replayGainAlbum { return ("RG Album", rg) }
                if let rg = track.replayGain { return ("RG", rg) }
            default:
                break
            }
            return nil
        }()
        
        return HStack(spacing: 8) {
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
            if let rg = rgInfo {
                if rg.value == 0 {
                    Text("RG: Off")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted.opacity(0.5))
                } else {
                    Text("\(rg.label): \(String(format: "%.1f", rg.value)) dB")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted.opacity(0.5))
                }
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
    
    @State private var topFraction: CGFloat = 0.5
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topView
                    .frame(height: max(geo.size.height * topFraction, 1))
                    .padding(.bottom, 6)
                    .clipShape(Rectangle())
                
                SplitterHandle(accentColor: SettingsManager.shared.accentNSColor)
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, -6)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newFraction = topFraction + value.translation.height / geo.size.height
                                topFraction = min(max(newFraction, 0.05), 0.85)
                                NotificationCenter.default.post(name: .splitterDidResize, object: nil)
                            }
                    )
                
                bottomView
                    .frame(maxHeight: .infinity)
                    .padding(.top, 6)
                    .clipShape(Rectangle())
            }
        }
    }
}
// MARK: - Сплиттер с NSTrackingArea + динамический accent цвет

struct SplitterHandle: NSViewRepresentable {
    let accentColor: NSColor
    
    func makeNSView(context: Context) -> SplitterHandleView {
        let view = SplitterHandleView()
        view.updateAccentColor(accentColor)
        return view
    }
    
    func updateNSView(_ nsView: SplitterHandleView, context: Context) {
        nsView.updateAccentColor(accentColor)
    }
}

final class SplitterHandleView: NSView {
    
    private var trackingArea: NSTrackingArea?
    private weak var handleLayer: CALayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayer() {
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let handleLayer = CALayer()
        handleLayer.cornerRadius = 2
        // Начальный цвет — будет переопределён при update
        handleLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        layer?.addSublayer(handleLayer)
        self.handleLayer = handleLayer
    }
    
    func updateAccentColor(_ color: NSColor) {
        handleLayer?.backgroundColor = color.withAlphaComponent(0.5).cgColor
    }
    
    override func layout() {
        super.layout()
        let inset: CGFloat = 20
        let handleHeight: CGFloat = 4
        let handleY = (bounds.height - handleHeight) / 2
        handleLayer?.frame = CGRect(
            x: inset,
            y: handleY,
            width: bounds.width - inset * 2,
            height: handleHeight
        )
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .enabledDuringMouseDrag
        ]
        
        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeUpDown.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }
    
    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            NSCursor.resizeUpDown.push()
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}
