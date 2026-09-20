// Views,LiquidGlass,LiquidGlassLyricsView.swift
import SwiftUI
import AppKit
import CoreVideo

// MARK: - Основной View

@available(macOS 26.0, *)
struct LiquidGlassLyricsView: View {
    let lyrics: [LyricsLine]
    @ObservedObject var progress: PlaybackProgress
    @Binding var userScrolled: Bool
    let trackId: UUID?
    let onTapLine: ((TimeInterval) -> Void)?
    
    @State private var currentIndex: Int = -1
    @State private var canShowButton: Bool = false
    @State private var hasInitialized: Bool = false
    
    private var settings: SettingsManager { SettingsManager.shared }
    
    private var metadataLines: [String] {
        let metadata = LyricsParser.lastMetadata
        var lines: [String] = []
        
        let fields: [(String, String?)] = [
            ("title", metadata.title),
            ("artist", metadata.artist),
            ("album", metadata.album),
            ("author", metadata.author),
            ("length", metadata.length.map { formatTime($0) })
        ]
        
        for (key, value) in fields {
            guard let value, !value.isEmpty,
                  settings.lrcMetadataFields[key] ?? false else { continue }
            let label = NSLocalizedString("lrc_meta_\(key)", comment: "")
            lines.append("\(label): \(value)")
        }
        return lines
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int32(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    
    private var showMetadata: Bool {
        guard settings.lrcShowMetadata, !metadataLines.isEmpty, !userScrolled else { return false }
        if settings.lrcMetadataPosition == "before" {
            let firstRealTime = lyrics.first(where: { !$0.text.isEmpty })?.time ?? 0
            return progress.currentTime < firstRealTime
        } else {
            let lastTime = lyrics.last?.time ?? 0
            return progress.currentTime > lastTime
        }
    }
    
    private var metadataView: some View {
        VStack(spacing: 2) {
            ForEach(metadataLines, id: \.self) { text in
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassEffect(.clear)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showMetadata && settings.lrcMetadataPosition == "before" {
                metadataView.transition(.opacity)
            }
            
            ZStack(alignment: .bottom) {
                LiquidGlassNativeLyricsView(
                    lyrics: lyrics,
                    currentIndex: $currentIndex,
                    currentTime: progress.currentTime,
                    userScrolled: $userScrolled,
                    onTapLine: onTapLine
                )
                .onAppear {
                    if !lyrics.isEmpty {
                        hasInitialized = true
                        canShowButton = true
                    }
                }
                .onChange(of: trackId) { _ in resetState() }
                .onChange(of: lyrics.map(\.id)) { _ in resetState() }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
                    NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                    userScrolled = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .splitterDidResize)) { _ in
                    NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                    userScrolled = false
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToCurrentTime"))) { _ in
                    NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                    userScrolled = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidScroll)) { _ in
                    userScrolled = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidSync)) { _ in
                    userScrolled = false
                }
                
                if userScrolled && canShowButton {
                    ZStack {
                        LiquidGlassInvisibleSyncButton {
                            userScrolled = false
                            NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                            NotificationCenter.default.post(name: .forceScrollNow, object: nil)
                        }
                        .frame(height: 48)
                        
                        syncButton
                            .allowsHitTesting(false)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.4), value: userScrolled)
                    .zIndex(10)
                }
            }
            
            if showMetadata && settings.lrcMetadataPosition == "after" {
                metadataView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showMetadata)
        .onChange(of: showMetadata) { _ in
            userScrolled = false
            NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .forceScrollNow, object: nil)
            }
        }
    }
    
    private func resetState() {
        currentIndex = -1
        userScrolled = false
        hasInitialized = true
        canShowButton = true
        NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .forceScrollNow, object: nil)
        }
    }
    
    private var syncButton: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
            Text(LocalizedStringKey("synch")).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .glassEffect(.regular.interactive(true))
        .padding(.bottom, 16)
    }
}

// MARK: - Liquid Glass Invisible Sync Button (AppKit hit area)

struct LiquidGlassInvisibleSyncButton: NSViewRepresentable {
    let action: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        
        let button = NSButton(
            title: "",
            target: context.coordinator,
            action: #selector(Coordinator.clicked)
        )
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = nil
        button.isTransparent = true
        button.wantsLayer = true
        button.layer?.opacity = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        
        init(action: @escaping () -> Void) {
            self.action = action
        }
        
        @objc func clicked() {
            action()
        }
    }
}

// MARK: - Layout Model

struct LiquidGlassLineLayout {
    let lines: [LyricsLine]
    let yPosition: CGFloat
    let height: CGFloat
}

// MARK: - NSViewRepresentable (движок)

