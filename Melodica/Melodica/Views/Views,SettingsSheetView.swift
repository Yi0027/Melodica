// SettingsSheetView.swift (полный файл)
import SwiftUI

// MARK: - Секции настроек

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "general"
    case theme = "theme"
    case folder = "folder"
    case lrc = "lrc"
    
    var id: String { rawValue }
    
    var titleKey: LocalizedStringKey {
        switch self {
        case .general: return "settings_general"
        case .theme: return "settings_theme"
        case .folder: return "settings_folder"
        case .lrc: return "settings_lrc"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .theme: return "paintbrush"
        case .folder: return "folder"
        case .lrc: return "text.bubble"
        }
    }
    
    var localizedTitle: String {
        switch self {
        case .general: return NSLocalizedString("settings_general", comment: "")
        case .theme: return NSLocalizedString("settings_theme", comment: "")
        case .folder: return NSLocalizedString("settings_folder", comment: "")
        case .lrc: return NSLocalizedString("settings_lrc", comment: "")
        }
    }
    
    var searchItems: [(titleKey: String, icon: String)] {
        switch self {
        case .general:
            return [
                ("update_frequency", "clock.arrow.circlepath"),
                ("grid_size", "square.grid.2x2"),
                ("language", "globe")
            ]
        case .theme:
            return [
                ("theme_select", "paintbrush"),
                ("color_theme", "swatchpalette"),
                ("theme_default", "rectangle.fill"),
                ("theme_liquid_glass", "drop.fill")
            ]
        case .folder:
            return [
                ("watched_folders", "folder"),
                ("add_folder", "externaldrive.badge.plus"),
                ("rescan", "arrow.clockwise"),
                ("thumbnail_speed", "photo.stack")
            ]
        case .lrc:
            return [
                ("lrc_settings_title", "text.bubble"),
                ("lrc_mode_title", "switch.2"),
                ("lrc_show_metadata", "info.circle"),
                ("lrc_cat_general", "textformat"),
                ("lrc_cat_languages", "globe"),
                ("lrc_cat_pronunciation", "character.book.closed")
            ]
        }
    }
}

// MARK: - Результат поиска

struct SettingsSearchResult: Identifiable {
    let id = UUID()
    let section: SettingsSection
    let title: String
    let icon: String
    let relevance: Int
}

