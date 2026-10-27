// Views,LiquidGlass,LiquidGlassArtworkPresetPickerView.swift
import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct LiquidGlassArtworkPresetPickerView: View {
    let type: UserArtworkManager.ArtworkType

    @ObservedObject var presetManager = ArtworkPresetManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGroupID: UUID?
    @State private var selectedArtworkPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.primary.opacity(0.1))

            if presetManager.groups.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(LocalizedStringKey("choose_artwork"))
                .font(.title3.bold())
                .foregroundColor(.primary)

            Spacer()

            Button(LocalizedStringKey("cancel")) {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.secondary.opacity(0.4))

            Text(LocalizedStringKey("no_artwork_groups"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Text(LocalizedStringKey("no_artwork_groups_hint"))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.5))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(spacing: 0) {
            groupsSidebar
                .frame(width: 180)

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)

            artworksGrid
        }
    }

    private var groupsSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(presetManager.groups) { group in
                    Button {
                        selectedGroupID = group.id
                        selectedArtworkPath = nil
                    } label: {
                        HStack {
                            Text(group.name)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedGroupID == group.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedGroupID == group.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var artworksGrid: some View {
        VStack(spacing: 12) {
            if let group = presetManager.groups.first(where: { $0.id == selectedGroupID }) {
                if group.artworkPaths.isEmpty {
                    VStack {
                        Spacer()
                        Text(LocalizedStringKey("group_empty"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                            ForEach(Array(group.artworkPaths.enumerated()), id: \.offset) { _, path in
                                artworkThumb(path: path)
                            }
                        }
                        .padding(12)
                    }
                }

                if selectedArtworkPath != nil {
                    Button(LocalizedStringKey("choose")) {
                        applySelectedArtwork()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .padding(.bottom, 12)
                }
            } else {
                VStack {
                    Spacer()
                    Text(LocalizedStringKey("select_group"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func artworkThumb(path: String) -> some View {
        Button {
            selectedArtworkPath = path
        } label: {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedArtworkPath == path ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 120, height: 120)
            }
        }
        .buttonStyle(.plain)
    }

    private func applySelectedArtwork() {
        guard let path = selectedArtworkPath,
              let image = NSImage(contentsOfFile: path) else { return }

        UserArtworkManager.save(image, for: type)
        dismiss()
    }
}