struct LiquidGlassNativeLyricsView: NSViewRepresentable {
    let lyrics: [LyricsLine]
    @Binding var currentIndex: Int
    let currentTime: TimeInterval
    @Binding var userScrolled: Bool
    let onTapLine: ((TimeInterval) -> Void)?
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeNSView(context: Context) -> NSView {
        LiquidGlassCoreAnimationView(coordinator: context.coordinator)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.lyrics = lyrics
        coordinator.currentTime = currentTime
        coordinator.onTapLine = onTapLine
        
        let newIDs = lyrics.map(\.id)
        if coordinator.lastLyricsID != newIDs {
            coordinator.lastLyricsID = newIDs
            coordinator.precalculateLayout(width: nsView.bounds.width)
            coordinator.nativeView?.resetAllLayers()
        }
        
        if coordinator.userScrolled != userScrolled {
            coordinator.userScrolled = userScrolled
            coordinator.nativeView?.refreshVisualState(
                currentIndex: coordinator.currentIndex,
                isUserScrolled: userScrolled
            )
        }
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject {
        var parent: LiquidGlassNativeLyricsView
        var lyrics: [LyricsLine] = []
        var layouts: [LiquidGlassLineLayout] = []
        var currentIndex = -1
        var currentTime: TimeInterval = 0
        var userScrolled = false
        var onTapLine: ((TimeInterval) -> Void)?
        var lastLyricsID: [UUID] = []
        
        weak var nativeView: LiquidGlassCoreAnimationView?
        
        private var displayLink: CVDisplayLink?
        private var displayLinkContext: UnsafeMutableRawPointer?
        private var settings: SettingsManager { SettingsManager.shared }
        private var groups: [LyricsGroup] = []
        var useAdvancedMode = false
        private var lastFrameTime: CFTimeInterval = 0
        
        init(_ parent: LiquidGlassNativeLyricsView) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            stopDisplayLink()
        }
        
        // MARK: - Layout
        
        func precalculateLayout(width: CGFloat) {
            guard width > 0 else { return }
            
            rebuildGroups()
            
            let contentInsetTop: CGFloat = 15
            let contentInsetBottom: CGFloat = 60
            let groupSpacing: CGFloat = 32
            
            var currentY: CGFloat = contentInsetTop
            
            if useAdvancedMode {
                let availableWidth = max(width - 32, 1)
                
                layouts = groups.map { group in
                    var lines = getVisibleLines(from: group, limit: 5)
                    
                    if let noteLine = group.lines.first(where: { $0.tag == "note" && isTagEnabled("note") }) {
                        lines.append(noteLine)
                    }
                    
                    if let instIndex = lines.firstIndex(where: { $0.tag == "inst" }) {
                        lines[instIndex].pauseUntil = group.pauseUntil
                    }
                    
                    let visibleLines = lines.filter { $0.tag != "note" }
                    let height = LiquidGlassLayerPair.measureGroupHeight(
                        lines: visibleLines,
                        width: availableWidth,
                        settings: settings
                    )
                    let layout = LiquidGlassLineLayout(lines: lines, yPosition: currentY, height: height)
                    currentY += height + groupSpacing
                    return layout
                }
            } else {
                layouts = lyrics.filter { $0.tag == nil }.map { line in
                    let height = LiquidGlassLayerPair.measureGroupHeight(
                        lines: [line],
                        width: max(width - 32, 1),
                        settings: settings
                    )
                    let layout = LiquidGlassLineLayout(lines: [line], yPosition: currentY, height: height)
                    currentY += height + groupSpacing
                    return layout
                }
            }
            
            nativeView?.totalContentHeight = max(0, currentY - groupSpacing) + contentInsetBottom
            nativeView?.layouts = layouts
        }
        
        private func rebuildGroups() {
            groups = LyricsParser.groupLines(lyrics).filter { group in
                !getVisibleLines(from: group, limit: 5).isEmpty
            }
            
            for i in 0..<groups.count where groups[i].lines.contains(where: { $0.tag == "inst" }) {
                var nextTime: TimeInterval?
                for j in (i + 1)..<groups.count {
                    let nextLines = getVisibleLines(from: groups[j], limit: 5)
                    if !nextLines.isEmpty && !nextLines.contains(where: { $0.tag == "inst" }) {
                        nextTime = groups[j].time
                        break
                    }
                }
                groups[i].pauseUntil = nextTime
            }
            
            useAdvancedMode = shouldUseAdvancedMode()
        }
        
        private func shouldUseAdvancedMode() -> Bool {
            switch settings.lrcMode {
            case "on": return true
            case "off": return false
            case "auto": return lyrics.contains { $0.tag != nil }
            default: return false
            }
        }
        
        private func getVisibleLines(from group: LyricsGroup, limit: Int) -> [LyricsLine] {
            if let inst = group.lines.first(where: { $0.tag == "inst" }), isTagEnabled("inst") {
                return [inst]
            }
            
            var result: [LyricsLine] = []
            
            if let mainLine = group.lines.first(where: { $0.isMain && isTagEnabled($0.tag ?? "orig") }) {
                result.append(mainLine)
            } else if let fallback = group.lines.first(where: { line in
                guard let tag = line.tag else { return false }
                return !LyricsParser.specialTags.contains(tag)
            }) {
                var mainFallback = fallback
                mainFallback.isMain = true
                result.append(mainFallback)
            }
            
            let tagGroups: [[LyricsLine]] = [
                group.lines.filter { LyricsParser.pronunciationTags.contains($0.tag ?? "") && isTagEnabled($0.tag!) },
                group.lines.filter { $0.tag == "trans" && isTagEnabled("trans") },
                group.lines.filter { LyricsParser.languageTags.contains($0.tag ?? "") && isTagEnabled($0.tag!) },
                group.lines.filter { LyricsParser.specialTags.contains($0.tag ?? "") && isTagEnabled($0.tag!) && !["inst", "orig", "trans", "note"].contains($0.tag ?? "") }
            ]
            
            for tagGroup in tagGroups {
                for line in tagGroup where result.count < limit && !result.contains(where: { $0.id == line.id }) {
                    result.append(line)
                }
            }
            
            return Array(result.prefix(limit))
        }
        
        private func isTagEnabled(_ tag: String) -> Bool { settings.lrcEnabledTags[tag] ?? false }
        
        // MARK: - Display Link
        
        func startDisplayLink() {
            guard displayLink == nil else { return }
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
            guard let displayLink else { return }
            
            let context = Unmanaged.passRetained(self).toOpaque()
            displayLinkContext = context
            
            CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, userData in
                guard let userData else { return kCVReturnError }
                let coordinator = Unmanaged<Coordinator>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    coordinator.updateFrame()
                }
                return kCVReturnSuccess
            }, context)
            
            CVDisplayLinkStart(displayLink)
        }
        
        func stopDisplayLink() {
            guard let displayLink else { return }
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
            
            if let context = displayLinkContext {
                Unmanaged<Coordinator>.fromOpaque(context).release()
                displayLinkContext = nil
            }
        }
        
        private func updateFrame() {
            guard let nativeView else { return }
            
            let now = CACurrentMediaTime()
            let dt = lastFrameTime == 0 ? 1.0 / 60.0 : now - lastFrameTime
            lastFrameTime = now
            
            nativeView.updateOverscroll(dt: min(dt, 1.0 / 30.0))
            
            if nativeView.needsLayerUpdate {
                nativeView.updateVisibleLayers()
                nativeView.needsLayerUpdate = false
            }
            
            let oldIndex = currentIndex
            updateCurrentIndexFromTime()
            if oldIndex != currentIndex {
                nativeView.refreshVisualState(currentIndex: currentIndex, isUserScrolled: userScrolled)
            }
            
            if nativeView.isAutoScrolling {
                nativeView.updateAutoScroll()
            }
            
            nativeView.updateTimers(currentIndex: currentIndex, currentTime: currentTime, isUserScrolled: userScrolled)
            
            autoScrollIfNeeded()
        }
        
        private func updateCurrentIndexFromTime() {
            guard !layouts.isEmpty else { return }
            
            var lo = 0
            var hi = layouts.count
            while lo < hi {
                let mid = (lo + hi) / 2
                let t = layouts[mid].lines.first?.time ?? 0
                if currentTime >= t {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            let newIndex = lo - 1
            
            guard newIndex != currentIndex else { return }
            currentIndex = newIndex
            DispatchQueue.main.async {
                self.parent.currentIndex = newIndex
            }
        }
        
        private func autoScrollIfNeeded() {
            guard !userScrolled, currentIndex >= 0, currentIndex < layouts.count,
                  nativeView?.isAutoScrolling != true else { return }
            
            let layout = layouts[currentIndex]
            // Активная строка — на 20pt от верхнего края view.
            let targetY = layout.yPosition - 20
            let currentY = nativeView?.scrollOffset ?? 0
            
            if abs(targetY - currentY) > 5 {
                nativeView?.startAutoScroll(toY: targetY)
            }
        }
        
        func getRemainingTime(for line: LyricsLine) -> String {
            guard let until = line.pauseUntil else { return "♪" }
            let remaining = max(0.0, until - currentTime)
            return remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
        }
    }
}

