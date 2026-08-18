// Views,VisMenuView.swift
import SwiftUI

struct VisMenuView: View {
    @ObservedObject var visualEngine = VisualizationEngine.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showCircularSettings = false
    @State private var showSpectrumSettings = false
    @State private var showWaveformSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            Text(LocalizedStringKey("visualization"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(settings.textMain)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { visualEngine.mode == .spectrum },
                    set: { if $0 { set(.spectrum) } else { set(.off) } }
                )) {
                    Text(LocalizedStringKey("vis_spectrum"))
                        .font(.system(size: 13))
                        .foregroundColor(settings.textMain)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 16).padding(.vertical, 6)
                
                if visualEngine.mode == .spectrum {
                    Divider().padding(.leading, 16)
                    
                    Button(action: { showSpectrumSettings.toggle() }) {
                        HStack {
                            Text(LocalizedStringKey("spectrum_settings"))
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(settings.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSpectrumSettings, arrowEdge: .trailing) {
                        SpectrumSettingsView()
                    }
                }
                
                Divider().padding(.leading, 16)
                
                Toggle(isOn: Binding(
                    get: { visualEngine.mode == .waveform },
                    set: { if $0 { set(.waveform) } else { set(.off) } }
                )) {
                    Text(LocalizedStringKey("vis_waveform"))
                        .font(.system(size: 13))
                        .foregroundColor(settings.textMain)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 16).padding(.vertical, 6)
                
                if visualEngine.mode == .waveform {
                    Divider().padding(.leading, 16)
                    
                    Button(action: { showWaveformSettings.toggle() }) {
                        HStack {
                            Text(LocalizedStringKey("waveform_settings"))
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(settings.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showWaveformSettings, arrowEdge: .trailing) {
                        WaveformSettingsView()
                    }
                }
                
                Divider().padding(.leading, 16)
                
                Toggle(isOn: Binding(
                    get: { visualEngine.mode == .circular },
                    set: { if $0 { set(.circular) } else { set(.off) } }
                )) {
                    Text(LocalizedStringKey("vis_circular"))
                        .font(.system(size: 13))
                        .foregroundColor(settings.textMain)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 16).padding(.vertical, 6)
                
                if visualEngine.mode == .circular {
                    Divider().padding(.leading, 16)
                    
                    Button(action: { showCircularSettings.toggle() }) {
                        HStack {
                            Text(LocalizedStringKey("circular_settings"))
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(settings.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCircularSettings, arrowEdge: .trailing) {
                        CircularVisualizationSettingsView()
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            Button(action: resetAll) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                    Text(LocalizedStringKey("reset"))
                        .font(.system(size: 11))
                }
                .foregroundColor(settings.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
        .padding(.vertical, 8)
        .background(settings.darkBg)
        .animation(.easeInOut(duration: 0.2), value: visualEngine.mode)
    }
    
    private func set(_ mode: VisualizationEngine.VisualizationMode) {
        visualEngine.setMode(mode)
    }
    
    private func resetAll() {
        visualEngine.setMode(.off)
        settings.setSpectrumMultiplier(10.0)
        settings.setSpectrumProcessing(true)
        settings.setWaveformCacheMode("off")
        settings.setCircularSensitivity(20.0)
        settings.setCircularFrequencyRange("sub_bass")
    }
}

// MARK: - Spectrum Settings

struct SpectrumSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey("spectrum_settings_title"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(settings.textMain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(LocalizedStringKey("spectrum_multiplier"))
                        .font(.system(size: 11))
                        .foregroundColor(settings.textMuted)
                    Spacer()
                    Text("\(Int(settings.spectrumMultiplier))x")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(settings.accent)
                }
                Slider(value: Binding(
                    get: { settings.spectrumMultiplier },
                    set: { settings.setSpectrumMultiplier($0) }
                ), in: 1...30, step: 1)
                .tint(settings.accent)
                
                Text(LocalizedStringKey("spectrum_multiplier_hint"))
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.5))
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            Toggle(isOn: Binding(
                get: { settings.spectrumProcessingEnabled },
                set: { settings.setSpectrumProcessing($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("spectrum_processing"))
                        .font(.system(size: 11))
                        .foregroundColor(settings.textMain)
                    Text(LocalizedStringKey("spectrum_processing_hint"))
                        .font(.system(size: 9))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
            }
            .toggleStyle(.switch)
            .tint(settings.accent)
        }
        .padding(16)
        .frame(width: 280)
        .background(settings.darkBg)
    }
}

// MARK: - Waveform Settings

struct WaveformSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("waveform_settings_title"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(settings.textMain)
            
            Text(LocalizedStringKey("waveform_cache"))
                .font(.system(size: 11))
                .foregroundColor(settings.textMain)
            
            VStack(alignment: .leading, spacing: 6) {
                Button(action: { settings.setWaveformCacheMode("off") }) {
                    HStack(spacing: 8) {
                        Image(systemName: settings.waveformCacheMode == "off" ? "circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(settings.waveformCacheMode == "off" ? settings.accent : settings.textMuted.opacity(0.4))
                        Text(LocalizedStringKey("cache_off"))
                            .font(.system(size: 11))
                            .foregroundColor(settings.textMain)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: { settings.setWaveformCacheMode("passive") }) {
                    HStack(spacing: 8) {
                        Image(systemName: settings.waveformCacheMode == "passive" ? "circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(settings.waveformCacheMode == "passive" ? settings.accent : settings.textMuted.opacity(0.4))
                        Text(LocalizedStringKey("cache_passive"))
                            .font(.system(size: 11))
                            .foregroundColor(settings.textMain)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: { settings.setWaveformCacheMode("active") }) {
                    HStack(spacing: 8) {
                        Image(systemName: settings.waveformCacheMode == "active" ? "circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(settings.waveformCacheMode == "active" ? settings.accent : settings.textMuted.opacity(0.4))
                        Text(LocalizedStringKey("cache_active"))
                            .font(.system(size: 11))
                            .foregroundColor(settings.textMain)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Text(LocalizedStringKey("waveform_cache_hint"))
                .font(.system(size: 9))
                .foregroundColor(settings.textMuted.opacity(0.5))
        }
        .padding(16)
        .frame(width: 260)
        .background(settings.darkBg)
    }
}
