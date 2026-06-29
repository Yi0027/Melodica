// ViewModels,LibraryViewModel.swift
import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var searchText = ""
    @Published var sortField: Track.SortField = .album
    @Published var sortAscending = true
    @Published var isLoading = false
    
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
            groups[i].2.sort { (a, b) in
                (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max)
            }
        }
        
        groups.sort { (a, b) in
            let cmp = a.0.localizedCompare(b.0) == .orderedAscending
            return sortAscending ? cmp : !cmp
        }
        
        return groups
    }
    
    var filteredTracks: [Track] {
        var result = tracks
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query) ||
                ($0.genre ?? "").lowercased().contains(query)
            }
        }
        
        result.sort { (a, b) in
            let cmp: Bool
            switch sortField {
            case .title:
                cmp = a.title.localizedCompare(b.title) == .orderedAscending
            case .artist:
                cmp = a.artist.localizedCompare(b.artist) == .orderedAscending
            case .album:
                cmp = a.album.localizedCompare(b.album) == .orderedAscending
            case .genre:
                cmp = (a.genre ?? "ЯЯЯ").localizedCompare(b.genre ?? "ЯЯЯ") == .orderedAscending
            case .year:
                cmp = (a.year ?? .max) < (b.year ?? .max)
            case .duration:
                cmp = a.duration < b.duration
            }
            return sortAscending ? cmp : !cmp
        }
        
        return result
    }
    
    func loadFolder(_ folderURL: URL) {
        let bookmarkData = try? folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        var state = PlayerStateManager.shared.load() ?? PlayerState(
            lastFolderBookmark: nil,
            currentTrackPath: nil,
            currentTime: 0,
            volume: 0.5,
            repeatMode: "off",
            shuffleMode: false,
            queuePaths: [],
            favoritePaths: [],
            timestamp: Date()
        )
        state.lastFolderBookmark = bookmarkData
        PlayerStateManager.shared.save(state: state)
        
        scanFolder(folderURL)
    }
    
    private func scanFolder(_ folderURL: URL) {
        let needsSecurity = folderURL.startAccessingSecurityScopedResource()
        defer { if needsSecurity { folderURL.stopAccessingSecurityScopedResource() } }
        
        isLoading = true
        
        let supportedExtensions: Set<String> = ["mp3", "flac", "m4a", "aac", "opus", "ogg"]
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("❌ Не удалось создать enumerator")
            isLoading = false
            return
        }
        
        // ✅ Собираем все URL на главном потоке (потокобезопасно)
        var allURLs: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                allURLs.append(url)
            }
        }
        
        print("📊 Найдено файлов: \(allURLs.count)")
        
        // ✅ Обрабатываем в фоновом потоке
        let urls = allURLs
        Task.detached(priority: .userInitiated) {
            var loaded: [Track] = []
            
            for url in urls {
                if let track = await MetadataReader.readTrack(from: url) {
                    loaded.append(track)
                }
            }
            
            print("📊 Загружено треков: \(loaded.count)")
            
            await MainActor.run {
                self.tracks = loaded
                self.isLoading = false
            }
        }
    }
    
    func restoreLastFolder() -> URL? {
        guard let state = PlayerStateManager.shared.load(),
              let bookmarkData = state.lastFolderBookmark else {
            print("❌ Нет bookmark'а")
            return nil
        }
        
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("❌ Не удалось разрешить bookmark")
            return nil
        }
        
        if isStale {
            print("⚠️ Bookmark устарел")
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            print("❌ Папка не существует: \(url.path)")
            return nil
        }
        
        return url
    }
}