// MARK: - Core Animation View (движок)

final class LiquidGlassCoreAnimationView: NSView {
    override var isFlipped: Bool { true }
    
    private let coordinator: LiquidGlassNativeLyricsView.Coordinator
    private(set) var layerPairs: [Int: LiquidGlassLayerPair] = [:]
    
    /// Индексы пар, которые сейчас видимы. Обновляется в updateVisibleLayers.
    /// updateTimers итерирует только по ним.
    private var visibleIndices: Set<Int> = []
    
    var scrollOffset: CGFloat = 0
    var totalContentHeight: CGFloat = 0
    var layouts: [LiquidGlassLineLayout] = []
    var needsLayerUpdate = false
    
    private(set) var isAutoScrolling = false
    private var allLayersLoaded = false
    private var targetScrollOffset: CGFloat = 0
    private var isUpdatingLayers = false
    private var scrollAnimationTimer: Timer?
    private var autoScrollTargetY: CGFloat?
    private var lastLayoutWidth: CGFloat = 0
    
    // MARK: - Overscroll
    
    private var virtualOffset: CGFloat = 0
    private var overscrollVelocity: CGFloat = 0
    private var isFingerDown = false
    private let maxOverscroll: CGFloat = 200
    private let springK: CGFloat = 200
    private var springC: CGFloat { 2 * sqrt(springK) }
    private let momentumToVelocity: CGFloat = 60
    private let fingerResistScale: CGFloat = 45
    
    init(coordinator: LiquidGlassNativeLyricsView.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        coordinator.nativeView = self
        coordinator.startDisplayLink()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    deinit {
        scrollAnimationTimer?.invalidate()
        coordinator.stopDisplayLink()
    }
    
    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        
        coordinator.precalculateLayout(width: bounds.width)
        
        let widthChanged = abs(bounds.width - lastLayoutWidth) > 0.5
        if widthChanged {
            lastLayoutWidth = bounds.width
            allLayersLoaded = false
            for pair in layerPairs.values { pair.removeFromSuperlayer() }
            layerPairs.removeAll()
            visibleIndices.removeAll()
            LiquidGlassLayerPair.clearTextCache()
        }
        
        preloadAllLayers()
        // Перерисовать видимые слои на следующем кадре — иначе после
        // ресайза окна (например, при первом открытии mini player)
        // visibleIndices остаются от старого размера.
        needsLayerUpdate = true
    }
    
    func resetAllLayers() {
        scrollAnimationTimer?.invalidate()
        scrollAnimationTimer = nil
        
        scrollOffset = 0
        targetScrollOffset = 0
        virtualOffset = 0
        overscrollVelocity = 0
        isFingerDown = false
        needsLayerUpdate = false
        
        for pair in layerPairs.values { pair.removeFromSuperlayer() }
        layerPairs.removeAll()
        visibleIndices.removeAll()
        allLayersLoaded = false
        LiquidGlassLayerPair.clearTextCache()
        preloadAllLayers()
        
        needsLayerUpdate = true
    }
    
    private func preloadAllLayers() {
        guard !allLayersLoaded, !layouts.isEmpty else { return }
        allLayersLoaded = true
        
        let textWidth = max(bounds.width - 32, 50)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for (index, layout) in layouts.enumerated() {
            let pair = LiquidGlassLayerPair()
            pair.index = index
            pair.updateLines(
                lines: layout.lines,
                width: textWidth,
                isCurrent: index == coordinator.currentIndex,
                animated: false,
                settings: SettingsManager.shared
            )
            pair.isHidden = true
            layer?.addSublayer(pair.containerLayer)
            layerPairs[index] = pair
        }
        
        CATransaction.commit()
        updateVisibleLayers()
        refreshVisualState(currentIndex: coordinator.currentIndex, isUserScrolled: coordinator.userScrolled, animated: false)
    }
    
    // MARK: - Scrolling
    
