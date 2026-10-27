import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassRecommendationsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedTrackID: UUID?
    @Binding var selectedSectionID: UUID?

    @State private var sections: [RecommendationSection] = []
    @State private var mixedItems: [RecommendationItem] = []
    @State private var isLoading = false

    @State private var gridPosition = ScrollPosition(idType: UUID.self)
    @State private var detailPosition = ScrollPosition(idType: UUID.self)
    @State private var lastSaveTime: Date?

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
        .onAppear {
            loadRecommendations()
        }
        .onChange(of: libraryVM.tracks.count) {
            loadRecommendations()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recommendationsDidUpdate)) { _ in
            loadRecommendations()
        }
        .onChange(of: selectedSectionID) { _, newID in
            if newID == nil {
                NotificationCenter.default.post(
                    name: .detailHeaderHeightChanged,
                    object: nil,
                    userInfo: ["height": CGFloat(0)]
                )
            }
        }
    }

    // MARK: - Recommendations Grid

    private var recommendationsGrid: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(.accentColor)
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
                .scrollTargetLayout()
            }
            .scrollPosition($gridPosition)
            .onAppear {
                if let saved = ScrollPositionManager.shared.getUUID(key: "liquid_rec_grid") {
                    gridPosition.scrollTo(id: saved, anchor: .top)
                }
            }
            .onChange(of: gridPosition.viewID(type: UUID.self)) { _, newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTime = now
                ScrollPositionManager.shared.saveUUID(key: "liquid_rec_grid", id: id)
            }
            .contentMargins(.vertical, 80, for: .scrollContent)
        }
    }

    // MARK: - Mixed Feed

    private var mixedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)

                Text(LocalizedStringKey("rec_mixed"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(mixedItems) { item in
                        LiquidGlassRecommendationCard(
                            item: item,
                            onTap: {
                                selectedTrackID = item.track.id
                                let tracks = mixedItems.map { $0.track }
                                playerVM.startPlayback(track: item.track, from: tracks, contextID: "rec_mixed")
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Sections List

    private var sectionsList: some View {
        VStack(spacing: 10) {
            ForEach(sections) { section in
                LiquidGlassRecommendationSectionRow(
                    section: section
                )
                .id(section.id)
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
        let contextID = "rec_section:\(section.id)"
        return ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        LiquidGlassRecommendationTrackRow(
                            item: item,
                            isCurrent: playerVM.isTrackCurrent(item.track, inContext: contextID),
                            isPlaying: playerVM.isPlaying,
                            index: index,
                            isSelected: selectedTrackID == item.track.id,
                            onSelect: { selectedTrackID = item.track.id },
                            onAddToQueue: { playerVM.addToQueue(item.track) },
                            isInQueue: playerVM.queue.contains(where: { $0.id == item.track.id }),
                            onRemoveFromQueue: { playerVM.removeFromQueue(item.track) },
                            onToggleFavorite: { playerVM.toggleFavorite(item.track) },
                            isFavorite: playerVM.isFavorite(item.track),
                            onDoubleClick: {
                                selectedTrackID = item.track.id
                                let tracks = section.items.map { $0.track }
                                playerVM.startPlayback(track: item.track, from: tracks, contextID: contextID)
                            }
                        )
                        .id(item.track.id)
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollPosition($detailPosition)
            .onAppear {
                if let saved = ScrollPositionManager.shared.getUUID(key: "liquid_rec_detail") {
                    detailPosition.scrollTo(id: saved, anchor: .top)
                }
            }
            .onChange(of: detailPosition.viewID(type: UUID.self)) { _, newID in
                guard let id = newID else { return }
                let now = Date()
                if let last = lastSaveTime, now.timeIntervalSince(last) < 0.3 { return }
                lastSaveTime = now
                ScrollPositionManager.shared.saveUUID(key: "liquid_rec_detail", id: id)
            }
            .contentMargins(.top, 80, for: .scrollContent)
            .contentMargins(.bottom, 80, for: .scrollContent)

            recommendationDetailHeader(section)
        }
    }

    private func recommendationDetailHeader(_ section: RecommendationSection) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedSectionID = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let artURL = section.items.first?.track.thumbURL(size: "84") ?? section.items.first?.track.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: 36, height: 36))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: section.type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                let countText = String(format: NSLocalizedString("tracks_count", comment: ""), section.items.count)
                Text(countText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(minHeight: 36)
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 15))
        .padding(.bottom, 16)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        NotificationCenter.default.post(
                            name: .detailHeaderHeightChanged,
                            object: nil,
                            userInfo: ["height": geo.size.height]
                        )
                    }
                    .onChange(of: geo.size.height) { _, newH in
                        NotificationCenter.default.post(
                            name: .detailHeaderHeightChanged,
                            object: nil,
                            userInfo: ["height": newH]
                        )
                    }
            }
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.4))

            Text(LocalizedStringKey("rec_empty_title"))
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text(LocalizedStringKey("rec_empty_hint"))
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
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

