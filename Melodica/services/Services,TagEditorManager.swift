// Services,TagEditorManager.swift
import Foundation
import SwiftUI
import Combine

@MainActor
final class TagEditorManager: ObservableObject {
    static let shared = TagEditorManager()

    @Published var isPresented: Bool = false
    @Published var tracks: [Track] = []

    private init() {}

    func openEditor(for tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        self.tracks = tracks
        self.isPresented = true
    }

    func close() {
        self.isPresented = false
        self.tracks = []
    }
}
