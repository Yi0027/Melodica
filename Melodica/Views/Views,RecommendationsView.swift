// Views/RecommendationsView.swift
import SwiftUI

struct RecommendationsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?

    @State private var sections: [RecommendationSection] = []
    @State private var mixedItems: [RecommendationItem] = []

    @State private var selectedSectionID: UUID?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let sectionID = selectedSectionID,
               let section = sections.first(where: { $0.id == sectionID }) {
                recommendationDetail(section)
            } else {
                recommendationsGrid
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedSectionID)
        .background(Color.darkBg)
        .onAppear {
            loadRecommendations()
        }
        .onChange(of: libraryVM.tracks.count) {
            loadRecommendations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recommendationsDidUpdate)) { _ in
            loadRecommendations()
        }
    }

    // MARK: - Recommendations Grid

    private var recommendationsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .tint(.accent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if !mixedItems.isEmpty {
                        mixedSection
                    }

                    if !sections.isEmpty {
                        sectionsList
                    }

                    if mixedItems.isEmpty && sections.isEmpty {
                        emptyState
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Mixed Feed

    private var mixedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accent)

                Text(LocalizedStringKey("rec_mixed"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textMain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(mixedItems) { item in
                        RecommendationCard(item: item) {
                            selectedTrackID = item.track.id
                            let tracks = mixedItems.map { $0.track }
                            playerVM.startPlayback(track: item.track, from: tracks, contextID: "rec_mixed")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Sections List

    private var sectionsList: some View {
        VStack(spacing: 8) {
            ForEach(sections) { section in
                RecommendationSectionRow(
                    section: section
                )
                .onTapGesture {
                    selectedSectionID = section.id
                }
            }
        }
    }

    // MARK: - Section Detail

    private func recommendationDetail(
        _ section: RecommendationSection
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedSectionID = nil
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 32, height: 28)

                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let artURL = section.items.first?.track.thumbURL(size: "84") ?? section.items.first?.track.albumArtURL {
                    CachedImage(url: artURL, size: CGSize(width: 42, height: 42))
                        .cornerRadius(6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 42, height: 42)

                        Image(systemName: section.type.icon)
                            .font(.system(size: 18))
                            .foregroundColor(.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain)
                        .lineLimit(1)

                    let count = section.items.count
                    let countText = String(format: NSLocalizedString("tracks_count", comment: ""), count)
                    Text(countText)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.darkSurface.opacity(0.8))

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(section.items) { item in
                        recommendationTrackRow(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.darkBg)
    }

    // MARK: - Section Track Row

    private func recommendationTrackRow(
        _ item: RecommendationItem
    ) -> some View {
        let contextID = selectedSectionID.map { "rec_section:\($0)" } ?? "rec_section"
        return TrackRowView(
            track: item.track,
            isCurrent: playerVM.isTrackCurrent(item.track, inContext: contextID),
            isPlaying: playerVM.isPlaying,
            onAddToQueue: { playerVM.addToQueue(item.track) },
            isInQueue: playerVM.queue.contains(where: { $0.id == item.track.id }),
            onRemoveFromQueue: { playerVM.removeFromQueue(item.track) },
            onToggleFavorite: { playerVM.toggleFavorite(item.track) },
            isFavorite: playerVM.isFavorite(item.track),
            showTrackNumber: false,
            onDoubleClick: {
                selectedTrackID = item.track.id
                let tracks = sectionItemsTracks()
                playerVM.startPlayback(track: item.track, from: tracks, contextID: contextID)
            },
            onShowInAlbum: nil,
            isHighlighted: false
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func sectionItemsTracks() -> [Track] {
        guard let sectionID = selectedSectionID,
              let section = sections.first(where: { $0.id == sectionID }) else {
            return []
        }

        return section.items.map { $0.track }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 36))
                .foregroundColor(.textMuted.opacity(0.3))

            Text(LocalizedStringKey("rec_empty_title"))
                .font(.system(size: 13))
                .foregroundColor(.textMuted.opacity(0.5))

            Text(LocalizedStringKey("rec_empty_hint"))
                .font(.system(size: 11))
                .foregroundColor(.textMuted.opacity(0.35))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Loading

    private func loadRecommendations() {
        guard SettingsManager.shared.trackStatisticsEnabled else {
            sections = []
            mixedItems = []
            return
        }

        let tracks = libraryVM.tracks

        guard !tracks.isEmpty else {
            sections = []
            mixedItems = []
            return
        }

        let favIDs = Set(playerVM.favorites.map { $0.id })
        isLoading = true

        Task.detached(priority: .userInitiated) {
            let service = RecommendationService.shared

            let (builtSections, mixed) = await service.buildAll(
                from: tracks,
                favoriteTrackIDs: favIDs,
                sectionLimit: 10,
                mixedLimit: 1000
            )

            await MainActor.run {
                self.sections = builtSections
                self.mixedItems = mixed
                self.isLoading = false
            }
        }
    }
}

// MARK: - Section Row

struct RecommendationSectionRow: View {
    let section: RecommendationSection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.type.icon)
                .foregroundColor(.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMain)
                    .lineLimit(1)

                Text(sectionReason)
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(section.items.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textMuted)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.02))
        )
        .contentShape(Rectangle())
    }

    private var sectionReason: String {
        switch section.type {
        case .timeOfDay:
            return section.items.first?.reason ?? ""
        case .weekday:
            return section.items.first?.reason ?? ""
        default:
            return ""
        }
    }
}

// MARK: - Card for Mixed Feed

struct RecommendationCard: View {
    let item: RecommendationItem
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let artURL = item.track.thumbURL(size: "200") ?? item.track.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: 120, height: 120))
                    .frame(width: 120, height: 120)
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.darkSurface)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 28))
                            .foregroundColor(.textMuted.opacity(0.4))
                    )
            }

            VStack(spacing: 2) {
                Text(item.track.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMain)
                    .lineLimit(1)
                    .frame(width: 120)

                Text(item.track.artist)
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                    .frame(width: 120)
            }
        }
        .padding(8)
        .background(Color.darkSurface.opacity(0.5))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
