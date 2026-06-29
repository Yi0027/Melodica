// Services,M3UParser.swift
import Foundation

enum M3UParser {
    
    /// Импорт M3U файла — возвращает имя плейлиста и список URL треков
    static func parse(_ url: URL) -> (name: String, urls: [URL]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .isoLatin1) else {
            return (url.deletingPathExtension().lastPathComponent, [])
        }
        
        let baseDir = url.deletingPathExtension().deletingLastPathComponent()
        var urls: [URL] = []
        var playlistName = url.deletingPathExtension().lastPathComponent
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty { continue }
            
            // Ищем имя плейлиста
            if trimmed.uppercased().hasPrefix("#PLAYLIST:") {
                let name = trimmed.replacingOccurrences(of: "#PLAYLIST:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    playlistName = name
                }
                continue
            }
            
            // Пропускаем другие комментарии
            if trimmed.hasPrefix("#") { continue }
            
            let trackURL: URL
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                trackURL = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            } else if trimmed.hasPrefix("file://") {
                trackURL = URL(string: trimmed) ?? URL(fileURLWithPath: trimmed)
            } else {
                trackURL = baseDir.appendingPathComponent(trimmed)
            }
            
            if FileManager.default.fileExists(atPath: trackURL.path) {
                urls.append(trackURL)
            }
        }
        
        return (playlistName, urls)
    }
    
    /// Экспорт в M3U
    static func export(playlist: (name: String, tracks: [Track]), to url: URL) {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#PLAYLIST: \(playlist.name)")
        
        for track in playlist.tracks {
            lines.append("#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)")
            lines.append(track.url.path)
        }
        
        let content = lines.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
