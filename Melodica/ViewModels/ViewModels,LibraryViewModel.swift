// ViewModels,LibraryViewModel.swift
import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    static weak var shared: LibraryViewModel?
    @Published var tracks: [Track] = []
    @Published var playlists: [(name: String, tracks: [Track])] = []
    @Published var searchText = "" {
        didSet {
            updateFilteredTracks()
            NotificationCenter.default.post(name: .clearTrackSelection, object: nil)
        }
    }
    @Published var sortField: Track.SortField = .album {
        didSet { updateFilteredTracks() }
    }
    @Published var sortAscending = true {
        didSet { updateFilteredTracks() }
    }
    @Published var isLoading = false
    @Published var isScanning = false
    @Published var watchedFolders: [(url: URL, isVisible: Bool)] = []
    
    @Published var isRestoring = false
    @Published var isEnriching = false
    @Published var enrichProgress: (current: Int, total: Int) = (0, 0)
    @Published var enrichPhase: Int = 1

    @Published var enrichElapsedTime: TimeInterval = 0
    @Published var folderQueueCount: Int = 0
    @Published var enrichFormattedTime: String = ""
    @Published var cueAlbums: [CUEAlbum] = []
    private var enrichLastRemaining: TimeInterval = 0

    private var enrichTimer: Timer?
    
    private var pendingFolderCount = 0
    private var folderQueue: [URL] = []
    private var isProcessingQueue = false
    private var queueUsesIncremental = false
    private var activeScanTask: Task<Void, Never>?
    private var activeEnrichTask: Task<Void, Never>?
    
    private var tracksURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tracks.json")
    }
    
    private let watcher = FolderWatcherService.shared
    @Published private(set) var watchModes: [String: FolderWatchMode] = [:]
    
    init() {
        LibraryViewModel.shared = self
        watcher.configure { [weak self] url in
            self?.handleFolderChange(url)
        }
    }
    
    @Published var albumGroups: [(album: String, artist: String, tracks: [Track], artURL: URL?)] = []
    @Published var artistGroups: [(artist: String, tracks: [Track], artURL: URL?)] = []
    @Published var genreGroups: [(genre: String, tracks: [Track], artURL: URL?)] = []

    private func recalculateGroups() {
        // albumGroups
        var newAlbumGroups: [(album: String, artist: String, tracks: [Track], artURL: URL?)] = []
        var seenAlbums: [String: Int] = [:]
        for track in filteredTracks {
            let key = "\(track.album)|\(track.albumArtist ?? track.artist)"
            if let idx = seenAlbums[key] {
                newAlbumGroups[idx].tracks.append(track)
            } else {
                seenAlbums[key] = newAlbumGroups.count
                newAlbumGroups.append((album: track.album, artist: track.albumArtist ?? track.artist, tracks: [track], artURL: track.albumArtURL))
            }
        }
        for i in 0..<newAlbumGroups.count {
            newAlbumGroups[i].tracks.sort { (a, b) in (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max) }
        }
        newAlbumGroups.sort { (a, b) in
            let albumCmp = a.album.localizedCompare(b.album)
            if albumCmp != .orderedSame {
                return sortAscending ? (albumCmp == .orderedAscending) : (albumCmp == .orderedDescending)
            }
            let artistCmp = a.artist.localizedCompare(b.artist)
            return sortAscending ? (artistCmp == .orderedAscending) : (artistCmp == .orderedDescending)
        }
        albumGroups = newAlbumGroups

        // artistGroups
        var newArtistGroups: [(artist: String, tracks: [Track], artURL: URL?)] = []
        var seenArtists: [String: Int] = [:]
        let unknownArtistGroup = NSLocalizedString("unknown_artist_group", comment: "")
        let unknownArtistLocalized = NSLocalizedString("unknown_artist", comment: "")
        for track in filteredTracks {
            let artists = track.artist
                .components(separatedBy: CharacterSet(charactersIn: "/,&;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for artist in artists {
                let localizedArtist = (artist == unknownArtistLocalized || artist == "Неизвестный исполнитель" || artist == "Unknown artist")
                    ? unknownArtistGroup
                    : artist
                if let idx = seenArtists[localizedArtist] {
                    newArtistGroups[idx].tracks.append(track)
                } else {
                    seenArtists[localizedArtist] = newArtistGroups.count
                    newArtistGroups.append((artist: localizedArtist, tracks: [track], artURL: track.albumArtURL))
                }
            }
        }
        newArtistGroups.sort { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        artistGroups = newArtistGroups

        // genreGroups
        var newGenreGroups: [(genre: String, tracks: [Track], artURL: URL?)] = []
        var seenGenres: [String: Int] = [:]
        let unknownGenre = NSLocalizedString("unknown_genre", comment: "")
        for track in filteredTracks {
            let rawGenre = track.genre ?? unknownGenre
            let genres = rawGenre
                .components(separatedBy: CharacterSet(charactersIn: "/,&;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if genres.isEmpty {
                if let idx = seenGenres[unknownGenre] {
                    newGenreGroups[idx].tracks.append(track)
                } else {
                    seenGenres[unknownGenre] = newGenreGroups.count
                    newGenreGroups.append((genre: unknownGenre, tracks: [track], artURL: track.albumArtURL))
                }
            } else {
                for genre in genres {
                    if let idx = seenGenres[genre] {
                        newGenreGroups[idx].tracks.append(track)
                    } else {
                        seenGenres[genre] = newGenreGroups.count
                        newGenreGroups.append((genre: genre, tracks: [track], artURL: track.albumArtURL))
                    }
                }
            }
        }
        newGenreGroups.sort { $0.genre.localizedCompare($1.genre) == .orderedAscending }
        genreGroups = newGenreGroups
    }
    @Published var filteredTracks: [Track] = []

    func updateFilteredTracks() {
        var result = tracks
        
        if !watchedFolders.isEmpty {
            result = result.filter { track in
                let containingFolders = watchedFolders.filter { track.url.path.hasPrefix($0.url.path + "/") }
                if containingFolders.isEmpty { return true }
                return containingFolders.contains { $0.isVisible }
            }
        }
        
        var seen: Set<String> = []
        var uniqueResult: [Track] = []
        for track in result {
            let key = track.url.path + (track.cueStartTime.map { "|\($0)" } ?? "")
            if !seen.contains(key) {
                seen.insert(key)
                uniqueResult.append(track)
            }
        }
        result = uniqueResult
        
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query) ||
                ($0.albumArtist ?? "").lowercased().contains(query) ||
                ($0.genre ?? "").lowercased().contains(query) ||
                ($0.year.map { String($0) } ?? "").contains(query)
            }
        }

        // Скрываем треки без рейтинга в режиме сортировки по рейтингу
        if sortField == .rating {
            result = result.filter { ($0.rating ?? 0) > 0 }
        }
        
        result.sort { (a, b) in
            let cmp: ComparisonResult
            switch sortField {
            case .title:
                cmp = a.title.localizedCompare(b.title)

            case .artist:
                cmp = a.artist.localizedCompare(b.artist)

            case .album:
                let aaA = a.albumArtist ?? a.artist
                let aaB = b.albumArtist ?? b.artist
                let artistCmp = aaA.localizedCompare(aaB)
                if artistCmp != .orderedSame {
                    cmp = artistCmp
                } else {
                    let albumCmp = a.album.localizedCompare(b.album)
                    if albumCmp != .orderedSame {
                        cmp = albumCmp
                    } else {
                        let aNum = a.trackNumber ?? Int.max
                        let bNum = b.trackNumber ?? Int.max
                        if aNum != bNum {
                            return sortAscending ? (aNum < bNum) : (aNum > bNum)
                        }
                        cmp = .orderedSame
                    }
                }

            case .genre:
                cmp = (a.genre ?? "ЯЯЯ").localizedCompare(b.genre ?? "ЯЯЯ")

            case .year:
                let yA = a.year ?? .max
                let yB = b.year ?? .max
                if yA != yB {
                    cmp = yA < yB ? .orderedAscending : .orderedDescending
                } else {
                    cmp = .orderedSame
                }

            case .rating:
                let rA = a.rating ?? 0
                let rB = b.rating ?? 0
                if rA != rB {
                    cmp = rA > rB ? .orderedAscending : .orderedDescending
                } else {
                    cmp = .orderedSame
                }

            case .duration:
                if a.duration != b.duration {
                    cmp = a.duration < b.duration ? .orderedAscending : .orderedDescending
                } else {
                    cmp = .orderedSame
                }

            case .playlists, .smart, .cue, .recommendations:
                cmp = .orderedSame
            }

            if cmp != .orderedSame {
                return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            
            if sortField == .album {
                let aNum = a.trackNumber ?? Int.max
                let bNum = b.trackNumber ?? Int.max
                if aNum != bNum { return aNum < bNum }
            }
            return a.url.path.localizedCompare(b.url.path) == .orderedAscending
        }
        
        filteredTracks = result
        recalculateGroups()
    }
    // MARK: - Таймер обогащения

    func startEnrichTimer() {
        enrichTimer?.invalidate()
        enrichElapsedTime = 0
        enrichLastRemaining = 0
        let startDate = Date()
        
        enrichTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(startDate)
            MainActor.assumeIsolated {
                guard let self else { return }
                if elapsed > self.enrichElapsedTime {
                    self.enrichElapsedTime = elapsed
                    self.updateEnrichTimeDisplay()
                }
            }
        }
    }
    func stopEnrichTimer() {
        enrichTimer?.invalidate()
        enrichTimer = nil
    }
    func updateEnrichTimeDisplay() {
        guard enrichProgress.current > 0,
              enrichProgress.total > 0,
              enrichElapsedTime > 5 else {
            enrichFormattedTime = NSLocalizedString("calculating_time", comment: "")
            return
        }
        
        let avgTimePerItem = enrichElapsedTime / Double(enrichProgress.current)
        let remaining = enrichProgress.total - enrichProgress.current
        var totalSeconds = Double(remaining) * avgTimePerItem
        totalSeconds = max(0, min(totalSeconds, 86400))
        
        // Защита от скачков вверх
        if enrichLastRemaining > 0 && totalSeconds > enrichLastRemaining {
            totalSeconds = enrichLastRemaining
        } else {
            enrichLastRemaining = totalSeconds
        }
        
        if totalSeconds < 60 {
            enrichFormattedTime = String(format: NSLocalizedString("time_seconds", comment: ""), Int(totalSeconds))
        } else if totalSeconds < 3600 {
            let minutes = Int(totalSeconds / 60)
            let secs = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
            enrichFormattedTime = String(format: NSLocalizedString("time_minutes", comment: ""), minutes, secs)
        } else {
            let hours = Int(totalSeconds / 3600)
            let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
            enrichFormattedTime = "\(hours) ч \(minutes) мин"
        }
    }
    
    // MARK: - Кеширование треков
    /// Принимает звёзды 1…5 (nil — снять рейтинг).
    /// Внутри хранит Track.rating в шкале 0…255, а в файл пишет звёзды 1…5.
    func setRating(_ stars: Int?, for track: Track) {
        let internalRating: Int? = stars.map { $0 * 51 }
        let previousRating = track.rating

        // 1. Оптимистично обновляем UI
        if let idx = tracks.firstIndex(where: {
            $0.id == track.id || (track.smartHash != nil && $0.smartHash == track.smartHash)
        }) {
            tracks[idx].rating = internalRating
        }

        filteredTracks = filteredTracks.map { t in
            let matches = t.id == track.id ||
                          (track.smartHash != nil && t.smartHash == track.smartHash)
            guard matches else { return t }
            var copy = t
            copy.rating = internalRating
            return copy
        }

        // 2. Оповещаем другие ViewModel'и
        var updated = track
        updated.rating = internalRating
        NotificationCenter.default.post(name: .trackRatingChanged, object: updated)
        NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)

        // 3. Кеш метаданных
        // 3. Кеш метаданных
        if let hash = track.smartHash {
            Task {
                await TrackMetadataCacheService.shared.updateRating(for: hash, rating: internalRating)
            }
        }

        // 4. tracks.json
        saveTracksToCache()

        // 5. Пишем тег в файл в фоне
        let url = track.url
        let title = track.title
        let originalId = track.id
        let originalHash = track.smartHash
        let attemptedRating = internalRating

        Task {
            let result = await MetadataWriter.writeRatingAsync(stars, to: url)

            guard case .failure(let error) = result else { return }

            // Мы уже на MainActor — Task { } наследует изоляцию от LibraryViewModel.
            // Никакого MainActor.run не нужно.
            let currentRating = self.tracks.first(where: {
                $0.id == originalId ||
                (originalHash != nil && $0.smartHash == originalHash)
            })?.rating

            guard currentRating == attemptedRating else {
                self.showRatingWriteError(error, trackTitle: title, fileName: url.lastPathComponent)
                return
            }

            if let idx = self.tracks.firstIndex(where: {
                $0.id == originalId ||
                (originalHash != nil && $0.smartHash == originalHash)
            }) {
                self.tracks[idx].rating = previousRating
            }

            self.filteredTracks = self.filteredTracks.map { t in
                let matches = t.id == originalId ||
                              (originalHash != nil && t.smartHash == originalHash)
                guard matches else { return t }
                var copy = t
                copy.rating = previousRating
                return copy
            }

            if let hash = originalHash {
                await TrackMetadataCacheService.shared.updateRating(for: hash, rating: previousRating)
            }

            self.saveTracksToCache()

            var reverted = track
            reverted.rating = previousRating
            NotificationCenter.default.post(name: .trackRatingChanged, object: reverted)
            NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)

            if self.sortField == .rating {
                self.updateFilteredTracks()
            }

            self.showRatingWriteError(error, trackTitle: title, fileName: url.lastPathComponent)
        }

        // 6. Пересортировка при оптимистичном обновлении
        if sortField == .rating {
            updateFilteredTracks()
        }
    }
    
    func saveTracksToCache() {
        let snapshot = tracks
        let url = tracksURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomicWrite)
            } catch {
            }
        }
    }

    func saveTracksToCacheSync() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: tracksURL, options: .atomicWrite)
        } catch {
        }
    }
    
    func loadTracksFromCache() async -> Bool {
        guard FileManager.default.fileExists(atPath: tracksURL.path),
              let data = try? Data(contentsOf: tracksURL),
              let cached = try? JSONDecoder().decode([Track].self, from: data) else {
            return false
        }

        // Загружаем все metadata разом — один переход через actor.
        let allHashes = cached.compactMap { $0.smartHash }
        var metadataByHash: [String: TrackMetadataCache] = [:]
        for hash in allHashes {
            if let m = await TrackMetadataCacheService.shared.metadata(for: hash) {
                metadataByHash[hash] = m
            }
        }

        tracks = cached.map { track in
            var updated = track
            if let hash = track.smartHash, let metadata = metadataByHash[hash] {
                updated.title = metadata.title
                updated.artist = metadata.artist
                updated.albumArtist = metadata.albumArtist
                updated.album = metadata.album
                updated.year = metadata.year
                updated.trackNumber = metadata.trackNumber
                updated.genre = metadata.genre
                updated.rating = metadata.rating
                updated.replayGain = metadata.replayGain
                updated.replayGainPeak = metadata.replayGainPeak
                updated.replayGainAlbum = metadata.replayGainAlbum
                updated.replayGainAlbumPeak = metadata.replayGainAlbumPeak
                updated.unsyncedLyrics = metadata.unsyncedLyrics

                if let lyricsPath = metadata.lyricsURL {
                    updated.lyricsURL = URL(fileURLWithPath: lyricsPath)
                }
            }
            return updated
        }

        updateFilteredTracks()
        return true
    }
    // MARK: - Рейтинг

    @MainActor
    private func showRatingWriteError(_ error: Error, trackTitle: String, fileName: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("rating_write_failed_title", comment: "")
        alert.informativeText = "\(trackTitle)\n\(fileName)\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("ok", comment: ""))
        alert.runModal()
    }
    
    // MARK: - Управление папками
    
    func toggleFolderVisibility(_ url: URL) {
        if let idx = watchedFolders.firstIndex(where: { $0.url == url }) {
            watchedFolders[idx].isVisible.toggle()
            saveWatchedFolders()
            updateFilteredTracks()
        }
    }
    
    func removeWatchedFolder(_ url: URL) {
        tracks.removeAll { $0.url.path.hasPrefix(url.path + "/") }
        watchedFolders.removeAll { $0.url == url }
        watchModes.removeValue(forKey: url.path)      // ← добавить
        saveWatchModes()                              // ← добавить
        saveWatchedFolders()
        updateFilteredTracks()
        syncWatchers()                                // ← добавить
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        cueAlbums.removeAll { $0.file.path.hasPrefix(folderPath) }
        saveCUEAlbumsToCache()
    }
    
    private func saveWatchedFolders() {
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.watchedFolderPaths = Dictionary(watchedFolders.map { ($0.url.path, $0.isVisible) }, uniquingKeysWith: { first, _ in first })
        PlayerStateManager.shared.saveLibrary(state)
    }
    
    func loadWatchedFolders() -> [URL] {
        guard let state = PlayerStateManager.shared.loadLibrary() else { return [] }
        watchedFolders = state.watchedFolderPaths?.map { (URL(fileURLWithPath: $0.key), $0.value) } ?? []
        loadWatchModes()
        objectWillChange.send()
        syncWatchers()
        return watchedFolders.map { $0.url }
    }
    // MARK: - Watch modes

    func watchMode(for url: URL) -> FolderWatchMode {
        watchModes[url.path] ?? .auto
    }

    func setWatchMode(_ mode: FolderWatchMode, for url: URL) {
        watchModes[url.path] = mode
        saveWatchModes()
        syncWatchers()
    }

    private func saveWatchModes() {
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.folderWatchModes = watchModes.mapValues { $0.rawValue }
        PlayerStateManager.shared.saveLibrary(state)
    }

    private func loadWatchModes() {
        guard let state = PlayerStateManager.shared.loadLibrary(),
              let raw = state.folderWatchModes else { return }
        watchModes = raw.compactMapValues { FolderWatchMode(rawValue: $0) }
    }

    private func syncWatchers() {
        var modes: [String: FolderWatchMode] = [:]
        for folder in watchedFolders {
            modes[folder.url.path] = watchModes[folder.url.path] ?? .auto
        }
        watcher.apply(modes: modes)
    }

    private func handleFolderChange(_ url: URL) {
        if isScanning || isEnriching {
            if !folderQueue.contains(url) {
                folderQueue.append(url)
                folderQueueCount = folderQueue.count
            }
            return
        }
        scanFolderIncremental(url)
    }
    
    // MARK: - Загрузка папок
    
    func addFolder(_ url: URL, forceRescan: Bool = false) {
        if !watchedFolders.contains(where: { $0.url == url }) {
            watchedFolders.append((url, true))
            saveWatchedFolders()
            // Новую папку — авто-наблюдение по умолчанию
            watchModes[url.path] = .auto
            saveWatchModes()
        }
        
        syncWatchers()    // ← добавить
        
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        let alreadyLoaded = tracks.contains { $0.url.path.hasPrefix(folderPath) }
        
        if forceRescan || !alreadyLoaded {
            if isScanning || isEnriching {
                if !folderQueue.contains(url) {
                    folderQueue.append(url)
                    folderQueueCount = folderQueue.count
                }
                return
            }
            saveLastFolder(url.path)
            scanFolder(url)
        }
    }
    /// Быстрая проверка — без очистки кеша метаданных и миниатюр.
    /// Используется для «Check for new» и для FSEvents-триггеров.
    func checkForNewFiles() {
        guard !watchedFolders.isEmpty else { return }
        guard !isScanning, !isEnriching else { return }
        queueUsesIncremental = true

        isRestoring = true
        pendingFolderCount = watchedFolders.count

        folderQueue.removeAll()
        folderQueueCount = 0

        let firstFolder = watchedFolders[0].url
        saveLastFolder(firstFolder.path)
        scanFolderIncremental(firstFolder)

        if watchedFolders.count > 1 {
            for i in 1..<watchedFolders.count {
                folderQueue.append(watchedFolders[i].url)
            }
            folderQueueCount = folderQueue.count
        }
    }
    
    func rescanAllFolders() {
        activeScanTask?.cancel()
        activeScanTask = nil
        activeEnrichTask?.cancel()
        activeEnrichTask = nil
        queueUsesIncremental = false
        Task {
            await TrackMetadataCacheService.shared.clearAll()
        }
        Task { @MainActor in
            ImageCache.shared.clearMemory()
        }
        let cacheDir = ImageCache.cacheDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        tracks.removeAll()
        cueAlbums.removeAll()
        saveCUEAlbumsToCache()
        updateFilteredTracks()
        
        let folderCount = watchedFolders.count
        guard folderCount > 0 else {
            saveTracksToCache()
            return
        }
        
        isRestoring = true
        pendingFolderCount = folderCount
        
        // Очищаем очередь
        folderQueue.removeAll()
        folderQueueCount = 0
        
        // Первую папку сканируем сразу
        let firstFolder = watchedFolders[0].url
        saveLastFolder(firstFolder.path)
        scanFolder(firstFolder)
        
        // Остальные — в очередь
        if folderCount > 1 {
            for i in 1..<folderCount {
                folderQueue.append(watchedFolders[i].url)
            }
            folderQueueCount = folderQueue.count
        }
    }
    
    private func saveLastFolder(_ path: String) {
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.lastFolderPath = path
        PlayerStateManager.shared.saveLibrary(state)
    }
    
    private func scanFolder(_ folderURL: URL) {
        isScanning = true
        isLoading = true
        isEnriching = true

        activeScanTask?.cancel()
        activeScanTask = Task.detached(priority: .high) {
            let (urls, cueURLs) = LibraryViewModel.enumerateAudioFolder(folderURL)
            if Task.isCancelled { return }

            // === Фаза 1: Сканирование ===
            await MainActor.run {
                self.enrichPhase = 1
                self.enrichProgress = (0, urls.count)
                self.enrichLastRemaining = 0
                self.startEnrichTimer()
            }

            var loaded: [Track] = []

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }

                if var track = await MetadataReader.readTrack(from: url) {
                    if track.albumArtURL == nil {
                        if let artURL = await MetadataReader.enrichArtwork(for: track) {
                            track.albumArtURL = artURL
                        }
                    }

                    loaded.append(track)
                }

                if index % 5 == 0 { await Task.yield() }

                if index % 10 == 0 || index == urls.count - 1 {
                    await MainActor.run {
                        self.enrichProgress = (index + 1, urls.count)
                    }
                }
            }

            // CUE
            var cueAudioFiles: Set<String> = []
            for url in cueURLs {
                if let album = CUEParser.parse(url) {
                    cueAudioFiles.insert(album.file.path)
                    cueAudioFiles.insert(album.file.standardizedFileURL.path)
                    cueAudioFiles.insert(album.file.resolvingSymlinksInPath().path)
                }
            }

            loaded = loaded.filter { track in
                let trackPath = track.url.path
                let standardizedPath = track.url.standardizedFileURL.path
                let resolvedPath = track.url.resolvingSymlinksInPath().path
                return !cueAudioFiles.contains(trackPath) &&
                       !cueAudioFiles.contains(standardizedPath) &&
                       !cueAudioFiles.contains(resolvedPath)
            }

            var cueAlbums: [CUEAlbum] = []

            for url in cueURLs {
                if var album = CUEParser.parse(url) {
                    if FileManager.default.fileExists(atPath: album.file.path) {
                        if let tags = await MetadataReader.readTrack(from: album.file) {
                            album.albumArtURL = tags.albumArtURL
                            album.replayGain = tags.replayGain
                            album.replayGainPeak = tags.replayGainPeak
                            album.replayGainAlbum = tags.replayGainAlbum
                            album.replayGainAlbumPeak = tags.replayGainAlbumPeak
                            album.genre = tags.genre
                            album.year = tags.year
                            album.unsyncedLyrics = tags.unsyncedLyrics

                            // ← НОВОЕ: если ридер не вытащил обложку — пробуем enrich,
                            // как это делается для обычных треков
                            if album.albumArtURL == nil {
                                if let artURL = await MetadataReader.enrichArtwork(for: tags) {
                                    album.albumArtURL = artURL
                                }
                            }

                            // ← НОВОЕ: финальный fallback — cover.jpg/folder.jpg рядом с cue
                            if album.albumArtURL == nil {
                                let dir = album.file.deletingLastPathComponent()
                                let candidates = ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png"]
                                for name in candidates {
                                    let candidate = dir.appendingPathComponent(name)
                                    if FileManager.default.fileExists(atPath: candidate.path) {
                                        album.albumArtURL = candidate
                                        break
                                    }
                                }
                            }
                        }

                        cueAlbums.append(album)
                    }
                }
            }

            await MainActor.run {
                let folderPath = folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/"
                self.tracks.removeAll { $0.url.path.hasPrefix(folderPath) }

                self.cueAlbums.append(contentsOf: cueAlbums)
                self.saveCUEAlbumsToCache()

                let existingPaths = Set(self.tracks.map { $0.url.path })
                for track in loaded {
                    if !existingPaths.contains(track.url.path) {
                        self.tracks.append(track)
                    }
                }

                self.updateFilteredTracks()
                self.isScanning = false
                self.isLoading = false
                self.saveTracksToCache()
                NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)

                if self.isRestoring {
                    self.pendingFolderCount -= 1
                    if self.pendingFolderCount <= 0 {
                        self.isRestoring = false
                        NotificationCenter.default.post(
                            name: NSNotification.Name("allFoldersLoaded"),
                            object: nil
                        )
                    }
                }
                self.startBackgroundEnrichment(onlyFor: loaded)
            }
        }
    }
    // MARK: - Инкрементальный скан

    /// Сканирует папку и применяет только diff: добавляет новые, удаляет исчезнувшие,
    /// не трогает существующие. Используется для FSEvents и «Check for new» —
    /// чтобы обход не перечитывал метаданные 100k треков.
    private func scanFolderIncremental(_ folderURL: URL) {
        isScanning = true
        isLoading = true
        isEnriching = true

        activeScanTask?.cancel()
        activeScanTask = Task.detached(priority: .high) {
            // 0. Обход файловой системы — синхронно в фоне, не блокирует UI.
            // Обход выполняется через nonisolated static-метод: FileManager.enumerator
            // не работает в async-контексте (`makeIterator is unavailable from asynchronous contexts`).
            let (diskAudioURLs, diskCueURLs) = LibraryViewModel.enumerateAudioFolder(folderURL)

            let folderPrefix = folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/"

            // 1. Снимок текущего состояния для этой папки
            let existingAudioPaths = await MainActor.run {
                Set(self.tracks
                    .filter { $0.url.path.hasPrefix(folderPrefix) }
                    .map { $0.url.path })
            }
            let existingCuePaths = await MainActor.run {
                Set(self.cueAlbums
                    .filter { $0.file.path.hasPrefix(folderPrefix) }
                    .map { $0.file.path })
            }

            // 2. Diff по аудио
            let diskAudioPaths = Set(diskAudioURLs.map { $0.path })
            let newAudioURLs = diskAudioURLs.filter { !existingAudioPaths.contains($0.path) }
            let removedAudioPaths = existingAudioPaths.subtracting(diskAudioPaths)

            // 3. Diff по CUE
            let diskCuePaths = Set(diskCueURLs.map { $0.path })
            let newCueURLs = diskCueURLs.filter { !existingCuePaths.contains($0.path) }
            let removedCuePaths = existingCuePaths.subtracting(diskCuePaths)

            // Ничего не поменялось — выходим без работы
            if newAudioURLs.isEmpty, removedAudioPaths.isEmpty,
               newCueURLs.isEmpty, removedCuePaths.isEmpty {
                await MainActor.run {
                    self.isScanning = false
                    self.isLoading = false
                    self.isEnriching = false
                    self.stopEnrichTimer()

                    if self.isRestoring {
                        self.pendingFolderCount -= 1
                        if self.pendingFolderCount <= 0 {
                            self.isRestoring = false
                            NotificationCenter.default.post(
                                name: NSNotification.Name("allFoldersLoaded"),
                                object: nil
                            )
                        }
                    }
                    self.processQueue()
                }
                return
            }

            // 4. Читаем метаданные новых аудио
            var newTracks: [Track] = []
            for (index, url) in newAudioURLs.enumerated() {
                if Task.isCancelled { break }
                if index % 5 == 0 { await Task.yield() }

                if var track = await MetadataReader.readTrack(from: url) {
                    if track.albumArtURL == nil {
                        if let artURL = await MetadataReader.enrichArtwork(for: track) {
                            track.albumArtURL = artURL
                        }
                    }
                    newTracks.append(track)
                }

                await MainActor.run {
                    self.enrichProgress = (index + 1, newAudioURLs.count)
                }
            }

            // 5. Читаем новые CUE
            var newCueAlbums: [CUEAlbum] = []
            for url in newCueURLs {
                if var album = CUEParser.parse(url) {
                    if FileManager.default.fileExists(atPath: album.file.path) {
                        if let tags = await MetadataReader.readTrack(from: album.file) {
                            album.albumArtURL = tags.albumArtURL
                            album.replayGain = tags.replayGain
                            album.replayGainPeak = tags.replayGainPeak
                            album.replayGainAlbum = tags.replayGainAlbum
                            album.replayGainAlbumPeak = tags.replayGainAlbumPeak
                            album.genre = tags.genre
                            album.year = tags.year
                            album.unsyncedLyrics = tags.unsyncedLyrics

                            if album.albumArtURL == nil,
                               let artURL = await MetadataReader.enrichArtwork(for: tags) {
                                album.albumArtURL = artURL
                            }
                        }
                        newCueAlbums.append(album)
                    }
                }
            }

            // 6. Применяем diff на main
            await MainActor.run {
                // Удаляем исчезнувшие
                if !removedAudioPaths.isEmpty {
                    self.tracks.removeAll { removedAudioPaths.contains($0.url.path) }
                }
                if !removedCuePaths.isEmpty {
                    self.cueAlbums.removeAll { removedCuePaths.contains($0.file.path) }
                }

                // Добавляем новые аудио — только те, что не покрыты CUE
                let cueFilePaths = Set(newCueAlbums.map { $0.file.path })
                let existingPaths = Set(self.tracks.map { $0.url.path })
                for track in newTracks {
                    if cueFilePaths.contains(track.url.path) { continue }
                    if !existingPaths.contains(track.url.path) {
                        self.tracks.append(track)
                    }
                }

                // Добавляем новые CUE и удаляем с ними совпадающие аудио-треки
                if !newCueAlbums.isEmpty {
                    self.cueAlbums.append(contentsOf: newCueAlbums)
                    self.saveCUEAlbumsToCache()

                    let cuePaths = Set(newCueAlbums.map { $0.file.path })
                    self.tracks.removeAll { cuePaths.contains($0.url.path) }
                }

                self.updateFilteredTracks()
                self.isScanning = false
                self.isLoading = false
                self.saveTracksToCache()
                NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)

                if self.isRestoring {
                    self.pendingFolderCount -= 1
                    if self.pendingFolderCount <= 0 {
                        self.isRestoring = false
                        NotificationCenter.default.post(
                            name: NSNotification.Name("allFoldersLoaded"),
                            object: nil
                        )
                    }
                }

                // Обогащение — только для новых треков
                if !newTracks.isEmpty {
                    self.startBackgroundEnrichment(onlyFor: newTracks)
                } else {
                    self.isEnriching = false
                    self.stopEnrichTimer()
                    self.processQueue()
                }
            }
        }
    }
    /// Синхронный обход папки. Вызывается из фонового Task — сам не async,
    /// поэтому FileManager.enumerator работает нормально.
    nonisolated private static func enumerateAudioFolder(_ folderURL: URL) -> (audio: [URL], cue: [URL]) {
        let supportedExtensions: Set<String> = ["mp3", "flac", "m4a", "aac", "opus", "ogg"]
        let fm = FileManager.default

        var audio: [URL] = []
        var cue: [URL] = []

        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ([], [])
        }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                audio.append(url)
            } else if ext == "cue" {
                cue.append(url)
            }
        }

        return (audio, cue)
    }
    // MARK: - Кеширование CUE

    func saveCUEAlbumsToCache() {
        do {
            let data = try JSONEncoder().encode(cueAlbums)
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("Melodica")
                .appendingPathComponent("cue_albums.json")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomicWrite)
        } catch {
        }
    }

    func loadCUEAlbumsFromCache() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
            .appendingPathComponent("cue_albums.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([CUEAlbum].self, from: data) else { return }
        cueAlbums = cached
    }
    
    // MARK: - Обработка очереди
    
    private func processQueue() {
        guard !folderQueue.isEmpty else {
            isProcessingQueue = false
            if isRestoring && pendingFolderCount <= 0 {
                isRestoring = false
                NotificationCenter.default.post(name: NSNotification.Name("allFoldersLoaded"), object: nil)
            }
            return
        }
        
        isProcessingQueue = true
        let nextURL = folderQueue.removeFirst()
        folderQueueCount = folderQueue.count
        saveLastFolder(nextURL.path)
        
        // Какой скан делать для следующей папки — решает тот, кто наполнил очередь.
        if queueUsesIncremental {
            scanFolderIncremental(nextURL)
        } else {
            scanFolder(nextURL)
        }
    }
    

    // MARK: - Фоновое обогащение (фазы 1-3)

    func startBackgroundEnrichment(onlyFor tracksSubset: [Track]? = nil) {
        isEnriching = true
        startEnrichTimer()

        // Читаем настройки ДО Task.detached, потому что SettingsManager — @MainActor.
        let pauseDuration = SettingsManager.shared.thumbnailCreationSpeed
        let waveformMode = SettingsManager.shared.waveformCacheMode

        activeEnrichTask?.cancel()
        activeEnrichTask = Task.detached(priority: .background) {
            // Если subset задан — работаем только с ним (например, только что загруженная папка).
            // Иначе — по всей библиотеке.
            let baseTracks = await MainActor.run {
                tracksSubset ?? self.tracks
            }

            // === Фаза 2: Миниатюры ===
            let tracksForThumbnails = await MainActor.run {
                baseTracks.filter { track in
                    guard let artURL = track.albumArtURL else { return false }
                    return !MetadataReader.thumbnailsExist(for: artURL)
                }
            }

            if !tracksForThumbnails.isEmpty {
                let thumbTotal = tracksForThumbnails.count

                await MainActor.run {
                    self.enrichPhase = 2
                    self.enrichProgress = (0, thumbTotal)
                    self.enrichLastRemaining = 0
                    self.startEnrichTimer()
                }

                for (index, track) in tracksForThumbnails.enumerated() {
                    if Task.isCancelled { break }
                    if index % 3 == 0 { await Task.yield() }

                    if let artURL = track.albumArtURL {
                        await MetadataReader.createThumbnails(for: artURL, sourceURL: track.url)
                    }

                    await MainActor.run {
                        self.enrichProgress = (index + 1, thumbTotal)
                    }

                    if pauseDuration > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(pauseDuration * 1_000_000_000))
                    }
                }
            }

            // === Фаза 3: Кеш волны ===
            if waveformMode == "active" {
                var tracksToCache: [Track] = []
                for track in baseTracks {
                    if await WaveformCache.shared.get(for: track.url) == nil {
                        tracksToCache.append(track)
                    }
                }

                if !tracksToCache.isEmpty {
                    let total = tracksToCache.count

                    await MainActor.run {
                        self.enrichPhase = 3
                        self.enrichProgress = (0, total)
                    }

                    for (index, track) in tracksToCache.enumerated() {
                        if Task.isCancelled { break }
                        if index % 3 == 0 { await Task.yield() }

                        let samples = await VisualizationEngine.shared.generateWaveformSamples(
                            for: track.url,
                            duration: track.duration,
                            track: track
                        )
                        await WaveformCache.shared.set(
                            for: track.url,
                            samples: samples,
                            duration: track.duration
                        )

                        await MainActor.run {
                            self.enrichProgress = (index + 1, total)
                        }
                    }
                }
            }

            // === Завершение ===
            await MainActor.run {
                self.isEnriching = false
                self.stopEnrichTimer()
                self.updateFilteredTracks()
                self.saveTracksToCache()
                self.recalculateLibraryStatistics()

                if self.folderQueue.isEmpty {
                    NotificationCenter.default.post(name: .enrichmentComplete, object: nil)
                    NotificationCenter.default.post(name: .smartPlaylistsNeedRefresh, object: nil)
                }

                self.processQueue()
            }
        }
    }
    
    // MARK: - Плейлисты
    
    func removePlaylist(at index: Int) {
        guard index < playlists.count else { return }
        let playlistName = playlists[index].name
        playlists.remove(at: index)
        
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.playlistPaths.removeAll { path in
            URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent == playlistName
        }
        state.savedPlaylists.removeAll { $0.name == playlistName }
        state.cachedPlaylists.removeAll { $0.name == playlistName }  // ← добавить
        PlayerStateManager.shared.saveLibrary(state)
    }
    
    func importM3U(_ url: URL) {
        let (name, trackURLs) = M3UParser.parse(url)
        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        
        playlists.removeAll { $0.name == name }
        
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.savedPlaylists.removeAll { $0.name == name }
        if let content = content {
            state.savedPlaylists.append(SavedPlaylist(name: name, m3uContent: content))
        }
        if !state.playlistPaths.contains(url.path) {
            state.playlistPaths.append(url.path)
        }
        PlayerStateManager.shared.saveLibrary(state)
        
        Task.detached(priority: .userInitiated) {
            // Пробуем найти треки в уже загруженных
            var loaded: [Track] = []
            var missingURLs: [URL] = []
            
            for url in trackURLs {
                if let existing = await MainActor.run(body: { self.tracks.first(where: { $0.url.path == url.path }) }) {
                    loaded.append(existing)
                } else {
                    missingURLs.append(url)
                }
            }
            
            // Если есть отсутствующие — читаем их
            for url in missingURLs {
                if let track = await MetadataReader.readTrack(from: url) {
                    loaded.append(track)
                }
            }
            
            await MainActor.run {
                // Добавляем новые треки в медиатеку
                for track in loaded {
                    if !self.tracks.contains(where: { $0.url.path == track.url.path }) {
                        self.tracks.append(track)
                    }
                }
                self.playlists.append((name, loaded))
                self.updateFilteredTracks()
                self.savePlaylistsToCache()
            }
        }
    }
    func savePlaylistsToCache() {
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )

        state.cachedPlaylists = playlists.map {
            CachedPlaylist(
                name: $0.name,
                trackPaths: $0.tracks.map { $0.smartHash ?? $0.url.path },
                totalTrackCount: $0.tracks.count
            )
        }

        PlayerStateManager.shared.saveLibrary(state)
    }
    func loadPlaylistsFromCache() {
        guard let state = PlayerStateManager.shared.loadLibrary() else { return }

        let watchedPaths = watchedFolders.map {
            $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/"
        }

        playlists = state.cachedPlaylists.compactMap { cached -> (String, [Track])? in
            let trackList: [Track] = cached.trackPaths.compactMap { path in

                // 1. По smartHash
                if let track = self.tracks.first(where: { $0.smartHash == path }) {
                    return track
                }

                // 2. По пути
                if let track = self.tracks.first(where: { $0.url.path == path }) {
                    if watchedPaths.isEmpty { return track }
                    if watchedPaths.contains(where: { track.url.path.hasPrefix($0) }) { return track }
                }

                // 3. По имени файла
                if let track = self.tracks.first(where: {
                    $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent
                }) {
                    if watchedPaths.isEmpty { return track }
                    if watchedPaths.contains(where: { track.url.path.hasPrefix($0) }) { return track }
                }

                return nil
            }

            return (cached.name, trackList)
        }
    }
    
    func restoreLastFolder() -> URL? {
        guard let state = PlayerStateManager.shared.loadLibrary(),
              let path = state.lastFolderPath else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }
    private func recalculateLibraryStatistics() {
        let allTracks = self.tracks
        Task { @MainActor in
            LibraryStatisticsService.shared.rebuildAndSave(tracks: allTracks)
        }
    }
}
extension LibraryViewModel {
    /// Отсортированный список жанров без «unknown» — для пикеров.
    var availableGenres: [String] {
        let unknown = NSLocalizedString("unknown_genre", comment: "")
        return genreGroups
            .map(\.genre)
            .filter { !$0.isEmpty && $0 != unknown }
            .sorted()
    }
}
