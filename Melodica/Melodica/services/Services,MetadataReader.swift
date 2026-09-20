// Services,MetadataReader.swift
import AVFoundation
import AppKit
import CryptoKit
import CoreServices
import AudioToolbox

enum MetadataReader {

    // MARK: - Полное чтение метаданных

    static func readTrack(from url: URL) async -> Track? {
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.deletingPathExtension().lastPathComponent
        var title = fileName
        var artist = NSLocalizedString("unknown_artist", comment: "")
        var albumArtist: String?
        var album = NSLocalizedString("unknown_album", comment: "")
        var year: Int?
        var trackNumber: Int?
        var genre: String?
        var rating: Int?
        var duration: TimeInterval = 0
        var replayGain: Float?
        var replayGainPeak: Float?
        var replayGainAlbum: Float?
        var replayGainAlbumPeak: Float?
        var unsyncedLyrics: String?
        var albumArtData: Data?

        let realURL: URL = {
            if let fragment = url.fragment, fragment.hasPrefix("cue_") {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? url
            }
            return url
        }()

        if let hash = SmartTrackIDService.makeHash(for: realURL),
           let cached = TrackMetadataCacheService.shared.metadata(for: hash) {
            return Track(
                url: url,
                fileName: url.lastPathComponent,
                title: cached.title,
                artist: cached.artist,
                albumArtist: cached.albumArtist,
                album: cached.album,
                year: cached.year,
                duration: cached.duration,
                trackNumber: cached.trackNumber,
                genre: cached.genre,
                rating: cached.rating,
                albumArtURL: nil,
                replayGain: cached.replayGain,
                replayGainPeak: cached.replayGainPeak,
                replayGainAlbum: cached.replayGainAlbum,
                replayGainAlbumPeak: cached.replayGainAlbumPeak,
                lyricsURL: cached.lyricsURL.map { URL(fileURLWithPath: $0) },
                unsyncedLyrics: cached.unsyncedLyrics,
                cueStartTime: nil,
                smartHash: hash
            )
        }

        let asset = AVAsset(url: realURL)

        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isFinite ? cmDuration.seconds : 0
        } catch {}
        guard duration > 0 else { return nil }
        let smartHash = SmartTrackIDService.makeHash(for: realURL)

