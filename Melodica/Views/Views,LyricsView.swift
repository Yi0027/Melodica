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
    @ObservedObject var progress: PlaybackProgress
    @Binding var userScrolled: Bool
    let trackId: UUID?
    let onTapLine: ((TimeInterval) -> Void)?
    
    private var currentTime: TimeInterval { progress.currentTime }
    
    @State private var currentIndex: Int = -1
    @State private var canShowButton: Bool = false
    @State private var hasInitialized: Bool = false
    
    private var settings: SettingsManager { SettingsManager.shared }
    @ObservedObject private var translationService = LyricsTranslationService.shared

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
        LyricsLogicEngine.metadataLines(metadata: LyricsParser.lastMetadata, settings: settings)
    }
    
    private var showMetadata: Bool {
        LyricsLogicEngine.shouldShowMetadata(
            lyrics: lyrics,
            currentTime: currentTime,
            userScrolled: userScrolled,
            settings: settings
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showMetadata && settings.lrcMetadataPosition == "before" {
                metadataView
                    .transition(.opacity)
            }
            
            if let unresolved = translationService.unresolvedRequest, unresolved.track.id == trackId {
                LyricsLanguageDetectionPopupView(request: unresolved, isLiquidGlass: false)
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
                .onChange(of: trackId) { resetState() }
                .onChange(of: lyrics.map(\.id)) { resetState() }
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
        .onChange(of: showMetadata) {
            // Forced synchronization when metadata appears or disappears
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
                let count = coordinator.rowCount
                if count > 0 {
                    tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<count))
                }
            }
            coordinator.updateIndexAndScroll()
        }
    }
}

// MARK: - Coordinator

extension NativeLyricsScroll {
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
        var lyrics: [LyricsLine] = [] {
            didSet {
                rebuildGroups()
            }
        }
        
        struct SimpleLyricsRow {
            let main: LyricsLine
            let trans: LyricsLine?
            var time: TimeInterval { main.time }
            var pauseUntil: TimeInterval? { main.pauseUntil }
        }
        
        private var simpleRows: [SimpleLyricsRow] {
            if useAdvancedMode { return [] }
            let includeTrans = settings.lrcAutoTranslate || (settings.lrcEnabledTags["trans"] ?? false)
            var rows: [SimpleLyricsRow] = []
            var i = 0
            while i < lyrics.count {
                let line = lyrics[i]
                if line.tag == "trans" {
                    i += 1
                    continue
                }
                var transLine: LyricsLine? = nil
                if includeTrans && (i + 1) < lyrics.count && lyrics[i + 1].tag == "trans" {
                    transLine = lyrics[i + 1]
                    i += 1
                }
                rows.append(SimpleLyricsRow(main: line, trans: transLine))
                i += 1
            }
            return rows
        }
        
