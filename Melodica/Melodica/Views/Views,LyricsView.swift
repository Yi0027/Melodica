import SwiftUI
import AppKit
import CoreVideo

// MARK: - Notifications
extension Notification.Name {
    static let splitterDidResize = Notification.Name("splitterDidResize")
    static let resetUserScrolled = Notification.Name("ResetUserScrolled")
    static let userDidScroll = Notification.Name("UserDidScroll")
    static let scrollLyricsToTop = Notification.Name("ScrollLyricsToTop")
    static let forceScrollNow = Notification.Name("ForceScrollNow")
    static let scrollToIndex = Notification.Name("ScrollToIndex")
    static let userDidSync = Notification.Name("UserDidSync")
}

// MARK: - Layout Model
struct LyricsLineLayout {
    let lines: [LyricsLine]
    let yPosition: CGFloat
    let height: CGFloat
}

// MARK: - SwiftUI Wrapper
struct LyricsView: View {
    let lyrics: [LyricsLine]
    @ObservedObject var progress: PlaybackProgress
    @Binding var userScrolled: Bool
    let trackId: UUID?
    let onTapLine: ((TimeInterval) -> Void)?
    @ObservedObject private var theme = SettingsManager.shared
    
    @State private var currentIndex = -1
    @State private var canShowButton = false
    @State private var isNativeScrolling = false
    
    private var settings: SettingsManager { SettingsManager.shared }
    
