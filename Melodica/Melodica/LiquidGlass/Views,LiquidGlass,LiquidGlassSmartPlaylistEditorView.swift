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

            if editable.kind == .titleContains ||
               editable.kind == .artistContains ||
               editable.kind == .artistEquals ||
               editable.kind == .albumContains ||
               editable.kind == .albumEquals ||
               editable.kind == .genreContains ||
               editable.kind == .genreEquals {
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
                      editable.kind == .durationLessThan {
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
               editable.kind == .isFavorite {
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
