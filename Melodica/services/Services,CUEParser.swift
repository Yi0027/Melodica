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
    var replayGain: Float?
    var replayGainPeak: Float?
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

nonisolated enum CUEParser {

    static func parse(_ cueURL: URL) -> CUEAlbum? {
        guard let content = (try? String(contentsOf: cueURL, encoding: .utf8))
                ?? (try? String(contentsOf: cueURL, encoding: .windowsCP1251))
                ?? (try? String(contentsOf: cueURL, encoding: .windowsCP1252))
                ?? (try? String(contentsOf: cueURL, encoding: .shiftJIS))
                ?? (try? String(contentsOf: cueURL, encoding: .isoLatin1))
        else { return nil }

        var albumTitle = cueURL.deletingPathExtension().lastPathComponent
        var albumPerformer = "Unknown Artist"
        var albumGenre: String?
        var albumYear: Int?
        var albumReplayGain: Float?
        var albumReplayGainPeak: Float?
        var audioFile: URL?
        var tracks: [CUETrack] = []

        var currentTrack: Int?
        var currentTitle: String?
        var currentPerformer: String?
        var currentIndex: TimeInterval?
        var currentTrackReplayGain: Float?
        var currentTrackReplayGainPeak: Float?

        let lines = content.components(separatedBy: .newlines)

        func extractQuoted(_ str: String) -> String {
            guard let start = str.firstIndex(of: "\""),
                  let end = str[str.index(after: start)...].firstIndex(of: "\"") else {
                return str.components(separatedBy: " ").dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }
            return String(str[str.index(after: start)..<end])
        }

        func extractFileName(from fileLine: String) -> String {
            if let start = fileLine.firstIndex(of: "\""),
               let end = fileLine[fileLine.index(after: start)...].firstIndex(of: "\"") {
                return String(fileLine[fileLine.index(after: start)..<end])
            }
            let parts = fileLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3 {
                return parts.dropFirst().dropLast().joined(separator: " ")
            } else if parts.count == 2 {
                return parts[1]
            }
            return ""
        }

        func resolveAudioFile(_ fileName: String, baseDir: URL) -> URL {
            let direct = baseDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let commonExts = ["flac", "wav", "m4a", "mp3", "aif", "aiff", "opus", "ogg"]
            for ext in commonExts {
                let alt = baseDir.appendingPathComponent("\(nameWithoutExt).\(ext)")
                if FileManager.default.fileExists(atPath: alt.path) {
                    return alt
                }
            }
            return direct
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let upperTrimmed = trimmed.uppercased()

            if upperTrimmed.hasPrefix("REM ") {
                if upperTrimmed.hasPrefix("REM GENRE ") {
                    let g = extractQuoted(trimmed.replacingOccurrences(of: "REM ", with: "", options: .caseInsensitive))
                    albumGenre = g.isEmpty ? nil : g
                } else if upperTrimmed.hasPrefix("REM DATE ") {
                    let d = extractQuoted(trimmed.replacingOccurrences(of: "REM ", with: "", options: .caseInsensitive))
                    albumYear = Int(d)
                } else if upperTrimmed.hasPrefix("REM REPLAYGAIN_TRACK_GAIN ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if let valStr = parts.dropFirst(2).first {
                        let clean = valStr.replacingOccurrences(of: "dB", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                        currentTrackReplayGain = Float(clean)
                    }
                } else if upperTrimmed.hasPrefix("REM REPLAYGAIN_TRACK_PEAK ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if let valStr = parts.dropFirst(2).first {
                        currentTrackReplayGainPeak = Float(valStr)
                    }
                } else if upperTrimmed.hasPrefix("REM REPLAYGAIN_ALBUM_GAIN ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if let valStr = parts.dropFirst(2).first {
                        let clean = valStr.replacingOccurrences(of: "dB", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                        albumReplayGain = Float(clean)
                    }
                } else if upperTrimmed.hasPrefix("REM REPLAYGAIN_ALBUM_PEAK ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if let valStr = parts.dropFirst(2).first {
                        albumReplayGainPeak = Float(valStr)
                    }
                }
                continue
            }

            if upperTrimmed.hasPrefix("TITLE ") {
                let title = extractQuoted(trimmed)
                if currentTrack == nil { albumTitle = title } else { currentTitle = title }
            }

            if upperTrimmed.hasPrefix("PERFORMER ") {
                let performer = extractQuoted(trimmed)
                if currentTrack == nil { albumPerformer = performer } else { currentPerformer = performer }
            }

            if upperTrimmed.hasPrefix("FILE ") {
                let fileName = extractFileName(from: trimmed)
                let baseDir = cueURL.deletingLastPathComponent()
                audioFile = resolveAudioFile(fileName, baseDir: baseDir)
            }

            if upperTrimmed.hasPrefix("TRACK ") {
                if let num = currentTrack, let index = currentIndex {
                    let title = currentTitle ?? "Track \(num)"
                    let performer = currentPerformer ?? albumPerformer
                    tracks.append(CUETrack(
                        title: title,
                        performer: performer,
                        trackNumber: num,
                        startTime: index,
                        duration: nil,
                        replayGain: currentTrackReplayGain,
                        replayGainPeak: currentTrackReplayGainPeak
                    ))
                }
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2, let num = Int(parts[1]) {
                    currentTrack = num
                    currentTitle = nil
                    currentPerformer = nil
                    currentIndex = nil
                    currentTrackReplayGain = nil
                    currentTrackReplayGainPeak = nil
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
            tracks.append(CUETrack(
                title: title,
                performer: performer,
                trackNumber: num,
                startTime: index,
                duration: nil,
                replayGain: currentTrackReplayGain,
                replayGainPeak: currentTrackReplayGainPeak
            ))
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
                    duration: duration,
                    replayGain: tracks[i].replayGain,
                    replayGainPeak: tracks[i].replayGainPeak
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
                    duration: computed,
                    replayGain: tracks[lastIdx].replayGain,
                    replayGainPeak: tracks[lastIdx].replayGainPeak
                )
            }
        }

        return CUEAlbum(
            title: albumTitle,
            performer: albumPerformer,
            file: file,
            tracks: tracks,
            albumArtURL: nil,
            replayGain: nil,
            replayGainPeak: nil,
            replayGainAlbum: albumReplayGain,
            replayGainAlbumPeak: albumReplayGainPeak,
            genre: albumGenre,
            year: albumYear,
            unsyncedLyrics: nil
        )
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
            var comp = URLComponents(url: file, resolvingAgainstBaseURL: false)
            comp?.fragment = "cue_\(String(format: "%.3f", cue.startTime))"
            let cueURL = comp?.url ?? (URL(string: file.absoluteString + "#cue_\(String(format: "%.3f", cue.startTime))") ?? file)
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
                replayGain: cue.replayGain ?? replayGainAlbum,
                replayGainPeak: cue.replayGainPeak ?? replayGainAlbumPeak,
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
