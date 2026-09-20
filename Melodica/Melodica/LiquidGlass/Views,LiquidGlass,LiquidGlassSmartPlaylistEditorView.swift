import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassSmartPlaylistEditorView: View {
    @ObservedObject var vm: SmartPlaylistViewModel
    let playlist: SmartPlaylist?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var matchAll: Bool
    @State private var rules: [EditableRule]

    init(vm: SmartPlaylistViewModel, playlist: SmartPlaylist?) {
        self.vm = vm
        self.playlist = playlist

        _name = State(initialValue: playlist?.name ?? "")
        _icon = State(initialValue: playlist?.icon ?? "sparkles")
        _matchAll = State(initialValue: playlist?.matchAll ?? true)
        _rules = State(initialValue: playlist?.rules.map { EditableRule(rule: $0) } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 20) {
                    nameSection
                    rulesSection
                    matchSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(playlist == nil
                 ? LocalizedStringKey("smart_playlist_new_title")
                 : LocalizedStringKey("smart_playlist_edit_title"))
                .font(.title3.bold())
                .foregroundColor(.primary)

            Spacer()

            Button(LocalizedStringKey("cancel")) { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            Button(LocalizedStringKey("save")) { save() }
                .buttonStyle(.glassProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 0))
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("smart_playlist_name"))
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(LocalizedStringKey("smart_playlist_name_placeholder"), text: $name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("smart_playlist_rules"))
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                ruleRow(index, rule)
            }

            Menu {
                ForEach(EditableRule.RuleKind.allCases) { kind in
                    Button(LocalizedStringKey(kind.localizationKey)) {
                        rules.append(EditableRule(kind: kind))
                    }
                }
            } label: {
                Label(LocalizedStringKey("smart_playlist_add_rule"), systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.glass)
        }
    }

    private func ruleRow(_ index: Int, _ editable: EditableRule) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: $rules[index].kind) {
                ForEach(EditableRule.RuleKind.allCases) { kind in
                    Text(LocalizedStringKey(kind.localizationKey))
                        .tag(kind)
                }
            }
            .frame(width: 190)

            if editable.kind == .genreContains || editable.kind == .genreEquals {
                glassGenrePicker(selection: $rules[index].textValue)
            } else if editable.kind == .titleContains ||
                      editable.kind == .artistContains ||
                      editable.kind == .artistEquals ||
                      editable.kind == .albumContains ||
                      editable.kind == .albumEquals {
                TextField(
                    LocalizedStringKey("smart_playlist_value"),
                    text: $rules[index].textValue
                )
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            } else if editable.kind == .yearGreaterThan ||
                      editable.kind == .yearLessThan ||
                      editable.kind == .yearEquals ||
                      editable.kind == .durationGreaterThan ||
                      editable.kind == .durationLessThan ||
                      editable.kind == .ratingGreaterThan ||
                      editable.kind == .ratingLessThan ||
                      editable.kind == .ratingEquals {
                TextField(
                    LocalizedStringKey("smart_playlist_number"),
                    text: $rules[index].numberValue
                )
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if editable.kind == .hasLyrics ||
               editable.kind == .hasReplayGain ||
               editable.kind == .isFavorite ||
               editable.kind == .hasRating {
                Toggle("", isOn: $rules[index].boolValue)
                    .toggleStyle(.switch)
                    .tint(Color.accentColor)
            }

            Button {
                rules.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Genre picker

    @ViewBuilder
    private func glassGenrePicker(selection: Binding<String>) -> some View {
        let genres = LibraryViewModel.shared?.availableGenres ?? []
        let current = selection.wrappedValue

        Menu {
            if genres.isEmpty {
                Text(LocalizedStringKey("eq_preset_no_genres"))
            } else {
                ForEach(genres, id: \.self) { genre in
                    Button {
                        selection.wrappedValue = genre
                    } label: {
                        if genre.caseInsensitiveCompare(current) == .orderedSame {
                            Label(genre, systemImage: "checkmark")
                        } else {
                            Text(genre)
                        }
                    }
                }
            }

            Divider()

            Button {
                promptForCustomGenre(selection: selection)
            } label: {
                Label(LocalizedStringKey("custom"), systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 6) {
                Text(current.isEmpty
                     ? NSLocalizedString("smart_playlist_value", comment: "")
                     : current)
                    .foregroundColor(current.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 160, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func promptForCustomGenre(selection: Binding<String>) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("smart_playlist_value", comment: "")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = selection.wrappedValue
        alert.accessoryView = tf
        alert.addButton(withTitle: NSLocalizedString("save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        alert.window.initialFirstResponder = tf
        if alert.runModal() == .alertFirstButtonReturn {
            let v = tf.stringValue.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { selection.wrappedValue = v }
        }
    }

    private var matchSection: some View {
        Toggle(
            LocalizedStringKey("smart_playlist_match_all"),
            isOn: $matchAll
        )
        .tint(Color.accentColor)
        .foregroundColor(.primary)
    }

    private func save() {
        let finalRules = rules.compactMap { $0.toRule() }

        let finalPlaylist = SmartPlaylist(
            id: playlist?.id ?? UUID(),
            name: name,
            icon: icon,
            rules: finalRules,
            matchAll: matchAll
        )

        if playlist == nil {
            vm.add(finalPlaylist)
        } else {
            vm.update(finalPlaylist)
        }

        dismiss()
    }
}
