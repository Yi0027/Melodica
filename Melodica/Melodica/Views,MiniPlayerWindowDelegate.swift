//Views,MiniPlayerWindowDelegate.swift
import AppKit

class MiniPlayerWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MiniPlayerWindowDelegate()
    
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        return NSSize(width: 400, height: max(520, frameSize.height))
    }
    
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
    }
}
