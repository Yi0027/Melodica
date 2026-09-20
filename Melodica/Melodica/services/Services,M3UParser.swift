// Services,M3UParser.swift
import Foundation

enum M3UParser {
    
    static func parse(_ url: URL) -> (name: String, urls: [URL]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .isoLatin1) else {
            return (url.deletingPathExtension().lastPathComponent, [])
        }
        let baseDir = url.deletingLastPathComponent()
        let defaultName = url.deletingPathExtension().lastPathComponent
        return parseContent(content, baseDir: baseDir, defaultName: defaultName)
    }
    
    static func parseContent(_ content: String, baseDir: URL, defaultName: String) -> (name: String, urls: [URL]) {
        var urls: [URL] = []
        var playlistName = defaultName
        
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty { i += 1; continue }
            
            // Заголовок
            if line.uppercased() == "#EXTM3U" { i += 1; continue }
            
            // Название плейлиста
            if line.uppercased().hasPrefix("#PLAYLIST:") {
                playlistName = line.replacingOccurrences(of: "#PLAYLIST:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                i += 1
                continue
            }
            
            // EXTINF — за ним следует путь к файлу
            if line.uppercased().hasPrefix("#EXTINF:") {
                if i + 1 < lines.count {
                    let pathLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    
                    if !pathLine.isEmpty && !pathLine.hasPrefix("#") {
                        let trackURL = resolveURL(pathLine, baseDir: baseDir)
                        if FileManager.default.fileExists(atPath: trackURL.path) {
                            urls.append(trackURL)
                        }
                    }
                }
                i += 2
                continue
            }
            
            // Простой путь без EXTINF
            if !line.hasPrefix("#") {
                let trackURL = resolveURL(line, baseDir: baseDir)
                if FileManager.default.fileExists(atPath: trackURL.path) {
                    urls.append(trackURL)
                }
            }
            
            i += 1
        }
        
        return (playlistName, urls)
    }
    
    private static func resolveURL(_ path: String, baseDir: URL) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        
        // Абсолютный путь
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        
        // Домашняя директория
        if trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        
        // file:// URL
        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed) ?? URL(fileURLWithPath: trimmed)
        }
        
        // Относительный путь с поддержкой ../ и ./
        if trimmed.contains("..") || trimmed.hasPrefix("./") {
            return URL(fileURLWithPath: trimmed, relativeTo: baseDir).absoluteURL
                ?? baseDir.appendingPathComponent(trimmed)
        }
        
        // Обычный относительный путь
        return baseDir.appendingPathComponent(trimmed)
    }
    
    /// Экспорт в M3U
    static func export(playlist: (name: String, tracks: [Track]), to url: URL, useAbsolutePaths: Bool = true) {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#PLAYLIST: \(playlist.name)")
        
        for track in playlist.tracks {
            lines.append("#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)")
            
            if useAbsolutePaths {
                lines.append(track.url.path)
            } else {
                let saveDir = url.deletingLastPathComponent()
                var relative = track.url.path.replacingOccurrences(of: saveDir.path + "/", with: "")
                if relative == track.url.path {
                    relative = "../" + track.url.lastPathComponent
                }
                lines.append(relative)
            }
        }
        
        let content = lines.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