    override func scrollWheel(with event: NSEvent) {
        isAutoScrolling = false
        autoScrollTargetY = nil
        
        let maxOffset = max(0, totalContentHeight - bounds.height)
        
        guard event.hasPreciseScrollingDeltas else {
            let step: CGFloat = 40
            let delta = event.scrollingDeltaY > 0 ? step : -step
            targetScrollOffset -= delta
            startScrollAnimationIfNeeded()
            postScrollNotification()
            return
        }
        
        scrollAnimationTimer?.invalidate()
        scrollAnimationTimer = nil
        
        if event.phase == .began {
            isFingerDown = true
            overscrollVelocity = 0
        }
        if event.phase == .changed { isFingerDown = true }
        if event.phase == .ended { isFingerDown = false }
        if event.momentumPhase == .began { isFingerDown = false }
        
        let fingerActive = (event.phase == .began || event.phase == .changed)
        let delta = event.scrollingDeltaY * 0.6
        let clamped = max(0, min(virtualOffset, maxOffset))
        let dist = virtualOffset - clamped
        
        if fingerActive {
            let proposed = virtualOffset - delta
            let proposedClamped = max(0, min(proposed, maxOffset))
            let proposedDist = proposed - proposedClamped
            
            if abs(proposedDist) > abs(dist) {
                let resist = exp(-abs(dist) / fingerResistScale)
                virtualOffset -= delta * resist
            } else {
                virtualOffset = proposed
            }
        } else if dist == 0 {
            let proposed = virtualOffset - delta
            let proposedClamped = max(0, min(proposed, maxOffset))
            let proposedDist = proposed - proposedClamped
            
            if proposedDist != 0 {
                virtualOffset = proposedClamped
                overscrollVelocity += -delta * momentumToVelocity
            } else {
                virtualOffset = proposed
            }
        }
        
        let newClamped = max(0, min(virtualOffset, maxOffset))
        let newDist = virtualOffset - newClamped
        if abs(newDist) > maxOverscroll {
            virtualOffset = newClamped + (newDist > 0 ? maxOverscroll : -maxOverscroll)
        }
        
        scrollOffset = max(0, min(virtualOffset, maxOffset))
        needsLayerUpdate = true
        postScrollNotification()
    }
    
    private func postScrollNotification() {
        refreshVisualState(currentIndex: coordinator.currentIndex, isUserScrolled: true, animated: true)
        
        let c = coordinator
        DispatchQueue.main.async {
            c.userScrolled = true
            c.parent.userScrolled = true
            NotificationCenter.default.post(name: .userDidScroll, object: nil)
        }
    }
    
    private func startScrollAnimationIfNeeded() {
        guard scrollAnimationTimer == nil else { return }
        scrollAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { [weak self] _ in
            self?.updateScrollAnimation()
        }
    }
    
    private func updateScrollAnimation() {
        let delta = targetScrollOffset - scrollOffset
        scrollOffset += delta * 0.15
        virtualOffset = scrollOffset
        
        let maxOffset = max(0, totalContentHeight - bounds.height)
        scrollOffset = max(0, min(scrollOffset, maxOffset))
        targetScrollOffset = max(0, min(targetScrollOffset, maxOffset))
        
        needsLayerUpdate = true
        
        if abs(delta) < 0.3 {
            scrollAnimationTimer?.invalidate()
            scrollAnimationTimer = nil
            scrollOffset = targetScrollOffset
            virtualOffset = scrollOffset
            needsLayerUpdate = true
        }
    }
    
    func updateOverscroll(dt: CFTimeInterval) {
        guard !isFingerDown else { return }
        
        let maxOffset = max(0, totalContentHeight - bounds.height)
        let clamped = max(0, min(virtualOffset, maxOffset))
        let dist = virtualOffset - clamped
        
        if dist == 0 && abs(overscrollVelocity) < 0.1 { return }
        
        let accel = -springK * dist - springC * overscrollVelocity
        overscrollVelocity += accel * CGFloat(dt)
        virtualOffset += overscrollVelocity * CGFloat(dt)
        
        let newClamped = max(0, min(virtualOffset, maxOffset))
        let newDist = virtualOffset - newClamped
        if abs(newDist) > maxOverscroll {
            virtualOffset = newClamped + (newDist > 0 ? maxOverscroll : -maxOverscroll)
            overscrollVelocity = 0
        }
        
        let finalClamped = max(0, min(virtualOffset, maxOffset))
        if abs(virtualOffset - finalClamped) < 0.2 && abs(overscrollVelocity) < 0.2 {
            virtualOffset = finalClamped
            overscrollVelocity = 0
        }
        
        scrollOffset = finalClamped
        needsLayerUpdate = true
    }
    
    func startAutoScroll(toY targetY: CGFloat) {
        isFingerDown = false
        overscrollVelocity = 0
        
        scrollAnimationTimer?.invalidate()
        scrollAnimationTimer = nil
        
        let clampedY = max(0, min(targetY, max(0, totalContentHeight - bounds.height)))
        autoScrollTargetY = clampedY
        isAutoScrolling = true
    }
    
    func updateAutoScroll() {
        guard isAutoScrolling, let targetY = autoScrollTargetY else { return }
        
        let current = scrollOffset
        let delta = targetY - current
        
        if abs(delta) < 0.5 {
            scrollOffset = targetY
            targetScrollOffset = targetY
            virtualOffset = targetY
            isAutoScrolling = false
            autoScrollTargetY = nil
            needsLayerUpdate = true
            return
        }
        
        let smoothing: CGFloat = 0.15
        scrollOffset += delta * smoothing
        targetScrollOffset = scrollOffset
        virtualOffset = scrollOffset
        needsLayerUpdate = true
    }
    
    func updateTimers(currentIndex: Int, currentTime: TimeInterval, isUserScrolled: Bool) {
        let settings = SettingsManager.shared
        
        // Итерируем только по видимым парам
        for index in visibleIndices {
            guard let pair = layerPairs[index] else { continue }
            guard index < layouts.count else { continue }
            let layout = layouts[index]
            let isActive = index == currentIndex
            
            if isActive {
                pair.updateWordHighlight(currentTime: currentTime, lineOpacity: 1.0)
            }
            
            if let instLine = layout.lines.first(where: { $0.tag == "inst" }) {
                if isActive {
                    pair.updateInstTimer(text: coordinator.getRemainingTime(for: instLine), settings: settings)
                    pair.setInstTimerVisible(true)
                } else {
                    pair.setInstTimerVisible(false)
                }
            }
            
            if let emptyLine = layout.lines.first(where: { $0.text.isEmpty && $0.words.isEmpty }),
               isActive {
                let remaining = coordinator.getRemainingTime(for: emptyLine)
                let displayText = remaining == "♪" ? "♪" : "♪ \(remaining.replacingOccurrences(of: "♪ ", with: ""))"
                pair.updateEmptyLineTimer(text: displayText, settings: settings)
            }
        }
    }
    
