// Services,MetadataReader.swift
import AVFoundation
import AppKit
import AudioToolbox
import CryptoKit
import CoreServices

enum MetadataReader {
    
    // MARK: - Быстрое чтение (Spotlight → AudioToolbox → AVAsset)
    
    static func readTrack(from url: URL) async -> Track? {
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }
        
        // Уровень 1: Spotlight (мгновенно)
        if let track = readViaSpotlight(url) { return track }
        
        // Уровень 2: AudioToolbox (быстро)
        if let track = readViaAudioToolbox(url) { return track }
        
        // Уровень 3: AVAsset (полный, один раз)
        return await readFullMetadata(from: url)
    }
    
    // MARK: - Фоновое обогащение (только то, что не требует AVAsset)
    
    static func enrichTrack(_ track: Track) async -> Track {
        var enriched = track
        
        // Читаем albumArtist + RG + LRC через AVAsset (один раз)
        if enriched.albumArtist == nil || enriched.replayGain == nil || enriched.unsyncedLyrics == nil {
            let asset = AVAsset(url: track.url)
            guard let _ = try? await asset.load(.metadata) else { return enriched }
            
            for item in asset.metadata {
                if let identifier = item.identifier?.rawValue {
                    let value = item.stringValue ?? ""
                    switch identifier {
                    case "itsk/aART", "vorb/ALBUMARTIST", "id3/TPE2":
                        if enriched.albumArtist == nil, !value.isEmpty { enriched.albumArtist = value }
                    case "itlk/com.apple.iTunes.replaygain_track_gain", "vorb/REPLAYGAIN_TRACK_GAIN":
                        if enriched.replayGain == nil, let v = parseRGValue(value) { enriched.replayGain = v }
                    case "itlk/com.apple.iTunes.replaygain_track_peak", "vorb/REPLAYGAIN_TRACK_PEAK":
                        if enriched.replayGainPeak == nil { enriched.replayGainPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                    case "itlk/com.apple.iTunes.replaygain_album_gain", "vorb/REPLAYGAIN_ALBUM_GAIN":
                        if enriched.replayGainAlbum == nil, let v = parseRGValue(value) { enriched.replayGainAlbum = v }
                    case "itlk/com.apple.iTunes.replaygain_album_peak", "vorb/REPLAYGAIN_ALBUM_PEAK":
                        if enriched.replayGainAlbumPeak == nil { enriched.replayGainAlbumPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                    case "itsk/%A9lyr", "vorb/LYRICS", "vorb/UNSYNCEDLYRICS", "id3/USLT":
                        if enriched.unsyncedLyrics == nil, !value.isEmpty { enriched.unsyncedLyrics = value }
                    default: break
                    }
                }
            }
        }
        
        // ID3 fallback для RG
        if enriched.replayGain == nil && enriched.replayGainAlbum == nil {
            let result = readReplayGainFromID3(url: track.url)
            enriched.replayGain = result.gain ?? enriched.replayGain
            enriched.replayGainPeak = result.peak ?? enriched.replayGainPeak
            enriched.replayGainAlbum = result.albumGain ?? enriched.replayGainAlbum
            enriched.replayGainAlbumPeak = result.albumPeak ?? enriched.replayGainAlbumPeak
        }
        
        if enriched.lyricsURL == nil {
            enriched.lyricsURL = LyricsParser.findLyrics(for: track.url)
        }
        
        return enriched
    }
    
    // MARK: - Сохранение обложки в полном размере
    
    static func enrichArtwork(for track: Track) async -> URL? {
        // Если обложка уже есть — пропускаем
        guard track.albumArtURL == nil else { return nil }
        
        // Открываем AVAsset ТОЛЬКО если обложки ещё нет
        let asset = AVAsset(url: track.url)
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if let commonKey = item.commonKey, commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue) {
                        return saveArtworkFromData(data, for: track.url)
                    }
                }
            }
        } catch {}
        
        return nil
    }
    
    // MARK: - Создание миниатюр
    
    static func createThumbnails(for artURL: URL?, sourceURL: URL) async {
        guard let artURL = artURL,
              let image = NSImage(contentsOf: artURL) else { return }
        
        let cacheDir = ImageCache.cacheDirectory()
        let hash = artURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "melodica_art_", with: "")
        
        let sizes: [(String, CGFloat)] = [
            ("thumb_84", 84),
            ("thumb_400", 400)
        ]
        
        for (folder, size) in sizes {
            let dir = cacheDir.appendingPathComponent(folder)
            let thumbFile = dir.appendingPathComponent("melodica_thumb_\(hash).jpg")
            
            guard !FileManager.default.fileExists(atPath: thumbFile.path) else { continue }
            
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let thumbSize = NSSize(width: size, height: size)
            let thumbImage = NSImage(size: thumbSize)
            thumbImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumbSize), from: .zero, operation: .copy, fraction: 1.0)
            thumbImage.unlockFocus()
            if let tiffData = thumbImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                try? jpegData.write(to: thumbFile)
            }
        }
    }
    
    // MARK: - Уровень 1: Spotlight
    
    private static func readViaSpotlight(_ url: URL) -> Track? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        
        let title = MDItemCopyAttribute(item, kMDItemTitle) as? String
        let artists = MDItemCopyAttribute(item, kMDItemAuthors) as? [String]
        let artist = artists?.first
        let album = MDItemCopyAttribute(item, kMDItemAlbum) as? String
        let duration = (MDItemCopyAttribute(item, kMDItemDurationSeconds) as? NSNumber)?.doubleValue
        let genre = MDItemCopyAttribute(item, kMDItemMusicalGenre) as? String
        let trackNumber = (MDItemCopyAttribute(item, kMDItemAudioTrackNumber) as? NSNumber)?.intValue
        let year = (MDItemCopyAttribute(item, kMDItemRecordingYear) as? NSNumber)?.intValue
            ?? (MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date).flatMap {
                Calendar.current.dateComponents([.year], from: $0).year
            }
        
        guard let duration = duration, duration > 0 else { return nil }
        
        return Track(
            url: url, fileName: url.lastPathComponent,
            title: title ?? url.deletingPathExtension().lastPathComponent,
            artist: artist ?? NSLocalizedString("unknown_artist", comment: ""),
            albumArtist: nil,
            album: album ?? NSLocalizedString("unknown_album", comment: ""),
            year: year,
            duration: duration ?? 0,
            trackNumber: trackNumber,
            genre: genre,
            albumArtURL: nil,
            replayGain: nil, replayGainPeak: nil,
            replayGainAlbum: nil, replayGainAlbumPeak: nil,
            lyricsURL: nil, unsyncedLyrics: nil
        )
    }
    
    // MARK: - Уровень 2: AudioToolbox
    
    private static func readViaAudioToolbox(_ url: URL) -> Track? {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr, let fileID = fileID else { return nil }
        defer { AudioFileClose(fileID) }
        
        var duration: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &size, &duration)
        guard duration > 0 else { return nil }
        
        var infoDict: CFDictionary?
        size = UInt32(MemoryLayout<CFDictionary?>.size)
        AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &size, &infoDict)
        
        guard let dict = infoDict as? [String: Any] else { return nil }
        
        let title = (dict["title"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let artist = (dict["artist"] as? String) ?? NSLocalizedString("unknown_artist", comment: "")
        let album = (dict["album"] as? String) ?? NSLocalizedString("unknown_album", comment: "")
        let genre = dict["genre"] as? String
        let year = (dict["year"] as? String).flatMap { Int($0) }
            ?? (dict["date"] as? String).flatMap { Int($0.prefix(4)) }
            ?? (dict["creationDate"] as? String).flatMap { Int($0.prefix(4)) }
            ?? (dict["recorded date"] as? String).flatMap { Int($0.prefix(4)) }
        let trackNumber = (dict["track number"] as? String).flatMap { Int($0.components(separatedBy: "/").first ?? "0") }
        
        return Track(
            url: url, fileName: url.lastPathComponent,
            title: title, artist: artist, albumArtist: nil,
            album: album, year: year, duration: duration,
            trackNumber: trackNumber, genre: genre,
            albumArtURL: nil,
            replayGain: nil, replayGainPeak: nil,
            replayGainAlbum: nil, replayGainAlbumPeak: nil,
            lyricsURL: nil, unsyncedLyrics: nil
        )
    }
    
    // MARK: - Уровень 3: AVAsset (один раз, всё сразу)
    
    private static func readFullMetadata(from url: URL) async -> Track? {
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
        var duration: TimeInterval = 0
        var replayGain: Float?
        var replayGainPeak: Float?
        var replayGainAlbum: Float?
        var replayGainAlbumPeak: Float?
        var unsyncedLyrics: String?
        var albumArtData: Data?
        
        let asset = AVAsset(url: url)

        // ← ДОБАВИТЬ ЭТОТ БЛОК:
        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isFinite ? cmDuration.seconds : 0
        } catch {}
        guard duration > 0 else { return nil }
        
        
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                // 🔍 ОТЛАДКА
                if let identifier = item.identifier?.rawValue {
                    let lower = identifier.lowercased()
                    if lower.contains("date") || lower.contains("year") {
                        let val = (try? await item.load(.stringValue)) ?? "nil"
                    }
                }
                
                if let commonKey = item.commonKey {
                    switch commonKey {
                    case .commonKeyTitle: title = (try? await item.load(.stringValue)) ?? title
                    case .commonKeyArtist: artist = (try? await item.load(.stringValue)) ?? artist
                    case .commonKeyAlbumName: album = (try? await item.load(.stringValue)) ?? album
                    case .commonKeyArtwork:
                        albumArtData = try? await item.load(.dataValue)
                    case .commonKeyCreationDate:
                        if let date = try? await item.load(.dateValue) {
                            year = Calendar.current.dateComponents([.year], from: date).year
                        }
                    case .commonKeyType: genre = (try? await item.load(.stringValue)) ?? genre
                    default: break
                    }
                    continue
                }
                
                guard let identifier = item.identifier?.rawValue else { continue }
                let value = (try? await item.load(.stringValue)) ?? ""
                
                switch identifier {
                case "itsk/aART", "vorb/ALBUMARTIST", "id3/TPE2":
                    if albumArtist == nil, !value.isEmpty { albumArtist = value }
                    
                case "itlk/com.apple.iTunes.replaygain_track_gain", "vorb/REPLAYGAIN_TRACK_GAIN":
                    if replayGain == nil, let v = parseRGValue(value) { replayGain = v }
                case "itlk/com.apple.iTunes.replaygain_track_peak", "vorb/REPLAYGAIN_TRACK_PEAK":
                    if replayGainPeak == nil { replayGainPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                    
                case "itlk/com.apple.iTunes.replaygain_album_gain", "vorb/REPLAYGAIN_ALBUM_GAIN":
                    if replayGainAlbum == nil, let v = parseRGValue(value) { replayGainAlbum = v }
                case "itlk/com.apple.iTunes.replaygain_album_peak", "vorb/REPLAYGAIN_ALBUM_PEAK":
                    if replayGainAlbumPeak == nil { replayGainAlbumPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                    
                case "itsk/%A9lyr", "vorb/LYRICS", "vorb/UNSYNCEDLYRICS", "id3/USLT":
                    if unsyncedLyrics == nil, !value.isEmpty { unsyncedLyrics = value }
                    
                case "itsk/%A9day", "vorb/DATE", "id3/TYER", "id3/TDRC":
                    if year == nil, let y = Int(value.prefix(4)) { year = y }
                case "itsk/%A9gen", "vorb/GENRE", "id3/TCON":
                    if genre == nil { genre = value.replacingOccurrences(of: #"\(\d+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
                case "vorb/TRACKNUMBER", "id3/TRCK":
                    if trackNumber == nil { trackNumber = Int(value.components(separatedBy: "/").first ?? "0") }
                    
                default: break
                }
            }
        } catch {}
        
        if replayGain == nil && replayGainAlbum == nil {
            let result = readReplayGainFromID3(url: url)
            replayGain = result.gain
            replayGainPeak = result.peak
            replayGainAlbum = result.albumGain
            replayGainAlbumPeak = result.albumPeak
        }
        
        let lyricsURL = LyricsParser.findLyrics(for: url)
        let artURL: URL? = albumArtData.flatMap { saveArtworkFromData($0, for: url) }
        
        return Track(
            url: url, fileName: url.lastPathComponent,
            title: title, artist: artist, albumArtist: albumArtist,
            album: album, year: year, duration: duration,
            trackNumber: trackNumber, genre: genre,
            albumArtURL: artURL,
            replayGain: replayGain, replayGainPeak: replayGainPeak,
            replayGainAlbum: replayGainAlbum, replayGainAlbumPeak: replayGainAlbumPeak,
            lyricsURL: lyricsURL, unsyncedLyrics: unsyncedLyrics
        )
    }
    
    // MARK: - Сохранение обложки из Data
    
    private static func saveArtworkFromData(_ data: Data, for url: URL) -> URL? {
        let cacheDir = ImageCache.cacheDirectory()
        let pathData = url.path.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: pathData).compactMap { String(format: "%02x", $0) }.joined()
        
        let fullDir = cacheDir.appendingPathComponent("full")
        try? FileManager.default.createDirectory(at: fullDir, withIntermediateDirectories: true)
        let artFile = fullDir.appendingPathComponent("melodica_art_\(hash.prefix(16)).jpg")
        
        if !FileManager.default.fileExists(atPath: artFile.path) {
            if let image = NSImage(data: data),
               let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? jpegData.write(to: artFile)
            } else {
                try? data.write(to: artFile)
            }
        }
        return artFile
    }
    
    // MARK: - ID3 Parser (MP3)
    
    private static func readReplayGainFromID3(url: URL) -> (gain: Float?, peak: Float?, albumGain: Float?, albumPeak: Float?) {
        var gain: Float?
        var peak: Float?
        var albumGain: Float?
        var albumPeak: Float?
        
        guard let fileID = fopen(url.path, "r") else { return (nil, nil, nil, nil) }
        defer { fclose(fileID) }
        
        fseek(fileID, 0, SEEK_SET)
        var header: [UInt8] = Array(repeating: 0, count: 10)
        fread(&header, 1, 10, fileID)
        
        if header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 {
            let tagSize = (Int(header[6]) << 21) | (Int(header[7]) << 14) | (Int(header[8]) << 7) | Int(header[9])
            var tagData: [UInt8] = Array(repeating: 0, count: tagSize)
            fseek(fileID, 10, SEEK_SET)
            fread(&tagData, 1, tagSize, fileID)
            
            var offset = 0
            while offset < tagSize - 10 {
                let frameID = String(bytes: tagData[offset..<offset+4], encoding: .isoLatin1) ?? ""
                var frameSize: Int
                if tagData[offset+4] & 0x80 == 0 {
                    frameSize = (Int(tagData[offset+4] & 0x7F) << 21) | (Int(tagData[offset+5]) << 14) | (Int(tagData[offset+6]) << 7) | Int(tagData[offset+7])
                } else {
                    frameSize = (Int(tagData[offset+4]) << 24) | (Int(tagData[offset+5]) << 16) | (Int(tagData[offset+6]) << 8) | Int(tagData[offset+7])
                }
                if frameSize <= 0 || offset + 10 + frameSize > tagSize { break }
                
                if frameID == "TXXX" && frameSize > 3 {
                    let frameData = Array(tagData[offset+10..<offset+10+frameSize])
                    if let descEnd = frameData[1...].firstIndex(of: 0) {
                        let valStart = descEnd + 1
                        if valStart < frameData.count {
                            let descData = frameData[1..<descEnd]
                            let valData = frameData[valStart...]
                            let description = String(bytes: descData, encoding: .utf8) ?? String(bytes: descData, encoding: .isoLatin1) ?? ""
                            let value = String(bytes: valData, encoding: .utf8) ?? String(bytes: valData, encoding: .isoLatin1) ?? ""
                            if description.uppercased().contains("REPLAYGAIN_TRACK_GAIN") { gain = parseRGValue(value) }
                            if description.uppercased().contains("REPLAYGAIN_TRACK_PEAK") { peak = Float(value.trimmingCharacters(in: .whitespaces)) }
                            if description.uppercased().contains("REPLAYGAIN_ALBUM_GAIN") { albumGain = parseRGValue(value) }
                            if description.uppercased().contains("REPLAYGAIN_ALBUM_PEAK") { albumPeak = Float(value.trimmingCharacters(in: .whitespaces)) }
                        }
                    }
                }
                offset += 10 + frameSize
            }
        }
        return (gain, peak, albumGain, albumPeak)
    }
    
    // MARK: - Helpers
    
    private static func parseRGValue(_ str: String) -> Float? {
        var cleaned = str
            .replacingOccurrences(of: "REPLAYGAIN_TRACK_GAIN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "REPLAYGAIN_ALBUM_GAIN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "REPLAYGAIN TRACK GAIN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "REPLAYGAIN ALBUM GAIN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " dB", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Float(cleaned)
    }
}