// MARK: - Card for Mixed Feed

@available(macOS 26.0, *)
struct LiquidGlassRecommendationCard: View {
    let item: RecommendationItem
    let onTap: () -> Void

    @State private var isHovering = false

    private let cardWidth: CGFloat = 140
    private let artSize: CGFloat = 140

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let artURL = item.track.thumbURL(size: "200") ?? item.track.albumArtURL {
                    CachedImage(url: artURL, size: CGSize(width: artSize, height: artSize))
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: artSize, height: artSize)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.4))
                        )
                }

                if isHovering {
                    Button(action: onTap) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .glassEffect(in: .circle)
                            .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            VStack(spacing: 2) {
                Text(item.track.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(item.track.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: artSize)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Section Row

@available(macOS 26.0, *)
struct LiquidGlassRecommendationSectionRow: View {
    let section: RecommendationSection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.type.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let reason = section.items.first?.reason,
                   !reason.isEmpty,
                   section.type == .timeOfDay || section.type == .weekday {
                    Text("• \(reason)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(section.items.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .glassEffect(in: .rect(cornerRadius: 14))
        .contentShape(Rectangle())
    }
}

// MARK: - Track Row

@available(macOS 26.0, *)
struct LiquidGlassRecommendationTrackRow: View {
    let item: RecommendationItem
    let isCurrent: Bool
    let isPlaying: Bool
    let index: Int

    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    var isInQueue: Bool = false
    var onRemoveFromQueue: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var isFavorite: Bool = false
    var onDoubleClick: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        let showStar = (isHovering || isSelected || isFavorite) && onToggleFavorite != nil

        HStack(spacing: 10) {
            if let onAdd = onAddToQueue {
                Button(action: { if !isInQueue { onAdd() } }) {
                    ZStack {
                        Color.clear
                            .frame(width: 28, height: 28)

                        Image(systemName: isInQueue ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(isInQueue ? .secondary.opacity(0.4) : .accentColor.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .disabled(isInQueue)
            }

            if let artURL = item.track.thumbURL(size: "84") ?? item.track.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: 38, height: 38))
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.4))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(isCurrent && isPlaying ? .accentColor : .primary)
                    .lineLimit(1)

                Text(item.track.artist)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(formatDuration(item.track.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

            if let onFav = onToggleFavorite {
                Button(action: onFav) {
                    ZStack {
                        Color.clear
                            .frame(width: 28, height: 28)

                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(isFavorite ? .accentColor : .secondary.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .opacity(showStar ? 1.0 : 0.0)
                .allowsHitTesting(showStar)
                .animation(.easeInOut(duration: 0.12), value: showStar)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.12) : Color.primary.opacity(isHovering ? 0.08 : 0.0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                onSelect?()
            }
        )
        .onTapGesture(count: 2) {
            onDoubleClick?()
        }
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec.isFinite else { return "--:--" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}
