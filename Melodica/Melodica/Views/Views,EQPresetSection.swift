// Views/EQPresetSection.swift
import SwiftUI

// MARK: - Preset Section (обычная тема Melodica)

struct EQPresetSectionRegular: View {
    @ObservedObject private var manager = EQPresetManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var eq = EqualizerManager.shared

    @State private var showingCreate = false
    @State private var editingPreset: EQPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            autoToggle
            content
        }
        .sheet(isPresented: $showingCreate) {
            EQPresetEditorSheetRegular(existingPreset: nil)
        }
        .sheet(item: $editingPreset) { preset in
            EQPresetEditorSheetRegular(existingPreset: preset)
        }
    }

    private var header: some View {
        HStack {
            Text(LocalizedStringKey("eq_presets"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(settings.textMain)
            Spacer()
            Button {
                showingCreate = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text(LocalizedStringKey("eq_preset_new"))
                        .font(.system(size: 11))
                }
                .foregroundColor(settings.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var autoToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("eq_presets_auto"))
                    .font(.system(size: 11))
                    .foregroundColor(settings.textMain)
                Text(LocalizedStringKey("eq_presets_auto_hint"))
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.6))
            }
            Spacer()
            Toggle("", isOn: $manager.autoApplyByGenre)
                .toggleStyle(.switch)
                .scaleEffect(0.9)
                .tint(settings.accent)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var content: some View {
        if manager.presets.isEmpty {
            Text(LocalizedStringKey("eq_presets_empty"))
                .font(.system(size: 11))
                .foregroundColor(settings.textMuted.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 2) {
                ForEach(manager.presets) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: EQPreset) -> some View {
        let isActive = manager.activePresetID == preset.id

        return HStack(spacing: 6) {
            Button {
                manager.applyPreset(preset)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? settings.accent : settings.textMuted.opacity(0.4))

                    Text(preset.name)
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? settings.accent : settings.textMain)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if !preset.genres.isEmpty {
                        Text(preset.genres.joined(separator: ", "))
                            .font(.system(size: 9))
                            .foregroundColor(settings.textMuted.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    editingPreset = preset
                } label: {
                    Label(LocalizedStringKey("eq_preset_edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    manager.delete(preset)
                } label: {
                    Label(LocalizedStringKey("delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundColor(settings.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? settings.accent.opacity(0.12) : .clear)
        )
    }
}

// MARK: - Editor sheet (обычная тема)

private struct EQPresetEditorSheetRegular: View {
    let existingPreset: EQPreset?

    @ObservedObject private var manager = EQPresetManager.shared
    @ObservedObject private var eq = EqualizerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedGenres: Set<String> = []
    @State private var allGenres: [String] = []
    @State private var genreSearchText: String = ""

    private var isEditing: Bool { existingPreset != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    nameField
                    if !isEditing { hintText }
                    divider
                    genreList
                    
                }
                .padding(16)
            }

            divider
            footer
        }
        .frame(width: 420, height: 540)
        .background(settings.darkBg)
        .onAppear {
            if let p = existingPreset {
                name = p.name
                selectedGenres = Set(p.genres)
            }
            allGenres = Self.loadGenres()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    private var header: some View {
        HStack {
            Text(LocalizedStringKey(isEditing ? "eq_preset_edit_title" : "eq_preset_create_title"))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(settings.textMain)
            Spacer()
        }
        .padding(16)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey("eq_preset_name"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(settings.textMuted)

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(settings.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.darkSurface.opacity(0.6))
                )
        }
    }

    private var hintText: some View {
        Text(LocalizedStringKey("eq_preset_current_hint"))
            .font(.system(size: 10))
            .foregroundColor(settings.textMuted.opacity(0.6))
    }

    @ViewBuilder
    private var genreList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("eq_preset_genres"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(settings.textMuted)

            if allGenres.isEmpty {
                Text(LocalizedStringKey("eq_preset_no_genres"))
                    .font(.system(size: 11))
                    .foregroundColor(settings.textMuted.opacity(0.5))
            } else {
                genreSearchField

                if filteredGenres.isEmpty {
                    Text(LocalizedStringKey("search_no_results"))
                        .font(.system(size: 11))
                        .foregroundColor(settings.textMuted.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredGenres, id: \.self) { genre in
                            genreRow(genre)
                        }
                    }
                }

                if hiddenGenreCount > 0 {
                    Text(String(
                        format: NSLocalizedString("eq_preset_hidden_genres", comment: ""),
                        hiddenGenreCount
                    ))
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.45))
                    .padding(.top, 4)
                }
            }
        }
    }

    private var genreSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(settings.textMuted)

            TextField(LocalizedStringKey("search_placeholder"), text: $genreSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(settings.textMain)

            if !genreSearchText.isEmpty {
                Button {
                    genreSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(settings.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(settings.darkSurface.opacity(0.6))
        )
    }

    private var filteredGenres: [String] {
        let q = genreSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allGenres.filter { genre in
            // Скрываем занятые другими пресетами
            let isTaken = !manager.conflicts(
                for: [genre],
                excluding: existingPreset?.id
            ).isEmpty
            if isTaken { return false }

            guard !q.isEmpty else { return true }
            return genre.lowercased().contains(q)
        }
    }

    private var hiddenGenreCount: Int {
        allGenres.reduce(into: 0) { acc, genre in
            let isTaken = !manager.conflicts(
                for: [genre],
                excluding: existingPreset?.id
            ).isEmpty
            if isTaken { acc += 1 }
        }
    }

    private func genreRow(_ genre: String) -> some View {
        let isSelected = selectedGenres.contains(genre)

        return Button {
            if isSelected {
                selectedGenres.remove(genre)
            } else {
                selectedGenres.insert(genre)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? settings.accent : settings.textMuted.opacity(0.5))

                Text(genre)
                    .font(.system(size: 12))
                    .foregroundColor(settings.textMain)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? settings.accent.opacity(0.14) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Text(LocalizedStringKey("cancel"))
                    .font(.system(size: 12))
                    .foregroundColor(settings.textMain)
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(settings.darkSurface.opacity(0.7))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                Text(LocalizedStringKey("save"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(canSave ? settings.accent : settings.accent.opacity(0.4))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(16)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let genreList = Array(selectedGenres)

        if let existing = existingPreset {
            manager.rename(existing, to: trimmed)
            manager.updateGenres(existing, genres: genreList)
        } else {
            let gains = eq.bands.map { $0.gain }
            manager.create(name: trimmed, gains: gains, genres: genreList)
        }
        dismiss()
    }

    private static func loadGenres() -> [String] {
        guard let lib = LibraryViewModel.shared else { return [] }
        let unknown = NSLocalizedString("unknown_genre", comment: "")
        return lib.genreGroups
            .map(\.genre)
            .filter { !$0.isEmpty && $0 != unknown }
            .sorted()
    }
}
