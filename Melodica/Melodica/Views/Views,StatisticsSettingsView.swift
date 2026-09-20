import SwiftUI

struct StatisticsSettingsView: View {
    @State private var statistics: LibraryStatistics?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let stats = statistics {
                    librarySection(stats)
                    Divider().background(Color.white.opacity(0.1))
                    coverageSection(stats)
                    Divider().background(Color.white.opacity(0.1))
                    lyricsSection(stats)
                    Divider().background(Color.white.opacity(0.1))
                    formatsSection(stats)
                    Divider().background(Color.white.opacity(0.1))

                    topSection(
                        title: LocalizedStringKey("stat_top_artists"),
                        entries: stats.topArtists
                    )

                    topSection(
                        title: LocalizedStringKey("stat_top_albums"),
                        entries: stats.topAlbums
                    )

                    topSection(
                        title: LocalizedStringKey("stat_top_genres"),
                        entries: stats.topGenres
                    )
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .onAppear {
            statistics = LibraryStatisticsService.shared.loadCached()
        }
    }

    private func librarySection(_ stats: LibraryStatistics) -> some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey("stat_library"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120))],
                spacing: 10
            ) {
                StatisticsStatCell(
                    titleKey: "stat_tracks",
                    value: "\(stats.totalTracks)",
                    icon: "music.note.list"
                )

                StatisticsStatCell(
                    titleKey: "stat_albums",
                    value: "\(stats.albumCount)",
                    icon: "opticaldisc"
                )

                StatisticsStatCell(
                    titleKey: "stat_artists",
                    value: "\(stats.artistCount)",
                    icon: "person.2.fill"
                )

                StatisticsStatCell(
                    titleKey: "stat_genres",
                    value: "\(stats.genreCount)",
                    icon: "tag.fill"
                )

                StatisticsStatCell(
                    titleKey: "stat_total_duration",
                    value: stats.formattedTotalDuration,
                    icon: "clock.fill"
                )

                StatisticsStatCell(
                    titleKey: "stat_average_duration",
                    value: stats.formattedAverageDuration,
                    icon: "timer"
                )

                StatisticsStatCell(
                    titleKey: "stat_file_size",
                    value: stats.formattedFileSize,
                    icon: "externaldrive.fill"
                )
            }
        }
    }

    private func coverageSection(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("stat_coverage"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMain)

            HStack(spacing: 16) {
                StatisticsCoverageBar(
                    percent: percent(stats.replayGainTracks, of: stats.totalTracks),
                    labelKey: "stat_replaygain"
                )

                StatisticsCoverageBar(
                    percent: percent(stats.artworkTracks, of: stats.totalTracks),
                    labelKey: "stat_artwork"
                )

                StatisticsCoverageBar(
                    percent: percent(stats.lyricsTracks, of: stats.totalTracks),
                    labelKey: "stat_lyrics"
                )
            }
        }
    }

    private func lyricsSection(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("stat_lyrics_details"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMain)

            VStack(spacing: 8) {
                HStack {
                    Text(LocalizedStringKey("stat_embedded_lyrics"))
                        .font(.system(size: 12))
                        .foregroundColor(.textMain)

                    Spacer()

                    Text("\(stats.embeddedLyricsTracks)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textMuted)
                }

                HStack {
                    Text(LocalizedStringKey("stat_lrc_lyrics"))
                        .font(.system(size: 12))
                        .foregroundColor(.textMain)

                    Spacer()

                    Text("\(stats.lrcLyricsTracks)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textMuted)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
        }
    }

    private func formatsSection(_ stats: LibraryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("stat_formats"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMain)

            VStack(spacing: 8) {
                ForEach(
                    stats.formatCounts.sorted { $0.value > $1.value },
                    id: \.key
                ) { format, count in
                    HStack {
                        Text(format.uppercased())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.textMain)
                            .frame(width: 60, alignment: .leading)

                        ProgressView(
                            value: Double(count),
                            total: Double(stats.totalTracks)
                        )
                        .progressViewStyle(.linear)
                        .tint(.accent)

                        Text("\(count)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textMuted)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func topSection(
        title: LocalizedStringKey,
        entries: [TopEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textMain)

            VStack(spacing: 4) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.name)
                            .font(.system(size: 12))
                            .foregroundColor(.textMain)
                            .lineLimit(1)

                        Spacer()

                        Text("\(entry.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundColor(.textMuted.opacity(0.4))

            Text(LocalizedStringKey("stat_not_built"))
                .font(.system(size: 12))
                .foregroundColor(.textMuted)

            Text(LocalizedStringKey("stat_rescan_hint"))
                .font(.system(size: 10))
                .foregroundColor(.textMuted.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func percent(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total) * 100
    }
}

// MARK: - Вспомогательные View

struct StatisticsStatCell: View {
    let titleKey: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accent)
                .frame(height: 18)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.textMain)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 10))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.darkSurface.opacity(0.5))
        .cornerRadius(10)
    }
}

struct StatisticsCoverageBar: View {
    let percent: Double
    let labelKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(labelKey))
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)

                Spacer()

                Text("\(Int(percent))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accent.opacity(0.7))
                        .frame(width: max(0, geo.size.width * percent / 100))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }
}
