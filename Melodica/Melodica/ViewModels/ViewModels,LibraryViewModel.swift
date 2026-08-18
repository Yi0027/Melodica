// ViewModels,LibraryViewModel.swift
import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    static weak var shared: LibraryViewModel?
    @Published var tracks: [Track] = []
    @Published var playlists: [(name: String, tracks: [Track])] = []
    @Published var searchText = "" {
        didSet { updateFilteredTracks() }
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
    
    private var tracksURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tracks.json")
    }
    
    
    init() {
        LibraryViewModel.shared = self
    }
    
    var albumGroups: [(album: String, artist: String, tracks: [Track], artURL: URL?)] {
        var groups: [(String, String, [Track], URL?)] = []
        var seen: [String: Int] = [:]
        
        for track in filteredTracks {
            let key = "\(track.album)|\(track.albumArtist ?? track.artist)"
            if let idx = seen[key] {
                groups[idx].2.append(track)
            } else {
                seen[key] = groups.count
                groups.append((track.album, track.albumArtist ?? track.artist, [track], track.albumArtURL))
            }
        }
        
        for i in 0..<groups.count {
            groups[i].2.sort { (a, b) in (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max) }
        }
        
        groups.sort { (a, b) in
            let albumCmp = a.0.localizedCompare(b.0)
            if albumCmp != .orderedSame {
                return sortAscending ? (albumCmp == .orderedAscending) : (albumCmp == .orderedDescending)
            }
            let artistCmp = a.1.localizedCompare(b.1)
            return sortAscending ? (artistCmp == .orderedAscending) : (artistCmp == .orderedDescending)
        }
        return groups
    }
    var artistGroups: [(artist: String, tracks: [Track], artURL: URL?)] {
        var groups: [(String, [Track], URL?)] = []
        var seen: [String: Int] = [:]
        for track in filteredTracks {
            let artists = track.artist
                .components(separatedBy: CharacterSet(charactersIn: "/,&"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for artist in artists {
                let localizedArtist = (artist == NSLocalizedString("unknown_artist", comment: "") || artist == "Неизвестный исполнитель" || artist == "Unknown artist")
                    ? NSLocalizedString("unknown_artist_group", comment: "")
                    : artist
                if let idx = seen[localizedArtist] {
                    groups[idx].1.append(track)
                } else {
                    seen[localizedArtist] = groups.count
                    groups.append((localizedArtist, [track], track.albumArtURL))
                }
            }
        }
        groups.sort { $0.0.localizedCompare($1.0) == .orderedAscending }
        return groups
    }

    var genreGroups: [(genre: String, tracks: [Track], artURL: URL?)] {
        var groups: [(String, [Track], URL?)] = []
        var seen: [String: Int] = [:]
        for track in filteredTracks {
            let rawGenre = track.genre ?? NSLocalizedString("unknown_genre", comment: "")
            let genres = rawGenre
                .components(separatedBy: CharacterSet(charactersIn: "/,&"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if genres.isEmpty {
                let unknown = NSLocalizedString("unknown_genre", comment: "")
                if let idx = seen[unknown] {
                    groups[idx].1.append(track)
                } else {
                    seen[unknown] = groups.count
                    groups.append((unknown, [track], track.albumArtURL))
                }
            } else {
                for genre in genres {
                    if let idx = seen[genre] {
                        groups[idx].1.append(track)
                    } else {
                        seen[genre] = groups.count
                        groups.append((genre, [track], track.albumArtURL))
                    }
                }
            }
        }
        groups.sort { $0.0.localizedCompare($1.0) == .orderedAscending }
        return groups
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
            let key = "\(track.title.lowercased())|\(track.artist.lowercased())|\(Int(track.duration))"
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
            let primary: Bool
            switch sortField {
            case .title:
                primary = a.title.localizedCompare(b.title) == .orderedAscending

            case .artist:
                primary = a.artist.localizedCompare(b.artist) == .orderedAscending

            case .album:
                let aaA = a.albumArtist ?? a.artist
                let aaB = b.albumArtist ?? b.artist
                let artistCmp = aaA.localizedCompare(aaB)
                if artistCmp != .orderedSame {
                    primary = artistCmp == .orderedAscending
                } else {
                    let albumCmp = a.album.localizedCompare(b.album)
                    if albumCmp != .orderedSame {
                        primary = albumCmp == .orderedAscending
                    } else {
                        primary = (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max)
                    }
                }

            case .genre:
                primary = (a.genre ?? "ЯЯЯ").localizedCompare(b.genre ?? "ЯЯЯ") == .orderedAscending

            case .year:
                primary = (a.year ?? .max) < (b.year ?? .max)

            case .rating:
                primary = (a.rating ?? 0) > (b.rating ?? 0)

            case .duration:
                primary = a.duration < b.duration

            case .playlists:
                primary = false

            case .smart:
                primary = false

            case .cue:
                primary = false
            }
            let aPrimary = sortAscending ? primary : !primary
            let bPrimary = sortAscending ? !primary : primary
            if aPrimary != bPrimary { return aPrimary }
            
            if sortField == .album {
                let aNum = a.trackNumber ?? Int.max
                let bNum = b.trackNumber ?? Int.max
                if aNum != bNum { return aNum < bNum }
            }
            return a.url.path.localizedCompare(b.url.path) == .orderedAscending
        }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            filteredTracks = result
        }
    }
    // MARK: - Таймер обогащения

    func startEnrichTimer() {
        enrichTimer?.invalidate()
        enrichElapsedTime = 0
        enrichLastRemaining = 0
        let startDate = Date()
        
        enrichTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(startDate)
            DispatchQueue.main.async {
                guard let self = self else { return }
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
    
    func saveTracksToCache() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: tracksURL, options: .atomicWrite)
        } catch {
        }
    }
    
    func loadTracksFromCache() -> Bool {
        guard FileManager.default.fileExists(atPath: tracksURL.path),
              let data = try? Data(contentsOf: tracksURL),
              let cached = try? JSONDecoder().decode([Track].self, from: data) else {
            return false
        }
        tracks = cached
        updateFilteredTracks()
        return true
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
        saveWatchedFolders()
        updateFilteredTracks()
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        cueAlbums.removeAll { $0.file.path.hasPrefix(folderPath) }
        saveCUEAlbumsToCache()
    }
    
    private func saveWatchedFolders() {
        var state = PlayerStateManager.shared.loadLibrary() ?? LibraryState(
            lastFolderPath: nil, playlistPaths: [], savedPlaylists: []
        )
        state.watchedFolderPaths = Dictionary(uniqueKeysWithValues: watchedFolders.map { ($0.url.path, $0.isVisible) })
        PlayerStateManager.shared.saveLibrary(state)
    }
    
    func loadWatchedFolders() -> [URL] {
        guard let state = PlayerStateManager.shared.loadLibrary() else { return [] }
        watchedFolders = state.watchedFolderPaths?.map { (URL(fileURLWithPath: $0.key), $0.value) } ?? []
        objectWillChange.send()
        return watchedFolders.map { $0.url }
    }
    
    // MARK: - Загрузка папок
    
    func addFolder(_ url: URL, forceRescan: Bool = false) {
        if !watchedFolders.contains(where: { $0.url == url }) {
            watchedFolders.append((url, true))
            saveWatchedFolders()
        }
        
        let folderPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
        let alreadyLoaded = tracks.contains { $0.url.path.hasPrefix(folderPath) }
        
        if forceRescan || !alreadyLoaded {
            // Если идёт сканирование или обогащение — в очередь
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
    
    func rescanAllFolders() {
        Task {
            await ImageCache.shared.clearMemory()
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

        let supportedExtensions: Set<String> = ["mp3", "flac", "m4a", "aac", "opus", "ogg"]
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            isLoading = false
            isScanning = false
            processQueue()
            return
        }

        var allURLs: [URL] = []
        var cueURLs: [URL] = []

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                allURLs.append(url)
            } else if ext == "cue" {
                cueURLs.append(url)
            }
        }

        let urls = allURLs

        Task.detached(priority: .high) {
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

                if let track = await MetadataReader.readTrack(from: url) {
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

                for track in loaded {
                    if !self.tracks.contains(where: { $0.url.path == track.url.path }) {
                        self.tracks.append(track)
                    }
                }

                self.updateFilteredTracks()
                self.isScanning = false
                self.isLoading = false
                self.saveTracksToCache()

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
                self.startBackgroundEnrichment()
            }
        }
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
            // Все папки обработаны
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
        scanFolder(nextURL)
    }
    

    // MARK: - Фоновое обогащение (фазы 1-3)

    func startBackgroundEnrichment() {
        isEnriching = true
        startEnrichTimer()

        Task.detached(priority: .background) {
            // === Фаза 2: Миниатюры ===
            let tracksForThumbnails = await MainActor.run {
                self.tracks.filter { $0.albumArtURL != nil }
            }

            if !tracksForThumbnails.isEmpty {
                let thumbTotal = tracksForThumbnails.count

                await MainActor.run {
                    self.enrichPhase = 2
                    self.enrichProgress = (0, thumbTotal)
                    self.enrichLastRemaining = 0
                    self.startEnrichTimer()
                }

                let pauseDuration = SettingsManager.shared.thumbnailCreationSpeed

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
            if SettingsManager.shared.waveformCacheMode == "active" {
                let tracksToCache = await MainActor.run {
                    self.tracks.filter { WaveformCache.get(for: $0.url) == nil }
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

                        let samples = VisualizationEngine.shared.generateWaveformSamples(
                            for: track.url,
                            duration: track.duration
                        )
                        WaveformCache.set(for: track.url, samples: samples, duration: track.duration)

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

                if self.folderQueue.isEmpty {
                    NotificationCenter.default.post(name: .enrichmentComplete, object: nil)
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
        let content = try? String(contentsOf: url, encoding: .utf8)
            ?? String(contentsOf: url, encoding: .isoLatin1)
        
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
            CachedPlaylist(name: $0.name, trackPaths: $0.tracks.map { $0.url.path }, totalTrackCount: $0.tracks.count)
        }
        PlayerStateManager.shared.saveLibrary(state)
    }
    func loadPlaylistsFromCache() {
        guard let state = PlayerStateManager.shared.loadLibrary() else { return }
        let watchedPaths = watchedFolders.map { $0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/" }
        
        playlists = state.cachedPlaylists.compactMap { cached -> (String, [Track])? in
            let trackList: [Track] = cached.trackPaths.compactMap { path in
                if let track = self.tracks.first(where: { $0.url.path == path }) {
                    if watchedPaths.isEmpty { return track }
                    if watchedPaths.contains(where: { track.url.path.hasPrefix($0) }) { return track }
                }
                if let track = self.tracks.first(where: { $0.url.lastPathComponent == URL(fileURLWithPath: path).lastPathComponent }) {
                    if watchedPaths.isEmpty { return track }
                    if watchedPaths.contains(where: { track.url.path.hasPrefix($0) }) { return track }
                }
                return nil  // Не создаём заглушку
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
}
