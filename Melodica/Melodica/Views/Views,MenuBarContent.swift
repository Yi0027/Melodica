// Views/MenuBarContent.swift
import SwiftUI
import AppKit

@MainActor
struct MenuBarContent: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var libraryVM: LibraryViewModel

    @ObservedObject private var visualEngine = VisualizationEngine.shared

    @State private var page: Page = .player
    @State private var searchText: String = ""

    enum Page { case player, tracks }

    private var isVizOn: Bool {
        visualEngine.mode == .spectrum
    }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .player: playerPage
            case .tracks: tracksPage
            }
        }
        .frame(width: 340)
        .frame(height: page == .player ? (isVizOn ? 250 : 170) : 460)
        .background(.regularMaterial)
        .tint(Color.accentColor)
        .animation(.easeInOut(duration: 0.2), value: isVizOn)
    }

    // MARK: - Player page

    private var playerPage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                topRow
                middleRow
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 0)

            utilityRow
                .padding(.horizontal, 14)

            Spacer(minLength: 0)

            bottomRow
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    private var topRow: some View {
        Text(trackLabel)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var middleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    transportButton("backward.fill", size: 14) {
                        playerVM.playPreviousTrack()
                    }
                    transportButton(
                        playerVM.isPlaying ? "pause.fill" : "play.fill",
                        size: 22
                    ) {
                        playerVM.togglePlayPause()
                    }
                    transportButton("forward.fill", size: 14) {
                        playerVM.playNextTrack()
                    }
                }
                HStack(spacing: 10) {
                    iconButton(
                        systemName: "shuffle",
                        active: playerVM.shuffleMode,
                        size: 13
                    ) {
                        playerVM.shuffleMode.toggle()
                        playerVM.service.clearPreload()
                        playerVM.saveState()
                    }
                    iconButton(
                        systemName: playerVM.repeatMode.icon,
                        active: playerVM.repeatMode.isActive,
                        size: 13
                    ) {
                        switch playerVM.repeatMode {
                        case .off: playerVM.repeatMode = .all
                        case .all: playerVM.repeatMode = .one
                        case .one: playerVM.repeatMode = .off
                        }
                        playerVM.saveState()
                    }
                }
            }

            MenuBarProgressArea(
                playerVM: playerVM,
                volume: $playerVM.volume
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 4)
        }
    }

    // MARK: - Utility row (spectrum / eye / settings)

    @ViewBuilder
    private var utilityRow: some View {
        if isVizOn {
            // Spectr слева растянут на всю доступную ширину,
            // глаз + настройки вертикальным столбиком справа.
            HStack(alignment: .center, spacing: 10) {
                MenuBarSpectrumView(
                    data: Array(visualEngine.spectrumData.prefix(40))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 42)

                VStack(spacing: 4) {
                    visualizationButton
                    audioSettingsButton
                }
            }
        } else {
            // Viz выключена → глаз и настройки в одну строку, справа.
            HStack(spacing: 6) {
                Spacer()
                visualizationButton
                audioSettingsButton
            }
        }
    }

    private var visualizationButton: some View {
        iconButton(
            systemName: visualEngine.mode == .off ? "eye.slash" : "eye",
            active: visualEngine.mode != .off,
            size: 14,
            action: toggleVisualization
        )
    }

    private var audioSettingsButton: some View {
        iconButton(
            systemName: "slider.horizontal.3",
            active: false,
            size: 14
        ) {
            MenuBarAudioWindow.shared.show()
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            bottomButton(LocalizedStringKey("menubar_full_ui")) {
                AppDelegate.shared.showMainWindow()
            }
            bottomButton(LocalizedStringKey("menubar_tracks")) { page = .tracks }
            bottomButton(LocalizedStringKey("quit")) {
                AppDelegate.shared.quitOrWarn()
            }
        }
    }

    private var trackLabel: String {
        guard let t = playerVM.currentTrack else { return "—" }
        return "\(t.artist) - \(t.title)"
    }

    // MARK: - Tracks page

    private var tracksPage: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            if filteredTracks.isEmpty {
                Spacer()
                Text(searchText.isEmpty
                     ? LocalizedStringKey("no_tracks")
                     : LocalizedStringKey("search_no_results"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTracks) { track in
                            trackRow(track)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().opacity(0.3)

            HStack {
                Button {
                    page = .player
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(LocalizedStringKey("back"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(10)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(LocalizedStringKey("search_placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.18))
        )
    }

    private func trackRow(_ track: Track) -> some View {
        let isCurrent = playerVM.currentTrack?.id == track.id

        return Button {
            playerVM.playerTracks = filteredTracks
            playerVM.play(track) { playerVM.playNextTrack() }
        } label: {
            HStack(spacing: 8) {
                Text(track.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.14) : .clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .trackContextMenu(
            track: track,
            libraryVM: libraryVM,
            playerVM: playerVM
        )
    }

    private var filteredTracks: [Track] {
        let base = libraryVM.filteredTracks
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q)
        }
    }

    // MARK: - Buttons

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemName: String,
        active: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bottomButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visualization

    private func toggleVisualization() {
        if visualEngine.mode == .off {
            visualEngine.setMode(.spectrum)
        } else {
            visualEngine.setMode(.off)
        }
        SettingsManager.shared.setVisualizationMode(
            visualEngine.mode == .off ? "off" : "spectrum"
        )
    }
}

// MARK: - Progress area (isolated to avoid re-rendering whole popup on every tick)

private struct MenuBarProgressArea: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var progress: PlaybackProgress
    @Binding var volume: Float

    init(playerVM: PlayerViewModel, volume: Binding<Float>) {
        self.playerVM = playerVM
        self.progress = playerVM.progress
        self._volume = volume
    }

    private var fraction: Double {
        guard progress.duration > 0 else { return 0 }
        return progress.currentTime / progress.duration
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)), height: 3)
                }
                .frame(height: 3)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = value.location.x / geo.size.width
                            playerVM.seek(to: min(max(f, 0), 1))
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTime(progress.currentTime))
                Spacer()
                Text("-" + formatTime(max(0, progress.duration - progress.currentTime)))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: volumeIconName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Slider(value: $volume, in: 0...1)
                    .controlSize(.mini)
                    .tint(Color(nsColor: NSColor.controlAccentColor))
            }
        }
    }

    private var volumeIconName: String {
        switch volume {
        case 0: return "speaker.slash.fill"
        case 0..<0.34: return "speaker.fill"
        case 0.34..<0.67: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Spectrum (stretches to fill available width)

private struct MenuBarSpectrumView: View {
    let data: [Float]

    var body: some View {
        GeometryReader { geo in
            spectrumBody(width: geo.size.width)
        }
        .animation(.easeOut(duration: 0.05), value: data)
    }

    private func spectrumBody(width: CGFloat) -> some View {
        let count = data.count
        let spacing: CGFloat = 2
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let barWidth = count > 0
            ? max(1.5, (width - totalSpacing) / CGFloat(count))
            : 3

        return HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(
                        width: barWidth,
                        height: max(3, CGFloat(data[i]) * 42)
                    )
            }
        }
        .frame(width: width, height: 42, alignment: .leading)
    }
}

