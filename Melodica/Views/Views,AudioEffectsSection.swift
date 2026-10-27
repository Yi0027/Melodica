// Views/AudioEffectsSectionRegular.swift
import SwiftUI

struct AudioEffectsSectionRegular: View {
    @ObservedObject private var effects = AudioEffectsManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    // Единая сетка
    private let labelWidth: CGFloat = 72
    private let valueWidth: CGFloat = 58
    private let rowSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            disclosureHeader
            if effects.advancedExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    spatialSection
                    sectionDivider
                    reverbSection
                    sectionDivider
                    delaySection
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Header

    private var disclosureHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                effects.advancedExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(settings.textMuted)
                    .rotationEffect(.degrees(effects.advancedExpanded ? 90 : 0))
                Text(LocalizedStringKey("advanced"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(settings.textMain)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(settings.textMuted.opacity(0.15))
            .frame(height: 1)
    }

    // MARK: - Sections

    private var spatialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(LocalizedStringKey("spatial_audio"), isOn: Binding(
                get: { settings.spatialAudioEnabled },
                set: { settings.setSpatialAudioEnabled($0) }
            ))

            if settings.spatialAudioEnabled {
                Toggle(isOn: Binding(
                    get: { settings.spatialStereoSpeakers },
                    set: { settings.setSpatialStereoSpeakers($0) }
                )) {
                    Text(LocalizedStringKey("spatial_stereo_speakers"))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)

                if settings.spatialStereoSpeakers {
                    paramRow(labelKey: LocalizedStringKey("spatial_speaker_spread"),
                             value: Binding(
                                get: { settings.spatialSpeakerSpread },
                                set: { settings.setSpatialSpeakerSpread($0) }
                             ),
                             range: 0.5...10.0, step: 0.5, format: "%.1f m")
                }

                pickerRow(labelKey: LocalizedStringKey("spatial_algorithm"), selection: Binding(
                    get: { settings.spatialAlgorithm },
                    set: { settings.setSpatialAlgorithm($0) }
                )) {
                    Text(LocalizedStringKey("spatial_eq_power")).tag("equalPower")
                    Text(LocalizedStringKey("spatial_spherical")).tag("spherical")
                    Text(LocalizedStringKey("spatial_hrtf")).tag("hrtf")
                    Text(LocalizedStringKey("spatial_hrtf_hq")).tag("hrtfHQ")
                    Text(LocalizedStringKey("spatial_soundfield")).tag("soundField")
                }

                pickerRow(labelKey: LocalizedStringKey("spatial_room_preset"), selection: Binding(
                    get: { settings.spatialRoomPreset },
                    set: { settings.setSpatialRoomPreset($0) }
                )) {
                    Text(LocalizedStringKey("reverb_off")).tag("off")
                    Text(LocalizedStringKey("reverb_small_room")).tag("smallRoom")
                    Text(LocalizedStringKey("reverb_medium_room")).tag("mediumRoom")
                    Text(LocalizedStringKey("reverb_large_room")).tag("largeRoom")
                    Text(LocalizedStringKey("reverb_medium_hall")).tag("mediumHall")
                    Text(LocalizedStringKey("reverb_large_hall")).tag("largeHall")
                    Text(LocalizedStringKey("reverb_cathedral")).tag("cathedral")
                    Text(LocalizedStringKey("reverb_plate")).tag("plate")
                }

                if settings.spatialRoomPreset != "off" {
                    percentParamRow(labelKey: LocalizedStringKey("spatial_reverb_blend"),
                                    value: Binding(
                                        get: { settings.spatialReverbBlend },
                                        set: { settings.setSpatialReverbBlend($0) }
                                    ),
                                    range: 0...100, step: 1)
                }

                paramRow(labelKey: LocalizedStringKey("spatial_distance"),
                         value: Binding(
                            get: { settings.spatialDistance },
                            set: { settings.setSpatialDistance($0) }
                         ),
                         range: 0.5...25.0, step: 0.5, format: "%.1f m")

                paramRow(labelKey: LocalizedStringKey("spatial_pan"),
                         value: Binding(
                            get: { settings.spatialPan },
                            set: { settings.setSpatialPan($0) }
                         ),
                         range: -10.0...10.0, step: 0.5, format: "%.1f m")

                paramRow(labelKey: LocalizedStringKey("spatial_elevation"),
                         value: Binding(
                            get: { settings.spatialElevation },
                            set: { settings.setSpatialElevation($0) }
                         ),
                         range: -5.0...5.0, step: 0.5, format: "%.1f m")

                paramRow(labelKey: LocalizedStringKey("spatial_obstruction"),
                         value: Binding(
                            get: { settings.spatialObstruction },
                            set: { settings.setSpatialObstruction($0) }
                         ),
                         range: -40.0...0.0, step: 1.0, format: "%.0f dB")

                paramRow(labelKey: LocalizedStringKey("spatial_occlusion"),
                         value: Binding(
                            get: { settings.spatialOcclusion },
                            set: { settings.setSpatialOcclusion($0) }
                         ),
                         range: -40.0...0.0, step: 1.0, format: "%.0f dB")

                paramRow(labelKey: LocalizedStringKey("spatial_rolloff"),
                         value: Binding(
                            get: { settings.spatialRolloff },
                            set: { settings.setSpatialRolloff($0) }
                         ),
                         range: 0.0...2.0, step: 0.1, format: "%.1f")

                HStack {
                    Spacer()
                    Button(action: {
                        settings.resetSpatialSettings()
                    }) {
                        Text(LocalizedStringKey("spatial_reset"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(settings.accent)
                }
                .padding(.top, 2)

                Text(LocalizedStringKey("spatial_hint"))
                    .font(.system(size: 10))
                    .foregroundColor(settings.textMuted.opacity(0.5))
            }
        }
    }

    // MARK: - Reverb

    private var reverbSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(LocalizedStringKey("reverb"), isOn: reverbEnabledBinding)

            if effects.reverbPreset != "off" {
                pickerRow(labelKey: LocalizedStringKey("preset"), selection: reverbPickerBinding) {
                    Text(LocalizedStringKey("reverb_small_room")).tag("smallRoom")
                    Text(LocalizedStringKey("reverb_medium_room")).tag("mediumRoom")
                    Text(LocalizedStringKey("reverb_large_room")).tag("largeRoom")
                    Text(LocalizedStringKey("reverb_medium_hall")).tag("mediumHall")
                    Text(LocalizedStringKey("reverb_large_hall")).tag("largeHall")
                    Text(LocalizedStringKey("reverb_plate")).tag("plate")
                    Text(LocalizedStringKey("reverb_cathedral")).tag("cathedral")
                }

                percentParamRow(labelKey: LocalizedStringKey("amount"),
                                value: $effects.reverbWetDry,
                                range: 0...100, step: 1)
            }
        }
    }