    private var metadataLines: [String] {
        let metadata = LyricsParser.lastMetadata
        var result: [String] = []
        
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
            result.append("\(label): \(value)")
        }
        return result
    }
    
    private var metadataView: some View {
        VStack(spacing: 2) {
            ForEach(metadataLines, id: \.self) { text in
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: settings.lrcMetadataColor) ?? .gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(settings.darkBg.opacity(0.5))
    }
    
    private var showMetadata: Bool {
        guard settings.lrcShowMetadata, !metadataLines.isEmpty, !userScrolled, !isNativeScrolling else {
            return false
        }
        
        if settings.lrcMetadataPosition == "before" {
            let firstRealTime = lyrics.first(where: { !$0.text.isEmpty })?.time ?? 0
            return progress.currentTime < firstRealTime
        } else {
            let lastTime = lyrics.last?.time ?? 0
            return progress.currentTime > lastTime
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showMetadata && settings.lrcMetadataPosition == "before" {
                metadataView.transition(.opacity)
            }
            
            ZStack(alignment: .bottom) {
                LyricsNativeView(
                    lyrics: lyrics,
                    currentIndex: $currentIndex,
                    currentTime: progress.currentTime,
                    userScrolled: $userScrolled,
                    onTapLine: onTapLine
                )
                .onReceive(NotificationCenter.default.publisher(for: .userDidScroll)) { _ in
                    isNativeScrolling = true
                    userScrolled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isNativeScrolling = false
                    }
                }
                .onAppear {
                    guard !lyrics.isEmpty else { return }
                    canShowButton = true
                }
                .onChange(of: trackId) { _ in resetState() }
                .onChange(of: lyrics.map(\.id)) { _ in resetState() }
                
                if userScrolled && canShowButton {
                    syncButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.4), value: userScrolled)
                }
            }
            
            if showMetadata && settings.lrcMetadataPosition == "after" {
                metadataView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showMetadata)
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
        canShowButton = true
        NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
    }
    
    private var syncButton: some View {
        Button {
            userScrolled = false
            NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
            NotificationCenter.default.post(name: .forceScrollNow, object: nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                Text(LocalizedStringKey("synch")).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }
}

// MARK: - NSViewRepresentable
struct LyricsNativeView: NSViewRepresentable {
    let lyrics: [LyricsLine]
    @Binding var currentIndex: Int
    let currentTime: TimeInterval
    @Binding var userScrolled: Bool
    let onTapLine: ((TimeInterval) -> Void)?
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeNSView(context: Context) -> NSView {
        let view = CoreAnimationLyricsView(coordinator: context.coordinator)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.lyrics = lyrics
        coordinator.currentTime = currentTime
        coordinator.userScrolled = userScrolled
        coordinator.onTapLine = onTapLine
        
        let newIDs = lyrics.map(\.id)
        guard coordinator.lastLyricsID != newIDs else { return }
        
        coordinator.lastLyricsID = newIDs
        coordinator.precalculateLayout(width: nsView.bounds.width)
        coordinator.nativeView?.resetAllLayers()
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, NSTableViewDelegate {
        var parent: LyricsNativeView
        var lyrics: [LyricsLine] = []
        var layouts: [LyricsLineLayout] = []
        var currentIndex = -1
        var currentTime: TimeInterval = 0
        var userScrolled = false
        var onTapLine: ((TimeInterval) -> Void)?
        var lastLyricsID: [UUID] = []
        
        weak var nativeView: CoreAnimationLyricsView?
        
        private var displayLink: CVDisplayLink?
        private var displayLinkContext: UnsafeMutableRawPointer?
        private var settings: SettingsManager { SettingsManager.shared }
        private var groups: [LyricsGroup] = []
        private var useAdvancedMode = false
        
        init(_ parent: LyricsNativeView) {
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
                    let height = LyricsLayerPair.measureGroupHeight(
                        lines: visibleLines,
                        width: availableWidth,
                        settings: settings
                    )
                    let layout = LyricsLineLayout(lines: lines, yPosition: currentY, height: height)
                    currentY += height + groupSpacing
                    return layout
                }
            } else {
                layouts = lyrics.filter { $0.tag == nil }.map { line in
                    let height = LyricsLayerPair.measureGroupHeight(
                        lines: [line],
                        width: max(width - 32, 1),
                        settings: settings
                    )
                    let layout = LyricsLineLayout(lines: [line], yPosition: currentY, height: height)
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
        
        private func getFontSize(for index: Int, total: Int) -> CGFloat {
            switch index {
            case 0: return 17
            case 1: return total >= 3 ? 11 : 13
            default: return 11
            }
        }
        
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
        
        private var lastFrameTime: CFTimeInterval = 0
        
        private func updateFrame() {
            guard let nativeView else { return }
            
            let now = CACurrentMediaTime()
            let dt = lastFrameTime == 0 ? 1.0 / 60.0 : now - lastFrameTime
            lastFrameTime = now
            
            nativeView.updateOverscroll(dt: dt)
            
            if nativeView.needsLayerUpdate {
                nativeView.updateVisibleLayers()
                nativeView.needsLayerUpdate = false
            }
            
            let oldIndex = currentIndex
            updateCurrentIndexFromTime()
            if oldIndex != currentIndex {
                nativeView.animateHighlightChange(from: oldIndex, to: currentIndex)
            }
            
            if nativeView.isAutoScrolling {
                nativeView.updateAutoScroll()
            }
            
            nativeView.updateTimers(currentIndex: currentIndex, currentTime: currentTime)
            
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
            let viewHeight = nativeView?.bounds.height ?? 0
            let targetY = layout.yPosition - viewHeight / 2 + layout.height / 2
            let currentY = nativeView?.scrollOffset ?? 0
            
            if abs(targetY - currentY) > 5 {
                nativeView?.startAutoScroll(toY: targetY)
            }
        }
        
        // MARK: - Colors & Time
        
        func getColor(for line: LyricsLine, isActive: Bool) -> NSColor {
            guard let tag = line.tag else {
                return isActive ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
            }
            
            let hex: String
            if line.isMain {
                hex = settings.lrcTagColors["orig"] ?? "#FFFFFF"
            } else {
                hex = settings.lrcTagColors[tag] ?? "#888888"
            }
            
            let baseColor = NSColor(hex: hex) ?? .white
            if isActive { return baseColor }
            if settings.lrcDimInactive {
                return baseColor.withAlphaComponent(baseColor.alphaComponent * 0.4)
            }
            return settings.lyricInactiveNSColor
        }
        
        func getRemainingTime(for line: LyricsLine) -> String {
            guard let until = line.pauseUntil else { return "♪" }
            let remaining = max(0.0, until - currentTime)
            return remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
        }
    }
}

// MARK: - Core Animation View
final class CoreAnimationLyricsView: NSView {
    override var isFlipped: Bool { true }
    
    private let coordinator: LyricsNativeView.Coordinator
    private(set) var layerPairs: [Int: LyricsLayerPair] = [:]
    
    var scrollOffset: CGFloat = 0
    var totalContentHeight: CGFloat = 0
    var layouts: [LyricsLineLayout] = []
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
    
    init(coordinator: LyricsNativeView.Coordinator) {
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
            LyricsLayerPair.clearTextCache()
        }
        
        preloadAllLayers()
        // Перерисовать видимые слои на следующем кадре — иначе после
        // ресайза (или первого открытия mini player) visibleIndices
        // остаются от старого размера.
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
        allLayersLoaded = false
        LyricsLayerPair.clearTextCache()
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
            let pair = LyricsLayerPair()
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
    
    func updateTimers(currentIndex: Int, currentTime: TimeInterval) {
        let settings = SettingsManager.shared
        
        for (index, pair) in layerPairs where !pair.isHidden {
            guard index < layouts.count else { continue }
            let layout = layouts[index]
            let isActive = index == currentIndex
            
            if isActive {
                pair.updateWordHighlight(currentTime: currentTime)
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
            
            let frame = NSRect(
                x: 16,
                y: layout.yPosition - visualOffset,
                width: max(bounds.width - 32, 50),
                height: layout.height
            )
            pair.updateFrame(frame)
        }
        
        CATransaction.commit()
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
            
            let oldIndex = coordinator.currentIndex
            coordinator.currentIndex = index
            animateHighlightChange(from: oldIndex, to: index)
            
            DispatchQueue.main.async {
                self.coordinator.parent.currentIndex = index
                self.coordinator.parent.userScrolled = false
                NotificationCenter.default.post(name: .userDidSync, object: nil)
            }
            
            coordinator.onTapLine?(layout.lines.first?.time ?? 0)
            coordinator.userScrolled = false
            
            let targetY = layout.yPosition - bounds.height / 2 + layout.height / 2
            startAutoScroll(toY: targetY)
            return
        }
    }
    
    func animateHighlightChange(from oldIndex: Int, to newIndex: Int) {
        for (index, pair) in layerPairs {
            pair.setHighlighted(index == newIndex, animated: true, settings: SettingsManager.shared)
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

// MARK: - Layer Pair
final class LyricsLayerPair {
    let containerLayer = CALayer()
    
    private var lineLayers: [(inactive: CALayer, active: CALayer, line: LyricsLine)] = []
    private var instTimerLayer: CALayer?
    private var noteButtonLayer: CALayer?
    private var lineFontSizes: [CGFloat] = []
    
    private static var textCache: [String: CGImage] = [:]
    private static let cacheLock = NSLock()
    private static let maxCacheSize = 200
    private static var heightCache: [String: CGFloat] = [:]
    
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
    
    // MARK: - Измерение
    
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
        let key = lines.map { $0.id.uuidString }.joined(separator: "|") + "_\(width)"
        
        cacheLock.lock()
        if let cached = heightCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let probe = LyricsLayerPair()
        probe.updateLines(lines: lines, width: width, isCurrent: true, animated: false, settings: settings)
        let h = max(probe.updateFrame(NSRect(x: 0, y: 0, width: max(width, 1), height: 10000)), 12)
        
        cacheLock.lock()
        if heightCache.count >= maxCacheSize { heightCache.removeAll() }
        heightCache[key] = h
        cacheLock.unlock()
        
        return h
    }
    
    // MARK: - Создание слоёв
    
    func updateLines(lines: [LyricsLine], width: CGFloat, isCurrent: Bool, animated: Bool, settings: SettingsManager) {
        // Устанавливаем ширину контейнера — от неё зависит раскладка и кэш картинок.
        containerLayer.frame = NSRect(x: 0, y: 0, width: max(width, 1), height: 0)
        
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
        
        for (index, line) in lines.enumerated() where line.tag != "note" {
            if line.tag == "inst" {
                createInstLayers(line: line, isCurrent: isCurrent, settings: settings)
                continue
            }
            
            if settings.lrcWordHighlight && line.hasWords {
                createWordLayers(line: line, isCurrent: isCurrent, settings: settings)
                continue
            }
            
            let fontSize: CGFloat
            if line.isMain || index == 0 {
                fontSize = 17
            } else if index == 1 {
                fontSize = lines.count >= 3 ? 12 : 13
            } else {
                fontSize = 12
            }
            
            lineFontSizes.append(fontSize)
            createTextLayers(line: line, fontSize: fontSize, isCurrent: isCurrent, settings: settings)
        }
        
        if let noteLine = lines.first(where: { $0.tag == "note" && (settings.lrcEnabledTags["note"] ?? false) }) {
            updateNoteButton(line: noteLine, settings: settings)
        } else {
            noteButtonLayer?.isHidden = true
        }
    }
    
    // MARK: - Words
    
    private func createWordLayers(line: LyricsLine, isCurrent: Bool, settings: SettingsManager) {
        let fontSize: CGFloat = 17
        lineFontSizes.append(fontSize)
        
        let activeColor = getColor(for: line, isCurrent: true, settings: settings)
        let inactiveColor = getColor(for: line, isCurrent: false, settings: settings)
        let width = containerLayer.frame.width > 0 ? containerLayer.frame.width : 400
        
        let weight: NSFont.Weight = .regular
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
            inactiveLayer.opacity = 1
            
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
    
    func updateWordHighlight(currentTime: TimeInterval) {
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
            
            inactive.opacity = 1.0
            
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
    
    private func createInstLayers(line: LyricsLine, isCurrent: Bool, settings: SettingsManager) {
        let timerLayer = CALayer()
        let timerColor = getColor(for: line, isCurrent: isCurrent, settings: settings)
        timerLayer.contents = getCachedText("♪", color: timerColor, fontSize: 10, weight: .regular, width: containerLayer.frame.width)
        timerLayer.contentsGravity = .center
        timerLayer.contentsScale = backingScale
        timerLayer.frame = NSRect(x: 0, y: 0, width: containerLayer.frame.width, height: 14)
        timerLayer.isHidden = !isCurrent
        timerLayer.opacity = isCurrent ? 1.0 : 0.0
        containerLayer.addSublayer(timerLayer)
        instTimerLayer = timerLayer
        
        let fontSize: CGFloat = 16
        lineFontSizes.append(fontSize)
        createTextLayers(line: line, fontSize: fontSize, isCurrent: isCurrent, settings: settings)
    }
    
    // MARK: - Text
    
    private func createTextLayers(line: LyricsLine, fontSize: CGFloat, isCurrent: Bool, settings: SettingsManager) {
        let activeColor = getColor(for: line, isCurrent: true, settings: settings)
        let inactiveColor = getColor(for: line, isCurrent: false, settings: settings)
        let displayText = line.text.isEmpty ? "♪" : line.text
        let width = containerLayer.frame.width > 0 ? containerLayer.frame.width : 400
        
        let weight: NSFont.Weight = .regular
        
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
        inactiveLayer.opacity = isCurrent ? 0.0 : 1.0
        
        lineLayers.append((inactive: inactiveLayer, active: activeLayer, line: line))
    }
    
    func updateInstTimer(text: String, settings: SettingsManager) {
        guard let instTimerLayer else { return }
        let color = NSColor(hex: settings.lrcTagColors["inst"] ?? "#888888") ?? .white
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
        
        first.active.contents = getCachedText(text, color: settings.lyricActiveNSColor, fontSize: fontSize, weight: .regular, width: width)
        first.inactive.contents = getCachedText("♪", color: settings.lyricInactiveNSColor, fontSize: fontSize, weight: .regular, width: width)
    }
    
    // MARK: - Highlight
    
    func setHighlighted(_ highlighted: Bool, animated: Bool, settings: SettingsManager) {
        if highlighted {
            needsProgressReset = true
        }
        
        let duration: CFTimeInterval = animated ? 0.25 : 0
        
        for layer in lineLayers {
            animateOpacity(layer.active, to: highlighted ? 1 : 0, duration: duration)
            animateOpacity(layer.inactive, to: highlighted ? 0 : 1, duration: duration)
        }
        
        if !highlighted {
            for wordLayer in wordLayers {
                animateOpacity(wordLayer.active, to: 0, duration: duration)
                animateOpacity(wordLayer.inactive, to: 1, duration: duration)
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
        
        if let instTimerLayer, !instTimerLayer.isHidden {
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
            let weight: NSFont.Weight = .regular
            
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
        
        let noteColor = NSColor(hex: settings.lrcTagColors["note"] ?? "#888888") ?? .white
        if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?.tinted(with: noteColor) {
            noteButtonLayer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        noteButtonLayer?.contentsScale = backingScale
        noteButtonLayer?.isHidden = false
    }
    
    // MARK: - Colors
    
    private func getColor(for line: LyricsLine, isCurrent: Bool, settings: SettingsManager) -> NSColor {
        guard let tag = line.tag else {
            return isCurrent ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
        }
        
        let hex = line.isMain
            ? (settings.lrcTagColors["orig"] ?? "#FFFFFF")
            : (settings.lrcTagColors[tag] ?? "#888888")
        
        let baseColor = NSColor(hex: hex) ?? .white
        if isCurrent { return baseColor }
        if settings.lrcDimInactive {
            return baseColor.withAlphaComponent(baseColor.alphaComponent * 0.4)
        }
        return settings.lyricInactiveNSColor
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
        
        if let cached = Self.textCache[cacheKey] {
            return cached
        }
        
        if Self.textCache.count >= Self.maxCacheSize {
            Self.textCache.removeAll()
        }
        
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