// MARK: - SwiftUI context menu mirror for the mini tracks list

private extension View {
    func trackContextMenu(
        track: Track,
        libraryVM: LibraryViewModel,
        playerVM: PlayerViewModel
    ) -> some View {
        self.contextMenu {
            let isFav = playerVM.isFavorite(track)
            Button {
                playerVM.toggleFavorite(track)
            } label: {
                Label(
                    isFav
                        ? LocalizedStringKey("remove_from_favorites")
                        : LocalizedStringKey("add_to_favorites"),
                    systemImage: isFav ? "star.slash" : "star"
                )
            }

            if track.cueStartTime == nil {
                Menu {
                    if (track.rating ?? 0) > 0 {
                        Button {
                            libraryVM.setRating(nil, for: track)
                        } label: {
                            Label(LocalizedStringKey("clear_rating"), systemImage: "xmark.circle")
                        }
                        Divider()
                    }
                    ForEach(1...5, id: \.self) { stars in
                        Button {
                            libraryVM.setRating(stars, for: track)
                        } label: {
                            Text(String(repeating: "★", count: stars))
                        }
                    }
                } label: {
                    Label(LocalizedStringKey("rating"), systemImage: "star")
                }
            }

            let isInQueue = playerVM.queue.contains { $0.id == track.id }
            if isInQueue {
                Button {
                    playerVM.removeFromQueue(track)
                } label: {
                    Label(LocalizedStringKey("remove_from_queue"), systemImage: "minus.circle")
                }
            } else {
                Button {
                    playerVM.addToQueue(track)
                } label: {
                    Label(LocalizedStringKey("add_to_queue"), systemImage: "plus.circle")
                }
            }

            if track.cueStartTime == nil {
                Divider()

                Menu {
                    Button {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("new_playlist_title", comment: "")
                        alert.informativeText = NSLocalizedString("new_playlist_desc", comment: "")
                        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                        alert.accessoryView = tf
                        alert.addButton(withTitle: NSLocalizedString("create", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
                        alert.window.initialFirstResponder = tf
                        if alert.runModal() == .alertFirstButtonReturn {
                            var name = tf.stringValue.trimmingCharacters(in: .whitespaces)
                            if name.isEmpty { name = "Playlist \(libraryVM.playlists.count + 1)" }
                            libraryVM.playlists.append((name, [track]))
                            libraryVM.savePlaylistsToCache()
                        }
                    } label: {
                        Label(LocalizedStringKey("new_playlist"), systemImage: "plus")
                    }
                    if !libraryVM.playlists.isEmpty {
                        Divider()
                        ForEach(Array(libraryVM.playlists.enumerated()), id: \.offset) { idx, pl in
                            Button {
                                libraryVM.playlists[idx].tracks.append(track)
                                libraryVM.savePlaylistsToCache()
                            } label: {
                                Label(pl.name, systemImage: "music.note.list")
                            }
                        }
                    }
                } label: {
                    Label(LocalizedStringKey("add_to_playlist"), systemImage: "music.note.list")
                }
            }

            Divider()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            } label: {
                Label(LocalizedStringKey("show_in_finder"), systemImage: "folder")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.title, forType: .string)
            } label: {
                Label(LocalizedStringKey("copy_title"), systemImage: "doc.on.doc")
            }
        }
    }
}