        do {
            let metadata = try await asset.load(.metadata)

            for item in metadata {
                if let commonKey = item.commonKey {
                    switch commonKey {
                    case .commonKeyTitle:
                        title = (try? await item.load(.stringValue)) ?? title
                    case .commonKeyArtist:
                        artist = (try? await item.load(.stringValue)) ?? artist
                    case .commonKeyAlbumName:
                        album = (try? await item.load(.stringValue)) ?? album
                    case .commonKeyArtwork:
                        albumArtData = try? await item.load(.dataValue)
                    case .commonKeyType:
                        genre = (try? await item.load(.stringValue)) ?? genre
                    default:
                        break
                    }
                    continue
                }

                guard let identifier = item.identifier?.rawValue else { continue }
                let value = (try? await item.load(.stringValue)) ?? ""

                if identifier == "id3/POPM",
                   let data = try? await item.load(.dataValue),
                   data.count >= 2 {
                    let bytes = [UInt8](data)
                    // POPM: email\0  rating(1)  counter(4)
                    // Ищем первый 0x00 — это конец email.
                    if let emailEnd = bytes.firstIndex(of: 0), emailEnd + 1 < bytes.count {
                        let rawRating = Int(bytes[emailEnd + 1])
                        let stars: Int
                        switch rawRating {
                        case 0:          stars = 0
                        case 1..<64:     stars = 1
                        case 64..<128:   stars = 2
                        case 128..<196:  stars = 3
                        case 196..<255:  stars = 4
                        default:         stars = 5
                        }
                        if stars > 0 { rating = stars * 51 }
                    }
                }

                switch identifier {
                case "itsk/aART", "vorb/ALBUMARTIST", "id3/TPE2",
                     "----:com.apple.iTunes:ALBUMARTIST":
                    if albumArtist == nil, !value.isEmpty {
                        albumArtist = value
                    }

                case "itlk/com.apple.iTunes.replaygain_track_gain",
                     "vorb/REPLAYGAIN_TRACK_GAIN",
                     "vorb/R128_TRACK_GAIN",
                     "----:com.apple.iTunes:replaygain_track_gain":
                    if replayGain == nil, let v = parseRGValue(value) {
                        replayGain = v
                    }

                case "itlk/com.apple.iTunes.replaygain_track_peak",
                     "vorb/REPLAYGAIN_TRACK_PEAK":
                    if replayGainPeak == nil {
                        replayGainPeak = Float(value.trimmingCharacters(in: .whitespaces))
                    }

                case "itlk/com.apple.iTunes.replaygain_album_gain",
                     "vorb/REPLAYGAIN_ALBUM_GAIN",
                     "vorb/R128_ALBUM_GAIN",
                     "----:com.apple.iTunes:replaygain_album_gain":
                    if replayGainAlbum == nil, let v = parseRGValue(value) {
                        replayGainAlbum = v
                    }

                case "itlk/com.apple.iTunes.replaygain_album_peak",
                     "vorb/REPLAYGAIN_ALBUM_PEAK":
                    if replayGainAlbumPeak == nil {
                        replayGainAlbumPeak = Float(value.trimmingCharacters(in: .whitespaces))
                    }

                case "itsk/%A9lyr", "vorb/LYRICS", "vorb/UNSYNCEDLYRICS", "id3/USLT":
                    if unsyncedLyrics == nil, !value.isEmpty {
                        unsyncedLyrics = value
                    }

                case "itsk/%A9day", "vorb/DATE", "vorb/YEAR",
                     "id3/TYER", "id3/TDRC", "id3/TYE":
                    if year == nil {
                        let yearStr = value.trimmingCharacters(in: .whitespaces)
                        if let yearMatch = yearStr.range(of: #"\d{4}"#, options: .regularExpression) {
                            year = Int(yearStr[yearMatch])
                        }
                    }

                case "itsk/com.apple.iTunes.year", "itsk/yr":
                    if year == nil {
                        year = Int(value.prefix(4))
                    }

                case "itsk/%A9gen", "vorb/GENRE", "id3/TCON":
                    if genre == nil {
                        genre = value
                            .replacingOccurrences(of: #"\(\d+\)"#, with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespaces)
                    }

                case "vorb/TRACKNUMBER", "id3/TRCK":
                    if trackNumber == nil {
                        trackNumber = Int(value.components(separatedBy: "/").first ?? "0")
                    }

                case "itsk/com.apple.iTunes.rating",
                     "itsk/rating",
                     "itsk/RATING",
                     "----:com.apple.iTunes:rating",
                     "----:com.apple.iTunes:RATING":
                    if rating == nil, let val = Int(value) {
                        // 0-100 шкала (iTunes) либо 0-255
                        if val <= 100 {
                            rating = val * 255 / 100
                        } else {
                            rating = val
                        }
                    }

                case "itsk/rtng":
                    if rating == nil, let val = Int(value) {
                        if val >= 0, val <= 5 {
                            rating = val * 51
                        } else if val > 5 {
                            rating = 255
                        }
                    }

                case "vorb/RATING", "vorb/FMPS_RATING":
                    if rating == nil {
                        if let intVal = Int(value), intVal >= 0, intVal <= 5 {
                            rating = intVal * 51
                        } else if let intVal = Int(value), intVal >= 0, intVal <= 100 {
                            rating = intVal * 255 / 100
                        } else if let floatVal = Float(value), floatVal >= 0, floatVal <= 1 {
                            rating = Int(floatVal * 255)
                        } else {
                            let parts = value.components(separatedBy: ":")
                            if let last = parts.last?.trimmingCharacters(in: .whitespaces),
                               let num = Int(last), num >= 0, num <= 5 {
                                rating = num * 51
                            }
                        }
                    }

                default:
                    break
                }
            }
        } catch {}

        // Fallback для MP3 RG
        if replayGain == nil || replayGainAlbum == nil,
           url.pathExtension.lowercased() == "mp3" {
            let result = await readReplayGainFromAVAsset(url: url)
            replayGain = replayGain ?? result.gain
            replayGainPeak = replayGainPeak ?? result.peak
            replayGainAlbum = replayGainAlbum ?? result.albumGain
            replayGainAlbumPeak = replayGainAlbumPeak ?? result.albumPeak

            if replayGain == nil || replayGainAlbum == nil {
                let id3 = readReplayGainFromID3(url: url)
                replayGain = replayGain ?? id3.gain
                replayGainPeak = replayGainPeak ?? id3.peak
                replayGainAlbum = replayGainAlbum ?? id3.albumGain
                replayGainAlbumPeak = replayGainAlbumPeak ?? id3.albumPeak
            }
        }

        // Fallback для MP3 Rating
        if rating == nil, url.pathExtension.lowercased() == "mp3" {
            rating = readRatingFromID3(url: url)
        }

        // Fallback для года
        if year == nil {
            year = readYearViaSpotlight(url: realURL)
        }
        if year == nil {
            year = readYearViaAudioToolbox(url: realURL)
        }

        let lyricsURL = LyricsParser.findLyrics(for: url)
        let artURL: URL? = albumArtData.flatMap { saveArtworkFromData($0, for: url) }

        if let hash = smartHash {
            let metadata = TrackMetadataCache(
                title: title,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                year: year,
                trackNumber: trackNumber,
                genre: genre,
                rating: rating,
                replayGain: replayGain,
                replayGainPeak: replayGainPeak,
                replayGainAlbum: replayGainAlbum,
                replayGainAlbumPeak: replayGainAlbumPeak,
                lyricsURL: lyricsURL?.path,
                unsyncedLyrics: unsyncedLyrics,
                duration: duration
            )

            TrackMetadataCacheService.shared.save(metadata, for: hash)
        }

        return Track(
            url: url,
            fileName: url.lastPathComponent,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            year: year,
            duration: duration,
            trackNumber: trackNumber,
            genre: genre,
            rating: rating,
            albumArtURL: artURL,
            replayGain: replayGain,
            replayGainPeak: replayGainPeak,
            replayGainAlbum: replayGainAlbum,
            replayGainAlbumPeak: replayGainAlbumPeak,
            lyricsURL: lyricsURL,
            unsyncedLyrics: unsyncedLyrics,
            cueStartTime: nil,
            smartHash: smartHash
        )
    }

