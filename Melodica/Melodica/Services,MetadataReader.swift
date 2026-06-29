// Services,MetadataReader.swift
import AVFoundation
import AppKit
import AudioToolbox
import CryptoKit

enum MetadataReader {
    
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
        var albumArt: NSImage?
        var replayGain: Float?
        var duration: TimeInterval = 0
        var unsyncedLyrics: String?
        
        let asset = AVAsset(url: url)
        
        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isFinite ? cmDuration.seconds : 0
        } catch { duration = 0 }
        
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
                        if let data = try? await item.load(.dataValue) {
                            albumArt = NSImage(data: data)
                        }
                    case .commonKeyCreationDate:
                        if let date = try? await item.load(.dateValue) {
                            year = Calendar.current.dateComponents([.year], from: date).year
                        }
                    case .commonKeyType:
                        genre = (try? await item.load(.stringValue)) ?? genre
                    default: break
                    }
                }
                
                if let keyString = item.key as? String {
                    let upperKey = keyString.uppercased().trimmingCharacters(in: .whitespaces)
                    let value = (try? await item.load(.stringValue)) ?? ""
                    
                    if upperKey == "TRCK" || upperKey == "TRACKNUMBER" {
                        trackNumber = Int(value.components(separatedBy: "/").first ?? "0")
                    }
                    
                    if upperKey == "TYER" || upperKey == "YEAR" || upperKey == "TDRC" || upperKey == "DATE" {
                        if let y = Int(value.prefix(4)) { year = y }
                    }
                    
                    if upperKey == "TCON" || upperKey == "GENRE" {
                        let cleaned = value.replacingOccurrences(of: #"\(\d+\)"#, with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespaces)
                        if !cleaned.isEmpty { genre = cleaned }
                    }
                    
                    if upperKey == "USLT" || upperKey == "LYRICS" || upperKey == "UNSYNCEDLYRICS" || upperKey == "UNSYNCED LYRICS" {
                        if !value.isEmpty { unsyncedLyrics = value }
                    }
                    
                    if upperKey == "TPE2" || upperKey == "ALBUMARTIST" || upperKey == "ALBUM ARTIST" {
                        if !value.isEmpty { albumArtist = value }
                    }
                    
                    if upperKey == "REPLAYGAIN_TRACK_GAIN" {
                        if let v = parseRGValue(value) { replayGain = v }
                    }
                    
                    if upperKey == "TXXX" && value.uppercased().contains("REPLAYGAIN_TRACK_GAIN") {
                        if let v = parseRGValue(value) { replayGain = v }
                    }
                }
            }
        } catch {
            print("Metadata error: \(error)")
        }
        
        if replayGain == nil {
            replayGain = readReplayGainFromID3(url: url)
        }
        
        // JPEG 80% качества с SHA256-хешем
        var albumArtURL: URL? = nil
        if let art = albumArt {
            let tempDir = FileManager.default.temporaryDirectory
            let pathData = url.path.data(using: .utf8) ?? Data()
            let hash = SHA256.hash(data: pathData).compactMap { String(format: "%02x", $0) }.joined()
            let artFile = tempDir.appendingPathComponent("melodica_art_\(hash.prefix(16)).jpg")
            
            if !FileManager.default.fileExists(atPath: artFile.path) {
                if let tiffData = art.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                    do {
                        try jpegData.write(to: artFile)
                    } catch {
                        print("Error saving album art: \(error)")
                    }
                }
            }
            albumArtURL = artFile
        }
        
        let lyricsURL = LyricsParser.findLyrics(for: url)
        
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
            albumArtURL: albumArtURL,
            replayGain: replayGain,
            lyricsURL: lyricsURL,
            unsyncedLyrics: unsyncedLyrics
        )
    }
    
    private static func readReplayGainFromID3(url: URL) -> Float? {
        guard let fileID = fopen(url.path, "r") else { return nil }
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
                            
                            if description.uppercased().contains("REPLAYGAIN_TRACK_GAIN") {
                                if let v = parseRGValue(value) { return v }
                            }
                        }
                    }
                }
                
                offset += 10 + frameSize
            }
        }
        
        return nil
    }
    
    private static func parseRGValue(_ str: String) -> Float? {
        var cleaned = str
            .replacingOccurrences(of: "REPLAYGAIN_TRACK_GAIN", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "REPLAYGAIN TRACK GAIN", with: "", options: .caseInsensitive)
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
