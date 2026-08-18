// Services,CUEParser.swift
import Foundation

struct CUETrack: Codable {
    let title: String
    let performer: String
    let trackNumber: Int
    let startTime: TimeInterval  // в секундах
    var duration: TimeInterval?   // nil если последний трек
}

struct CUEAlbum: Codable {
    let title: String
    let performer: String
    let file: URL
    let tracks: [CUETrack]
    var albumArtURL: URL?
    var replayGain: Float?
    var replayGainPeak: Float?
    var replayGainAlbum: Float?
    var replayGainAlbumPeak: Float?
    var genre: String?
    var year: Int?
    var unsyncedLyrics: String?
}

enum CUEParser {
    
    static func parse(_ cueURL: URL) -> CUEAlbum? {
        guard let content = try? String(contentsOf: cueURL, encoding: .utf8)
                ?? String(contentsOf: cueURL, encoding: .isoLatin1) else { return nil }
        
        var albumTitle = cueURL.deletingPathExtension().lastPathComponent
        var albumPerformer = "Неизвестный исполнитель"
        var audioFile: URL?
        var tracks: [CUETrack] = []
        
        var currentTrack: Int?
        var currentTitle: String?
        var currentPerformer: String?
        var currentIndex: TimeInterval?
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("REM") else { continue }
            
            // Извлекаем значение в кавычках
            func extractQuoted(_ str: String) -> String {
                guard let start = str.firstIndex(of: "\""),
                      let end = str[str.index(after: start)...].firstIndex(of: "\"") else {
                    return str.components(separatedBy: " ").dropFirst().joined(separator: " ")
                }
                return String(str[str.index(after: start)..<end])
            }
            
            let upperTrimmed = trimmed.uppercased()
            
            // TITLE "Album Name"
            if upperTrimmed.hasPrefix("TITLE "), !upperTrimmed.hasPrefix("TITLE \"") == false {
                let title = extractQuoted(trimmed)
                if currentTrack == nil {
                    albumTitle = title
                } else {
                    currentTitle = title
                }
            }
            
            // PERFORMER "Artist"
            if upperTrimmed.hasPrefix("PERFORMER ") {
                let performer = extractQuoted(trimmed)
                if currentTrack == nil {
                    albumPerformer = performer
                } else {
                    currentPerformer = performer
                }
            }
            
            // FILE "audio.flac" WAVE
            if upperTrimmed.hasPrefix("FILE ") {
                let fileName = extractQuoted(trimmed)
                let baseDir = cueURL.deletingLastPathComponent()
                audioFile = baseDir.appendingPathComponent(fileName)
            }
            
            // TRACK 01 AUDIO
            if upperTrimmed.hasPrefix("TRACK ") {
                // Сохраняем предыдущий трек
                if let num = currentTrack, let index = currentIndex {
                    let title = currentTitle ?? "Track \(num)"
                    let performer = currentPerformer ?? albumPerformer
                    tracks.append(CUETrack(title: title, performer: performer, trackNumber: num, startTime: index, duration: nil))
                }
                
                // Начинаем новый трек
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2, let num = Int(parts[1]) {
                    currentTrack = num
                    currentTitle = nil
                    currentPerformer = nil
                    currentIndex = nil
                }
            }
            
            // INDEX 01 00:00:00
            if upperTrimmed.hasPrefix("INDEX 01 ") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 3 {
                    let timeParts = parts[2].components(separatedBy: ":")
                    if timeParts.count == 3,
                       let min = Int(timeParts[0]),
                       let sec = Int(timeParts[1]),
                       let frames = Int(timeParts[2]) {
                        currentIndex = TimeInterval(min * 60 + sec) + TimeInterval(frames) / 75.0
                    }
                }
            }
        }
        
        // Сохраняем последний трек
        if let num = currentTrack, let index = currentIndex {
            let title = currentTitle ?? "Track \(num)"
            let performer = currentPerformer ?? albumPerformer
            tracks.append(CUETrack(title: title, performer: performer, trackNumber: num, startTime: index, duration: nil))
        }
        
        guard let file = audioFile, !tracks.isEmpty else { return nil }
        
        // Вычисляем длительности
        for i in 0..<tracks.count {
            if i + 1 < tracks.count {
                let duration = tracks[i + 1].startTime - tracks[i].startTime
                tracks[i] = CUETrack(title: tracks[i].title, performer: tracks[i].performer, trackNumber: tracks[i].trackNumber, startTime: tracks[i].startTime, duration: duration)
            }
        }
        
        return CUEAlbum(title: albumTitle, performer: albumPerformer, file: file, tracks: tracks)
    }
}
