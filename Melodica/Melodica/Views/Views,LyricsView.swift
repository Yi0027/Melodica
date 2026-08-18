// Views,LyricsView.swift
import SwiftUI
import AppKit

extension Notification.Name {
    static let splitterDidResize = Notification.Name("splitterDidResize")
    static let resetUserScrolled = Notification.Name("ResetUserScrolled")
    static let userDidScroll = Notification.Name("UserDidScroll")
    static let scrollLyricsToTop = Notification.Name("ScrollLyricsToTop")
    static let forceScrollNow = Notification.Name("ForceScrollNow")
    static let scrollToIndex = Notification.Name("ScrollToIndex")
    static let userDidSync = Notification.Name("UserDidSync")
}

struct LyricsView: View {
    let lyrics: [LyricsLine]
    let currentTime: TimeInterval
    @Binding var userScrolled: Bool
    let trackId: UUID?
    let onTapLine: ((TimeInterval) -> Void)?
    
    @State private var currentIndex: Int = -1
    @State private var canShowButton: Bool = false
    @State private var hasInitialized: Bool = false
    
    private var settings: SettingsManager { SettingsManager.shared }

    private var metadataView: some View {
        VStack(spacing: 2) {
            ForEach(metadataLines, id: \.self) { text in
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: NSColor(hex: settings.lrcMetadataColor) ?? .gray))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(settings.darkBg.opacity(0.5))
    }

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
        guard !userScrolled else { return false } // Не показываем если пользователь скроллит
        
        if settings.lrcMetadataPosition == "before" {
            let firstRealTime = lyrics.first(where: { !$0.text.isEmpty })?.time ?? 0
            return currentTime < firstRealTime
        } else {
            let lastTime = lyrics.last?.time ?? 0
            return currentTime > lastTime
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showMetadata && settings.lrcMetadataPosition == "before" {
                metadataView
                    .transition(.opacity)
            }
            
            ZStack(alignment: .bottom) {
                NativeLyricsScroll(
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
                .onReceive(NotificationCenter.default.publisher(for: .userDidScroll)) { _ in userScrolled = true }
                .onReceive(NotificationCenter.default.publisher(for: .userDidSync)) { _ in userScrolled = false }
                
                if userScrolled && canShowButton {
                    syncButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.4), value: userScrolled)
                }
            }
            
            if showMetadata && settings.lrcMetadataPosition == "after" {
                metadataView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showMetadata)
        .onChange(of: showMetadata) { showing in
            // Принудительная синхронизация при появлении И исчезновении метаданных
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

// MARK: - Native Scroll

struct NativeLyricsScroll: NSViewRepresentable {
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
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lyrics"))
        column.width = scrollView.frame.width
        tableView.addTableColumn(column)
        
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollViewDidResize), name: NSView.frameDidChangeNotification, object: scrollView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.boundsDidChange), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.resetUserScrolled), name: .resetUserScrolled, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.forceScroll), name: .forceScrollNow, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToTop), name: .scrollLyricsToTop, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToIndexNotif(_:)), name: .scrollToIndex, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.themeDidChange), name: NSNotification.Name("themeDidChange"), object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.lrcSettingsChanged), name: NSNotification.Name("lrcSettingsChanged"), object: nil)
        
        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.currentIndex = currentIndex
        coordinator.hasInitialized = hasInitialized
        coordinator.canShowButton = canShowButton
        coordinator.lyrics = lyrics
        coordinator.onTapLine = onTapLine
        coordinator.currentTime = currentTime
        
        if userScrolled != coordinator.isUserScrolled {
            coordinator.isUserScrolled = userScrolled
        }
        
        if let tableView = nsView.documentView as? NSTableView {
            if !coordinator.suppressReload {
                tableView.reloadData()
                if !lyrics.isEmpty {
                    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<lyrics.count))
                }
            }
            coordinator.updateIndexAndScroll()
        }
    }
}

// MARK: - Coordinator

