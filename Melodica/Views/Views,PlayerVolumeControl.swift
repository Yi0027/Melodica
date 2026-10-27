// Views,PlayerVolumeControl.swift
import SwiftUI

struct PlayerVolumeControl: View {
    @ObservedObject var volumeState: PlaybackVolume
    var isFilled: Bool = true
    var sliderWidth: CGFloat? = 60
    var iconSize: CGFloat = 10
    var iconColor: Color = .secondary
    var tint: Color? = nil
    var controlSize: ControlSize = .regular

    @State private var previousNonZeroVolume: Float = 0.5

    var body: some View {
        HStack(spacing: 5) {
            Button(action: toggleMute) {
                Image(systemName: volumeState.iconName(filled: isFilled))
                    .font(.system(size: iconSize))
                    .foregroundColor(iconColor)
                    .frame(width: 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            sliderView
        }
    }

    @ViewBuilder
    private var sliderView: some View {
        if let sliderWidth {
            if let tint {
                Slider(value: $volumeState.volume, in: 0...1)
                    .controlSize(controlSize)
                    .frame(width: sliderWidth)
                    .tint(tint)
            } else {
                Slider(value: $volumeState.volume, in: 0...1)
                    .controlSize(controlSize)
                    .frame(width: sliderWidth)
            }
        } else {
            if let tint {
                Slider(value: $volumeState.volume, in: 0...1)
                    .controlSize(controlSize)
                    .tint(tint)
            } else {
                Slider(value: $volumeState.volume, in: 0...1)
                    .controlSize(controlSize)
            }
        }
    }

    private func toggleMute() {
        if volumeState.volume > 0.001 {
            previousNonZeroVolume = volumeState.volume
            volumeState.volume = 0
        } else {
            volumeState.volume = previousNonZeroVolume > 0.001 ? previousNonZeroVolume : 0.5
        }
    }
}
