// Services,M3UParser.swift
import Foundation

nonisolated enum M3UParser {
    
    static func parse(_ url: URL, validateExistence: Bool = false) -> (name: String, urls: [URL]) {
        guard let content = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            return (url.deletingPathExtension().lastPathComponent, [])
        }
        let baseDir = url.deletingLastPathComponent()
        let defaultName = url.deletingPathExtension().lastPathComponent
        return parseContent(content, baseDir: baseDir, defaultName: defaultName, validateExistence: validateExistence)
    }
    
    static func parseContent(_ content: String, baseDir: URL, defaultName: String, validateExistence: Bool = false) -> (name: String, urls: [URL]) {
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
            
            // EXTINF — ищем следующий не-комментарий (путь к файлу)
            if line.uppercased().hasPrefix("#EXTINF:") {
                i += 1
                while i < lines.count {
                    let pathLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if pathLine.isEmpty {
                        i += 1
                        continue
                    }
                    if pathLine.hasPrefix("#") {
                        if pathLine.uppercased().hasPrefix("#PLAYLIST:") {
                            playlistName = pathLine.replacingOccurrences(of: "#PLAYLIST:", with: "", options: .caseInsensitive)
                                .trimmingCharacters(in: .whitespaces)
                        }
                        i += 1
                        continue
                    }
                    let trackURL = resolveURL(pathLine, baseDir: baseDir)
                    if !validateExistence || FileManager.default.fileExists(atPath: trackURL.path) {
                        urls.append(trackURL)
                    }
                    i += 1
                    break
                }
                continue
            }
            
            // Простой путь без EXTINF
            if !line.hasPrefix("#") {
                let trackURL = resolveURL(line, baseDir: baseDir)
                if !validateExistence || FileManager.default.fileExists(atPath: trackURL.path) {
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
                let prefix = saveDir.path.hasSuffix("/") ? saveDir.path : saveDir.path + "/"
                if track.url.path.hasPrefix(prefix) {
                    let relative = String(track.url.path.dropFirst(prefix.count))
                    lines.append(relative)
                } else {
                    lines.append(track.url.path)
                }
            }
        }
        
        let content = lines.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