    func updateVisibleLayers() {
        guard !isUpdatingLayers else { return }
        isUpdatingLayers = true
        defer { isUpdatingLayers = false }
        
        let visualOffset = virtualOffset
        
        let visibleStart = visualOffset - bounds.height
        let visibleEnd = visualOffset + bounds.height * 2
        
        var newVisible: Set<Int> = []
        newVisible.reserveCapacity(64)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        for (index, pair) in layerPairs {
            guard index < layouts.count else { continue }
            let layout = layouts[index]
            let isVisible = layout.yPosition + layout.height >= visibleStart
                         && layout.yPosition <= visibleEnd
            
            if pair.isHidden != !isVisible {
                pair.isHidden = !isVisible
            }
            
            guard isVisible else { continue }
            
            newVisible.insert(index)
            
            let frame = NSRect(
                x: 16,
                y: layout.yPosition - visualOffset,
                width: max(bounds.width - 32, 50),
                height: layout.height
            )
            pair.updateFrame(frame)
        }
        
        CATransaction.commit()
        visibleIndices = newVisible
    }
    
    func refreshVisualState(currentIndex: Int, isUserScrolled: Bool, animated: Bool = true) {
        let settings = SettingsManager.shared
        let advanced = coordinator.useAdvancedMode
        for (index, pair) in layerPairs {
            let distance = currentIndex < 0 ? 99 : abs(index - currentIndex)
            pair.applyVisualState(
                isActive: index == currentIndex,
                distance: distance,
                isUserScrolled: isUserScrolled,
                isAdvancedMode: advanced,
                animated: animated,
                settings: settings
            )
        }
    }
    
    // MARK: - Interaction
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        for (index, pair) in layerPairs {
            guard let noteFrame = pair.noteButtonFrame,
                  pair.containerLayer.convert(noteFrame, to: layer).contains(point) else { continue }
            showNotePopover(for: index, noteFrame: noteFrame)
            return
        }
        
        let visualOffset = virtualOffset
        let yInContent = point.y + visualOffset
        for (index, layout) in layouts.enumerated()
        where yInContent >= layout.yPosition && yInContent <= layout.yPosition + layout.height {
            isAutoScrolling = false
            autoScrollTargetY = nil
            isFingerDown = false
            overscrollVelocity = 0
            virtualOffset = scrollOffset
            
            coordinator.currentIndex = index
            refreshVisualState(currentIndex: index, isUserScrolled: false)
            
            DispatchQueue.main.async {
                self.coordinator.parent.currentIndex = index
                self.coordinator.parent.userScrolled = false
                self.coordinator.userScrolled = false
                NotificationCenter.default.post(name: .userDidSync, object: nil)
            }
            
            coordinator.onTapLine?(layout.lines.first?.time ?? 0)
            
            let targetY = layout.yPosition - 20
            startAutoScroll(toY: targetY)
            return
        }
    }
    
    private func showNotePopover(for index: Int, noteFrame: NSRect) {
        guard index < layouts.count,
              let noteText = layouts[index].lines.first(where: { $0.tag == "note" })?.text else { return }
        
        let settings = SettingsManager.shared
        let textField = NSTextField(wrappingLabelWithString: noteText)
        textField.font = .systemFont(ofSize: 12)
        textField.textColor = NSColor(hex: settings.lrcTagColors["note"] ?? "#888888") ?? .white
        textField.lineBreakMode = .byWordWrapping
        textField.preferredMaxLayoutWidth = 250
        textField.isEditable = false
        textField.drawsBackground = false
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 100))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(settings.darkBg).cgColor
        containerView.layer?.cornerRadius = 10
        containerView.addSubview(textField)
        
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            textField.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14)
        ])
        
        let popover = NSPopover()
        popover.contentViewController = {
            let vc = NSViewController()
            vc.view = containerView
            return vc
        }()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.show(relativeTo: noteFrame, of: self, preferredEdge: .maxY)
    }
}

// MARK: - Layer Pair (Liquid Glass style)

final class LiquidGlassLayerPair {
    let containerLayer = CALayer()
    
    private var lineLayers: [(inactive: CALayer, active: CALayer, line: LyricsLine)] = []
    private var instTimerLayer: CALayer?
    private var noteButtonLayer: CALayer?
    private var lineFontSizes: [CGFloat] = []
    
    private static var textCache: [String: CGImage] = [:]
    private static var heightCache: [String: CGFloat] = [:]
    private static let cacheLock = NSLock()
    private static let maxCacheSize = 200
    private static let maxHeightCacheSize = 500
    
    private var wordLayers: [(
        inactive: CALayer,
        active: CALayer,
        word: LyricsWord,
        displayedProgress: CGFloat,
        mask: CALayer,
        fill: CALayer
    )] = []
    
    private var needsProgressReset = true
    
    var index = -1
    
    private let backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    
    var noteButtonFrame: NSRect? { noteButtonLayer?.frame }
    
    var isHidden: Bool {
        get { containerLayer.isHidden }
        set { containerLayer.isHidden = newValue }
    }
    
    init() {
        containerLayer.contentsGravity = .center
    }
    
    static func clearTextCache() {
        cacheLock.lock()
        textCache.removeAll()
        heightCache.removeAll()
        cacheLock.unlock()
    }
    
    func removeFromSuperlayer() {
        containerLayer.removeFromSuperlayer()
    }
    
    // MARK: - Создание слоёв
    
