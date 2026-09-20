// Services,CUEParser.swift
import Foundation
import AVFoundation
import CryptoKit

struct CUETrack: Codable {
    let title: String
    let performer: String
    let trackNumber: Int
    let startTime: TimeInterval  // в секундах
    var duration: TimeInterval?   // nil если не удалось вычислить (нет аудиофайла)
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

            func extractQuoted(_ str: String) -> String {
                guard let start = str.firstIndex(of: "\""),
                      let end = str[str.index(after: start)...].firstIndex(of: "\"") else {
                    return str.components(separatedBy: " ").dropFirst().joined(separator: " ")
                }
                return String(str[str.index(after: start)..<end])
            }

            let upperTrimmed = trimmed.uppercased()

            if upperTrimmed.hasPrefix("TITLE "), !upperTrimmed.hasPrefix("TITLE \"") == false {
                let title = extractQuoted(trimmed)
                if currentTrack == nil { albumTitle = title } else { currentTitle = title }
            }

            if upperTrimmed.hasPrefix("PERFORMER ") {
                let performer = extractQuoted(trimmed)
                if currentTrack == nil { albumPerformer = performer } else { currentPerformer = performer }
            }

            if upperTrimmed.hasPrefix("FILE ") {
                let fileName = extractQuoted(trimmed)
                let baseDir = cueURL.deletingLastPathComponent()
                audioFile = baseDir.appendingPathComponent(fileName)
            }

            if upperTrimmed.hasPrefix("TRACK ") {
                if let num = currentTrack, let index = currentIndex {
                    let title = currentTitle ?? "Track \(num)"
                    let performer = currentPerformer ?? albumPerformer
                    tracks.append(CUETrack(title: title, performer: performer, trackNumber: num, startTime: index, duration: nil))
                }
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2, let num = Int(parts[1]) {
                    currentTrack = num
                    currentTitle = nil
                    currentPerformer = nil
                    currentIndex = nil
                }
            }

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

        if let num = currentTrack, let index = currentIndex {
            let title = currentTitle ?? "Track \(num)"
            let performer = currentPerformer ?? albumPerformer
            tracks.append(CUETrack(title: title, performer: performer, trackNumber: num, startTime: index, duration: nil))
        }

        guard let file = audioFile, !tracks.isEmpty else { return nil }

        // Длительности всех треков кроме последнего — разница со следующим.
        for i in 0..<tracks.count {
            if i + 1 < tracks.count {
                let duration = tracks[i + 1].startTime - tracks[i].startTime
                tracks[i] = CUETrack(
                    title: tracks[i].title,
                    performer: tracks[i].performer,
                    trackNumber: tracks[i].trackNumber,
                    startTime: tracks[i].startTime,
                    duration: duration
                )
            }
        }

        // Последний трек — общая длина аудио минус startTime.
        if tracks.last?.duration == nil,
           let audioDuration = readAudioDuration(file) {
            let lastIdx = tracks.count - 1
            let lastStart = tracks[lastIdx].startTime
            let computed = audioDuration - lastStart
            if computed > 0 {
                tracks[lastIdx] = CUETrack(
                    title: tracks[lastIdx].title,
                    performer: tracks[lastIdx].performer,
                    trackNumber: tracks[lastIdx].trackNumber,
                    startTime: lastStart,
                    duration: computed
                )
            }
        }

        return CUEAlbum(title: albumTitle, performer: albumPerformer, file: file, tracks: tracks)
    }

    // MARK: - Helpers

    /// Читает длительность аудиофайла через AVAudioFile (синхронно, но быстро).
    private static func readAudioDuration(_ url: URL) -> TimeInterval? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Double(file.length) / sampleRate
    }

    /// Детерминированный хеш для cue-трека.
    /// Уникален для (файл + startTime), стабилен между запусками.
    static func cueTrackHash(fileURL: URL, startTime: TimeInterval) -> String {
        let key = fileURL.path + "#cue_" + String(format: "%.3f", startTime)
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CUEAlbum → [Track]

extension CUEAlbum {

    /// Строит массив Track-ов для этого cue-альбома.
    /// `id` и `smartHash` детерминированные — favorites/queue/rating будут
    /// корректно восстанавливаться между сессиями.
    func makeTracks() -> [Track] {
        tracks.map { cue in
            let cueURL = URL(string: file.absoluteString + "#cue_\(String(format: "%.3f", cue.startTime))") ?? file
            let hash = CUEParser.cueTrackHash(fileURL: file, startTime: cue.startTime)

            var track = Track(
                url: cueURL,
                fileName: "\(cue.trackNumber). \(cue.title)",
                title: cue.title,
                artist: cue.performer,
                album: title,
                year: year,
                duration: cue.duration ?? 0,
                trackNumber: cue.trackNumber,
                genre: genre,
                albumArtURL: albumArtURL,
                replayGain: replayGain,
                replayGainPeak: replayGainPeak,
                replayGainAlbum: replayGainAlbum,
                replayGainAlbumPeak: replayGainAlbumPeak,
                lyricsURL: Self.findLyrics(for: cue, in: self),
                unsyncedLyrics: unsyncedLyrics,
                cueStartTime: cue.startTime,
                smartHash: hash
            )
            track.id = Track.stableUUID(from: hash)
            return track
        }
    }

    private static func findLyrics(for cue: CUETrack, in album: CUEAlbum) -> URL? {
        let baseDir = album.file.deletingLastPathComponent()
        let names = [
            "\(cue.performer) - \(cue.title).lrc",
            "\(cue.title).lrc"
        ]
        for name in names {
            let url = baseDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
