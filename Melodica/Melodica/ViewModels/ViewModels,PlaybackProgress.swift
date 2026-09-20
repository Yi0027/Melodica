// ViewModels,PlaybackProgress.swift
import Foundation
import Combine

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}