    func updateLines(lines: [LyricsLine], width: CGFloat, isCurrent: Bool, animated: Bool, settings: SettingsManager) {
        for layer in lineLayers {
            layer.inactive.removeFromSuperlayer()
            layer.active.removeFromSuperlayer()
        }
        for wordLayer in wordLayers {
            wordLayer.inactive.removeFromSuperlayer()
            wordLayer.active.removeFromSuperlayer()
        }
        
        lineLayers.removeAll()
        wordLayers.removeAll()
        lineFontSizes.removeAll()
        instTimerLayer?.removeFromSuperlayer()
        instTimerLayer = nil
        
        let effectiveWidth = width > 0 ? width : 400
        
        for (index, line) in lines.enumerated() where line.tag != "note" {
            if line.tag == "inst" {
                createInstLayers(line: line, width: effectiveWidth, isCurrent: isCurrent, settings: settings)
                continue
            }
            
            if settings.lrcWordHighlight && line.hasWords {
                createWordLayers(line: line, width: effectiveWidth, isCurrent: isCurrent, settings: settings)
                continue
            }
            
            let fontSize: CGFloat
            if line.isMain || index == 0 {
                fontSize = 17
            } else if index == 1 {
                fontSize = lines.count >= 3 ? 11 : 13
            } else {
                fontSize = 11
            }
            
            lineFontSizes.append(fontSize)
            createTextLayers(line: line, fontSize: fontSize, index: index, width: effectiveWidth, isCurrent: isCurrent, settings: settings)
        }
        
        if let noteLine = lines.first(where: { $0.tag == "note" && (settings.lrcEnabledTags["note"] ?? false) }) {
            updateNoteButton(line: noteLine, settings: settings)
        } else {
            noteButtonLayer?.isHidden = true
        }
    }
    
    // MARK: - Measuring
    
