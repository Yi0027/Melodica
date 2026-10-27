// Views,ArtworkPresetsSettingsView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArtworkPresetsSettingsView: View {
    @ObservedObject var presetManager = ArtworkPresetManager.shared
    @State private var showingAddGroup = false
    @State private var newGroupName = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if presetManager.groups.isEmpty {
                emptyState
            } else {
                groupsList
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color.darkBg)
        .alert(LocalizedStringKey("add_group"), isPresented: $showingAddGroup) {
            TextField(LocalizedStringKey("group_name"), text: $newGroupName)

            Button(LocalizedStringKey("create")) {
                let name = newGroupName.trimmingCharacters(in: .whitespaces)

                if !name.isEmpty {
                    presetManager.addGroup(name: name)
                    newGroupName = ""
                }
            }

            Button(LocalizedStringKey("cancel"), role: .cancel) {
                newGroupName = ""
            }
        }
    }

    private var header: some View {
        HStack {
            Text(LocalizedStringKey("artwork_presets"))
                .font(.title3.bold())
                .foregroundColor(.textMain)

            Spacer()

            Button {
                showingAddGroup = true
            } label: {
                Label(LocalizedStringKey("add_group"), systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderedProminent)
            .tint(.accent)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.textMuted.opacity(0.4))

            Text(LocalizedStringKey("no_artwork_groups"))
                .font(.system(size: 13))
                .foregroundColor(.textMuted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(presetManager.groups) { group in
                    ArtworkPresetGroupRow(group: group)
                }
            }
            .padding(12)
        }
    }
}

struct ArtworkPresetGroupRow: View {
    let group: ArtworkPresetGroup
    @ObservedObject var presetManager = ArtworkPresetManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMain)

                Spacer()

                Button(role: .destructive) {
                    presetManager.removeGroup(group)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if group.artworkPaths.isEmpty {
                Text(LocalizedStringKey("group_empty"))
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(group.artworkPaths.enumerated()), id: \.offset) { index, path in
                            ArtworkPresetThumb(path: path)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        presetManager.removeArtwork(path, from: group)
                                    } label: {
                                        Label(LocalizedStringKey("delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }

            Button {
                addArtwork(to: group)
            } label: {
                Label(LocalizedStringKey("add_artwork_to_group"), systemImage: "plus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.darkSurface.opacity(0.6))
        )
    }

    private func addArtwork(to group: ArtworkPresetGroup) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    presetManager.addArtwork(url.path, to: group)
                }
            }
        }
    }
}

struct ArtworkPresetThumb: View {
    let path: String

    var body: some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .frame(width: 70, height: 70)
        }
    }
}
