// ViewModels,PlaybackProgress.swift
import Foundation
import Combine

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

@MainActor
final class PlaybackVolume: ObservableObject {
    @Published var volume: Float = 0.5

    func iconName(filled: Bool) -> String {
        if volume <= 0.001 {
            return filled ? "speaker.slash.fill" : "speaker.slash"
        } else if volume < 0.33 {
            return filled ? "speaker.wave.1.fill" : "speaker.wave.1"
        } else if volume < 0.67 {
            return filled ? "speaker.wave.2.fill" : "speaker.wave.2"
        } else {
            return filled ? "speaker.wave.3.fill" : "speaker.wave.3"
        }
    }
}
