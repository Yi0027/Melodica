// Views,LiquidGlass,LiquidGlassDetailView.swift
import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct LiquidGlassDetailView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?
    @ObservedObject var visualEngine = VisualizationEngine.shared
    
    @State private var showHeader = true
    @State private var lyrics: [LyricsLine] = []
    @State private var displayLyrics: String?
    @State private var userScrolled = false
    @State private var topFraction: CGFloat = 0.5
    @State private var showQueue = false
    @State private var isHovering = false
    @State private var hideButtonWorkItem: DispatchWorkItem?
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if showQueue {
                    queueView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                } else if playerVM.currentTrack == nil {
                    VStack(spacing: 8) {
                        Spacer()

                        Image(systemName: "music.note.list")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(LocalizedStringKey("open_folder_and_play"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                } else {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            if showHeader {
                                headerView
                                    .frame(height: max(geo.size.height * topFraction, 150))
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                                    .clipShape(Rectangle())
                                    .background(Color(NSColor.windowBackgroundColor))
                            }

                            if showHeader, playerVM.currentTrack != nil {
                                LiquidGlassSplitterHandle()
                                    .frame(height: 16)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, -6)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                topFraction = min(max(topFraction + value.translation.height / geo.size.height, 0.05), 0.85)
                                            }
                                    )
                            }

                            lyricsView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.top, showHeader ? 6 : 0)
                                .clipShape(Rectangle())
                                .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                }
            }

            // Кнопка всегда поверх, но с правильной обработкой наведения
            if !showQueue {
                VStack {
                    HStack {
                        Spacer()

                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showHeader.toggle()
                            }
                        }) {
                            Image(systemName: showHeader ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(5)
                                .glassEffect(in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovering ? 1 : 0) // Плавное появление/скрытие
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 15)

                    Spacer()
                }
                .allowsHitTesting(isHovering) // Разрешаем клики только при наведении
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onHover { hovering in
            handleHover(hovering)
        }
        .onAppear { updateLyrics() }
        .onChange(of: playerVM.currentTrack) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                updateLyrics()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: playerVM.currentTrack?.id)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: playerVM.isPlaying)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleQueue"))) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showQueue.toggle()
            }
        }
    }
    
    private func handleHover(_ hovering: Bool) {
        // Отменяем предыдущую отложенную задачу
        hideButtonWorkItem?.cancel()
        
        if hovering {
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = true
            }
        } else {
            // Задержка перед скрытием, чтобы кнопка не исчезала слишком быстро
            let workItem = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = false
                }
            }
            hideButtonWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }
    
    // MARK: - Очередь
    
    private var queueView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showQueue = false } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                Text(LocalizedStringKey("queue"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !playerVM.queue.isEmpty {
                    Button(LocalizedStringKey("clear")) {
                        playerVM.clearQueue()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            
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
            } else {
                List {
                    ForEach(playerVM.queue) { track in
                        HStack(spacing: 8) {
                            CachedImage(url: track.thumbURL(size: "84") ?? track.albumArtURL, size: CGSize(width: 28, height: 28))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: { playerVM.removeFromQueue(track) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
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
    }
    
    // MARK: - Верхняя часть (обложка с кольцами)
    
    private var headerView: some View {
        GeometryReader { geo in
            let dynamicSize = min(geo.size.width * 0.9, geo.size.height * 0.7, 1000)
            let ringSize = dynamicSize * 1.1
            
            VStack(spacing: 6) {
                Spacer()
                
                if let track = playerVM.currentTrack {
                    ZStack {
                        // Кольца вокруг обложки
                        if visualEngine.mode == .circular && visualEngine.isRunning {
                            LiquidGlassCircularVisualizationView(
                                spectrumData: visualEngine.spectrumData,
                                waveformData: visualEngine.waveformData
                            )
                            .frame(width: ringSize, height: ringSize)
                            .allowsHitTesting(false)
                        }
                        
                        CachedImage(url: track.albumArtURL, size: CGSize(width: dynamicSize, height: dynamicSize))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(width: ringSize, height: ringSize)
                    
                    Text(track.title)
                        .font(.system(size: 13, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if !track.album.isEmpty, track.album != "Неизвестный альбом" {
                        Text(track.album)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        if let genre = track.genre, !genre.isEmpty {
                            Text(genre)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if let year = track.year {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(String(year))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .glassEffect(in: .rect(cornerRadius: 20))
                    if let rg = track.replayGain {
                        Text("RG: \(String(format: "%.1f", rg)) dB")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Нижняя часть (текст)
    
    private var lyricsView: some View {
        Group {
            if let track = playerVM.currentTrack {
                if !lyrics.isEmpty {
                    LiquidGlassLyricsView(
                        lyrics: lyrics,
                        currentTime: playerVM.currentTime,
                        userScrolled: $userScrolled,
                        trackId: track.id,
                        onTapLine: { time in
                            let fraction = time / (playerVM.duration > 0 ? playerVM.duration : 1)
                            playerVM.seek(to: fraction)
                        }
                    )
                    .id(track.id)
                } else if let unsynced = displayLyrics, !unsynced.isEmpty {
                    ScrollView {
                        Text(unsynced)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .padding(6)
                    }
                } else {
                    Text(LocalizedStringKey("no_lyrics"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
    
    private func updateLyrics() {
        guard let track = playerVM.currentTrack else {
            lyrics = []
            displayLyrics = nil
            return
        }
        
        if let lrcURL = track.lyricsURL {
            let parsed = LyricsParser.parse(lrcURL)
            if !parsed.isEmpty {
                lyrics = parsed
                displayLyrics = nil
                return
            }
        }
        
        if let unsynced = track.unsyncedLyrics, !unsynced.isEmpty {
            lyrics = []
            displayLyrics = unsynced
            return
        }
        
        lyrics = []
        displayLyrics = nil
    }
}

// MARK: - Сплиттер

struct LiquidGlassSplitterHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> LiquidGlassSplitterHandleView {
        let view = LiquidGlassSplitterHandleView()
        view.updateAccentColor(NSColor.controlAccentColor)
        return view
    }
    
    func updateNSView(_ nsView: LiquidGlassSplitterHandleView, context: Context) {
        nsView.updateAccentColor(NSColor.controlAccentColor)
    }
}

final class LiquidGlassSplitterHandleView: NSView {
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
        let handleHeight: CGFloat = 2
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