    /// Безопасный Binding для Picker: никогда не отдаёт "off".
    private var reverbPickerBinding: Binding<String> {
        Binding(
            get: {
                let current = effects.reverbPreset
                return current == "off" ? settings.lastReverbPreset : current
            },
            set: { newValue in
                guard newValue != "off" else { return }
                effects.reverbPreset = newValue
                settings.setLastReverbPreset(newValue)
            }
        )
    }

    /// switch «вкл/выкл» реверба поверх `reverbPreset`, где "off" = выключено.
    private var reverbEnabledBinding: Binding<Bool> {
        Binding(
            get: { effects.reverbPreset != "off" },
            set: { isOn in
                if isOn {
                    effects.reverbPreset = settings.lastReverbPreset
                } else {
                    if effects.reverbPreset != "off" {
                        settings.setLastReverbPreset(effects.reverbPreset)
                    }
                    effects.reverbPreset = "off"
                }
            }
        )
    }

    // MARK: - Delay

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(LocalizedStringKey("delay"), isOn: $effects.delayEnabled)

            if effects.delayEnabled {
                paramRow(labelKey: LocalizedStringKey("delay_time"),
                         value: $effects.delayTime,
                         range: 0.05...0.5, step: 0.01, format: "%.2f s")

                // Feedback + чекбокс "advanced" под слайдером
                VStack(alignment: .leading, spacing: 4) {
                    percentParamRow(
                        labelKey: LocalizedStringKey("delay_feedback"),
                        value: $effects.delayFeedback,
                        range: effects.delayAdvanced ? -100...100 : 0...60,
                        step: 1
                    )
                    HStack(spacing: 0) {
                        Spacer().frame(width: labelWidth + rowSpacing)
                        Toggle(LocalizedStringKey("advanced_short"), isOn: $effects.delayAdvanced)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 10))
                            .foregroundColor(settings.textMuted)
                            .tint(settings.accent)
                            .help(LocalizedStringKey("delay_feedback_advanced_hint"))
                        Spacer()
                    }
                }

                paramRow(labelKey: LocalizedStringKey("delay_lowpass"),
                         value: $effects.delayLowPassCutoff,
                         range: 2000...12000, step: 100, format: "%.0f Hz")

                percentParamRow(labelKey: LocalizedStringKey("amount"),
                                value: $effects.delayWetDry,
                                range: 0...100, step: 1)
            }
        }
    }

    // MARK: - Building Blocks

    /// Универсальный заголовок секции: title слева, switch справа (если нужен).
    private func sectionHeader(_ key: LocalizedStringKey, isOn: Binding<Bool>? = nil) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(settings.textMain)
            Spacer()
            if let isOn {
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(settings.accent)
                    .labelsHidden()
            }
        }
    }

    private func pickerRow<Content: View>(
        labelKey: LocalizedStringKey,
        selection: Binding<String>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: rowSpacing) {
            labelView(labelKey)
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .tint(settings.accent)
        }
    }

    private func paramRow(
        labelKey: LocalizedStringKey,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        format: String
    ) -> some View {
        HStack(spacing: rowSpacing) {
            labelView(labelKey)
            Slider(value: value, in: range, step: step)
                .tint(settings.accent)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.textMuted)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    private func percentParamRow(
        labelKey: LocalizedStringKey,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float
    ) -> some View {
        HStack(spacing: rowSpacing) {
            labelView(labelKey)
            Slider(value: value, in: range, step: step)
                .tint(settings.accent)
            Text((Double(value.wrappedValue) / 100)
                    .formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(settings.textMuted)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    private func labelView(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11))
            .foregroundColor(settings.textMuted)
            .frame(width: labelWidth, alignment: .leading)
    }
}
