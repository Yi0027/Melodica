import SwiftUI

@MainActor
struct RecommendationSimulatorView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    var onClose: () -> Void

    @State private var sections: [RecommendationSection] = []
    @State private var mixedItems: [RecommendationItem] = []
    @State private var statsCount: Int = 0
    @State private var calculationTimeMs: Double = 0
    @State private var isCalculating = false

    @State private var selectedTab: SimulatorTab = .mixed
    @State private var simulatedHourOption: SimulatedHourOption = .system
    @State private var simulatedDayOption: SimulatedDayOption = .system

    @State private var searchTrackQuery: String = ""
    @State private var inspectedTrackStats: (track: Track, stats: TrackStatistics)? = nil

    enum SimulatorTab: String, CaseIterable, Identifiable {
        case mixed = "Mixed Feed"
        case sections = "Sections"
        case inspector = "Track Inspector"

        var id: String { rawValue }
    }

    enum SimulatedHourOption: String, CaseIterable, Identifiable {
        case system = "System Real Time"
        case morning = "Morning (08:00)"
        case day = "Day (14:00)"
        case evening = "Evening (20:00)"
        case night = "Night (02:00)"

        var id: String { rawValue }

        var hourValue: Int? {
            switch self {
            case .system: return nil
            case .morning: return 8
            case .day: return 14
            case .evening: return 20
            case .night: return 2
            }
        }
    }

    enum SimulatedDayOption: String, CaseIterable, Identifiable {
        case system = "System Day"
        case weekday = "Weekday (Wed)"
        case weekend = "Weekend (Sat)"

        var id: String { rawValue }

        var weekdayValue: Int? {
            switch self {
            case .system: return nil
            case .weekday: return 3
            case .weekend: return 6
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.darkSurface.opacity(0.5))
            controlsSection
            Divider().background(Color.darkSurface.opacity(0.5))

            Picker("View Mode", selection: $selectedTab) {
                ForEach(SimulatorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            contentArea
        }
        .frame(minWidth: 800, minHeight: 620)
        .background(Color.darkBg)
        .onAppear {
            recompute()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.accent)

            Text("Recommendation Engine Simulator & Debugger")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textMain)

            Spacer()

            if isCalculating {
                ProgressView()
                    .controlSize(.small)
                    .tint(.accent)
            } else {
                Text(String(format: "Computed in %.1f ms", calculationTimeMs))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accent.opacity(0.12))
                    .cornerRadius(4)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textMuted)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Scenario shortcuts
            HStack(spacing: 8) {
                Text("Scenario:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SimulationScenario.allCases) { scenario in
                            Button(scenario.displayName) {
                                applyScenario(scenario)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // Context simulation
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Time:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)

                    Picker("", selection: $simulatedHourOption) {
                        ForEach(SimulatedHourOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: simulatedHourOption) {
                        updateTimeContext()
                    }
                }

                HStack(spacing: 6) {
                    Text("Day:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)

                    Picker("", selection: $simulatedDayOption) {
                        ForEach(SimulatedDayOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: simulatedDayOption) {
                        updateTimeContext()
                    }
                }

                Spacer()

                Button("Reset Stats") {
                    resetStatistics()
                }
                .controlSize(.small)

                Button("Recompute") {
                    recompute()
                }
                .controlSize(.small)
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.darkSurface)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case .mixed:
            mixedRecommendationsList
        case .sections:
            sectionsBreakdownList
        case .inspector:
            trackInspectorView
        }
    }

    // MARK: - Tab 1: Mixed Feed

    private var mixedRecommendationsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if mixedItems.isEmpty {
                    Text("No recommendations generated for current state.")
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted)
                        .padding(40)
                } else {
                    HStack {
                        Text("#").frame(width: 30, alignment: .leading)
                        Text("Track & Artist").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Category").frame(width: 140, alignment: .leading)
                        Text("Reason").frame(width: 160, alignment: .leading)
                        Text("Score").frame(width: 60, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    ForEach(Array(mixedItems.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.textMuted)
                                .frame(width: 30, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.track.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textMain)
                                    .lineLimit(1)

                                Text(item.track.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(.textMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 4) {
                                Image(systemName: item.type.icon)
                                    .font(.system(size: 10))
                                Text(NSLocalizedString(item.type.titleKey, comment: ""))
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.accent)
                            .frame(width: 140, alignment: .leading)

                            Text(item.reason)
                                .font(.system(size: 11))
                                .foregroundColor(.textMuted)
                                .frame(width: 160, alignment: .leading)
                                .lineLimit(1)

                            Text(String(format: "%.1f", item.score))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.accent)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(idx % 2 == 0 ? Color.darkSurface.opacity(0.4) : Color.clear)
                        .cornerRadius(4)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Tab 2: Sections Breakdown

    private var sectionsBreakdownList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sections.isEmpty {
                    Text("No sections generated for current state.")
                        .font(.system(size: 13))
                        .foregroundColor(.textMuted)
                        .padding(40)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: section.type.icon)
                                    .foregroundColor(.accent)
                                Text(section.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textMain)

                                Spacer()

                                Text("\(section.items.count) tracks")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accent.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.darkSurface)
                            .cornerRadius(6)

                            VStack(spacing: 2) {
                                ForEach(section.items) { item in
                                    HStack {
                                        Text(item.track.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.textMain)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)

                                        Text(item.track.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(.textMuted)
                                            .frame(width: 140, alignment: .leading)
                                            .lineLimit(1)

                                        Text(item.reason)
                                            .font(.system(size: 11))
                                            .foregroundColor(.textMuted)
                                            .frame(width: 120, alignment: .leading)

                                        Text(String(format: "%.1f", item.score))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.accent)
                                            .frame(width: 50, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Tab 3: Track Inspector

    private var trackInspectorView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textMuted)
                TextField("Search track by title, artist, or album…", text: $searchTrackQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(Color.darkSurface)
            .cornerRadius(6)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            let filteredTracks = libraryVM.tracks.filter { track in
                searchTrackQuery.isEmpty ||
                track.title.localizedCaseInsensitiveContains(searchTrackQuery) ||
                track.artist.localizedCaseInsensitiveContains(searchTrackQuery)
            }.prefix(50)

            HStack(spacing: 12) {
                // List of matching tracks
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredTracks) { track in
                            Button {
                                inspect(track: track)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.textMain)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(.textMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let rating = track.rating, rating > 0 {
                                        Text(String(repeating: "★", count: track.starRating))
                                            .font(.system(size: 10))
                                            .foregroundColor(.accent)
                                    }
                                }
                                .padding(8)
                                .background(inspectedTrackStats?.track.id == track.id ? Color.accent.opacity(0.18) : Color.darkSurface.opacity(0.3))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: 320)

                Divider().background(Color.darkSurface.opacity(0.5))

                // Track detail inspection pane
                ScrollView {
                    if let inspected = inspectedTrackStats {
                        trackDiagnosticsDetails(track: inspected.track, stats: inspected.stats)
                    } else {
                        Text("Select a track on the left to inspect its recommendation scoring, play counts, and block status.")
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func trackDiagnosticsDetails(track: Track, stats: TrackStatistics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMain)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                if stats.blockReason != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "slash.circle.fill")
                        Text("Blocked")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(4)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Eligible")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
                }
            }

            if let reason = stats.blockReason {
                Text("Reason: \(reason)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)

                Button("Unblock Track") {
                    Task {
                        await TrackStatisticsService.shared.unblockTrack(track: track)
                        inspect(track: track)
                        recompute()
                    }
                }
                .controlSize(.small)
            }

            Divider().background(Color.darkSurface.opacity(0.5))

            // Statistics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                diagnosticCell(title: "Play Count", value: "\(stats.playCount)")
                diagnosticCell(title: "Skip Count", value: "\(stats.skipCount)")
                diagnosticCell(title: "Total Time Listened", value: String(format: "%.0f s", stats.totalTimeListened))
                diagnosticCell(title: "Last Played", value: stats.lastPlayedDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                diagnosticCell(title: "Rating (0..255)", value: track.rating != nil ? "\(track.rating!) (\(track.starRating) ★)" : "Unrated")
                diagnosticCell(title: "Genre", value: track.genre ?? "None")
                diagnosticCell(title: "Has Lyrics", value: track.hasLyrics ? "Yes" : "No")
                diagnosticCell(title: "Has Artwork", value: track.albumArtURL != nil ? "Yes" : "No")
            }

            Divider().background(Color.darkSurface.opacity(0.5))

            // Time of Day distribution
            VStack(alignment: .leading, spacing: 4) {
                Text("Time of Day Distribution (24 Hours)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textMuted)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<24, id: \.self) { h in
                        let val = stats.timeOfDay.indices.contains(h) ? stats.timeOfDay[h] : 0
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(val > 0 ? Color.accent : Color.darkSurface)
                                .frame(height: max(4, CGFloat(val) * 6))
                            Text(String(format: "%02d", h))
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.textMuted)
                        }
                    }
                }
                .frame(height: 50)
            }

            // Day of Week distribution
            VStack(alignment: .leading, spacing: 4) {
                Text("Day of Week Distribution (Sun - Sat)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textMuted)

                let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { d in
                        let val = stats.dayOfWeek.indices.contains(d) ? stats.dayOfWeek[d] : 0
                        VStack(spacing: 2) {
                            Text(days[d])
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.textMuted)
                            Text("\(val)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(val > 0 ? .accent : .textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.darkSurface)
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding(16)
    }

    private func diagnosticCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textMain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.darkSurface)
        .cornerRadius(4)
    }

    // MARK: - Actions

    private func recompute() {
        isCalculating = true
        let start = CFAbsoluteTimeGetCurrent()
        let tracks = libraryVM.tracks

        Task {
            let service = RecommendationService.shared
            await service.invalidateCache()

            let (builtSections, mixed) = await service.buildAll(
                from: tracks,
                sectionLimit: 10,
                mixedLimit: 30
            )

            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            await MainActor.run {
                self.sections = builtSections
                self.mixedItems = mixed
                self.calculationTimeMs = duration
                self.isCalculating = false
            }
        }
    }

    private func applyScenario(_ scenario: SimulationScenario) {
        isCalculating = true
        Task {
            await TrackStatisticsService.shared.seedSimulation(tracks: libraryVM.tracks, scenario: scenario)
            recompute()
            NotificationCenter.default.post(name: .recommendationsDidUpdate, object: nil)
        }
    }

    private func updateTimeContext() {
        Task {
            await RecommendationService.shared.setSimulatedContext(
                hour: simulatedHourOption.hourValue,
                weekday: simulatedDayOption.weekdayValue
            )
            recompute()
            NotificationCenter.default.post(name: .recommendationsDidUpdate, object: nil)
        }
    }

    private func resetStatistics() {
        Task {
            await TrackStatisticsService.shared.resetAll()
            recompute()
            NotificationCenter.default.post(name: .recommendationsDidUpdate, object: nil)
        }
    }

    private func inspect(track: Track) {
        Task {
            let stat = await TrackStatisticsService.shared.statistics(for: track) ?? TrackStatistics(trackHash: TrackStatisticsService.hash(for: track))
            await MainActor.run {
                self.inspectedTrackStats = (track, stat)
            }
        }
    }
}
