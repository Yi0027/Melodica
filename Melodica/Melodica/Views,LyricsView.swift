// Views/LyricsView.swift
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
    
    var body: some View {
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
            .onChange(of: trackId) { _ in
                resetState()
            }
            .onChange(of: lyrics.map(\.id)) { _ in
                resetState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
                NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                userScrolled = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitterDidResize)) { _ in
                NotificationCenter.default.post(name: .resetUserScrolled, object: nil)
                userScrolled = false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToCurrentTime"))) { notification in
                guard let time = notification.object as? TimeInterval else { return }
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
                syncButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.4), value: userScrolled)
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
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text(LocalizedStringKey("synch"))
                    .font(.system(size: 11, weight: .medium))
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
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )
        
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.boundsDidChange), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.resetUserScrolled), name: .resetUserScrolled, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.forceScroll), name: .forceScrollNow, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToTop), name: .scrollLyricsToTop, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrollToIndexNotif(_:)), name: .scrollToIndex, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.themeDidChange), name: NSNotification.Name("themeDidChange"), object: nil)
        
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
            tableView.reloadData()
            
            if !lyrics.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<lyrics.count))
            }
            
            coordinator.updateIndexAndScroll()
        }
    }
}

// MARK: - Coordinator

extension NativeLyricsScroll {
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
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
        
        func numberOfRows(in tableView: NSTableView) -> Int { lyrics.count }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let lineText = lyrics[row].text
            let isCurrent = row == currentIndex
            
            // ✅ Пустая строка — показываем таймер паузы
            if lineText.isEmpty {
                let displayText: String
                if isCurrent {
                    let pauseUntil = lyrics[row].pauseUntil
                    let remaining: TimeInterval
                    if let until = pauseUntil {
                        remaining = max(0, until - currentTime)
                    } else {
                        remaining = 0
                    }
                    displayText = remaining > 0 ? String(format: "♪ %0.1fс", remaining) : "♪"
                } else {
                    displayText = "♪"
                }
                
                let text = NSTextField(labelWithString: displayText)
                  text.alignment = .center
                  text.font = NSFont.systemFont(ofSize: 16)
                  // ✅ Подсвечиваем если это текущая строка
                  text.textColor = isCurrent
                      ? SettingsManager.shared.lyricActiveNSColor.withAlphaComponent(0.6)
                      : NSColor.secondaryLabelColor.withAlphaComponent(0.4)
                text.lineBreakMode = .byWordWrapping
                text.maximumNumberOfLines = 0
                
                let cell = NSTableCellView()
                cell.addSubview(text)
                text.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    text.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    text.widthAnchor.constraint(equalTo: cell.widthAnchor, constant: -16)
                ])
                return cell
            }
            
            // Обычная строка с текстом
            let text = NSTextField(labelWithString: lineText)
            text.alignment = .center
            text.font = isCurrent ? NSFont.systemFont(ofSize: 17) : NSFont.systemFont(ofSize: 15)
            text.textColor = isCurrent
                ? SettingsManager.shared.lyricActiveNSColor
                : SettingsManager.shared.lyricInactiveNSColor  // ✅ Из настроек NSColor.secondaryLabelColor
            text.lineBreakMode = .byWordWrapping
            text.maximumNumberOfLines = 0
            
            let cell = NSTableCellView()
            cell.addSubview(text)
            text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.widthAnchor.constraint(equalTo: cell.widthAnchor, constant: -16)
            ])
            return cell
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if lyrics[row].text.isEmpty { return 16 }
            let text = lyrics[row].text
            let font = NSFont.systemFont(ofSize: 15)
            let width = tableView.frame.width - 32
            let rect = (text as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            return max(rect.height + 16, 36)
        }
        
        @objc func scrollViewDidResize() {
            guard let tableView = tableView, !lyrics.isEmpty else { return }
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(0..<lyrics.count))
        }
        
        @objc func tableViewClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < lyrics.count else { return }
            onTapLine?(lyrics[row].time)
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
        
        func updateIndexAndScroll() {
            guard !lyrics.isEmpty else { return }
            var idx = -1
            for (i, line) in lyrics.enumerated() {
                if currentTime >= line.time { idx = i } else { break }
            }
            
            // ✅ Если достигли последней строки и она пустая — гасим предыдущую
            if idx == lyrics.count - 1 && lyrics[idx].text.isEmpty {
                idx = -1  // Гасим всё
            }
            
            if idx != currentIndex {
                currentIndex = idx
            }
            
            if !isUserScrolled {
                autoScrollToCurrentPosition()
            }
        }
        
        private func autoScrollToCurrentPosition() {
            guard !lyrics.isEmpty else { return }
            
            let targetRow: Int
            if let firstLine = lyrics.first, currentTime < firstLine.time {
                targetRow = 0
            } else if let lastLine = lyrics.last, currentTime >= lastLine.time {
                targetRow = lyrics.count - 1
            } else if currentIndex >= 0 {
                targetRow = currentIndex
            } else {
                return
            }
            
            performScrollToRow(targetRow, force: false)
        }
        
        private func performScrollToRow(_ row: Int, force: Bool) {
            guard let scrollView = scrollView, let tableView = tableView,
                  row >= 0, row < lyrics.count else { return }
            
            if force {
                isAnimating = false
                animationQueue.removeAll()
            }
            
            if isAnimating && !force {
                if animationQueue.last != row {
                    animationQueue.append(row)
                }
                return
            }
            
            let rowRect = tableView.rect(ofRow: row)
            let visibleRect = tableView.visibleRect
            let targetY = rowRect.midY - visibleRect.height / 2
            let maxY = max(0, tableView.frame.height - visibleRect.height)
            let clampedY = min(max(0, targetY), maxY)
            
            let currentOrigin = scrollView.contentView.bounds.origin
            let distance = abs(currentOrigin.y - clampedY)
            
            if distance < 1 {
                processQueue()
                return
            }
            
            isAnimating = true
            lastProgrammaticScroll = Date()
            
            // ✅ Динамическая длительность: от 0.1 до 0.25 сек в зависимости от расстояния
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
        
        @objc func forceScroll() {
            guard !lyrics.isEmpty else { return }
            
            isAnimating = false
            animationQueue.removeAll()
            
            let targetRow: Int
            if let firstLine = lyrics.first, currentTime < firstLine.time {
                targetRow = 0
            } else if let lastLine = lyrics.last, currentTime >= lastLine.time {
                targetRow = lyrics.count - 1
            } else if currentIndex >= 0 {
                targetRow = currentIndex
            } else {
                targetRow = 0
            }
            
            performScrollToRow(targetRow, force: true)
        }
        
        @objc func scrollToTop() {
            lastProgrammaticScroll = Date()
            isUserScrolled = false
            isAnimating = false
            animationQueue.removeAll()
            performScrollToRow(0, force: true)
        }
        
        @objc func scrollToIndexNotif(_ notification: Notification) {
            guard let index = notification.object as? Int, !isUserScrolled else { return }
            animationQueue.removeAll()
            performScrollToRow(index, force: true)
        }
        
        @objc func themeDidChange() {
            DispatchQueue.main.async { [weak self] in
                self?.tableView?.reloadData()
            }
        }
    }
}
