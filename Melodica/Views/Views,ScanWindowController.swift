import AppKit
import SwiftUI
import Combine

// MARK: - Scan Event Throttler

/// Throttles high-frequency progress updates (~10-20/sec) from the background scan task
/// to avoid saturating the MainActor and SwiftUI render passes, while delivering
/// discrete state transitions immediately.
nonisolated final class ScanEventThrottler: @unchecked Sendable {
    private let minInterval: TimeInterval = 0.05 // ~20 updates per second (50ms)
    private var lastProgressDispatch: CFAbsoluteTime = 0
    private let lock = NSLock()
    private let onApply: @MainActor @Sendable (BitrateAnalyzer.ScanEvent, Int) -> Void

    init(onApply: @escaping @MainActor @Sendable (BitrateAnalyzer.ScanEvent, Int) -> Void) {
        self.onApply = onApply
    }

    func handle(event: BitrateAnalyzer.ScanEvent, indexOffset: Int) {
        switch event {
        case .stageProgress:
            lock.lock()
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastProgressDispatch >= minInterval {
                lastProgressDispatch = now
                lock.unlock()
                Task { @MainActor in
                    self.onApply(event, indexOffset)
                }
            } else {
                lock.unlock()
            }

        default:
            lock.lock()
            lastProgressDispatch = CFAbsoluteTimeGetCurrent()
            lock.unlock()
            Task { @MainActor in
                self.onApply(event, indexOffset)
            }
        }
    }
}

// MARK: - Controller

@MainActor
final class ScanWindowController: NSWindowController, NSWindowDelegate {

    static let shared = ScanWindowController()

    let session = ScanSession()

    /// Резолвер UUID → Track. Устанавливается снаружи (в MelodicaApp),
    /// потому что контроллер не видит библиотеку/очередь. Должен уметь
    /// находить трек и по `Track.id` (drops из списков библиотеки),
    /// и по `QueueItem.id` (drops из очереди).
    var trackResolver: ((UUID) -> Track?)?

    private var scanTask: Task<Void, Never>?
    private var pendingBatches: [(indexOffset: Int, tracks: [Track])] = []
    private var isBatchRunning = false
    private var hostingView: ScanHostingView<ScanWindowView>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("scan_window_title", comment: "")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 560)
        window.center()
        window.isReleasedWhenClosed = false

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)
        window.delegate = self

        applyTheme(SettingsManager.shared.activeTheme)

        SettingsManager.shared.$activeTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in
                self?.applyTheme(theme)
            }
            .store(in: &cancellables)

        let view = ScanWindowView(
            session: session,
            onClose: { [weak window] in window?.close() }
        )
        let hosting = ScanHostingView(rootView: view)
        hosting.onDrop = { [weak self] ids in
            self?.present(trackIDs: ids)
        }
        window.contentView = hosting
        // Сохраним ссылку для возможного удаления/перенастройки
        self.hostingView = hosting
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme(_ theme: String) {
        guard let window = self.window else { return }
        window.isOpaque = true
        if theme == "liquid_glass" {
            window.backgroundColor = NSColor.windowBackgroundColor
        } else {
            window.backgroundColor = NSColor.darkBg
        }
    }

    // MARK: - Public

    /// Открывает окно и запускает или дополняет сканирование.
    func present(tracks: [Track]) {
        if case .idle = session.state {
            startScan(tracks: tracks)
            return
        }

        // Уже идёт сканирование или finished — аппендим.
        if let result = session.appendTracks(tracks) {
            pendingBatches.append((indexOffset: result.startIndex, tracks: result.filtered))
            drainPending()
        }
        raiseWindow()
    }

    /// Резолвит UUID → Track и вызывает `present(tracks:)`.
    func present(trackIDs: [UUID]) {
        guard let resolver = trackResolver else { return }
        let tracks = trackIDs.compactMap { resolver($0) }
        guard !tracks.isEmpty else { return }
        present(tracks: tracks)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        scanTask?.cancel()
        scanTask = nil
        isBatchRunning = false
        pendingBatches.removeAll()
    }

    // MARK: - Private

    private func startScan(tracks: [Track]) {
        session.start(tracks: tracks)
        raiseWindow()

        scanTask?.cancel()
        let session = self.session
        let throttler = ScanEventThrottler { [weak session] event, offset in
            session?.apply(event: event, indexOffset: offset)
        }

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            _ = await BitrateAnalyzer.analyze(tracks: tracks) { event in
                throttler.handle(event: event, indexOffset: 0)
            }
            await MainActor.run { [weak self] in
                self?.drainPending()
            }
        }
    }

    private func drainPending() {
        guard !isBatchRunning, !pendingBatches.isEmpty else {
            if pendingBatches.isEmpty {
                session.markFinished()
            }
            return
        }
        let batch = pendingBatches.removeFirst()
        isBatchRunning = true

        scanTask?.cancel()
        let session = self.session
        let throttler = ScanEventThrottler { [weak session] event, offset in
            session?.apply(event: event, indexOffset: offset)
        }

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            _ = await BitrateAnalyzer.analyze(tracks: batch.tracks) { event in
                throttler.handle(event: event, indexOffset: batch.indexOffset)
            }
            await MainActor.run { [weak self] in
                self?.isBatchRunning = false
                self?.drainPending()
            }
        }
    }

    private func raiseWindow() {
        guard let window = self.window else { return }
        applyTheme(SettingsManager.shared.activeTheme)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