extension NativeLyricsScroll {
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
        var lyrics: [LyricsLine] = []
        var currentIndex: Int = -1 {
            didSet {
                guard oldValue != currentIndex else { return }
                invalidateHeightCache(forRows: [oldValue, currentIndex])
            }
        }
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
        
        private var settings: SettingsManager { SettingsManager.shared }
        private var visibleLyrics: [LyricsLine] {
            if useAdvancedMode { return lyrics }
            return lyrics.filter { $0.tag == nil }
        }
        
        var groups: [LyricsGroup] = []
        private var useAdvancedMode: Bool = false
        
        // MARK: - Height measurement cache
        
        private lazy var sizingCell: NSTableCellView = NSTableCellView(frame: .zero)
        private var heightCache: [Int: CGFloat] = [:]
        private var heightCacheWidth: CGFloat = -1
        
        private func invalidateHeightCache() {
            heightCache.removeAll()
        }
        
        private func invalidateHeightCache(forRows rows: [Int]) {
            for row in rows where row >= 0 {
                heightCache.removeValue(forKey: row)
            }
            guard let tableView = tableView else { return }
            let valid = rows.filter { $0 >= 0 && $0 < groups.count }
            if !valid.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(valid))
            }
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
            case "auto":
                return lyrics.contains { $0.tag != nil }
            default: return false
            }
        }
        
        // MARK: - TableView DataSource
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            rebuildGroups()
            return useAdvancedMode ? groups.count : visibleLyrics.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if useAdvancedMode {
                return advancedCell(row: row)
            } else {
                return simpleCell(row: row)
            }
        }
        
        // MARK: - Simple cell
        
        private func simpleCell(row: Int) -> NSView? {
            guard row < visibleLyrics.count else { return nil }
            let line = visibleLyrics[row]
            let isCurrent = row == currentIndex
            
            let cell = NSTableCellView()
            
            if line.text.isEmpty {
                let displayText: String
                if isCurrent {
                    let pauseUntil = line.pauseUntil
                    let remaining: TimeInterval
                    if let until = pauseUntil { remaining = max(0, until - currentTime) }
                    else { remaining = 0 }
                    displayText = remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
                } else {
                    displayText = "♪"
                }
                
                let label = NSTextField(labelWithString: displayText)
                label.alignment = .center
                label.font = NSFont.systemFont(ofSize: 16)
                label.textColor = isCurrent ? settings.lyricActiveNSColor.withAlphaComponent(0.6) : settings.lyricInactiveNSColor.withAlphaComponent(0.4)
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                let label = NSTextField(labelWithString: line.text)
                label.alignment = .center
                label.font = isCurrent ? NSFont.systemFont(ofSize: 17) : NSFont.systemFont(ofSize: 15)
                label.textColor = isCurrent ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
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
        
        // MARK: - Advanced cell content
        
        private func advancedCellContent(row: Int, width: CGFloat) -> NSView? {
            guard row < groups.count else { return nil }
            let group = groups[row]
            let isActive = row == currentIndex
            
            let container = NSView()
            
            let visibleLines = getVisibleLines(from: group, limit: 5)
            let noteLine = group.lines.first(where: { $0.tag == "note" && isTagEnabled("note") })
            let hasNote = noteLine != nil
            
            let lineSpacing: CGFloat = 8
            let topPadding: CGFloat = 4
            let bottomPadding: CGFloat = 4
            
            var previousView: NSView?
            
            for (index, line) in visibleLines.enumerated() {
                let fontSize = getFontSize(for: index, total: visibleLines.count)
                let color = getColor(for: line, isActive: isActive)
                
                if line.tag == "inst" {
                    let remaining = getRemainingTime(for: group)
                    
                    let timerLabel = NSTextField(labelWithString: remaining)
                    timerLabel.alignment = .center
                    timerLabel.font = NSFont.systemFont(ofSize: 10)
                    timerLabel.textColor = color.withAlphaComponent(0.6)
                    timerLabel.lineBreakMode = .byWordWrapping
                    timerLabel.maximumNumberOfLines = 0
                    timerLabel.isHidden = !isActive
                    container.addSubview(timerLabel)
                    timerLabel.translatesAutoresizingMaskIntoConstraints = false
                    
                    NSLayoutConstraint.activate([
                        timerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                        timerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                        timerLabel.topAnchor.constraint(equalTo: previousView?.bottomAnchor ?? container.topAnchor,
                                                       constant: previousView == nil ? topPadding : 2)
                    ])
                    
                    if isActive {
                        previousView = timerLabel
                    }
                    
                    let displayText = line.text.isEmpty ? "♪" : line.text
                    let label = NSTextField(labelWithString: displayText)
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
                label.font = NSFont.systemFont(ofSize: fontSize)
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
                let noteIcon = NSButton()
                noteIcon.title = ""
                noteIcon.bezelStyle = .inline
                noteIcon.isBordered = false
                noteIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
                noteIcon.image?.size = NSSize(width: 12, height: 12)
                let noteColorHex = settings.lrcTagColors["note"] ?? "#888888"
                noteIcon.contentTintColor = NSColor(hex: noteColorHex) ?? .white
                noteIcon.alphaValue = CGFloat(settings.lrcNoteIconOpacity / 100)
                noteIcon.wantsLayer = true
                noteIcon.target = self
                noteIcon.action = #selector(Coordinator.toggleNote(_:))
                noteIcon.tag = row
                
                container.addSubview(noteIcon)
                noteIcon.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    noteIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                    noteIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                    noteIcon.widthAnchor.constraint(equalToConstant: 14),
                    noteIcon.heightAnchor.constraint(equalToConstant: 14)
                ])
            }
            
            return container
        }
        
        private func advancedCell(row: Int) -> NSView? {
            let width = (tableView?.bounds.width ?? 0)
            guard let content = advancedCellContent(row: row, width: width) else { return nil }
            
            let cell = NSTableCellView()
            cell.addSubview(content)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                content.topAnchor.constraint(equalTo: cell.topAnchor),
                content.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
            ])
            return cell
        }

        private func getRemainingTime(for group: LyricsGroup) -> String {
            guard let until = group.pauseUntil else { return "♪" }
            let remaining = max(0, until - currentTime)
            if remaining > 0 {
                return String(format: "♪ %0.1fс", remaining)
            }
            return "♪"
        }
        
        // MARK: - Helpers
        
        private func getVisibleLines(from group: LyricsGroup, limit: Int) -> [LyricsLine] {
            if let inst = group.lines.first(where: { $0.tag == "inst" }) {
                if isTagEnabled("inst") {
                    return [inst]
                }
            }
            
            var result: [LyricsLine] = []
            
            if let mainLine = group.lines.first(where: { $0.isMain && isTagEnabled($0.tag ?? "orig") }) {
                result.append(mainLine)
            } else {
                if let fallback = group.lines.first(where: { line in
                    guard let tag = line.tag else { return false }
                    return !LyricsParser.specialTags.contains(tag)
                }) {
                    var mainFallback = fallback
                    mainFallback.isMain = true
                    result.append(mainFallback)
                }
            }
            
            for line in group.lines {
                guard result.count < limit else { break }
                guard let tag = line.tag else { continue }
                if LyricsParser.pronunciationTags.contains(tag) && isTagEnabled(tag) {
                    if !result.contains(where: { $0.id == line.id }) {
                        result.append(line)
                    }
                }
            }
            
            for line in group.lines {
                guard result.count < limit else { break }
                guard let tag = line.tag else { continue }
                if tag == "trans" && isTagEnabled("trans") {
                    if !result.contains(where: { $0.id == line.id }) {
                        result.append(line)
                    }
                }
            }
            
            for line in group.lines {
                guard result.count < limit else { break }
                guard let tag = line.tag else { continue }
                if LyricsParser.languageTags.contains(tag) && isTagEnabled(tag) {
                    if !result.contains(where: { $0.id == line.id }) {
                        result.append(line)
                    }
                }
            }
            
            for line in group.lines {
                guard result.count < limit else { break }
                guard let tag = line.tag else { continue }
                if LyricsParser.specialTags.contains(tag) && isTagEnabled(tag) && tag != "inst" && tag != "orig" && tag != "trans" && tag != "note" {
                    if !result.contains(where: { $0.id == line.id }) {
                        result.append(line)
                    }
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
        
        private func getColor(for line: LyricsLine, isActive: Bool) -> NSColor {
            guard let tag = line.tag else {
                return isActive ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
            }
            
            if line.isMain {
                let hex = settings.lrcTagColors["orig"] ?? "#FFFFFF"
                let baseColor = NSColor(hex: hex) ?? NSColor.white
                if isActive {
                    return baseColor
                } else if settings.lrcDimInactive {
                    return baseColor.withAlphaComponent(baseColor.alphaComponent * 0.4)
                } else {
                    return settings.lyricInactiveNSColor
                }
            }
            
            let hex = settings.lrcTagColors[tag] ?? "#888888"
            let baseColor = NSColor(hex: hex) ?? NSColor.white
            
            if isActive {
                return baseColor
            } else if settings.lrcDimInactive {
                return baseColor.withAlphaComponent(baseColor.alphaComponent * 0.4)
            } else {
                return settings.lyricInactiveNSColor
            }
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if useAdvancedMode {
                guard row < groups.count else { return 36 }
                
                let width = tableView.bounds.width
                if width != heightCacheWidth {
                    heightCacheWidth = width
                    heightCache.removeAll()
                }
                if let cached = heightCache[row] {
                    return cached
                }
                
                guard let content = advancedCellContent(row: row, width: width) else { return 36 }
                
                sizingCell.subviews.forEach { $0.removeFromSuperview() }
                sizingCell.addSubview(content)
                content.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    content.leadingAnchor.constraint(equalTo: sizingCell.leadingAnchor),
                    content.trailingAnchor.constraint(equalTo: sizingCell.trailingAnchor),
                    content.topAnchor.constraint(equalTo: sizingCell.topAnchor),
                    content.bottomAnchor.constraint(equalTo: sizingCell.bottomAnchor)
                ])
                
                sizingCell.setFrameSize(NSSize(width: max(width, 1), height: 0))
                sizingCell.layoutSubtreeIfNeeded()
                let fitting = sizingCell.fittingSize
                
                let height = max(ceil(fitting.height), 12)
                heightCache[row] = height
                return height
            } else {
                guard row < visibleLyrics.count else { return 36 }
                if visibleLyrics[row].text.isEmpty { return 16 }
                let font = NSFont.systemFont(ofSize: 15)
                let width = tableView.frame.width - 32
                let rect = (visibleLyrics[row].text as NSString).boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                )
                return max(rect.height + 16, 36)
            }
        }
        
        // MARK: - Scroll & Index
        
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
            let time: TimeInterval
            if useAdvancedMode {
                guard row >= 0, row < groups.count else { return }
                time = groups[row].time
            } else {
                guard row >= 0, row < visibleLyrics.count else { return }
                time = visibleLyrics[row].time
            }
            onTapLine?(time)
            isUserScrolled = false
            DispatchQueue.main.async { NotificationCenter.default.post(name: .userDidSync, object: nil) }
            animationQueue.removeAll()
            performScrollToRow(row, force: true)
        }
        
        @objc func resetUserScrolled() {
            isUserScrolled = false
            lastProgrammaticScroll = Date().addingTimeInterval(1.0)
            animationQueue.removeAll()
        }
        
        @objc func boundsDidChange() {
            guard hasInitialized, !isAnimating else { return }
            let timeSinceProgrammaticScroll = Date().timeIntervalSince(lastProgrammaticScroll)
            guard timeSinceProgrammaticScroll > 0.15 else { return }

            if !isUserScrolled {
                isUserScrolled = true
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .userDidScroll, object: nil)
                }
            }
        }
        
        @objc func toggleNote(_ sender: NSButton) {
            let row = sender.tag
            
            activePopover?.close()
            activePopover = nil
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
            let noteColorHex = settings.lrcTagColors["note"] ?? "#888888"
            textField.textColor = NSColor(hex: noteColorHex) ?? NSColor(settings.textMain)
            textField.lineBreakMode = .byWordWrapping
            textField.preferredMaxLayoutWidth = 250
            textField.isEditable = false
            textField.drawsBackground = false
            textField.backgroundColor = .clear

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
            
            let controller = NSViewController()
            controller.view = containerView
            
            let popover = NSPopover()
            popover.contentViewController = controller
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = self
            
            activePopover = popover
            activeNoteRow = row
            suppressReload = true
            
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
        
        func popoverDidClose(_ notification: Notification) {
            activePopover = nil
            activeNoteRow = -1
            suppressReload = false
        }
        
        func updateIndexAndScroll() {
            guard !lyrics.isEmpty else { return }
            
            if useAdvancedMode {
                var idx = -1
                for (i, group) in groups.enumerated() {
                    if currentTime >= group.time { idx = i } else { break }
                }
                if idx != currentIndex { currentIndex = idx }
            } else {
                var idx = -1
                for (i, line) in visibleLyrics.enumerated() {
                    if currentTime >= line.time { idx = i } else { break }
                }
                if idx == visibleLyrics.count - 1 && visibleLyrics[idx].text.isEmpty { idx = -1 }
                if idx != currentIndex { currentIndex = idx }
            }
            
            if !isUserScrolled { autoScrollToCurrentPosition() }
        }
        
        private func autoScrollToCurrentPosition() {
            let count = useAdvancedMode ? groups.count : visibleLyrics.count
            guard count > 0 else { return }
            let targetRow = max(0, min(currentIndex, count - 1))
            if targetRow >= 0 { performScrollToRow(targetRow, force: false) }
        }
        
        private func performScrollToRow(_ row: Int, force: Bool) {
            guard let scrollView = scrollView, let tableView = tableView, row >= 0 else { return }
            
            if force { isAnimating = false; animationQueue.removeAll() }
            if isAnimating && !force {
                if animationQueue.last != row { animationQueue.append(row) }
                return
            }
            
            let rowRect = tableView.rect(ofRow: row)
            let visibleRect = tableView.visibleRect
            let targetY = rowRect.midY - visibleRect.height / 2
            let maxY = max(0, tableView.frame.height - visibleRect.height)
            let clampedY = min(max(0, targetY), maxY)
            
            let currentOrigin = scrollView.contentView.bounds.origin
            let distance = abs(currentOrigin.y - clampedY)
            if distance < 1 { processQueue(); return }
            
            isAnimating = true
            lastProgrammaticScroll = Date()
            let duration = min(0.25, max(0.1, distance / 800))
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.completionHandler = { [weak self] in
                    DispatchQueue.main.async {
                        self?.isAnimating = false
                        self?.processQueue()
                    }
                }
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
            }
        }
        
        private func processQueue() {
            guard !animationQueue.isEmpty else { return }
            let nextRow = animationQueue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.performScrollToRow(nextRow, force: false)
            }
        }
        
        @objc func forceScroll() { autoScrollToCurrentPosition() }
        @objc func scrollToTop() { performScrollToRow(0, force: true) }
        
        @objc func scrollToIndexNotif(_ notification: Notification) {
            guard let index = notification.object as? Int, !isUserScrolled else { return }
            animationQueue.removeAll()
            performScrollToRow(index, force: true)
        }
        
        @objc func themeDidChange() {
            DispatchQueue.main.async { [weak self] in
                self?.invalidateHeightCache()
                self?.tableView?.reloadData()
            }
        }
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((int >> 24) & 0xFF) / 255
            g = CGFloat((int >> 16) & 0xFF) / 255
            b = CGFloat((int >> 8) & 0xFF) / 255
            a = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    
    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#888888" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let a = Int(rgb.alphaComponent * 255)
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