    // MARK: - Обложки

    static func enrichArtwork(for track: Track) async -> URL? {
        guard track.albumArtURL == nil else { return nil }

        let asset = AVAsset(url: track.url)
        do {
            let metadata = try await asset.load(.metadata)

            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue) {
                        return saveArtworkFromData(data, for: track.url)
                    }
                }
            }
        } catch {}

        return nil
    }
    /// Все ли нужные миниатюры уже есть на диске.
    static func thumbnailsExist(for artURL: URL) -> Bool {
        let cacheDir = ImageCache.cacheDirectory()
        let hash = artURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "melodica_art_", with: "")
        let sizes = ["thumb_84", "thumb_400"]
        for size in sizes {
            let file = cacheDir
                .appendingPathComponent(size)
                .appendingPathComponent("melodica_thumb_\(hash).jpg")
            if !FileManager.default.fileExists(atPath: file.path) {
                return false
            }
        }
        return true
    }

    static func createThumbnails(for artURL: URL?, sourceURL: URL) async {
        guard let artURL else { return }

        // Дёшево: проверили на диске и ушли, не грузя картинку.
        if thumbnailsExist(for: artURL) { return }

        guard let image = NSImage(contentsOf: artURL) else { return }

        let cacheDir = ImageCache.cacheDirectory()
        let hash = artURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "melodica_art_", with: "")

        let sizes: [(String, CGFloat)] = [("thumb_84", 84), ("thumb_400", 400)]

        for (folder, size) in sizes {
            let dir = cacheDir.appendingPathComponent(folder)
            let thumbFile = dir.appendingPathComponent("melodica_thumb_\(hash).jpg")

            guard !FileManager.default.fileExists(atPath: thumbFile.path) else { continue }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let thumbSize = NSSize(width: size, height: size)
            let thumbImage = NSImage(size: thumbSize)
            thumbImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumbSize),
                       from: .zero, operation: .copy, fraction: 1.0)
            thumbImage.unlockFocus()

            if let tiff = thumbImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                try? jpeg.write(to: thumbFile)
            }
        }
    }

    // MARK: - Сохранение обложки

    private static func saveArtworkFromData(_ data: Data, for url: URL) -> URL? {
        let cacheDir = ImageCache.cacheDirectory()
        let hash = SHA256.hash(data: url.path.data(using: .utf8) ?? Data())
            .compactMap { String(format: "%02x", $0) }
            .joined()

        let fullDir = cacheDir.appendingPathComponent("full")
        try? FileManager.default.createDirectory(at: fullDir, withIntermediateDirectories: true)
        let artFile = fullDir.appendingPathComponent("melodica_art_\(hash.prefix(16)).jpg")

        guard !FileManager.default.fileExists(atPath: artFile.path) else { return artFile }

        if let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpeg.write(to: artFile)
        } else {
            try? data.write(to: artFile)
        }

        return artFile
    }

    // MARK: - Fallback: Год

    private static func readYearViaSpotlight(url: URL) -> Int? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return (MDItemCopyAttribute(item, kMDItemRecordingYear) as? NSNumber)?.intValue
    }

    private static func readYearViaAudioToolbox(url: URL) -> Int? {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else { return nil }
        defer { AudioFileClose(fileID) }

        var dict: CFDictionary?
        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &size, &dict)

        guard let info = dict as? [String: Any] else { return nil }

        if let year = info["year"] as? String {
            return Int(year.prefix(4))
        }
        if let date = info["recorded date"] as? String {
            return Int(date.prefix(4))
        }
        return nil
    }

    // MARK: - MP3: ReplayGain

    private static func readReplayGainFromAVAsset(url: URL) async -> (gain: Float?, peak: Float?, albumGain: Float?, albumPeak: Float?) {
        let asset = AVAsset(url: url)

        guard let metadata = try? await asset.load(.metadata) else {
            return (nil, nil, nil, nil)
        }

        var gain: Float?
        var peak: Float?
        var albumGain: Float?
        var albumPeak: Float?

        for item in metadata {
            guard item.identifier?.rawValue == "id3/TXXX" else { continue }

            let value = (try? await item.load(.stringValue)) ?? ""

            guard let extraInfo = item.extraAttributes?[AVMetadataExtraAttributeKey(rawValue: "info")] as? String else {
                continue
            }

            switch extraInfo.lowercased() {
            case "replaygain_track_gain":
                gain = parseRGValue(value)
            case "replaygain_track_peak":
                peak = Float(value.trimmingCharacters(in: .whitespaces))
            case "replaygain_album_gain":
                albumGain = parseRGValue(value)
            case "replaygain_album_peak":
                albumPeak = Float(value.trimmingCharacters(in: .whitespaces))
            default:
                break
            }
        }

        return (gain, peak, albumGain, albumPeak)
    }

    private static func readReplayGainFromID3(url: URL) -> (gain: Float?, peak: Float?, albumGain: Float?, albumPeak: Float?) {
        var gain: Float?
        var peak: Float?
        var albumGain: Float?
        var albumPeak: Float?

        guard let fileID = fopen(url.path, "r") else { return (nil, nil, nil, nil) }
        defer { fclose(fileID) }

        var header = [UInt8](repeating: 0, count: 10)
        fread(&header, 1, 10, fileID)

        guard header.prefix(3) == [0x49, 0x44, 0x33] else { return (nil, nil, nil, nil) }

        let tagSize = (Int(header[6]) << 21) |
                      (Int(header[7]) << 14) |
                      (Int(header[8]) << 7) |
                      Int(header[9])

        var tagData = [UInt8](repeating: 0, count: tagSize)
        fseek(fileID, 10, SEEK_SET)
        fread(&tagData, 1, tagSize, fileID)

        var offset = 0

        while offset < tagSize - 10 {
            let frameID = String(bytes: tagData[offset..<offset+4], encoding: .isoLatin1) ?? ""

            let frameSize: Int
            if tagData[offset+4] & 0x80 == 0 {
                frameSize = (Int(tagData[offset+4] & 0x7F) << 21) |
                            (Int(tagData[offset+5]) << 14) |
                            (Int(tagData[offset+6]) << 7) |
                            Int(tagData[offset+7])
            } else {
                frameSize = (Int(tagData[offset+4]) << 24) |
                            (Int(tagData[offset+5]) << 16) |
                            (Int(tagData[offset+6]) << 8) |
                            Int(tagData[offset+7])
            }

            guard frameSize > 0, offset + 10 + frameSize <= tagSize else { break }

            if frameID == "TXXX" {
                let frameData = Array(tagData[offset+10..<offset+10+frameSize])

                if let descEnd = frameData[1...].firstIndex(of: 0),
                   descEnd + 1 < frameData.count {
                    let desc = String(bytes: frameData[1..<descEnd], encoding: .utf8) ?? ""
                    let value = String(bytes: frameData[(descEnd+1)...], encoding: .utf8) ?? ""

                    let upper = desc.uppercased()

                    if upper.contains("REPLAYGAIN_TRACK_GAIN") { gain = parseRGValue(value) }
                    if upper.contains("REPLAYGAIN_TRACK_PEAK") { peak = Float(value.trimmingCharacters(in: .whitespaces)) }
                    if upper.contains("REPLAYGAIN_ALBUM_GAIN") { albumGain = parseRGValue(value) }
                    if upper.contains("REPLAYGAIN_ALBUM_PEAK") { albumPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                }
            }

            offset += 10 + frameSize
        }

        return (gain, peak, albumGain, albumPeak)
    }

    private static func readRatingFromID3(url: URL) -> Int? {
        guard let fileID = fopen(url.path, "r") else { return nil }
        defer { fclose(fileID) }

        var header = [UInt8](repeating: 0, count: 10)
        fread(&header, 1, 10, fileID)

        guard header.prefix(3) == [0x49, 0x44, 0x33] else { return nil }

        let tagSize = (Int(header[6]) << 21) |
                      (Int(header[7]) << 14) |
                      (Int(header[8]) << 7) |
                      Int(header[9])

        var tagData = [UInt8](repeating: 0, count: tagSize)
        fseek(fileID, 10, SEEK_SET)
        fread(&tagData, 1, tagSize, fileID)

        var offset = 0

        while offset < tagSize - 10 {
            let frameID = String(bytes: tagData[offset..<offset+4], encoding: .isoLatin1) ?? ""

            let frameSize: Int
            if tagData[offset+4] & 0x80 == 0 {
                frameSize = (Int(tagData[offset+4] & 0x7F) << 21) |
                            (Int(tagData[offset+5]) << 14) |
                            (Int(tagData[offset+6]) << 7) |
                            Int(tagData[offset+7])
            } else {
                frameSize = (Int(tagData[offset+4]) << 24) |
                            (Int(tagData[offset+5]) << 16) |
                            (Int(tagData[offset+6]) << 8) |
                            Int(tagData[offset+7])
            }

            guard frameSize > 0, offset + 10 + frameSize <= tagSize else { break }

            if frameID == "POPM" {
                let frameData = Array(tagData[offset+10..<offset+10+frameSize])

                if let emailEnd = frameData.firstIndex(of: 0),
                   emailEnd + 1 < frameData.count {
                    let rawRating = Int(frameData[emailEnd + 1])

                    let stars: Int
                    switch rawRating {
                    case 0:          stars = 0
                    case 1..<64:     stars = 1
                    case 64..<128:   stars = 2
                    case 128..<196:  stars = 3
                    case 196..<255:  stars = 4
                    default:         stars = 5
                    }

                    return stars * 51
                }
                break
            }

            offset += 10 + frameSize
        }

        return nil
    }

    // MARK: - Helpers

    private static func parseRGValue(_ str: String) -> Float? {
        let prefixes = [
            "REPLAYGAIN_TRACK_GAIN",
            "REPLAYGAIN_ALBUM_GAIN",
            "REPLAYGAIN TRACK GAIN",
            "REPLAYGAIN ALBUM GAIN",
            "TRACK_GAIN",
            "ALBUM_GAIN",
            "R128_TRACK_GAIN",
            "R128_ALBUM_GAIN"
        ]

        var cleaned = str

        for prefix in prefixes {
            cleaned = cleaned.replacingOccurrences(
                of: prefix,
                with: "",
                options: [.caseInsensitive, .anchored]
            )
        }

        for variant in ["−", "–", "—", "‐", "‑", "‒"] {
            cleaned = cleaned.replacingOccurrences(of: variant, with: "-")
        }

        cleaned = cleaned
            .replacingOccurrences(of: " dB", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " LU", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "LU", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)

        if let value = Float(cleaned) {
            if abs(value) > 50 {
                return value / 1000.0
            }
            return value
        }

        return nil
    }
}
