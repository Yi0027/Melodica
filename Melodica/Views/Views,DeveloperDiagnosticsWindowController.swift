import AppKit
import SwiftUI
import Combine

@MainActor
final class DeveloperDiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = DeveloperDiagnosticsWindowController()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Developer Diagnostics"
        window.minSize = NSSize(width: 720, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.darkBg

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(libraryVM: LibraryViewModel, playerVM: PlayerViewModel) {
        guard let window = self.window else { return }

        let view = DeveloperDiagnosticsView(
            libraryVM: libraryVM,
            playerVM: playerVM,
            onClose: { [weak window] in
                window?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        DeveloperDiagnosticsService.shared.stopTestTone()
        window?.contentView = nil
    }
}