    static func measureLineHeight(
        text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        width: CGFloat
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font, .paragraphStyle: paragraphStyle]
        )
        let rect = attributedString.boundingRect(
            with: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }
    
    static func measureGroupHeight(
        lines: [LyricsLine],
        width: CGFloat,
        settings: SettingsManager
    ) -> CGFloat {
        let idsPart = lines.map { $0.id.uuidString }.joined(separator: "|")
        let key = "\(idsPart)_\(width)"
        
        cacheLock.lock()
        if let cached = heightCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let probe = LiquidGlassLayerPair()
        probe.updateLines(lines: lines, width: width, isCurrent: true, animated: false, settings: settings)
        let h = max(probe.updateFrame(NSRect(x: 0, y: 0, width: max(width, 1), height: 10000)), 12)
        
        cacheLock.lock()
        if heightCache.count >= maxHeightCacheSize {
            heightCache.removeAll()
        }
        heightCache[key] = h
        cacheLock.unlock()
        
        return h
    }
    
    // MARK: - Liquid Glass Colors
    
    private func baseColor(for line: LyricsLine, settings: SettingsManager) -> NSColor {
        if let tag = line.tag {
            return NSColor(hex: settings.lrcTagColors[tag] ?? "#FFFFFF") ?? NSColor.labelColor
        }
        return NSColor.labelColor
    }
    
    private func accentColor(for line: LyricsLine, settings: SettingsManager) -> NSColor {
        if let tag = line.tag {
            return NSColor(hex: settings.lrcTagColors[tag] ?? "#FFFFFF") ?? NSColor.controlAccentColor
        }
        return NSColor.controlAccentColor
    }
    
    private func distanceOpacity(distance: Int, isUserScrolled: Bool) -> CGFloat {
        if isUserScrolled { return 0.8 }
        // Резче убывает и доходит до 10% (было 20% и шаг 0.2).
        // d=0: 1.0, d=1: 0.7, d=2: 0.4, d=3+: 0.1
        return max(0.1, 1.0 - CGFloat(distance) * 0.3)
    }
    
    // MARK: - Words
    
    private func createWordLayers(line: LyricsLine, width: CGFloat, isCurrent: Bool, settings: SettingsManager) {
        let fontSize: CGFloat = 17
        lineFontSizes.append(fontSize)
        
        let inactiveColor = baseColor(for: line, settings: settings)
        let activeColor = accentColor(for: line, settings: settings)
        
        let weight: NSFont.Weight = .semibold
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        
        for var word in line.words {
            let textSize = (word.text as NSString).size(withAttributes: [.font: font])
            word.textWidth = ceil(textSize.width)
            
            let inactiveLayer = CALayer()
            let activeLayer = CALayer()
            
            inactiveLayer.contents = getCachedText(word.text, color: inactiveColor, fontSize: fontSize, weight: weight, width: width)
            activeLayer.contents = getCachedText(word.text, color: activeColor, fontSize: fontSize, weight: weight, width: width)
            
            for layer in [inactiveLayer, activeLayer] {
                layer.contentsGravity = .center
                layer.contentsScale = backingScale
                containerLayer.addSublayer(layer)
            }
            
            activeLayer.opacity = 0
            inactiveLayer.opacity = 1.0
            
            let mask = CALayer()
            mask.contentsScale = backingScale
            
            let fill = CALayer()
            fill.contentsScale = backingScale
            fill.backgroundColor = NSColor.white.cgColor
            mask.addSublayer(fill)
            
            wordLayers.append((
                inactive: inactiveLayer,
                active: activeLayer,
                word: word,
                displayedProgress: 0,
                mask: mask,
                fill: fill
            ))
        }
    }
    
    func updateWordHighlight(currentTime: TimeInterval, lineOpacity: CGFloat) {
        guard !wordLayers.isEmpty else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let smoothing: CGFloat = 0.25
        
        for i in 0..<wordLayers.count {
            let active = wordLayers[i].active
            let inactive = wordLayers[i].inactive
            let word = wordLayers[i].word
            let mask = wordLayers[i].mask
            let fill = wordLayers[i].fill
            
            active.removeAnimation(forKey: "opacity")
            inactive.removeAnimation(forKey: "opacity")
            
            inactive.opacity = Float(lineOpacity)
            
            guard let endTime = word.endTime else {
                active.mask = nil
                active.opacity = 0
                wordLayers[i].displayedProgress = 0
                continue
            }
            
            let duration = max(endTime - word.time, 0.001)
            let layerWidth = active.frame.width
            let layerHeight = active.frame.height
            
            if currentTime >= endTime {
                wordLayers[i].displayedProgress = 1
                active.mask = nil
                active.opacity = 1.0
            } else if currentTime >= word.time {
                let raw = (currentTime - word.time) / duration
                let target = CGFloat(1 - pow(1 - min(max(raw, 0), 1), 2))
                
                let displayed: CGFloat
                if needsProgressReset {
                    displayed = target
                } else {
                    let current = wordLayers[i].displayedProgress
                    displayed = current + (target - current) * smoothing
                }
                wordLayers[i].displayedProgress = displayed
                
                if duration < 0.15 {
                    active.mask = nil
                    active.opacity = 1.0
                } else {
                    mask.frame = CGRect(x: 0, y: 0, width: layerWidth, height: layerHeight)
                    fill.frame = CGRect(x: 0, y: 0, width: layerWidth * displayed, height: layerHeight)
                    active.mask = mask
                    active.opacity = 1.0
                }
            } else {
                wordLayers[i].displayedProgress = 0
                active.mask = nil
                active.opacity = 0.0
            }
        }
        
        if needsProgressReset {
            needsProgressReset = false
        }
        
        CATransaction.commit()
    }
    
    // MARK: - Inst
    
    private func createInstLayers(line: LyricsLine, width: CGFloat, isCurrent: Bool, settings: SettingsManager) {
        let timerLayer = CALayer()
        let timerColor = accentColor(for: line, settings: settings)
        timerLayer.contents = getCachedText("♪", color: timerColor, fontSize: 10, weight: .regular, width: width)
        timerLayer.contentsGravity = .center
        timerLayer.contentsScale = backingScale
        timerLayer.frame = NSRect(x: 0, y: 0, width: width, height: 14)
        timerLayer.isHidden = !isCurrent
        timerLayer.opacity = isCurrent ? 1.0 : 0.0
        containerLayer.addSublayer(timerLayer)
        instTimerLayer = timerLayer
        
        let fontSize: CGFloat = 16
        lineFontSizes.append(fontSize)
        createTextLayers(line: line, fontSize: fontSize, index: 0, width: width, isCurrent: isCurrent, settings: settings)
    }
    
    // MARK: - Text
    
    private func createTextLayers(
        line: LyricsLine,
        fontSize: CGFloat,
        index: Int,
        width: CGFloat,
        isCurrent: Bool,
        settings: SettingsManager
    ) {
        let inactiveColor = baseColor(for: line, settings: settings)
        let activeColor = accentColor(for: line, settings: settings)
        let displayText = line.text.isEmpty ? "♪" : line.text
        let weight: NSFont.Weight = index == 0 ? .semibold : .regular
        
        let inactiveLayer = CALayer()
        let activeLayer = CALayer()
        
        inactiveLayer.contents = getCachedText(displayText, color: inactiveColor, fontSize: fontSize, weight: weight, width: width)
        activeLayer.contents = getCachedText(displayText, color: activeColor, fontSize: fontSize, weight: weight, width: width)
        
        for layer in [inactiveLayer, activeLayer] {
            layer.contentsGravity = .top
            layer.contentsScale = backingScale
            containerLayer.addSublayer(layer)
        }
        
        activeLayer.opacity = isCurrent ? 1.0 : 0.0
        inactiveLayer.opacity = isCurrent ? 0.0 : 0.8
        
        lineLayers.append((inactive: inactiveLayer, active: activeLayer, line: line))
    }
    
    func updateInstTimer(text: String, settings: SettingsManager) {
        guard let instTimerLayer else { return }
        let color = NSColor.controlAccentColor.withAlphaComponent(0.6)
        let width = containerLayer.frame.width > 0 ? containerLayer.frame.width : 400
        instTimerLayer.contents = getCachedText(text, color: color, fontSize: 10, weight: .regular, width: width)
        instTimerLayer.frame.size.width = containerLayer.frame.width
    }
    
    func setInstTimerVisible(_ visible: Bool) {
        instTimerLayer?.isHidden = !visible
        instTimerLayer?.opacity = visible ? 1.0 : 0.0
    }
    
    func updateEmptyLineTimer(text: String, settings: SettingsManager) {
        guard let first = lineLayers.first else { return }
        let fontSize = lineFontSizes.first ?? 17
        let width = containerLayer.frame.width > 0 ? containerLayer.frame.width : 400
        
        first.active.contents = getCachedText(text, color: NSColor.controlAccentColor, fontSize: fontSize, weight: .regular, width: width)
        first.inactive.contents = getCachedText("♪", color: NSColor.labelColor.withAlphaComponent(0.4), fontSize: fontSize, weight: .regular, width: width)
    }
    
    // MARK: - Liquid Glass Visual State
    
    func applyVisualState(
        isActive: Bool,
        distance: Int,
        isUserScrolled: Bool,
        isAdvancedMode: Bool,
        animated: Bool,
        settings: SettingsManager
    ) {
        let opacity: CGFloat
        if isAdvancedMode && !isActive {
            // В advanced-тексте все неактивные — фиксированные 20%.
            opacity = isUserScrolled ? 0.8 : 0.2
        } else {
            opacity = distanceOpacity(distance: distance, isUserScrolled: isUserScrolled)
        }
        let duration: CFTimeInterval = animated ? 0.25 : 0
        
        if isActive {
            needsProgressReset = true
        }
        
        for layer in lineLayers {
            if isActive {
                animateOpacity(layer.active, to: 1.0, duration: duration)
                animateOpacity(layer.inactive, to: 0.0, duration: duration)
            } else {
                animateOpacity(layer.active, to: 0.0, duration: duration)
                animateOpacity(layer.inactive, to: Float(opacity), duration: duration)
            }
        }
        
        if !wordLayers.isEmpty && !isActive {
            for wordLayer in wordLayers {
                animateOpacity(wordLayer.active, to: 0.0, duration: duration)
                animateOpacity(wordLayer.inactive, to: Float(opacity), duration: duration)
            }
        }
    }
    
    private func animateOpacity(_ layer: CALayer, to value: Float, duration: CFTimeInterval) {
        if duration <= 0 {
            layer.removeAnimation(forKey: "opacity")
            layer.opacity = value
            return
        }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = value
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.opacity = value
        layer.add(anim, forKey: "opacity")
    }
    
    // MARK: - Layout
    
    @discardableResult
    func updateFrame(_ frame: NSRect) -> CGFloat {
        containerLayer.frame = frame
        
        var yOffset: CGFloat = 0
        let lineSpacing: CGFloat = 8
        
        // Резервируем место под inst-таймер всегда, когда слой существует.
        // Видимость рулится через isHidden — на layout это не влияет.
        if let instTimerLayer {
            instTimerLayer.frame = NSRect(x: 0, y: yOffset, width: frame.width, height: 14)
            yOffset += 14 + lineSpacing
        }
        
        if !wordLayers.isEmpty {
            layoutWordLayers(frame: frame, yOffset: &yOffset, lineSpacing: lineSpacing)
        } else {
            layoutTextLayers(frame: frame, yOffset: &yOffset, lineSpacing: lineSpacing)
        }
        
        noteButtonLayer?.frame = NSRect(x: 4, y: frame.height - 18, width: 14, height: 14)
        
        return yOffset
    }
    
    private func layoutWordLayers(frame: NSRect, yOffset: inout CGFloat, lineSpacing: CGFloat) {
        let wordSpacing: CGFloat = 4
        let wordHeight: CGFloat = 24
        let maxWidth = frame.width
        
        // 1. Разбиваем слова на строки по ширине
        var rows: [[(inactive: CALayer, active: CALayer, textWidth: CGFloat)]] = []
        var currentRow: [(inactive: CALayer, active: CALayer, textWidth: CGFloat)] = []
        var currentWidth: CGFloat = 0
        
        for wl in wordLayers {
            let w = wl.word.textWidth
            let needed = currentRow.isEmpty ? w : currentWidth + wordSpacing + w
            
            if needed > maxWidth && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentWidth = w
            } else {
                currentWidth = needed
            }
            
            currentRow.append((inactive: wl.inactive, active: wl.active, textWidth: w))
        }
        if !currentRow.isEmpty { rows.append(currentRow) }
        
        // 2. Раскладываем построчно
        for row in rows {
            let totalWidth = row.reduce(0) { $0 + $1.textWidth }
                + CGFloat(max(0, row.count - 1)) * wordSpacing
            var x = max(0, (frame.width - totalWidth) / 2)
            
            for item in row {
                let layerFrame = NSRect(x: x, y: yOffset, width: item.textWidth, height: wordHeight)
                item.inactive.frame = layerFrame
                item.active.frame = layerFrame
                x += item.textWidth + wordSpacing
            }
            
            yOffset += wordHeight
        }
    }
    
    private func layoutTextLayers(frame: NSRect, yOffset: inout CGFloat, lineSpacing: CGFloat) {
        for (index, layer) in lineLayers.enumerated() {
            let fontSize = index < lineFontSizes.count ? lineFontSizes[index] : 17
            let weight: NSFont.Weight = index == 0 ? .semibold : .regular
            
            if layer.line.text.isEmpty {
                let layerFrame = NSRect(x: 0, y: yOffset, width: frame.width, height: 20)
                layer.inactive.frame = layerFrame
                layer.active.frame = layerFrame
                yOffset += 20
            } else {
                let textHeight = Self.measureLineHeight(
                    text: layer.line.text,
                    fontSize: fontSize,
                    weight: weight,
                    width: frame.width
                )
                
                let layerFrame = NSRect(x: 0, y: yOffset, width: frame.width, height: textHeight)
                layer.inactive.frame = layerFrame
                layer.active.frame = layerFrame
                yOffset += textHeight
            }
            
            if index < lineLayers.count - 1 {
                yOffset += lineSpacing
            }
        }
    }
    
    // MARK: - Note
    
    private func updateNoteButton(line: LyricsLine, settings: SettingsManager) {
        if noteButtonLayer == nil {
            let buttonLayer = CALayer()
            buttonLayer.contentsGravity = .center
            buttonLayer.contentsScale = backingScale
            containerLayer.addSublayer(buttonLayer)
            noteButtonLayer = buttonLayer
        }
        
        let noteColor = NSColor(hex: settings.lrcTagColors["note"] ?? "#888888") ?? NSColor.labelColor
        if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?.tinted(with: noteColor) {
            noteButtonLayer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        noteButtonLayer?.contentsScale = backingScale
        noteButtonLayer?.isHidden = false
    }
    
    // MARK: - Text Cache
    
    private func getCachedText(
        _ text: String,
        color: NSColor,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        width: CGFloat
    ) -> CGImage? {
        let actualWidth = width > 0 ? width : 400
        let cacheKey = "\(text)_\(color.description)_\(fontSize)_\(weight.rawValue)_\(actualWidth)"
        
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        
        if let cached = Self.textCache[cacheKey] { return cached }
        if Self.textCache.count >= Self.maxCacheSize { Self.textCache.removeAll() }
        
        guard let rendered = renderText(text: text, color: color, fontSize: fontSize, weight: weight, width: actualWidth) else {
            return nil
        }
        Self.textCache[cacheKey] = rendered
        return rendered
    }

    private func renderText(
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        width: CGFloat
    ) -> CGImage? {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
        )
        
        let height = Self.measureLineHeight(text: text, fontSize: fontSize, weight: weight, width: width)
        let size = NSSize(width: max(width, 1), height: height)
        guard size.width > 0, size.height > 0 else { return nil }
        
        let image = NSImage(size: size)
        image.lockFocus()
        attributedString.draw(with: NSRect(origin: .zero, size: size), options: [.usesLineFragmentOrigin, .usesFontLeading])
        image.unlockFocus()
        
        return image.tiffRepresentation
            .flatMap { NSBitmapImageRep(data: $0) }
            .flatMap { $0.cgImage }
    }
}

// MARK: - NSImage Extension
private extension NSImage {
    func tinted(with color: NSColor) -> NSImage? {
        guard let copy = copy() as? NSImage else { return nil }
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}