// MARK: - Основной View

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: SettingsSection = .general
    @State private var searchText = ""
    @State private var cachedSearchResults: [SettingsSearchResult] = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Поиск + заголовок
            HStack(spacing: 16) {
                Text(LocalizedStringKey("settings_title"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textMain)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                    
                    TextField(LocalizedStringKey("search_settings"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.textMain)
                        .frame(width: 180)
                        .focused($isSearchFocused)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isSearchFocused = false
                            }
                        }
                        .onChange(of: searchText) { _ in
                            updateSearchResults()
                        }
                        .onSubmit {
                            if let firstResult = cachedSearchResults.first {
                                navigateToResult(firstResult)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            cachedSearchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.darkSurface)
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Если есть поисковый запрос — показываем результаты
            if !searchText.isEmpty {
                searchResultsView
            } else {
                // Обычный режим: вкладки + контент
                VStack(spacing: 0) {
                    // Навигация
                    HStack(spacing: 4) {
                        ForEach(SettingsSection.allCases) { section in
                            sectionButton(section)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    
                    Divider()
                    
                    // Контент
                    ScrollView {
                        sectionContent
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Кнопка закрытия
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Text(LocalizedStringKey("close"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.darkSurface)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(width: 700, height: 560)
        .background(Color.darkBg)
        .onTapGesture {
            isSearchFocused = false
        }
    }
    
    // MARK: - Навигация к результату
    
    private func navigateToResult(_ result: SettingsSearchResult) {
        let targetSection = result.section
        
        withAnimation(.easeInOut(duration: 0.2)) {
            searchText = ""
            isSearchFocused = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            selectedSection = targetSection
        }
    }
    
    // MARK: - Обновление результатов поиска
    
    private func updateSearchResults() {
        guard !searchText.isEmpty else {
            cachedSearchResults = []
            return
        }
        
        let query = searchText.lowercased()
        var results: [SettingsSearchResult] = []
        
        for section in SettingsSection.allCases {
            // Проверяем заголовок секции
            let sectionTitle = section.localizedTitle
            if sectionTitle.lowercased().contains(query) {
                results.append(SettingsSearchResult(
                    section: section,
                    title: sectionTitle,
                    icon: section.icon,
                    relevance: 0
                ))
            }
            
            // Проверяем элементы секции
            for item in section.searchItems {
                let localizedTitle = NSLocalizedString(item.titleKey, comment: "")
                let localizedLower = localizedTitle.lowercased()
                
                if localizedLower == query {
                    results.append(SettingsSearchResult(section: section, title: localizedTitle, icon: item.icon, relevance: 0))
                } else if localizedLower.hasPrefix(query) {
                    results.append(SettingsSearchResult(section: section, title: localizedTitle, icon: item.icon, relevance: 1))
                } else if localizedLower.contains(query) {
                    results.append(SettingsSearchResult(section: section, title: localizedTitle, icon: item.icon, relevance: 2))
                }
            }
        }
        
        // Убираем дубликаты и сортируем
        var uniqueResults: [SettingsSearchResult] = []
        var seenKeys = Set<String>()
        
        for result in results.sorted(by: { $0.relevance < $1.relevance }) {
            let key = "\(result.section.id)-\(result.title)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniqueResults.append(result)
            }
        }
        
        cachedSearchResults = uniqueResults
    }
    
    // MARK: - Кнопка секции
    
    private func sectionButton(_ section: SettingsSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                Text(section.titleKey)
                    .font(.system(size: 11, weight: selectedSection == section ? .semibold : .regular))
            }
            .foregroundColor(selectedSection == section ? .textMain : .textMuted.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedSection == section ? Color.accent.opacity(0.2) : Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Контент секции
    
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .theme:
            ThemeSettingsView()
        case .folder:
            FolderSettingsView()
        case .lrc:
            LRCSettingsView()
        }
    }
    
    // MARK: - Результаты поиска
    
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(cachedSearchResults) { result in
                    Button {
                        navigateToResult(result)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.icon)
                                .font(.system(size: 14))
                                .foregroundColor(.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textMain)
                                Text(result.section.titleKey)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textMuted.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.textMuted.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.darkSurface.opacity(0.5))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
                
                if cachedSearchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.textMuted.opacity(0.3))
                        Text(LocalizedStringKey("no_results"))
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.top, 40)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Частота обновления прогресс-бара
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("update_frequency"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    HStack(spacing: 12) {
                        Text("\(Int(settings.progressUpdateInterval)) ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(settings.textMuted)
                            .frame(width: 60, alignment: .leading)
                        
                        Slider(value: Binding(
                            get: { settings.progressUpdateInterval },
                            set: { settings.setProgressInterval($0) }
                        ), in: 50...1000, step: 50)
                        .tint(settings.accent)
                    }
                    
                    Text(LocalizedStringKey("update_frequency_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Размер плиток
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("grid_size"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    HStack(spacing: 12) {
                        Text("\(Int(settings.albumGridSize)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(settings.textMuted)
                            .frame(width: 60, alignment: .leading)
                        
                        Slider(value: Binding(
                            get: { settings.albumGridSize },
                            set: { settings.setAlbumGridSize($0) }
                        ), in: 120...200, step: 10)
                        .tint(settings.accent)
                    }
                    
                    Text(LocalizedStringKey("grid_size_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Выбор языка
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("language"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    HStack(spacing: 16) {
                        Button(action: { settings.setLanguage("ru") }) {
                            HStack {
                                Image(systemName: settings.language == "ru" ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                Text(LocalizedStringKey("russian"))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(settings.language == "ru" ? .accent : settings.textMuted)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { settings.setLanguage("en") }) {
                            HStack {
                                Image(systemName: settings.language == "en" ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                Text(LocalizedStringKey("english"))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(settings.language == "en" ? .accent : settings.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text(LocalizedStringKey("restart_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Theme Settings

struct ThemeSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    private var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("theme_select"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    HStack(spacing: 16) {
                        // Default
                        Button {
                            settings.setTheme("default")
                            restartApp()
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.07, green: 0.07, blue: 0.10))
                                    .frame(width: 80, height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(settings.activeTheme == "default" ? Color.accent : Color.white.opacity(0.2), lineWidth: 2)
                                    )
                                Text(LocalizedStringKey("theme_default"))
                                    .font(.system(size: 11, weight: settings.activeTheme == "default" ? .semibold : .regular))
                                    .foregroundColor(settings.activeTheme == "default" ? .textMain : .textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Liquid Glass
                        Button {
                            if isLiquidGlassAvailable {
                                settings.setTheme("liquid_glass")
                                restartApp()
                            } else {
                                showUnavailableAlert()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isLiquidGlassAvailable ? Color(red: 0.15, green: 0.15, blue: 0.2) : Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 50)
                                    
                                    if !isLiquidGlassAvailable {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(settings.activeTheme == "liquid_glass" ? Color.accent : Color.white.opacity(0.2), lineWidth: 2)
                                )
                                
                                Text(LocalizedStringKey("theme_liquid_glass"))
                                    .font(.system(size: 11, weight: settings.activeTheme == "liquid_glass" ? .semibold : .regular))
                                    .foregroundColor(isLiquidGlassAvailable ? (settings.activeTheme == "liquid_glass" ? .textMain : .textMuted) : .textMuted.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!isLiquidGlassAvailable)
                    }
                    
                    if !isLiquidGlassAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.yellow)
                            Text(LocalizedStringKey("theme_requires_macos26"))
                                .font(.system(size: 11))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.top, 4)
                    }
                    
                    Text(LocalizedStringKey("theme_restart_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
                
                if settings.activeTheme == "default" {
                    Divider().background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LocalizedStringKey("color_theme"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(settings.textMain)
                        
                        ColorRow(label: LocalizedStringKey("background"), r: $settings.theme.darkBgR, g: $settings.theme.darkBgG, b: $settings.theme.darkBgB, alpha: $settings.theme.darkBgAlpha)
                        ColorRow(label: LocalizedStringKey("surface"), r: $settings.theme.darkSurfaceR, g: $settings.theme.darkSurfaceG, b: $settings.theme.darkSurfaceB, alpha: $settings.theme.darkSurfaceAlpha)
                        ColorRow(label: LocalizedStringKey("accent"), r: $settings.theme.accentR, g: $settings.theme.accentG, b: $settings.theme.accentB, alpha: $settings.theme.accentAlpha)
                        ColorRow(label: LocalizedStringKey("text"), r: $settings.theme.textMainR, g: $settings.theme.textMainG, b: $settings.theme.textMainB, alpha: $settings.theme.textMainAlpha)
                        ColorRow(label: LocalizedStringKey("text_secondary"), r: $settings.theme.textMutedR, g: $settings.theme.textMutedG, b: $settings.theme.textMutedB, alpha: $settings.theme.textMutedAlpha)
                        ColorRow(label: LocalizedStringKey("lyrics_text"), r: $settings.theme.lyricActiveR, g: $settings.theme.lyricActiveG, b: $settings.theme.lyricActiveB, alpha: $settings.theme.lyricActiveAlpha)
                        ColorRow(label: LocalizedStringKey("player_controls"), r: $settings.theme.playerControlsR, g: $settings.theme.playerControlsG, b: $settings.theme.playerControlsB, alpha: $settings.theme.playerControlsAlpha)
                    }
                    
                    Button(action: { settings.resetToDefaults() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text(LocalizedStringKey("reset_colors"))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(settings.textMuted)
                    }
                    .buttonStyle(.plain)
                } else if isLiquidGlassAvailable {
                    Divider().background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("liquid_glass_info"))
                            .font(.system(size: 12))
                            .foregroundColor(settings.textMuted)
                        Text(LocalizedStringKey("liquid_glass_system_colors"))
                            .font(.system(size: 10))
                            .foregroundColor(settings.textMuted.opacity(0.5))
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func showUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("theme_unavailable", comment: "")
        alert.informativeText = NSLocalizedString("theme_requires_macos26", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }
    
    private func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        
        // Жёсткий выход
        exit(0)
    }
}
// MARK: - ColorRow

struct ColorRow: View {
    let label: LocalizedStringKey
    @Binding var r: Double
    @Binding var g: Double
    @Binding var b: Double
    var alpha: Binding<Double>? = nil
    
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: r, green: g, blue: b).opacity(alpha?.wrappedValue ?? 1.0))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(settings.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 4) {
                TextField("0-255", value: Binding(get: { Int(r * 255) }, set: { r = Double(min(max($0, 0), 255)) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.textMain)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                
                TextField("0-255", value: Binding(get: { Int(g * 255) }, set: { g = Double(min(max($0, 0), 255)) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.textMain)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                
                TextField("0-255", value: Binding(get: { Int(b * 255) }, set: { b = Double(min(max($0, 0), 255)) / 255.0 }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.textMain)
                    .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
            }
            
            if let alpha = alpha {
                VStack(spacing: 2) {
                    Text(LocalizedStringKey("transparency_short"))
                        .font(.system(size: 8))
                        .foregroundColor(.textMuted.opacity(0.5))
                    TextField("0-100", value: Binding(get: { Int(alpha.wrappedValue * 100) }, set: { alpha.wrappedValue = Double(min(max($0, 0), 100)) / 100.0 }), format: .number)
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundColor(.textMain)
                        .frame(width: 45).padding(4).background(Color.white.opacity(0.05)).cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Folder Settings

struct FolderSettingsView: View {
    @ObservedObject var libraryVM = LibraryViewModel.shared!
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Список папок
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("watched_folders"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    if libraryVM.watchedFolders.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 24))
                                .foregroundColor(settings.textMuted.opacity(0.3))
                            Text(LocalizedStringKey("no_folders"))
                                .font(.system(size: 12))
                                .foregroundColor(settings.textMuted.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(libraryVM.watchedFolders, id: \.url) { folder in
                                HStack {
                                    Button(action: { libraryVM.toggleFolderVisibility(folder.url) }) {
                                        Image(systemName: folder.isVisible ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(folder.isVisible ? .accent : .textMuted.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accent)
                                    Text(folder.url.lastPathComponent)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textMain)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: { libraryVM.removeWatchedFolder(folder.url) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.textMuted.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(settings.darkSurface.opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Кнопки
                    HStack(spacing: 12) {
                        Button(action: openFolder) {
                            HStack {
                                Image(systemName: "externaldrive.badge.plus")
                                Text(LocalizedStringKey("add_folder"))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(settings.darkSurface)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { libraryVM.rescanAllFolders() }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(LocalizedStringKey("rescan"))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(settings.darkSurface)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Скорость создания миниатюр
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("thumbnail_speed"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.textMain)
                    
                    HStack(spacing: 8) {
                        ForEach([0, 0.02, 0.05, 0.1, 0.15, 0.2], id: \.self) { speed in
                            Button(action: {
                                settings.setThumbnailCreationSpeed(speed)
                            }) {
                                Text("\(Int(speed * 1000))")
                                    .font(.system(size: 11, weight: settings.thumbnailCreationSpeed == speed ? .bold : .regular))
                                    .foregroundColor(settings.thumbnailCreationSpeed == speed ? .white : .textMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(settings.thumbnailCreationSpeed == speed ? Color.accent : Color.white.opacity(0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Text(LocalizedStringKey("thumbnail_speed_hint"))
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                }
            }
            .padding(20)
        }
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("choose_folder", comment: "")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                LibraryViewModel.shared?.addFolder(url)
            }
        }
    }
}