        var rowCount: Int {
            useAdvancedMode ? groups.count : simpleRows.count
        }
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
            let count = useAdvancedMode ? groups.count : simpleRows.count
            let valid = rows.filter { $0 >= 0 && $0 < count }
            if !valid.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(valid))
            }
        }
        
        private func rebuildGroups() {
            let (g, adv) = LyricsLogicEngine.buildGroups(from: lyrics, settings: settings)
            groups = g
            useAdvancedMode = adv
            invalidateHeightCache()
        }
        
        private func shouldUseAdvancedMode() -> Bool {
            LyricsLogicEngine.shouldUseAdvancedMode(lyrics: lyrics, settings: settings)
        }
        
        // MARK: - TableView DataSource
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            rebuildGroups()
            return useAdvancedMode ? groups.count : simpleRows.count
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
            let rows = simpleRows
            guard row < rows.count else { return nil }
            let item = rows[row]
            let isCurrent = row == currentIndex
            
            let cell = NSTableCellView()
            
            if item.main.text.isEmpty && item.trans == nil {
                let displayText: String
                if isCurrent {
                    let pauseUntil = item.pauseUntil
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
                let stack = NSStackView()
                stack.orientation = .vertical
                stack.alignment = .centerX
                stack.spacing = 4
                stack.translatesAutoresizingMaskIntoConstraints = false
                
                let mainLabel = NSTextField(labelWithString: item.main.text.isEmpty ? "♪" : item.main.text)
                mainLabel.alignment = .center
                mainLabel.font = isCurrent ? NSFont.systemFont(ofSize: 17, weight: .semibold) : NSFont.systemFont(ofSize: 15)
                mainLabel.textColor = isCurrent ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
                mainLabel.lineBreakMode = .byWordWrapping
                mainLabel.maximumNumberOfLines = 0
                stack.addArrangedSubview(mainLabel)
                
                if let trans = item.trans, !trans.text.isEmpty {
                    let transLabel = NSTextField(labelWithString: trans.text)
                    transLabel.alignment = .center
                    transLabel.font = isCurrent ? NSFont.systemFont(ofSize: 13) : NSFont.systemFont(ofSize: 12)
                    let transColor = (NSColor(hex: settings.lrcTagColors["trans"] ?? "#FFFFFF") ?? settings.lyricInactiveNSColor)
                    transLabel.textColor = isCurrent ? transColor : transColor.withAlphaComponent(0.6)
                    transLabel.lineBreakMode = .byWordWrapping
                    transLabel.maximumNumberOfLines = 0
                    stack.addArrangedSubview(transLabel)
                }
                
                cell.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    stack.widthAnchor.constraint(equalTo: cell.widthAnchor, constant: -16)
                ])
            }
            return cell
        }
        
        // MARK: - Advanced cell content
        
        private func advancedCellContent(row: Int, width: CGFloat) -> NSView? {
            guard row < groups.count else { return nil }
            let group = groups[row]
            let isCurrent = row == currentIndex
            
            let lines = LyricsLogicEngine.getVisibleLines(from: group, limit: 5, settings: settings)
            guard !lines.isEmpty else { return nil }
            
            let container = NSView()
            var currentY: CGFloat = 0
            let spacing: CGFloat = 4
            
            for (lineIndex, line) in lines.enumerated() {
                let view: NSView
                if line.tag == "inst" || (line.text.isEmpty && line.words.isEmpty) {
                    view = instLineView(line: line, group: group, isCurrent: isCurrent)
                } else {
                    view = textLineView(line: line, lineIndex: lineIndex, totalLines: lines.count, isCurrent: isCurrent)
                }
                
                container.addSubview(view)
                view.translatesAutoresizingMaskIntoConstraints = false
                
                NSLayoutConstraint.activate([
                    view.topAnchor.constraint(equalTo: container.topAnchor, constant: currentY),
                    view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                ])
                
                let fitting = view.fittingSize
                currentY += fitting.height + spacing
            }
            
            if isTagEnabled("note"),
               let note = group.lines.first(where: { $0.tag == "note" }),
               !note.text.isEmpty {
                let button = noteButton(row: row)
                container.addSubview(button)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                    button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
                    button.widthAnchor.constraint(equalToConstant: 14),
                    button.heightAnchor.constraint(equalToConstant: 14)
                ])
            }
            
            container.heightAnchor.constraint(equalToConstant: max(currentY - spacing, 16)).isActive = true
            return container
        }
        
        // MARK: - Advanced cell components
        
        private func advancedCell(row: Int) -> NSView? {
            guard let tableView = tableView,
                  let content = advancedCellContent(row: row, width: tableView.bounds.width) else { return nil }
            
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
        
        private func instLineView(line: LyricsLine, group: LyricsGroup, isCurrent: Bool) -> NSView {
            let container = NSView()
            
            let symbolLabel = NSTextField(labelWithString: "♪")
            symbolLabel.alignment = .center
            symbolLabel.font = NSFont.systemFont(ofSize: 16)
            symbolLabel.textColor = isCurrent ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
            container.addSubview(symbolLabel)
            
            let remaining: String
            if let pauseUntil = group.pauseUntil ?? line.pauseUntil {
                let rem = max(0, pauseUntil - currentTime)
                remaining = rem > 0 ? String(format: "♪ %0.1fс", rem) : "♪"
            } else {
                remaining = "♪"
            }
            let timerLabel = NSTextField(labelWithString: isCurrent ? remaining : "")
            timerLabel.alignment = .center
            timerLabel.font = NSFont.systemFont(ofSize: 10)
            timerLabel.textColor = settings.lyricActiveNSColor.withAlphaComponent(0.6)
            container.addSubview(timerLabel)
            
            symbolLabel.translatesAutoresizingMaskIntoConstraints = false
            timerLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                timerLabel.topAnchor.constraint(equalTo: container.topAnchor),
                timerLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                symbolLabel.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 2),
                symbolLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                symbolLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            return container
        }
        
        private func textLineView(line: LyricsLine, lineIndex: Int, totalLines: Int, isCurrent: Bool) -> NSView {
            let label = NSTextField(labelWithString: line.text.isEmpty ? "♪" : line.text)
            label.alignment = .center
            label.font = fontForLine(isMain: line.isMain, lineIndex: lineIndex, totalLines: totalLines)
            label.textColor = colorForLine(line, isActive: isCurrent)
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            return label
        }
        
        private func noteButton(row: Int) -> NSButton {
            let button = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Note")!, target: self, action: #selector(toggleNote(_:)))
            button.isBordered = false
            button.bezelStyle = .inline
            button.contentTintColor = NSColor(hex: settings.lrcTagColors["note"] ?? "#888888") ?? .gray
            button.tag = row
            return button
        }
        
        // MARK: - Helpers
        
        private func isTagEnabled(_ tag: String) -> Bool {
            LyricsLogicEngine.isTagEnabled(tag, settings: settings)
        }
        
        private func fontForLine(isMain: Bool, lineIndex: Int, totalLines: Int) -> NSFont {
            if isMain {
                return NSFont.systemFont(ofSize: 17, weight: .semibold)
            } else if lineIndex == 1 {
                return NSFont.systemFont(ofSize: totalLines >= 3 ? 11 : 13)
            } else {
                return NSFont.systemFont(ofSize: 11)
            }
        }
        
        private func colorForLine(_ line: LyricsLine, isActive: Bool) -> NSColor {
            let baseColor: NSColor
            if let tag = line.tag {
                let hex = settings.lrcTagColors[tag] ?? "#FFFFFF"
                baseColor = NSColor(hex: hex) ?? settings.lyricInactiveNSColor
            } else {
                baseColor = isActive ? settings.lyricActiveNSColor : settings.lyricInactiveNSColor
            }
            
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
                let rows = simpleRows
                guard row < rows.count else { return 36 }
                let item = rows[row]
                if item.main.text.isEmpty && item.trans == nil { return 16 }
                let width = max(tableView.frame.width - 32, 1)
                let mainFont = NSFont.systemFont(ofSize: 15)
                let mainRect = (item.main.text as NSString).boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: mainFont]
                )
                var totalHeight = ceil(mainRect.height)
                if let trans = item.trans, !trans.text.isEmpty {
                    let transFont = NSFont.systemFont(ofSize: 12)
                    let transRect = (trans.text as NSString).boundingRect(
                        with: NSSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: transFont]
                    )
                    totalHeight += ceil(transRect.height) + 4
                }
                return max(totalHeight + 16, 36)
            }
        }
        
        // MARK: - Scroll & Index
        
        @objc func scrollViewDidResize() {
            guard let tableView = tableView, !lyrics.isEmpty else { return }
            invalidateHeightCache()
            let count = useAdvancedMode ? groups.count : simpleRows.count
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<max(lyrics.count, count)))
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
                let rows = simpleRows
                guard row >= 0, row < rows.count else { return }
                time = rows[row].time
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
            guard timeSinceProgrammaticScroll > 0.5 else { return }
            if !isUserScrolled {
                isUserScrolled = true
                DispatchQueue.main.async { NotificationCenter.default.post(name: .userDidScroll, object: nil) }
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
                if idx < 0 && !groups.isEmpty { idx = 0 }
                if idx != currentIndex { currentIndex = idx }
            } else {
                let rows = simpleRows
                var idx = -1
                for (i, item) in rows.enumerated() {
                    if currentTime >= item.time { idx = i } else { break }
                }
                if idx < 0 && !rows.isEmpty { idx = 0 }
                if idx == rows.count - 1 && rows[idx].main.text.isEmpty && rows[idx].trans == nil { idx = -1 }
                if idx != currentIndex { currentIndex = idx }
            }
            
            if !isUserScrolled { autoScrollToCurrentPosition() }
        }
        
        private func autoScrollToCurrentPosition() {
            let count = useAdvancedMode ? groups.count : simpleRows.count
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
