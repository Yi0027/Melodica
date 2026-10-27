// Views/TagEditorView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit

// MARK: - Tag Editor Container

struct TagEditorContainerView: View {
    let tracks: [Track]
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @State private var trackList: [Track]
    @State private var selectedTrack: Track?

    init(tracks: [Track], libraryVM: LibraryViewModel, playerVM: PlayerViewModel) {
        self.tracks = tracks
        self.libraryVM = libraryVM
        self.playerVM = playerVM
        _trackList = State(initialValue: tracks)
        _selectedTrack = State(initialValue: tracks.count == 1 ? tracks.first : nil)
    }

    private var isLiquidGlass: Bool {
        settings.activeTheme == "liquid_glass"
    }

    var body: some View {
        Group {
            if let track = selectedTrack {
                SingleTagEditorView(
                    track: track,
                    showBackButton: trackList.count > 1,
                    onBack: { selectedTrack = nil },
                    onFinish: { updatedTrack in
                        if let idx = trackList.firstIndex(where: { $0.id == updatedTrack.id || $0.url == updatedTrack.url }) {
                            trackList[idx] = updatedTrack
                        }
                        if trackList.count > 1 {
                            selectedTrack = nil
                        } else {
                            dismiss()
                        }
                    },
                    libraryVM: libraryVM,
                    playerVM: playerVM
                )
            } else {
                TagEditorMultiTrackListView(
                    tracks: trackList,
                    onSelect: { track in
                        selectedTrack = track
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            }
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 520, idealHeight: 560)
        .background(
            isLiquidGlass
                ? AnyView(
                    ZStack {
                        Color(NSColor.windowBackgroundColor).opacity(0.85)
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    }
                  )
                : AnyView(Color(NSColor.windowBackgroundColor))
        )
    }
}

// MARK: - Multi-Track Selection List View

struct TagEditorMultiTrackListView: View {
    let tracks: [Track]
    let onSelect: (Track) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(LocalizedStringKey("select_track_to_edit"))
                    .font(.headline)
                Spacer()
                Text("\(tracks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(16)

            Divider()

            List(tracks) { track in
                Button {
                    onSelect(track)
                } label: {
                    HStack(spacing: 12) {
                        if let artURL = track.albumArtURL, let img = NSImage(contentsOf: artURL) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                )
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(track.artist + (track.album.isEmpty ? "" : " — \(track.album)"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(track.url.pathExtension.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(LocalizedStringKey("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
    }
}

// MARK: - Single Track Editor View

struct SingleTagEditorView: View {
    let track: Track
    let showBackButton: Bool
    let onBack: () -> Void
    let onFinish: (Track) -> Void
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    // Loaded Original State
    @State private var originalTags: TrackTags?
    @State private var isLoading = true

    // Editable State
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var albumArtist: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    @State private var trackNumber: String = ""

    // Cover State
    @State private var coverImage: NSImage?
    @State private var isCoverDeleted: Bool = false
    @State private var newCoverData: Data?
    @State private var coverFormat: CoverFormat = .jpeg
    @State private var maxDimensionText: String = ""
    @State private var isCoverDropTargeted: Bool = false

    // ID3 Version (MP3 only)
    @State private var id3Version: ID3TargetVersion = .v2_3

    // Status State
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var isMP3: Bool {
        track.url.pathExtension.lowercased() == "mp3"
    }

    var isYearWarningVisible: Bool {
        !year.isEmpty && (year.count != 4 || Int(year) == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(LocalizedStringKey("loading"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    leftColumn
                        .frame(width: 200)

                    Divider()

                    rightColumn
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }

            Divider()
            bottomBar
        }
        .task {
            await loadTrackTags()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(LocalizedStringKey("writing_failed_title")),
                message: Text(errorMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if showBackButton {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 12, weight: .bold))
                        Text(LocalizedStringKey("tracks"))
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            Text(LocalizedStringKey("edit_tags"))
                .font(.headline)

            Spacer()

            if isMP3 {
                HStack(spacing: 6) {
                    Text("ID3:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Picker("", selection: $id3Version) {
                        Text("v2.3").tag(ID3TargetVersion.v2_3)
                        Text("v2.4").tag(ID3TargetVersion.v2_4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)

                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .help(NSLocalizedString("id3_version_tooltip", comment: ""))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Left Column (Cover)

    private var leftColumn: some View {
        VStack(spacing: 12) {
            // Cover Preview Box
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 180, height: 180)

                if let img = coverImage, !isCoverDeleted {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(LocalizedStringKey("no_cover"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isCoverDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isCoverDropTargeted ? 2 : 1
                    )
            )
            .onDrop(of: [.fileURL, .image], isTargeted: $isCoverDropTargeted) { providers in
                handleCoverDrop(providers: providers)
            }

            // Cover Action Buttons
            HStack(spacing: 8) {
                Button(LocalizedStringKey("change_cover")) {
                    chooseCoverFromFile()
                }
                .controlSize(.small)

                Button(LocalizedStringKey("delete_cover")) {
                    deleteCover()
                }
                .controlSize(.small)
                .disabled(coverImage == nil && !isCoverDeleted)
            }

            Divider()
                .padding(.vertical, 4)

            // Cover format & resize options
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey("format"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $coverFormat) {
                        ForEach(CoverFormat.allCases) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }

                HStack {
                    Text(LocalizedStringKey("max_px"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField(LocalizedStringKey("cover_original_placeholder"), text: $maxDimensionText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: maxDimensionText) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                maxDimensionText = filtered
                            }
                        }
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
    }

    // MARK: - Right Column (Fields)

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tagFieldRow(
                    label: NSLocalizedString("tag_title", comment: "Title"),
                    text: $title,
                    originalValue: originalTags?.title ?? ""
                )

                tagFieldRow(
                    label: NSLocalizedString("tag_artist", comment: "Artist"),
                    text: $artist,
                    originalValue: originalTags?.artist ?? ""
                )

                tagFieldRow(
                    label: NSLocalizedString("tag_album", comment: "Album"),
                    text: $album,
                    originalValue: originalTags?.album ?? ""
                )

                tagFieldRow(
                    label: NSLocalizedString("tag_album_artist", comment: "Album Artist"),
                    text: $albumArtist,
                    originalValue: originalTags?.albumArtist ?? ""
                )

                VStack(alignment: .leading, spacing: 4) {
                    tagFieldRow(
                        label: NSLocalizedString("tag_year", comment: "Year"),
                        text: $year,
                        originalValue: originalTags?.year ?? ""
                    )
                    if isYearWarningVisible {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text(LocalizedStringKey("tag_year_warning"))
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 2)
                    }
                }

                tagFieldRow(
                    label: NSLocalizedString("tag_genre", comment: "Genre"),
                    text: $genre,
                    originalValue: originalTags?.genre ?? ""
                )

                tagFieldRow(
                    label: NSLocalizedString("tag_track_number", comment: "Track Number"),
                    text: $trackNumber,
                    originalValue: originalTags?.trackNumber ?? "",
                    isNumericOnly: true
                )
            }
            .padding(.trailing, 4)
        }
    }

    private func tagFieldRow(
        label: String,
        text: Binding<String>,
        originalValue: String,
        isNumericOnly: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        if isNumericOnly {
                            let filtered = newValue.filter { $0.isNumber }
                            if let num = Int(filtered) {
                                // Cap at UInt16 max (65535) for audio formats
                                text.wrappedValue = String(min(num, 65535))
                            } else {
                                text.wrappedValue = filtered
                            }
                        }
                    }

                if text.wrappedValue != originalValue {
                    Button(action: {
                        text.wrappedValue = originalValue
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("revert", comment: "Revert"))
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                Text(LocalizedStringKey("saving"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(LocalizedStringKey("cancel")) {
                if showBackButton {
                    onBack()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button(LocalizedStringKey("apply")) {
                applyChanges()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Operations

    private func loadTrackTags() async {
        do {
            let tags = try await MetadataWriter.readTags(from: track.url)
            await MainActor.run {
                self.originalTags = tags
                self.title = tags.title
                self.artist = tags.artist
                self.album = tags.album
                self.albumArtist = tags.albumArtist
                self.year = tags.year
                self.genre = tags.genre
                self.trackNumber = tags.trackNumber

                if let id3 = tags.id3Version {
                    self.id3Version = id3
                } else {
                    self.id3Version = .v2_3
                }

                if let picData = tags.coverData, let img = NSImage(data: picData) {
                    self.coverImage = img
                    self.isCoverDeleted = false
                } else {
                    self.coverImage = nil
                    self.isCoverDeleted = false
                }

                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                // Fallback to track object values
                let fallback = TrackTags(
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    albumArtist: track.albumArtist ?? "",
                    year: track.year.map(String.init) ?? "",
                    genre: track.genre ?? "",
                    trackNumber: track.trackNumber.map(String.init) ?? "",
                    coverData: nil,
                    coverMimeType: nil,
                    id3Version: .v2_3,
                    isMP3: isMP3
                )
                self.originalTags = fallback
                self.title = fallback.title
                self.artist = fallback.artist
                self.album = fallback.album
                self.albumArtist = fallback.albumArtist
                self.year = fallback.year
                self.genre = fallback.genre
                self.trackNumber = fallback.trackNumber
                self.isLoading = false
            }
        }
    }

    private func chooseCoverFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            if let img = NSImage(data: data) {
                self.coverImage = img
                self.newCoverData = data
                self.isCoverDeleted = false
            }
        }
    }

    private func deleteCover() {
        self.coverImage = nil
        self.newCoverData = nil
        self.isCoverDeleted = true
    }

    private func handleCoverDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let fileData = try? Data(contentsOf: url),
                          let img = NSImage(data: fileData) else { return }
                    DispatchQueue.main.async {
                        self.coverImage = img
                        self.newCoverData = fileData
                        self.isCoverDeleted = false
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self.coverImage = img
                        self.newCoverData = data
                        self.isCoverDeleted = false
                    }
                }
                return true
            }
        }
        return false
    }

    private func applyChanges() {
        isSaving = true

        let coverMod: CoverModification
        if isCoverDeleted {
            coverMod = .remove
        } else if let raw = newCoverData {
            let maxDim = Int(maxDimensionText)
            coverMod = .replace(data: raw, format: coverFormat, maxDimension: maxDim)
        } else {
            coverMod = .keep
        }

        let payload = TagEditPayload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            albumArtist: albumArtist.trimmingCharacters(in: .whitespacesAndNewlines),
            year: year.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: genre.trimmingCharacters(in: .whitespacesAndNewlines),
            trackNumber: trackNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            coverChange: coverMod,
            targetID3Version: isMP3 ? id3Version : nil
        )

        Task {
            let result = await MetadataWriter.writeTagsAsync(payload, to: track.url)
            await MainActor.run {
                switch result {
                case .success:
                    let updated = updateUIAndCacheAfterWrite(payload: payload)
                    isSaving = false
                    onFinish(updated)
                case .failure(let error):
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func updateUIAndCacheAfterWrite(payload: TagEditPayload) -> Track {
        let cacheDir = ImageCache.cacheDirectory()
        let pathHash = SHA256.hash(data: track.url.path.data(using: .utf8) ?? Data())
            .compactMap { String(format: "%02x", $0) }
            .joined()
        let hashPrefix = String(pathHash.prefix(16))
        let fullDir = cacheDir.appendingPathComponent("full")

        var newArtURL: URL? = track.albumArtURL

        if isCoverDeleted {
            if let contents = try? FileManager.default.contentsOfDirectory(at: fullDir, includingPropertiesForKeys: nil) {
                for file in contents where file.lastPathComponent.hasPrefix("melodica_art_\(hashPrefix)") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            for folder in ["thumb_64", "thumb_84", "thumb_200", "thumb_400"] {
                let dir = cacheDir.appendingPathComponent(folder)
                if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for file in contents where file.lastPathComponent.hasPrefix("melodica_thumb_\(hashPrefix)") {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
            ImageCache.shared.clearMemory()
            newArtURL = nil
        } else if let raw = newCoverData {
            if let contents = try? FileManager.default.contentsOfDirectory(at: fullDir, includingPropertiesForKeys: nil) {
                for file in contents where file.lastPathComponent.hasPrefix("melodica_art_\(hashPrefix)") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            for folder in ["thumb_64", "thumb_84", "thumb_200", "thumb_400"] {
                let dir = cacheDir.appendingPathComponent(folder)
                if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for file in contents where file.lastPathComponent.hasPrefix("melodica_thumb_\(hashPrefix)") {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }

            let token = "\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))"
            let artFile = fullDir.appendingPathComponent("melodica_art_\(hashPrefix)_\(token).jpg")

            let maxDim = Int(maxDimensionText)
            if let processed = MetadataWriter.processCoverImage(data: raw, format: coverFormat, maxDimension: maxDim) {
                try? FileManager.default.createDirectory(at: fullDir, withIntermediateDirectories: true)
                try? processed.write(to: artFile)

                // Generate thumbnails for 64, 84, 400
                if let img = NSImage(data: processed) {
                    for (folder, size) in [("thumb_64", CGFloat(64)), ("thumb_84", CGFloat(84)), ("thumb_400", CGFloat(400))] {
                        let dir = cacheDir.appendingPathComponent(folder)
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        let tf = dir.appendingPathComponent("melodica_thumb_\(hashPrefix)_\(token).jpg")
                        let thumbSize = NSSize(width: size, height: size)
                        let thumbImage = NSImage(size: thumbSize)
                        thumbImage.lockFocus()
                        img.draw(in: NSRect(origin: .zero, size: thumbSize), from: .zero, operation: .copy, fraction: 1.0)
                        thumbImage.unlockFocus()
                        if let tiffThumb = thumbImage.tiffRepresentation,
                           let bThumb = NSBitmapImageRep(data: tiffThumb),
                           let jThumb = bThumb.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                            try? jThumb.write(to: tf)
                        }
                    }
                }
                newArtURL = artFile
            }
            ImageCache.shared.clearMemory()
        }

        // Compute new smartHash from the updated file on disk
        let newSmartHash = SmartTrackIDService.makeHash(for: track.url)
        let effectiveNewHash = newSmartHash ?? track.smartHash ?? ""

        // Update in LibraryViewModel
        var updatedTrack = track
        for idx in 0..<libraryVM.tracks.count {
            if libraryVM.tracks[idx].id == track.id || libraryVM.tracks[idx].url == track.url {
                libraryVM.tracks[idx].title = payload.title
                libraryVM.tracks[idx].artist = payload.artist
                libraryVM.tracks[idx].album = payload.album
                libraryVM.tracks[idx].albumArtist = payload.albumArtist.isEmpty ? nil : payload.albumArtist
                libraryVM.tracks[idx].year = Int(payload.year)
                libraryVM.tracks[idx].genre = payload.genre.isEmpty ? nil : payload.genre
                libraryVM.tracks[idx].trackNumber = Int(payload.trackNumber)
                libraryVM.tracks[idx].albumArtURL = newArtURL
                if let newSmartHash {
                    libraryVM.tracks[idx].smartHash = newSmartHash
                }
                updatedTrack = libraryVM.tracks[idx]
            }
        }

        libraryVM.updateFilteredTracks()
        libraryVM.saveTracksToCache()

        // Update in PlayerViewModel
        if var current = playerVM.currentTrack, current.id == track.id || current.url == track.url {
            current.title = payload.title
            current.artist = payload.artist
            current.album = payload.album
            current.albumArtist = payload.albumArtist.isEmpty ? nil : payload.albumArtist
            current.year = Int(payload.year)
            current.genre = payload.genre.isEmpty ? nil : payload.genre
            current.trackNumber = Int(payload.trackNumber)
            current.albumArtURL = newArtURL
            if let newSmartHash {
                current.smartHash = newSmartHash
            }
            playerVM.currentTrack = current
        }

        for i in 0..<playerVM.favorites.count {
            if playerVM.favorites[i].id == track.id || playerVM.favorites[i].url == track.url {
                playerVM.favorites[i].title = payload.title
                playerVM.favorites[i].artist = payload.artist
                playerVM.favorites[i].album = payload.album
                playerVM.favorites[i].albumArtist = payload.albumArtist.isEmpty ? nil : payload.albumArtist
                playerVM.favorites[i].year = Int(payload.year)
                playerVM.favorites[i].genre = payload.genre.isEmpty ? nil : payload.genre
                playerVM.favorites[i].trackNumber = Int(payload.trackNumber)
                playerVM.favorites[i].albumArtURL = newArtURL
                if let newSmartHash {
                    playerVM.favorites[i].smartHash = newSmartHash
                }
                playerVM.saveState()
            }
        }

        for i in 0..<playerVM.queue.count {
            if playerVM.queue[i].track.id == track.id || playerVM.queue[i].track.url == track.url {
                playerVM.queue[i] = QueueItem(id: playerVM.queue[i].id, track: updatedTrack)
            }
        }

        for i in 0..<playerVM.playerTracks.count {
            if playerVM.playerTracks[i].id == track.id || playerVM.playerTracks[i].url == track.url {
                playerVM.playerTracks[i].title = payload.title
                playerVM.playerTracks[i].artist = payload.artist
                playerVM.playerTracks[i].album = payload.album
                playerVM.playerTracks[i].albumArtist = payload.albumArtist.isEmpty ? nil : payload.albumArtist
                playerVM.playerTracks[i].year = Int(payload.year)
                playerVM.playerTracks[i].genre = payload.genre.isEmpty ? nil : payload.genre
                playerVM.playerTracks[i].trackNumber = Int(payload.trackNumber)
                playerVM.playerTracks[i].albumArtURL = newArtURL
                if let newSmartHash {
                    playerVM.playerTracks[i].smartHash = newSmartHash
                }
            }
        }

        // Update in TrackMetadataCacheService
        let oldHash = track.smartHash
        Task {
            await TrackMetadataCacheService.shared.updateTags(
                oldHash: oldHash,
                newHash: effectiveNewHash,
                title: payload.title,
                artist: payload.artist,
                albumArtist: payload.albumArtist.isEmpty ? nil : payload.albumArtist,
                album: payload.album,
                year: Int(payload.year),
                trackNumber: Int(payload.trackNumber),
                genre: payload.genre.isEmpty ? nil : payload.genre,
                fallbackTrack: updatedTrack
            )
        }

        return updatedTrack
    }
}

// MARK: - Visual Effect View Helper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
