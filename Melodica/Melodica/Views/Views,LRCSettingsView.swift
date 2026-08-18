// Views,LRCSettingsView.swift (адаптированный для SettingsSheetView)
import SwiftUI

struct LRCSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedTab = "general"
    
    private let categories: [(name: String, key: String, tags: [(tag: String, label: String)])] = [
        (NSLocalizedString("lrc_cat_general", comment: ""), "general", [
            ("orig", NSLocalizedString("lrc_tag_orig", comment: "")),
            ("trans", NSLocalizedString("lrc_tag_trans", comment: ""))
        ]),
        (NSLocalizedString("lrc_cat_languages", comment: ""), "languages", [
            ("ja", "日本語"), ("en", "English"), ("ko", "한국어"), ("zh", "中文"),
            ("ru", "Русский"), ("uk", "Українська"), ("fr", "Français"), ("de", "Deutsch"),
            ("es", "Español"), ("it", "Italiano"), ("pt", "Português")
        ]),
        (NSLocalizedString("lrc_cat_pronunciation", comment: ""), "pronunciation", [
            ("ja-rom", "Romaji"), ("ja-furi", "ふりがな"), ("ja-hira", "ひらがな"),
            ("ko-rom", "Romaja"), ("zh-pinyin", "Pīnyīn"), ("zh-bpmf", "Bopomofo"),
            ("ru-lat", "Latin")
        ]),
        (NSLocalizedString("lrc_cat_special", comment: ""), "special", [
            ("lit", NSLocalizedString("lrc_tag_lit", comment: "")),
            ("note", NSLocalizedString("lrc_tag_note", comment: "")),
            ("inst", NSLocalizedString("lrc_tag_inst", comment: "")),
            ("bg", NSLocalizedString("lrc_tag_bg", comment: "")),
            ("rap", NSLocalizedString("lrc_tag_rap", comment: "")),
            ("chord", NSLocalizedString("lrc_tag_chord", comment: ""))
        ]),
        (NSLocalizedString("lrc_cat_metadata", comment: ""), "metadata", [])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Режим LRC
            HStack(spacing: 12) {
                Text(LocalizedStringKey("lrc_mode_title"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(settings.textMain)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.lrcMode },
                    set: { newValue in DispatchQueue.main.async { settings.setLRCMode(newValue) } }
                )) {
                    Text(LocalizedStringKey("lrc_mode_off")).tag("off")
                    Text(LocalizedStringKey("lrc_mode_auto")).tag("auto")
                    Text(LocalizedStringKey("lrc_mode_on")).tag("on")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Вкладки категорий
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(categories, id: \.key) { cat in
                        Button(action: { selectedTab = cat.key }) {
                            Text(cat.name)
                                .font(.system(size: 11, weight: selectedTab == cat.key ? .semibold : .regular))
                                .foregroundColor(selectedTab == cat.key ? settings.textMain : settings.textMuted)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTab == cat.key ? settings.accent.opacity(0.2) : Color.clear)
                                )
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Контент
            ScrollView {
                VStack(spacing: 6) {
                    if selectedTab == "metadata" {
                        metadataContent
                    } else {
                        tagsContent
                    }
                }
                .padding(20)
            }
            
            // Нижняя панель: галочка подкрашивания + сброс
            HStack {
                // Сброс
                Button(action: { DispatchQueue.main.async { settings.resetLRCSettings() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
                        Text(LocalizedStringKey("lrc_reset")).font(.system(size: 11))
                    }.foregroundColor(settings.textMuted)
                }.buttonStyle(.plain)
                
                // Галочка подкрашивания
                HStack(spacing: 4) {
                    Toggle("", isOn: Binding(
                        get: { settings.lrcDimInactive },
                        set: { newValue in DispatchQueue.main.async { settings.setLRCDimInactive(newValue) } }
                    ))
                    .toggleStyle(.checkbox).labelsHidden().scaleEffect(0.8)
                    
                    Text(LocalizedStringKey("tint_inactive"))
                        .font(.system(size: 11)).foregroundColor(settings.textMuted)
                }
                .padding(.leading, 12)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Контент тегов
    
    @ViewBuilder
    private var tagsContent: some View {
        let infoTags = ["orig"] + LyricsParser.languageTags.map { $0 } + LyricsParser.pronunciationTags.map { $0 } + ["trans", "lit", "bg", "rap", "chord"]
        let enabledCount = infoTags.filter { settings.lrcEnabledTags[$0] == true }.count
        
        // Счётчик полей
        HStack(spacing: 6) {
            Text(settings.lrcUnlimitedFields ?
                 NSLocalizedString("lrc_fields_unlimited", comment: "") :
                 String(format: NSLocalizedString("lrc_fields_count", comment: ""), enabledCount, 5))
                .font(.system(size: 10))
                .foregroundColor(!settings.lrcUnlimitedFields && enabledCount > 5 ? .red : settings.textMuted.opacity(0.5))
            
            Toggle("", isOn: Binding(
                get: { settings.lrcUnlimitedFields },
                set: { newValue in
                    settings.lrcUnlimitedFields = newValue
                    settings.save()
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .scaleEffect(0.7)
            
            Text(LocalizedStringKey("lrc_unlimited_label"))
                .font(.system(size: 9))
                .foregroundColor(settings.textMuted.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        
        // Теги
        let currentTags = categories.first(where: { $0.key == selectedTab })?.tags ?? []
        ForEach(currentTags, id: \.tag) { tagInfo in
            LRCTagRow(
                tag: tagInfo.tag, label: tagInfo.label,
                isEnabled: Binding(
                    get: { settings.lrcEnabledTags[tagInfo.tag] ?? false },
                    set: { newValue in DispatchQueue.main.async {
                        var tags = settings.lrcEnabledTags
                        let n = infoTags.filter { tags[$0] == true }.count
                        if !settings.lrcUnlimitedFields && newValue && n >= 5 && ["orig", "trans", "lit", "bg", "rap", "chord"].contains(tagInfo.tag) && !(tags[tagInfo.tag] ?? false) { return }
                        tags[tagInfo.tag] = newValue; settings.setLRCEnabledTags(tags)
                    }}
                ),
                color: Binding(
                    get: { settings.lrcTagColors[tagInfo.tag] ?? "#888888" },
                    set: { newValue in
                        settings.lrcTagColors[tagInfo.tag] = newValue
                        settings.save()
                        NotificationCenter.default.post(name: NSNotification.Name("lrcSettingsChanged"), object: nil)
                    }
                ),
                showOrigOverride: selectedTab == "general" && tagInfo.tag == "orig",
                origOverride: $settings.lrcOrigOverride
            )
        }
    }
    
    // MARK: - Контент метаданных
    
    @ViewBuilder
    private var metadataContent: some View {
        // Строка: галочка + «Показывать метаданные» + Picker позиции
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { settings.lrcShowMetadata },
                set: { settings.setLRCShowMetadata($0) }
            ))
            .toggleStyle(.checkbox).labelsHidden().scaleEffect(0.8)

            Text(LocalizedStringKey("lrc_show_metadata"))
                .font(.system(size: 12, weight: .medium)).foregroundColor(settings.textMain)

            Picker("", selection: Binding(
                get: { settings.lrcMetadataPosition },
                set: { settings.setLRCMetadataPosition($0) }
            )) {
                Text(LocalizedStringKey("lrc_position_before")).tag("before")
                Text(LocalizedStringKey("lrc_position_after")).tag("after")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .disabled(!settings.lrcShowMetadata)
            .fixedSize()
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(settings.darkSurface.opacity(0.5))
        .cornerRadius(8)

        // Цвет метаданных
        HStack(spacing: 10) {
            NativeColorWell(hex: $settings.lrcMetadataColor)
                .disabled(!settings.lrcShowMetadata)
            Text(LocalizedStringKey("lrc_metadata_color"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(settings.lrcShowMetadata ? settings.textMain : settings.textMuted.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(settings.darkSurface.opacity(0.5))
        .cornerRadius(8)

        // Выбор полей метаданных
        let metaFields = ["title", "artist", "album", "author", "length"]
        let metaLabels = [
            "title": NSLocalizedString("lrc_meta_title", comment: ""),
            "artist": NSLocalizedString("lrc_meta_artist", comment: ""),
            "album": NSLocalizedString("lrc_meta_album", comment: ""),
            "author": NSLocalizedString("lrc_meta_author", comment: ""),
            "length": NSLocalizedString("lrc_meta_length", comment: "")
        ]

        ForEach(metaFields, id: \.self) { field in
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { settings.lrcMetadataFields[field] ?? false },
                    set: { newValue in
                        var fields = settings.lrcMetadataFields
                        fields[field] = newValue
                        settings.setLRCMetadataFields(fields)
                    }
                ))
                .toggleStyle(.checkbox).labelsHidden().scaleEffect(0.8)
                .disabled(!settings.lrcShowMetadata)

                Text(metaLabels[field] ?? field)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(settings.lrcShowMetadata ? settings.textMain : settings.textMuted.opacity(0.4))
                Spacer()
                Text("<\(field)>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(settings.textMuted.opacity(0.4))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(settings.darkSurface.opacity(0.5))
            .cornerRadius(8)
        }
    }
}

// MARK: - Строка тега (без изменений)

struct LRCTagRow: View {
    let tag: String
    let label: String
    @Binding var isEnabled: Bool
    @Binding var color: String
    var showOrigOverride: Bool = false
    @Binding var origOverride: Bool
    
    @ObservedObject private var settings = SettingsManager.shared
    
    init(tag: String, label: String, isEnabled: Binding<Bool>, color: Binding<String>, showOrigOverride: Bool = false, origOverride: Binding<Bool> = .constant(false)) {
        self.tag = tag
        self.label = label
        self._isEnabled = isEnabled
        self._color = color
        self.showOrigOverride = showOrigOverride
        self._origOverride = origOverride
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isEnabled).toggleStyle(.checkbox).labelsHidden().frame(width: 20)
            NativeColorWell(hex: $color).disabled(!isEnabled)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(isEnabled ? settings.textMain : settings.textMuted.opacity(0.4))
                Text("<\(tag)>").font(.system(size: 9, design: .monospaced)).foregroundColor(settings.textMuted.opacity(0.4))
            }
            Spacer()
            
            if showOrigOverride {
                Text(LocalizedStringKey("lrc_orig_override"))
                    .font(.system(size: 10))
                    .foregroundColor(settings.textMuted.opacity(0.6))
                Toggle("", isOn: $origOverride)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            
            Text("Aa").font(.system(size: 13, weight: .bold))
                .foregroundColor(isEnabled ? Color(nsColor: NSColor(hex: color) ?? .white) : Color.clear).frame(width: 28)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(settings.darkSurface.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - ColorWell и ColorPanelManager (без изменений)

struct NativeColorWell: View {
    @Binding private var hex: String
    
    init(hex: Binding<String>) {
        self._hex = hex
    }
    
    var body: some View {
        Button(action: {
            ColorPanelManager.shared.show(hex: $hex)
        }) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: NSColor(hex: hex) ?? .white))
                .frame(width: 32, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

class ColorPanelManager: NSObject {
    static let shared = ColorPanelManager()
    private var currentHex: Binding<String>?
    
    func show(hex: Binding<String>) {
        if currentHex != nil {
            NSColorPanel.shared.close()
        }
        
        currentHex = hex
        
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = NSColor(hex: hex.wrappedValue) ?? .white
        panel.makeKeyAndOrderFront(nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelWillClose),
            name: NSWindow.willCloseNotification,
            object: panel
        )
    }
    
    @objc private func colorChanged(_ sender: NSColorPanel) {
        currentHex?.wrappedValue = sender.color.toHex()
    }
    
    @objc private func panelWillClose() {
        currentHex = nil
        NotificationCenter.default.removeObserver(self)
    }
}
