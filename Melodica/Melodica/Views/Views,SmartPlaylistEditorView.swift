// Views,SmartPlaylistEditorView.swift
import SwiftUI

struct SmartPlaylistEditorView: View {
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
                .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        .background(Color.darkBg)
    }

    private var header: some View {
        HStack {
            Text(playlist == nil
                 ? LocalizedStringKey("smart_playlist_new_title")
                 : LocalizedStringKey("smart_playlist_edit_title"))
                .font(.title3.bold())
                .foregroundColor(.textMain)

            Spacer()

            Button(LocalizedStringKey("cancel")) { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.textMuted)

            Button(LocalizedStringKey("save")) { save() }
                .buttonStyle(.borderedProminent)
                .tint(.accent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("smart_playlist_name"))
                .font(.caption)
                .foregroundColor(.textMuted)

            TextField(LocalizedStringKey("smart_playlist_name_placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey("smart_playlist_rules"))
                .font(.caption)
                .foregroundColor(.textMuted)

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
                .textFieldStyle(.roundedBorder)
            } else if editable.kind == .yearGreaterThan ||
                      editable.kind == .yearLessThan ||
                      editable.kind == .yearEquals ||
                      editable.kind == .durationGreaterThan ||
                      editable.kind == .durationLessThan {
                TextField(
                    LocalizedStringKey("smart_playlist_number"),
                    text: $rules[index].numberValue
                )
                .textFieldStyle(.roundedBorder)
            }

            if editable.kind == .hasLyrics ||
               editable.kind == .hasReplayGain ||
               editable.kind == .isFavorite {
                Toggle("", isOn: $rules[index].boolValue)
                    .toggleStyle(.switch)
                    .tint(.accent)
            }

            Button {
                rules.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private var matchSection: some View {
        Toggle(
            LocalizedStringKey("smart_playlist_match_all"),
            isOn: $matchAll
        )
        .tint(.accent)
        .foregroundColor(.textMain)
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

struct EditableRule: Identifiable {
    let id = UUID()

    var kind: RuleKind
    var textValue: String = ""
    var numberValue: String = ""
    var boolValue: Bool = true

    enum RuleKind: String, CaseIterable, Identifiable {
        case titleContains
        case artistContains
        case artistEquals
        case albumContains
        case albumEquals
        case genreContains
        case genreEquals
        case yearGreaterThan
        case yearLessThan
        case yearEquals
        case durationGreaterThan
        case durationLessThan
        case hasLyrics
        case hasReplayGain
        case isFavorite

        var id: String { rawValue }

        var localizationKey: String {
            switch self {
            case .titleContains:       return "rule_title_contains"
            case .artistContains:      return "rule_artist_contains"
            case .artistEquals:        return "rule_artist_equals"
            case .albumContains:       return "rule_album_contains"
            case .albumEquals:         return "rule_album_equals"
            case .genreContains:       return "rule_genre_contains"
            case .genreEquals:         return "rule_genre_equals"
            case .yearGreaterThan:     return "rule_year_greater"
            case .yearLessThan:        return "rule_year_less"
            case .yearEquals:          return "rule_year_equal"
            case .durationGreaterThan: return "rule_duration_greater"
            case .durationLessThan:    return "rule_duration_less"
            case .hasLyrics:           return "rule_has_lyrics"
            case .hasReplayGain:       return "rule_has_replaygain"
            case .isFavorite:          return "rule_is_favorite"
            }
        }
    }

    init(kind: RuleKind) {
        self.kind = kind
    }

    init(rule: SmartPlaylistRule) {
        switch rule {
        case .titleContains(let v):
            kind = .titleContains
            textValue = v
        case .artistContains(let v):
            kind = .artistContains
            textValue = v
        case .artistEquals(let v):
            kind = .artistEquals
            textValue = v
        case .albumContains(let v):
            kind = .albumContains
            textValue = v
        case .albumEquals(let v):
            kind = .albumEquals
            textValue = v
        case .genreContains(let v):
            kind = .genreContains
            textValue = v
        case .genreEquals(let v):
            kind = .genreEquals
            textValue = v
        case .yearGreaterThan(let v):
            kind = .yearGreaterThan
            numberValue = String(v)
        case .yearLessThan(let v):
            kind = .yearLessThan
            numberValue = String(v)
        case .yearEquals(let v):
            kind = .yearEquals
            numberValue = String(v)
        case .durationGreaterThan(let v):
            kind = .durationGreaterThan
            numberValue = String(Int(v))
        case .durationLessThan(let v):
            kind = .durationLessThan
            numberValue = String(Int(v))
        case .hasLyrics(let v):
            kind = .hasLyrics
            boolValue = v
        case .hasReplayGain(let v):
            kind = .hasReplayGain
            boolValue = v
        case .isFavorite(let v):
            kind = .isFavorite
            boolValue = v
        }
    }

    func toRule() -> SmartPlaylistRule? {
        switch kind {
        case .titleContains:
            return .titleContains(textValue)
        case .artistContains:
            return .artistContains(textValue)
        case .artistEquals:
            return .artistEquals(textValue)
        case .albumContains:
            return .albumContains(textValue)
        case .albumEquals:
            return .albumEquals(textValue)
        case .genreContains:
            return .genreContains(textValue)
        case .genreEquals:
            return .genreEquals(textValue)
        case .yearGreaterThan:
            guard let v = Int(numberValue) else { return nil }
            return .yearGreaterThan(v)
        case .yearLessThan:
            guard let v = Int(numberValue) else { return nil }
            return .yearLessThan(v)
        case .yearEquals:
            guard let v = Int(numberValue) else { return nil }
            return .yearEquals(v)
        case .durationGreaterThan:
            guard let v = Int(numberValue) else { return nil }
            return .durationGreaterThan(TimeInterval(v))
        case .durationLessThan:
            guard let v = Int(numberValue) else { return nil }
            return .durationLessThan(TimeInterval(v))
        case .hasLyrics:
            return .hasLyrics(boolValue)
        case .hasReplayGain:
            return .hasReplayGain(boolValue)
        case .isFavorite:
            return .isFavorite(boolValue)
        }
    }
}
