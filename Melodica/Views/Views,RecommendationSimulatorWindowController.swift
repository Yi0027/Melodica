import AppKit
import SwiftUI
import Combine

@MainActor
final class RecommendationSimulatorWindowController: NSWindowController, NSWindowDelegate {
    static let shared = RecommendationSimulatorWindowController()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Recommendation Simulator & Debugger", comment: "")
        window.minSize = NSSize(width: 750, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.darkBg

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(libraryVM: LibraryViewModel) {
        guard let window = self.window else { return }

        let view = RecommendationSimulatorView(
            libraryVM: libraryVM,
            onClose: { [weak window] in
                window?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}
