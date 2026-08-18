// Views,LiquidGlass,LiquidGlassLyricsView.swift
import SwiftUI
import AppKit

// MARK: - Основной View

@available(macOS 26.0, *)
struct LiquidGlassLyricsView: View {
    let lyrics: [LyricsLine]
    let currentTime: TimeInterval
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
            guard let value = value, !value.isEmpty else { continue }
            guard settings.lrcMetadataFields[key] ?? false else { continue }
            let label = NSLocalizedString("lrc_meta_\(key)", comment: "")
            lines.append("\(label): \(value)")
        }
        return lines
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    private var showMetadata: Bool {
        guard settings.lrcShowMetadata, !metadataLines.isEmpty else { return false }
        guard !userScrolled else { return false }
        if settings.lrcMetadataPosition == "before" {
            let firstRealTime = lyrics.first(where: { !$0.text.isEmpty })?.time ?? 0
            return currentTime < firstRealTime
        } else {
            let lastTime = lyrics.last?.time ?? 0
            return currentTime > lastTime
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
                metadataView
                    .transition(.opacity)
            }
            
            ZStack(alignment: .bottom) {
                LiquidGlassNativeLyricsScroll(
                    lyrics: lyrics,
                    currentIndex: $currentIndex,
                    currentTime: currentTime,
                    userScrolled: $userScrolled,
                    hasInitialized: $hasInitialized,
                    canShowButton: $canShowButton,
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
                metadataView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showMetadata)
        .onChange(of: showMetadata) { showing in
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
        Button(action: {
            userScrolled = false
            NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
            NotificationCenter.default.post(name: .forceScrollNow, object: nil)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                Text(LocalizedStringKey("synch")).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glassEffect(.regular.interactive(true))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }
}
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
        button.title = ""
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

// MARK: - Native Scroll (AppKit-подход)

@available(macOS 26.0, *)
struct LiquidGlassNativeLyricsScroll: NSViewRepresentable {
    let lyrics: [LyricsLine]
    @Binding var currentIndex: Int
    let currentTime: TimeInterval
    @Binding var userScrolled: Bool
    @Binding var hasInitialized: Bool
    @Binding var canShowButton: Bool
    let onTapLine: ((TimeInterval) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = NSSize(width: 0, height: 12)
        tableView.selectionHighlightStyle = .none
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(Coordinator.tableViewClicked(_:))
        tableView.wantsLayer = true
        tableView.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lyrics"))
        column.width = scrollView.frame.width
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        if context.coordinator.updateTimer == nil {
            context.coordinator.setupUpdateTimer()
        }

        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollViewDidResize), name: NSView.frameDidChangeNotification, object: scrollView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.boundsDidChange), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.resetUserScrolled), name: .resetUserScrolled, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.forceScroll), name: .forceScrollNow, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToTop), name: .scrollLyricsToTop, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToIndexNotif(_:)), name: .scrollToIndex, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.lrcSettingsChanged), name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.applicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)

        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapLine = onTapLine
        coordinator.hasInitialized = hasInitialized
        coordinator.canShowButton = canShowButton

        if userScrolled != coordinator.isUserScrolled {
            coordinator.isUserScrolled = userScrolled
            if let tableView = nsView.documentView as? NSTableView {
                tableView.reloadData()
            }
        }

        let newIDs = lyrics.map { $0.id }
        if newIDs != coordinator.lastLyricsID {
            coordinator.updateLyrics(lyrics)
            if let tableView = nsView.documentView as? NSTableView {
                tableView.reloadData()
            }
        }

        coordinator.currentTime = currentTime

        DispatchQueue.main.async {
            if self.currentIndex != coordinator.currentIndex {
                self.currentIndex = coordinator.currentIndex
            }
        }
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
        var lyrics: [LyricsLine] = []
        var currentIndex: Int = -1
        var currentTime: TimeInterval = 0
        var isUserScrolled: Bool = false
        var hasInitialized: Bool = false
        var canShowButton: Bool = false
        var onTapLine: ((TimeInterval) -> Void)?
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?

        private var isAnimating = false
        private var lastProgrammaticScroll: Date = Date.distantPast
        private var animationQueue: [Int] = []
        var suppressReload: Bool = false
        var activePopover: NSPopover?
        var activeNoteRow: Int = -1
        var lastLyricsID: [UUID] = []
        private var isProgrammaticScroll = false
        
        var updateTimer: Timer?
        private var lastScrollTarget: CGFloat = -1
        private var lastTimerUpdate = Date.distantPast

        private var settings: SettingsManager { SettingsManager.shared }
        private var visibleLyrics: [LyricsLine] {
            if useAdvancedMode { return lyrics }
            return lyrics.filter { $0.tag == nil }
        }
        var groups: [LyricsGroup] = []
        private var useAdvancedMode: Bool = false

        private lazy var sizingCell: NSTableCellView = NSTableCellView(frame: .zero)
        private var heightCache: [Int: CGFloat] = [:]
        private var heightCacheWidth: CGFloat = -1

        func setupUpdateTimer() {
            updateTimer?.invalidate()

            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.timerTick()
            }

            RunLoop.main.add(timer, forMode: .common)
            updateTimer = timer
        }

        private func timerTick() {
            guard hasInitialized, !lyrics.isEmpty else { return }
            updateIndexAndScroll()
            updateInstrumentalTimers()
        }

        private func processQueue() {
            guard !animationQueue.isEmpty else { return }
            let nextRow = animationQueue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.performScrollToRow(nextRow, force: false)
            }
        }

        private func updateInstrumentalTimers() {
            guard let tableView = tableView else { return }

            let hasInstrumental = useAdvancedMode
                ? groups.contains(where: { $0.lines.contains { $0.tag == "inst" } })
                : visibleLyrics.contains(where: { $0.text.isEmpty })

            guard hasInstrumental else { return }

            let now = Date()
            guard now.timeIntervalSince(lastTimerUpdate) >= 0.1 else { return }
            lastTimerUpdate = now

            let visibleRange = tableView.rows(in: tableView.visibleRect)
            let startRow = max(0, visibleRange.location)
            let endRow = min(startRow + visibleRange.length, tableView.numberOfRows - 1)

            guard startRow <= endRow else { return }

            for row in startRow...endRow {
                var shouldUpdate = false

                if useAdvancedMode {
                    guard row >= 0 && row < groups.count else { continue }
                    shouldUpdate = groups[row].lines.contains(where: { $0.tag == "inst" })
                } else {
                    guard row >= 0 && row < visibleLyrics.count else { continue }
                    shouldUpdate = visibleLyrics[row].text.isEmpty
                }

                if shouldUpdate, let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                    updateTimerText(in: cellView, row: row)
                }
            }
        }

        private func updateTimerText(in cellView: NSView, row: Int) {
            for subview in cellView.subviews {
                if let textField = subview as? NSTextField,
                   textField.identifier?.rawValue == "timerLabel" {
                    let newText: String
                    if useAdvancedMode {
                        newText = getGroupForRow(row).map { getRemainingTime(for: $0) } ?? "♪"
                    } else {
                        if row < visibleLyrics.count, row == currentIndex {
                            let line = visibleLyrics[row]
                            let remaining = line.pauseUntil.map { max(0, $0 - currentTime) } ?? 0
                            newText = remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
                        } else {
                            newText = "♪"
                        }
                    }
                    if textField.stringValue != newText {
                        textField.stringValue = newText
                    }
                }
            }
        }

        private func invalidateHeightCache() {
            heightCache.removeAll()
        }

        private func rebuildGroups() {
            groups = LyricsParser.groupLines(lyrics)
            groups = groups.filter { group in
                let lines = getVisibleLines(from: group, limit: 5)
                return !lines.isEmpty
            }
            for i in 0..<groups.count {
                if groups[i].lines.contains(where: { $0.tag == "inst" }) {
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
            }
            useAdvancedMode = shouldUseAdvancedMode()
            invalidateHeightCache()
        }

        private func shouldUseAdvancedMode() -> Bool {
            switch settings.lrcMode {
            case "on": return true
            case "off": return false
            case "auto": return lyrics.contains { $0.tag != nil }
            default: return false
            }
        }

        func updateLyrics(_ newLyrics: [LyricsLine]) {
            let lyricsChanged = lyrics.count != newLyrics.count ||
                                zip(lyrics, newLyrics).contains {
                                    $0.id != $1.id ||
                                    $0.text != $1.text ||
                                    $0.tag != $1.tag
                                }

            guard lyricsChanged else { return }

            let currentLineTime = currentIndex >= 0 && currentIndex < lyrics.count
                ? lyrics[currentIndex].time
                : nil

            lyrics = newLyrics
            lastLyricsID = newLyrics.map { $0.id }
            rebuildGroups()
            invalidateHeightCache()
            lastScrollTarget = -1

            if let time = currentLineTime {
                currentIndex = findIndex(for: time)
            } else {
                currentIndex = -1
            }
        }

        private func findIndex(for time: TimeInterval) -> Int {
            if useAdvancedMode {
                return groups.lastIndex(where: { $0.time <= time }) ?? -1
            } else {
                return visibleLyrics.lastIndex(where: { $0.time <= time }) ?? -1
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            return useAdvancedMode ? groups.count : visibleLyrics.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cellView: NSView?
            if useAdvancedMode {
                cellView = createAdvancedCell(row: row)
            } else {
                cellView = createSimpleCell(row: row)
            }

            if let cellView = cellView {
                DispatchQueue.main.async { [weak self] in
                    self?.updateTimerText(in: cellView, row: row)
                }
            }

            return cellView
        }

        private func createSimpleCell(row: Int) -> NSView? {
            guard row >= 0, row < visibleLyrics.count else { return nil }
            let line = visibleLyrics[row]
            let distance = abs(row - currentIndex)
            let isCurrent = row == currentIndex

            let cell = NSTableCellView()
            let opacity: CGFloat

            if isUserScrolled {
                opacity = isCurrent ? 1.0 : 0.8
            } else {
                opacity = max(0.2, 1.0 - Double(distance) * 0.2)
            }

            if line.text.isEmpty {
                let displayText: String
                if isCurrent {
                    let remaining = line.pauseUntil.map { max(0, $0 - currentTime) } ?? 0
                    displayText = remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
                } else {
                    displayText = "♪"
                }

                let label = NSTextField(labelWithString: displayText)
                label.alignment = .center
                label.font = NSFont.systemFont(ofSize: 16)
                label.textColor = isCurrent ? NSColor.controlAccentColor.withAlphaComponent(0.6) : NSColor.labelColor.withAlphaComponent(opacity * 0.4)
                label.identifier = NSUserInterfaceItemIdentifier("timerLabel")
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                let label = NSTextField(labelWithString: line.text)
                label.alignment = .center
                label.font = isCurrent ? NSFont.systemFont(ofSize: 17, weight: .semibold) : NSFont.systemFont(ofSize: 15)
                label.textColor = isCurrent ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(opacity)
                label.lineBreakMode = .byWordWrapping
                label.maximumNumberOfLines = 0
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    label.widthAnchor.constraint(equalTo: cell.widthAnchor, constant: -16)
                ])
            }
            return cell
        }

        private func createAdvancedCell(row: Int) -> NSView? {
            guard row >= 0, row < groups.count else { return nil }
            let group = groups[row]
            let distance = abs(row - currentIndex)
            let isActive = row == currentIndex
            let width = max(tableView?.bounds.width ?? 0, 1)

            let container = NSView()
            let visibleLines = getVisibleLines(from: group, limit: 5)
            let noteLine = group.lines.first(where: { $0.tag == "note" && isTagEnabled("note") })
            let lineSpacing: CGFloat = 8
            let topPadding: CGFloat = 4
            let bottomPadding: CGFloat = 4
            var previousView: NSView?

            for (index, line) in visibleLines.enumerated() {
                let fontSize = getFontSize(for: index, total: visibleLines.count)
                let color = getColorForLiquidGlass(for: line, isActive: isActive, distance: distance)

                if line.tag == "inst" {
                    let timerLabel = NSTextField(labelWithString: getRemainingTime(for: group))
                    timerLabel.alignment = .center
                    timerLabel.font = NSFont.systemFont(ofSize: 10)
                    timerLabel.textColor = color.withAlphaComponent(0.6)
                    timerLabel.lineBreakMode = .byWordWrapping
                    timerLabel.maximumNumberOfLines = 0
                    timerLabel.isHidden = !isActive
                    timerLabel.identifier = NSUserInterfaceItemIdentifier("timerLabel")
                    container.addSubview(timerLabel)
                    timerLabel.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        timerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                        timerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                        timerLabel.topAnchor.constraint(equalTo: previousView?.bottomAnchor ?? container.topAnchor, constant: previousView == nil ? topPadding : 2)
                    ])
                    if isActive { previousView = timerLabel }

                    let label = NSTextField(labelWithString: line.text.isEmpty ? "♪" : line.text)
                    label.alignment = .center
                    label.font = NSFont.systemFont(ofSize: 16)
                    label.textColor = color
                    label.lineBreakMode = .byWordWrapping
                    label.maximumNumberOfLines = 0
                    container.addSubview(label)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    let topConstant: CGFloat = isActive ? 2 : topPadding
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                        label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                        label.topAnchor.constraint(equalTo: previousView?.bottomAnchor ?? container.topAnchor, constant: topConstant)
                    ])
                    previousView = label
                    continue
                }

                let label = NSTextField(labelWithString: line.text)
                label.alignment = .center
                label.font = NSFont.systemFont(ofSize: fontSize, weight: isActive && index == 0 ? .semibold : .regular)
                label.textColor = color
                label.lineBreakMode = .byWordWrapping
                label.maximumNumberOfLines = 0
                label.preferredMaxLayoutWidth = max(0, width - 32)
                container.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                let topConstant: CGFloat = (previousView == nil) ? topPadding : lineSpacing
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                    label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                    label.topAnchor.constraint(equalTo: previousView?.bottomAnchor ?? container.topAnchor, constant: topConstant)
                ])
                previousView = label
            }

            if let lastView = previousView {
                lastView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomPadding).isActive = true
            }

            if let note = noteLine {
                let noteButton = NSButton()
                noteButton.title = ""
                noteButton.bezelStyle = .inline
                noteButton.isBordered = false
                noteButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
                noteButton.image?.size = NSSize(width: 12, height: 12)
                noteButton.contentTintColor = NSColor(hex: settings.lrcTagColors["note"] ?? "#888888") ?? NSColor.labelColor
                noteButton.target = self
                noteButton.action = #selector(toggleNote(_:))
                noteButton.tag = row
                container.addSubview(noteButton)
                noteButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    noteButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                    noteButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                    noteButton.widthAnchor.constraint(equalToConstant: 14),
                    noteButton.heightAnchor.constraint(equalToConstant: 14)
                ])
            }

            let cell = NSTableCellView()
            cell.addSubview(container)
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                container.topAnchor.constraint(equalTo: cell.topAnchor),
                container.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
            ])
            return cell
        }

        private func getRemainingTime(for group: LyricsGroup) -> String {
            guard let until = group.pauseUntil else { return "♪" }
            let remaining = max(0, until - currentTime)
            return remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
        }

        private func getColorForLiquidGlass(for line: LyricsLine, isActive: Bool, distance: Int) -> NSColor {
            guard let tag = line.tag else {
                if isActive { return NSColor.controlAccentColor }
                let opacity: CGFloat = isUserScrolled ? 0.8 : max(0.2, 1.0 - Double(distance) * 0.2)
                return NSColor.labelColor.withAlphaComponent(opacity)
            }

            let hex = settings.lrcTagColors[tag] ?? "#FFFFFF"
            let baseColor = NSColor(hex: hex) ?? NSColor.labelColor
            if isActive { return baseColor }

            let opacity: CGFloat = isUserScrolled ? 0.8 : max(0.2, 1.0 - Double(distance) * 0.2)
            return baseColor.withAlphaComponent(opacity)
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

            for line in group.lines {
                guard result.count < limit, let tag = line.tag else { continue }
                if LyricsParser.pronunciationTags.contains(tag) && isTagEnabled(tag) && !result.contains(where: { $0.id == line.id }) {
                    result.append(line)
                }
            }

            for line in group.lines {
                guard result.count < limit, let tag = line.tag else { continue }
                if tag == "trans" && isTagEnabled("trans") && !result.contains(where: { $0.id == line.id }) {
                    result.append(line)
                }
            }

            for line in group.lines {
                guard result.count < limit, let tag = line.tag else { continue }
                if LyricsParser.languageTags.contains(tag) && isTagEnabled(tag) && !result.contains(where: { $0.id == line.id }) {
                    result.append(line)
                }
            }

            for line in group.lines {
                guard result.count < limit, let tag = line.tag else { continue }
                if LyricsParser.specialTags.contains(tag), isTagEnabled(tag), tag != "inst", tag != "orig", tag != "trans", tag != "note", !result.contains(where: { $0.id == line.id }) {
                    result.append(line)
                }
            }

            return Array(result.prefix(limit))
        }

        private func isTagEnabled(_ tag: String) -> Bool {
            settings.lrcEnabledTags[tag] ?? false
        }

        private func getFontSize(for index: Int, total: Int) -> CGFloat {
            switch index {
            case 0: return 17
            case 1: return total >= 3 ? 11 : 13
            case 2: return 11
            default: return 11
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0 else { return 0 }

            if useAdvancedMode {
                guard row < groups.count else { return 0 }
                let width = max(tableView.bounds.width, 1)
                if width != heightCacheWidth {
                    heightCacheWidth = width
                    heightCache.removeAll()
                }
                if let cached = heightCache[row] { return cached }

                let height = calculateHeightForAdvancedCell(row: row, width: width)
                heightCache[row] = height
                return height
            } else {
                guard row < visibleLyrics.count else { return 0 }
                if visibleLyrics[row].text.isEmpty { return 16 }

                let font = NSFont.systemFont(ofSize: 15)
                let width = max(tableView.frame.width - 32, 1)
                let rect = (visibleLyrics[row].text as NSString).boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                )
                return min(max(rect.height + 16, 36), 300)
            }
        }
        private func calculateHeightForAdvancedCell(row: Int, width: CGFloat) -> CGFloat {
            guard row >= 0, row < groups.count else { return 36 }
            let group = groups[row]
            let visibleLines = getVisibleLines(from: group, limit: 5)

            var totalHeight: CGFloat = 8

            for (index, line) in visibleLines.enumerated() {
                if line.tag == "inst" {
                    totalHeight += 20
                    if index > 0 { totalHeight += 8 }
                    continue
                }

                let fontSize = getFontSize(for: index, total: visibleLines.count)
                let font = NSFont.systemFont(ofSize: fontSize,
                                             weight: index == 0 ? .semibold : .regular)
                let textWidth = max(width - 32, 1)
                let rect = (line.text as NSString).boundingRect(
                    with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                )
                totalHeight += ceil(rect.height) + (index > 0 ? 8 : 0)
            }

            return min(max(totalHeight, 12), 300)
        }
        @objc func scrollViewDidResize() {
            guard let tableView = tableView, !lyrics.isEmpty else { return }
            invalidateHeightCache()
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<max(lyrics.count, groups.count)))
        }

        @objc func lrcSettingsChanged() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.invalidateHeightCache()
                self.rebuildGroups()
                self.tableView?.reloadData()
                self.updateIndexAndScroll()
            }
        }

        @objc func tableViewClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, !isAnimating else { return }

            let time: TimeInterval
            if useAdvancedMode {
                guard row < groups.count else { return }
                time = groups[row].time
            } else {
                guard row < visibleLyrics.count else { return }
                time = visibleLyrics[row].time
            }

            onTapLine?(time)
            currentTime = time
            isUserScrolled = false
            lastScrollTarget = -1
            lastProgrammaticScroll = Date().addingTimeInterval(1.0)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .userDidSync, object: nil)
                NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
            }

            updateIndexAndScroll()
            tableView?.reloadData()

            animationQueue.removeAll()
            performScrollToRow(row, force: false)
        }

        @objc func resetUserScrolled() {
            isUserScrolled = false
            lastProgrammaticScroll = Date().addingTimeInterval(1.0)
            animationQueue.removeAll()
            lastScrollTarget = -1
            tableView?.reloadData()
        }

        @objc func boundsDidChange() {
            guard hasInitialized, !isAnimating else { return }
            let timeSinceProgrammaticScroll = Date().timeIntervalSince(lastProgrammaticScroll)
            guard timeSinceProgrammaticScroll > 0.15 else { return }
            guard !isProgrammaticScroll else { return }

            if let event = NSApp.currentEvent {
                let isUserEvent = event.type == .scrollWheel ||
                                  event.type == .leftMouseDragged ||
                                  event.type == .keyDown

                if isUserEvent, !isUserScrolled {
                    isUserScrolled = true
                    tableView?.reloadData()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .userDidScroll, object: nil)
                    }
                }
            }
        }

        @objc func toggleNote(_ sender: NSButton) {
            let row = sender.tag

            if let existingPopover = activePopover {
                existingPopover.close()
                activePopover = nil
            }

            suppressReload = false

            if activeNoteRow == row {
                activeNoteRow = -1
                return
            }

            guard row < groups.count else { return }
            let group = groups[row]
            guard let note = group.lines.first(where: { $0.tag == "note" && isTagEnabled("note") }) else { return }

            let textField = NSTextField(wrappingLabelWithString: note.text)
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.textColor = NSColor.labelColor
            textField.lineBreakMode = .byWordWrapping
            textField.preferredMaxLayoutWidth = 250
            textField.isEditable = false
            textField.drawsBackground = false
            textField.backgroundColor = .clear

            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 100))
            containerView.wantsLayer = true
            containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            containerView.layer?.cornerRadius = 10
            containerView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
                textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
                textField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
                textField.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14)
            ])

            let controller = NSViewController()
            controller.view = containerView

            let popover = NSPopover()
            popover.contentViewController = controller
            popover.behavior = .transient
            popover.delegate = self

            activePopover = popover
            activeNoteRow = row
            suppressReload = true

            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        func popoverDidClose(_ notification: Notification) {
            if let popover = notification.object as? NSPopover,
               popover === activePopover {
                activePopover = nil
            }

            activeNoteRow = -1
            suppressReload = false
        }

        func updateIndexAndScroll() {
            guard !lyrics.isEmpty, (useAdvancedMode ? !groups.isEmpty : !visibleLyrics.isEmpty) else {
                currentIndex = -1
                return
            }

            let oldIndex = currentIndex

            if useAdvancedMode {
                if groups.count > 100 {
                    let times = groups.map { $0.time }
                    currentIndex = binarySearch(in: times, for: currentTime)
                } else {
                    var idx = -1
                    for (i, group) in groups.enumerated() {
                        if currentTime >= group.time { idx = i } else { break }
                    }
                    currentIndex = idx
                }
            } else {
                var idx = -1
                for (i, line) in visibleLyrics.enumerated() {
                    if currentTime >= line.time { idx = i } else { break }
                }
                if idx == visibleLyrics.count - 1 && visibleLyrics[idx].text.isEmpty { idx = -1 }
                currentIndex = idx
            }

            if oldIndex != currentIndex, !suppressReload {
                var rowsToUpdate = IndexSet()

                if oldIndex >= 0 { rowsToUpdate.insert(oldIndex) }
                if currentIndex >= 0 { rowsToUpdate.insert(currentIndex) }

                for offset in -2...2 {
                    let row1 = oldIndex + offset
                    let row2 = currentIndex + offset

                    if row1 >= 0 { rowsToUpdate.insert(row1) }
                    if row2 >= 0 { rowsToUpdate.insert(row2) }
                }

                tableView?.reloadData(forRowIndexes: rowsToUpdate, columnIndexes: IndexSet(integer: 0))
            }

            if !isUserScrolled {
                autoScrollToCurrentPosition()
            }
        }
        private func binarySearch(in times: [TimeInterval], for time: TimeInterval) -> Int {
            var left = 0
            var right = times.count - 1
            var result = -1

            while left <= right {
                let mid = (left + right) / 2
                if times[mid] <= time {
                    result = mid
                    left = mid + 1
                } else {
                    right = mid - 1
                }
            }

            return result
        }

        private func autoScrollToCurrentPosition() {
            let lastTime = lyrics.last?.time ?? 0
            if currentTime >= lastTime { return }

            let count = useAdvancedMode ? groups.count : visibleLyrics.count
            guard count > 0 else { return }
            let targetRow = max(0, min(currentIndex, count - 1))
            if targetRow >= 0 {
                performScrollToRow(targetRow, force: false)
            }
        }

        private func performScrollToRow(_ row: Int, force: Bool) {
            guard let scrollView = scrollView, let tableView = tableView, row >= 0 else { return }

            let animationDuration: TimeInterval

            if force {
                animationDuration = 0
            } else {
                let rowRect = tableView.rect(ofRow: row)
                let targetY = rowRect.minY - 40
                let maxY = max(0, tableView.frame.height - tableView.visibleRect.height)
                let clampedY = min(max(0, targetY), maxY)
                let currentOrigin = scrollView.contentView.bounds.origin
                let distance = abs(currentOrigin.y - clampedY)
                animationDuration = min(0.45, max(0.2, distance / 500))
            }

            isProgrammaticScroll = true

            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) { [weak self] in
                self?.isProgrammaticScroll = false
            }

            if force {
                isAnimating = false
                animationQueue.removeAll()
                let rowRect = tableView.rect(ofRow: row)
                let targetY = rowRect.minY - 40
                let maxY = max(0, tableView.frame.height - tableView.visibleRect.height)
                let clampedY = min(max(0, targetY), maxY)
                scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                lastProgrammaticScroll = Date()
                lastScrollTarget = clampedY
                return
            }

            let rowRect = tableView.rect(ofRow: row)
            let visibleRect = tableView.visibleRect
            let targetY = rowRect.minY - 40
            let maxY = max(0, tableView.frame.height - visibleRect.height)
            let clampedY = min(max(0, targetY), maxY)

            if abs(clampedY - lastScrollTarget) < 1 { return }
            lastScrollTarget = clampedY

            let currentOrigin = scrollView.contentView.bounds.origin
            let distance = abs(currentOrigin.y - clampedY)

            if distance < 1 { return }
            if isAnimating { return }

            isAnimating = true
            lastProgrammaticScroll = Date()

            NSAnimationContext.runAnimationGroup { [weak self] context in
                guard let self = self else { return }
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.completionHandler = {
                    DispatchQueue.main.async { [weak self] in
                        self?.isAnimating = false
                        self?.processQueue()
                    }
                }
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
            }
        }

        @objc func forceScroll() {
            lastScrollTarget = -1
            autoScrollToCurrentPosition()
        }

        @objc func scrollToTop() {
            performScrollToRow(0, force: true)
        }

        @objc func scrollToIndexNotif(_ notification: Notification) {
            guard let index = notification.object as? Int, !isUserScrolled else { return }
            animationQueue.removeAll()
            performScrollToRow(index, force: true)
        }

        @objc func applicationDidBecomeActive() {
            if !isUserScrolled {
                lastScrollTarget = -1
                autoScrollToCurrentPosition()
            }
        }

        func getGroupForRow(_ row: Int) -> LyricsGroup? {
            guard row >= 0, row < groups.count else { return nil }
            return groups[row]
        }

        deinit {
            updateTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
