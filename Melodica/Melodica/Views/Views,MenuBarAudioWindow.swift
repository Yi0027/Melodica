// Views/MenuBarAudioWindow.swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarAudioWindow {
    static let shared = MenuBarAudioWindow()
    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LiquidGlassEqualizerView(onClose: { [weak self] in
            self?.window?.close()
        })
        let hosting = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = NSLocalizedString("sound", comment: "")
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
        }

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
