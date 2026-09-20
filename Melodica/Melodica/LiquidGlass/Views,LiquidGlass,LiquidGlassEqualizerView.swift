// Views,LiquidGlass,LiquidGlassEqualizerView.swift
import SwiftUI

struct LiquidGlassEqualizerView: View {
    @ObservedObject var eqManager = EqualizerManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    var onClose: (() -> Void)? = nil
    
    private var systemAccent: Color { Color(nsColor: NSColor.controlAccentColor) }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LocalizedStringKey("sound"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Button(LocalizedStringKey("reset")) {
                    eqManager.reset()
                    settings.setGapless(enabled: false)
                    settings.setCrossfade(enabled: false)
                    settings.setCrossfadeDuration(5)
                    settings.setSilenceSkip(enabled: false)
                    settings.setSilenceSkipThreshold(-50)
                    settings.setRGMode("track")
                    NotificationCenter.default.post(name: .eqDidChange, object: nil)
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
                .overlay(systemAccent.opacity(0.2))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Эквалайзер
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(LocalizedStringKey("equalizer"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            Toggle("", isOn: $eqManager.isEnabled)
                                .toggleStyle(.switch)
                                .tint(systemAccent)
                                .labelsHidden()
                                .onChange(of: eqManager.isEnabled) { _ in
                                    eqManager.save()
                                    NotificationCenter.default.post(name: .eqDidChange, object: nil)
                                }
                        }
                        HStack(alignment: .bottom, spacing: 16) {
                            ForEach($eqManager.bands) { $band in
                                VStack(spacing: 6) {
                                    Text(String(format: "%+.0f", band.gain))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.6))
                                    Slider(value: $band.gain, in: -12...12)
                                        .frame(width: 140, height: 20)
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 20, height: 140)
                                        .tint(systemAccent)
                                    Text(band.label)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .onChange(of: band.gain) { _ in
                                    eqManager.save()
                                    EQPresetManager.shared.syncActivePresetState()
                                    NotificationCenter.default.post(name: .eqDidChange, object: nil)
                                }
                            }
                        }
                    }
                    
                    LiquidGlassEQPresetSection()
                    
                    Divider()
                        .overlay(systemAccent.opacity(0.15))
                    
                    // Gapless
                    HStack {
                        Text(LocalizedStringKey("gapless"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(LocalizedStringKey("gapless_enable"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Toggle("", isOn: Binding(get: { settings.gaplessEnabled }, set: { settings.setGapless(enabled: $0) }))
                            .toggleStyle(.switch)
                            .tint(systemAccent)
                            .labelsHidden()
                    }
                    
                    Divider()
                        .overlay(systemAccent.opacity(0.15))
                    
                    // Crossfade
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(LocalizedStringKey("crossfade"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(LocalizedStringKey("crossfade_enable"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Toggle("", isOn: Binding(get: { settings.crossfadeEnabled }, set: { settings.setCrossfade(enabled: $0) }))
                                .toggleStyle(.switch)
                                .tint(systemAccent)
                                .labelsHidden()
                        }
                        if settings.crossfadeEnabled {
                            HStack(spacing: 12) {
                                Text(String(format: NSLocalizedString("crossfade_duration_value", comment: ""), Int(settings.crossfadeDuration)))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Slider(value: Binding(get: { settings.crossfadeDuration }, set: { settings.setCrossfadeDuration($0) }), in: 1...20, step: 1)
                                    .tint(systemAccent)
                            }
                            Text(LocalizedStringKey("crossfade_hint"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    
                    Divider()
                        .overlay(systemAccent.opacity(0.15))
                    
                    // Silence Skip
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(LocalizedStringKey("silence_skip"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(LocalizedStringKey("silence_skip_enable"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Toggle("", isOn: Binding(get: { settings.silenceSkipEnabled }, set: { settings.setSilenceSkip(enabled: $0) }))
                                .toggleStyle(.switch)
                                .tint(systemAccent)
                                .labelsHidden()
                        }
                        if settings.silenceSkipEnabled {
                            HStack(spacing: 12) {
                                Text(String(format: NSLocalizedString("silence_threshold_value", comment: ""), Int(settings.silenceSkipThreshold)))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                Slider(value: Binding(get: { settings.silenceSkipThreshold }, set: { settings.setSilenceSkipThreshold($0) }), in: (-80)...(-20), step: 1)
                                    .tint(systemAccent)
                            }
                            Text(LocalizedStringKey("silence_skip_hint"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    
                    Divider()
                        .overlay(systemAccent.opacity(0.15))
                    
                    // ReplayGain Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ReplayGain")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 16) {
                            ForEach(["off", "track", "album"], id: \.self) { mode in
                                Button(action: { settings.setRGMode(mode) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: settings.rgMode == mode ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 12))
                                        Text(modeName(mode))
                                            .font(.system(size: 12))
                                    }
                                    .foregroundColor(settings.rgMode == mode ? systemAccent : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Text(rgDescription)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .padding(16)
            }
            
            Divider()
                .overlay(systemAccent.opacity(0.2))
            
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Text(LocalizedStringKey("done"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(systemAccent)
                    .frame(maxWidth: .infinity).frame(height: 40).contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .buttonStyle(.plain)
        }
        .frame(width: 520, height: 620)
    }
    
    private func modeName(_ mode: String) -> String {
        switch mode {
        case "off": return NSLocalizedString("rg_off", comment: "")
        case "track": return NSLocalizedString("rg_track", comment: "")
        case "album": return NSLocalizedString("rg_album", comment: "")
        default: return mode
        }
    }
    
    private var rgDescription: String {
        switch settings.rgMode {
        case "off": return NSLocalizedString("rg_off_desc", comment: "")
        case "track": return NSLocalizedString("rg_track_desc", comment: "")
        case "album": return NSLocalizedString("rg_album_desc", comment: "")
        default: return ""
        }
    }
}
