// Services,MetadataWriter+Tags.swift
import Foundation
import AVFoundation
import AppKit

public nonisolated enum CoverFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG"
    case png = "PNG"
    public var id: String { rawValue }
    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        }
    }
}

public nonisolated enum ID3TargetVersion: String, CaseIterable, Identifiable, Sendable {
    case v2_3 = "v2.3"
    case v2_4 = "v2.4"
    public var id: String { rawValue }
    public var majorVersion: UInt8 {
        switch self {
        case .v2_3: return 3
        case .v2_4: return 4
        }
    }
}

public nonisolated struct TrackTags: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var year: String
    public var genre: String
    public var trackNumber: String
    public var coverData: Data?
    public var coverMimeType: String?
    public var id3Version: ID3TargetVersion?
    public var isMP3: Bool

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        year: String = "",
        genre: String = "",
        trackNumber: String = "",
        coverData: Data? = nil,
        coverMimeType: String? = nil,
        id3Version: ID3TargetVersion? = nil,
        isMP3: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.trackNumber = trackNumber
        self.coverData = coverData
        self.coverMimeType = coverMimeType
        self.id3Version = id3Version
        self.isMP3 = isMP3
    }
}

public nonisolated enum CoverModification: Sendable {
    case keep
    case remove
    case replace(data: Data, format: CoverFormat, maxDimension: Int?)
}

public nonisolated struct TagEditPayload: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var year: String
    public var genre: String
    public var trackNumber: String
    public var coverChange: CoverModification
    public var targetID3Version: ID3TargetVersion?

    public init(
        title: String,
        artist: String,
        album: String,
        albumArtist: String,
        year: String,
        genre: String,
        trackNumber: String,
        coverChange: CoverModification = .keep,
        targetID3Version: ID3TargetVersion? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.trackNumber = trackNumber
        self.coverChange = coverChange
        self.targetID3Version = targetID3Version
    }
}

extension MetadataWriter {

    // MARK: - Image Processing

    public nonisolated static func processCoverImage(
        data: Data,
        format: CoverFormat,
        maxDimension: Int?
    ) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        var targetSize = image.size
        if let maxDim = maxDimension, maxDim > 0 {
            let maxSide = max(image.size.width, image.size.height)
            if maxSide > CGFloat(maxDim) {
                let scale = CGFloat(maxDim) / maxSide
                targetSize = CGSize(width: round(image.size.width * scale), height: round(image.size.height * scale))
            }
        }

        let pixelWidth = Int(max(1, targetSize.width))
        let pixelHeight = Int(max(1, targetSize.height))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        image.draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        switch format {
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        case .png:
            return rep.representation(using: .png, properties: [:])
        }
    }

    // MARK: - ID3 Helpers

    nonisolated static func decodeID3Text(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        let encoding = data[0]
        let textData = data.dropFirst()
        var result: String?
        switch encoding {
        case 0:
            result = String(data: textData, encoding: .isoLatin1)
        case 1:
            result = String(data: textData, encoding: .utf16)
        case 2:
            result = String(data: textData, encoding: .utf16BigEndian)
        case 3:
            result = String(data: textData, encoding: .utf8)
        default:
            result = String(data: textData, encoding: .utf8) ?? String(data: textData, encoding: .isoLatin1)
        }
        return result?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n")) ?? ""
    }

    nonisolated static func encodeID3Text(_ text: String, majorVersion: UInt8) -> Data {
        var out = Data()
        if majorVersion >= 4 {
            out.append(0x03) // UTF-8
            out.append(contentsOf: text.utf8)
        } else {
            out.append(0x01) // UTF-16 with BOM
            out.append(contentsOf: [0xFF, 0xFE]) // Little-endian BOM
            if let utf16Data = text.data(using: .utf16LittleEndian) {
                out.append(utf16Data)
            }
        }
        return out
    }

    nonisolated static func parseAPICFrame(_ data: Data) -> (mime: String, imageData: Data)? {
        guard data.count > 4 else { return nil }
        let encoding = data[0]
        var offset = 1
        guard let nullIdx = data[offset...].firstIndex(of: 0) else { return nil }
        let mime = String(data: data.subdata(in: offset..<nullIdx), encoding: .isoLatin1) ?? "image/jpeg"
        offset = nullIdx + 1
        guard offset < data.count else { return nil }
        offset += 1 // Picture type
        guard offset <= data.count else { return nil }
        // Skip description
        if encoding == 1 || encoding == 2 {
            var descEnd = offset
            while descEnd + 1 < data.count {
                if data[descEnd] == 0 && data[descEnd+1] == 0 {
                    descEnd += 2
                    break
                }
                descEnd += 2
            }
            offset = descEnd
        } else {
            if let dEnd = data[offset...].firstIndex(of: 0) {
                offset = dEnd + 1
            }
        }
        guard offset < data.count else { return nil }
        let picData = data.subdata(in: offset..<data.count)
        return (mime, picData)
    }

    nonisolated static func buildAPICBody(imageData: Data, mimeType: String) -> Data {
        var out = Data()
        out.append(0x00) // Latin-1
        if let m = mimeType.data(using: .isoLatin1) {
            out.append(m)
        } else {
            out.append(Data("image/jpeg".utf8))
        }
        out.append(0x00) // MIME null
        out.append(0x03) // Picture type: Cover (front)
        out.append(0x00) // Empty description null
        out.append(imageData)
        return out
    }

    // MARK: - FLAC Picture Block Helpers

    nonisolated static func buildFLACPictureBlock(
        imageData: Data,
        mimeType: String,
        width: Int = 0,
        height: Int = 0,
        depth: Int = 24
    ) -> Data {
        var out = Data()
        out.append(contentsOf: [0, 0, 0, 3]) // Type 3 Front cover

        let mimeData = mimeType.data(using: .ascii) ?? Data("image/jpeg".utf8)
        let mimeLen = UInt32(mimeData.count)
        out.append(contentsOf: [
            UInt8((mimeLen >> 24) & 0xFF),
            UInt8((mimeLen >> 16) & 0xFF),
            UInt8((mimeLen >> 8) & 0xFF),
            UInt8(mimeLen & 0xFF)
        ])
        out.append(mimeData)

        out.append(contentsOf: [0, 0, 0, 0]) // Desc length 0

        let w = UInt32(width)
        out.append(contentsOf: [UInt8((w >> 24) & 0xFF), UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF)])
        let h = UInt32(height)
        out.append(contentsOf: [UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF), UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF)])
        let d = UInt32(depth)
        out.append(contentsOf: [UInt8((d >> 24) & 0xFF), UInt8((d >> 16) & 0xFF), UInt8((d >> 8) & 0xFF), UInt8(d & 0xFF)])
        out.append(contentsOf: [0, 0, 0, 0]) // Colors

        let dataLen = UInt32(imageData.count)
        out.append(contentsOf: [
            UInt8((dataLen >> 24) & 0xFF),
            UInt8((dataLen >> 16) & 0xFF),
            UInt8((dataLen >> 8) & 0xFF),
            UInt8(dataLen & 0xFF)
        ])
        out.append(imageData)
        return out
    }

    nonisolated static func parseFLACPictureBlock(_ data: Data) -> (mime: String, imageData: Data)? {
        guard data.count >= 32 else { return nil }
        var offset = 4 // skip type
        let mimeLen = (Int(data[offset]) << 24) | (Int(data[offset+1]) << 16) | (Int(data[offset+2]) << 8) | Int(data[offset+3])
        offset += 4
        guard offset + mimeLen <= data.count else { return nil }
        let mime = String(data: data.subdata(in: offset..<(offset+mimeLen)), encoding: .ascii) ?? "image/jpeg"
        offset += mimeLen
        guard offset + 4 <= data.count else { return nil }
        let descLen = (Int(data[offset]) << 24) | (Int(data[offset+1]) << 16) | (Int(data[offset+2]) << 8) | Int(data[offset+3])
        offset += 4 + descLen
        guard offset + 16 <= data.count else { return nil }
        offset += 16
        guard offset + 4 <= data.count else { return nil }
        let picLen = (Int(data[offset]) << 24) | (Int(data[offset+1]) << 16) | (Int(data[offset+2]) << 8) | Int(data[offset+3])
        offset += 4
        guard offset + picLen <= data.count else { return nil }
        let picData = data.subdata(in: offset..<(offset+picLen))
        return (mime, picData)
    }

    // MARK: - Reading Tags

    public nonisolated static func readTags(from url: URL) async throws -> TrackTags {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp3":
            let data = try Data(contentsOf: url, options: .alwaysMapped)
            return try readMP3Tags(data: data)
        case "flac":
            let data = try Data(contentsOf: url, options: .alwaysMapped)
            return try readFLACTags(data: data)
        case "ogg", "opus":
            let data = try Data(contentsOf: url, options: .alwaysMapped)
            return try readOGGTags(data: data)
        case "m4a", "aac", "mp4":
            return try await readM4ATags(url: url)
        default:
            throw WriteError.unsupported(ext)
        }
    }

    nonisolated private static func readMP3Tags(data: Data) throws -> TrackTags {
        let info = try parseMP3Structure(data)
        var tags = TrackTags(isMP3: true)
        tags.id3Version = info.majorVersion >= 4 ? .v2_4 : .v2_3

        for frame in info.frames {
            switch frame.id {
            case "TIT2":
                tags.title = decodeID3Text(frame.data)
            case "TPE1":
                tags.artist = decodeID3Text(frame.data)
            case "TALB":
                tags.album = decodeID3Text(frame.data)
            case "TPE2":
                tags.albumArtist = decodeID3Text(frame.data)
            case "TYER", "TDRC":
                let text = decodeID3Text(frame.data)
                if !text.isEmpty {
                    tags.year = text
                }
            case "TCON":
                tags.genre = decodeID3Text(frame.data)
            case "TRCK":
                tags.trackNumber = decodeID3Text(frame.data)
            case "APIC":
                if tags.coverData == nil, let pic = parseAPICFrame(frame.data) {
                    tags.coverData = pic.imageData
                    tags.coverMimeType = pic.mime
                }
            default:
                break
            }
        }
        return tags
    }

    nonisolated private static func readFLACTags(data: Data) throws -> TrackTags {
        let info = try parseFLACStructure(data)
        var tags = TrackTags(isMP3: false)

        if let vcBlock = info.blocks.first(where: { $0.type == 4 }),
           let vc = parseVorbisComment(vcBlock.data) {
            applyVorbisComments(vc.comments, to: &tags)
        }

        if let picBlock = info.blocks.first(where: { $0.type == 6 }),
           let pic = parseFLACPictureBlock(picBlock.data) {
            tags.coverData = pic.imageData
            tags.coverMimeType = pic.mime
        }
        return tags
    }

    nonisolated private static func readOGGTags(data: Data) throws -> TrackTags {
        let pages = try parseOggPages(data, validateCRC: false)
        guard !pages.isEmpty else { return TrackTags(isMP3: false) }
        var tags = TrackTags(isMP3: false)

        let isOpus = pages[0].body.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3

        let headerEndPage = try findHeaderEndPage(pages: pages, targetCount: headerPacketCount)
        let allHeaderPackets = extractPackets(pages: pages, from: 0, to: headerEndPage)
        guard allHeaderPackets.count >= 2 else { return tags }

        let (comments, _, _) = try parseCommentPacket(allHeaderPackets[1], isOpus: isOpus)
        applyVorbisComments(comments, to: &tags)

        for c in comments {
            let u = c.uppercased()
            if u.hasPrefix("METADATA_BLOCK_PICTURE=") {
                let b64 = String(c.dropFirst("METADATA_BLOCK_PICTURE=".count))
                if let picData = Data(base64Encoded: b64),
                   let pic = parseFLACPictureBlock(picData) {
                    tags.coverData = pic.imageData
                    tags.coverMimeType = pic.mime
                    break
                }
            } else if u.hasPrefix("COVERART=") && tags.coverData == nil {
                let b64 = String(c.dropFirst("COVERART=".count))
                if let rawPic = Data(base64Encoded: b64) {
                    tags.coverData = rawPic
                    tags.coverMimeType = "image/jpeg"
                }
            }
        }
        return tags
    }

    nonisolated private static func applyVorbisComments(_ comments: [String], to tags: inout TrackTags) {
        for comment in comments {
            let parts = comment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let val = parts[1]
            switch key {
            case "TITLE":
                tags.title = val
            case "ARTIST":
                tags.artist = val
            case "ALBUM":
                tags.album = val
            case "ALBUMARTIST", "ALBUM ARTIST":
                tags.albumArtist = val
            case "DATE", "YEAR":
                if tags.year.isEmpty { tags.year = val }
            case "GENRE":
                tags.genre = val
            case "TRACKNUMBER", "TRACK":
                tags.trackNumber = val
            default:
                break
            }
        }
    }

    nonisolated private static func readM4ATags(url: URL) async throws -> TrackTags {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.metadata)
        var tags = TrackTags(isMP3: false)

        for item in metadata {
            let key = (item.key as? String)?.lowercased() ?? ""
            let id = item.identifier?.rawValue ?? ""

            if let commonKey = item.commonKey {
                switch commonKey {
                case .commonKeyTitle:
                    tags.title = (try? await item.load(.stringValue)) ?? tags.title
                case .commonKeyArtist:
                    tags.artist = (try? await item.load(.stringValue)) ?? tags.artist
                case .commonKeyAlbumName:
                    tags.album = (try? await item.load(.stringValue)) ?? tags.album
                case .commonKeyArtwork:
                    if let d = try? await item.load(.dataValue) {
                        tags.coverData = d
                        tags.coverMimeType = "image/jpeg"
                    }
                case .commonKeyType:
                    tags.genre = (try? await item.load(.stringValue)) ?? tags.genre
                default:
                    break
                }
            }

            if id == "itsk/aART" || id == "----:com.apple.iTunes:ALBUMARTIST" || key == "aart" {
                if let s = try? await item.load(.stringValue), !s.isEmpty {
                    tags.albumArtist = s
                }
            } else if id == "itsk/%A9day" || key == "©day" || key == "date" {
                if let s = try? await item.load(.stringValue), !s.isEmpty {
                    tags.year = s
                }
            } else if id == "itsk/trkn" || key == "trkn" {
                if let data = try? await item.load(.dataValue), data.count >= 6 {
                    let trk = (Int(data[4]) << 8) | Int(data[5])
                    if trk > 0 { tags.trackNumber = String(trk) }
                } else if let num = try? await item.load(.numberValue) {
                    tags.trackNumber = num.stringValue
                } else if let s = try? await item.load(.stringValue) {
                    tags.trackNumber = s
                }
            } else if id == "itsk/covr" || key == "covr" {
                if let d = try? await item.load(.dataValue) {
                    tags.coverData = d
                    tags.coverMimeType = "image/jpeg"
                }
            }
        }
        return tags
    }

    // MARK: - Writing Tags (Public Entry Point)

    public nonisolated static func writeTagsAsync(
        _ payload: TagEditPayload,
        to url: URL
    ) async -> Result<Void, Error> {
        let ext = url.pathExtension.lowercased()
        do {
            try await WriteSerializer.shared.enqueue {
                switch ext {
                case "mp3":
                    try writeMP3Tags(payload, to: url)
                case "flac":
                    try writeFLACTags(payload, to: url)
                case "ogg", "opus":
                    try writeOGGTags(payload, to: url)
                case "m4a", "aac", "mp4":
                    try await writeM4ATags(payload, to: url)
                default:
                    throw WriteError.unsupported(ext)
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - MP3 Tag Writer

    nonisolated private static func writeMP3Tags(_ payload: TagEditPayload, to url: URL) throws {
        let originalData = try Data(contentsOf: url, options: .alwaysMapped)
        let info = try parseMP3Structure(originalData)

        let targetMajor = payload.targetID3Version?.majorVersion ?? info.majorVersion

        let editedFrameIDs: Set<String> = [
            "TIT2", "TPE1", "TALB", "TPE2", "TYER", "TDRC", "TCON", "TRCK", "APIC"
        ]

        let preservedFrames = info.frames.filter { !editedFrameIDs.contains($0.id) }
        var newFrames: [(id: String, data: Data)] = []

        if !payload.title.isEmpty {
            newFrames.append(("TIT2", encodeID3Text(payload.title, majorVersion: targetMajor)))
        }
        if !payload.artist.isEmpty {
            newFrames.append(("TPE1", encodeID3Text(payload.artist, majorVersion: targetMajor)))
        }
        if !payload.album.isEmpty {
            newFrames.append(("TALB", encodeID3Text(payload.album, majorVersion: targetMajor)))
        }
        if !payload.albumArtist.isEmpty {
            newFrames.append(("TPE2", encodeID3Text(payload.albumArtist, majorVersion: targetMajor)))
        }
        if !payload.year.isEmpty {
            let yearId = targetMajor >= 4 ? "TDRC" : "TYER"
            newFrames.append((yearId, encodeID3Text(payload.year, majorVersion: targetMajor)))
        }
        if !payload.genre.isEmpty {
            newFrames.append(("TCON", encodeID3Text(payload.genre, majorVersion: targetMajor)))
        }
        if !payload.trackNumber.isEmpty {
            newFrames.append(("TRCK", encodeID3Text(payload.trackNumber, majorVersion: targetMajor)))
        }

        switch payload.coverChange {
        case .keep:
            if let existingAPIC = info.frames.first(where: { $0.id == "APIC" }) {
                newFrames.append(existingAPIC)
            }
        case .remove:
            break
        case .replace(let rawData, let format, let maxDim):
            if let processed = processCoverImage(data: rawData, format: format, maxDimension: maxDim) {
                let body = buildAPICBody(imageData: processed, mimeType: format.mimeType)
                newFrames.append(("APIC", body))
            }
        }

        let allFrames = preservedFrames + newFrames

        var framesData = Data()
        for frame in allFrames {
            guard let idData = frame.id.data(using: .isoLatin1), idData.count == 4 else { continue }
            framesData.append(idData)
            let size = frame.data.count
            if targetMajor >= 4 {
                framesData.append(contentsOf: [
                    UInt8((size >> 21) & 0x7F),
                    UInt8((size >> 14) & 0x7F),
                    UInt8((size >> 7) & 0x7F),
                    UInt8(size & 0x7F)
                ])
            } else {
                framesData.append(contentsOf: [
                    UInt8((size >> 24) & 0xFF),
                    UInt8((size >> 16) & 0xFF),
                    UInt8((size >> 8) & 0xFF),
                    UInt8(size & 0xFF)
                ])
            }
            framesData.append(contentsOf: [0, 0])
            framesData.append(frame.data)
        }

        framesData.append(Data(count: 128))

        var newTag = Data()
        newTag.append(contentsOf: [0x49, 0x44, 0x33])
        newTag.append(contentsOf: [targetMajor, 0])
        newTag.append(contentsOf: [0x00])
        let totalSize = framesData.count
        newTag.append(contentsOf: [
            UInt8((totalSize >> 21) & 0x7F),
            UInt8((totalSize >> 14) & 0x7F),
            UInt8((totalSize >> 7) & 0x7F),
            UInt8(totalSize & 0x7F)
        ])
        newTag.append(framesData)

        var resultData = Data()
        resultData.reserveCapacity(newTag.count + (originalData.count - info.audioStart))
        resultData.append(newTag)
        resultData.append(originalData[info.audioStart...])

        try safeWrite(
            resultData,
            originalData: originalData,
            to: url,
            basicValidator: validateMP3,
            deepVerifier: { orig, updated in
                try verifyMP3Rewrite(original: orig, updated: updated, ignoredFrameIDs: editedFrameIDs)
            }
        )
    }

    // MARK: - FLAC Tag Writer

    nonisolated private static func writeFLACTags(_ payload: TagEditPayload, to url: URL) throws {
        let originalData = try Data(contentsOf: url, options: .alwaysMapped)
        let info = try parseFLACStructure(originalData)

        guard let vcBlock = info.blocks.first(where: { $0.type == 4 }),
              let origVC = parseVorbisComment(vcBlock.data) else {
            throw WriteError.corrupted("FLAC не содержит Vorbis Comment блока")
        }

        let editedKeys: Set<String> = [
            "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "ALBUM ARTIST", "DATE", "YEAR", "GENRE", "TRACKNUMBER", "TRACK"
        ]

        var newComments = origVC.comments.filter { comment in
            let key = comment.split(separator: "=", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
            return !editedKeys.contains(key)
        }

        if !payload.title.isEmpty { newComments.append("TITLE=\(payload.title)") }
        if !payload.artist.isEmpty { newComments.append("ARTIST=\(payload.artist)") }
        if !payload.album.isEmpty { newComments.append("ALBUM=\(payload.album)") }
        if !payload.albumArtist.isEmpty { newComments.append("ALBUMARTIST=\(payload.albumArtist)") }
        if !payload.year.isEmpty { newComments.append("DATE=\(payload.year)") }
        if !payload.genre.isEmpty { newComments.append("GENRE=\(payload.genre)") }
        if !payload.trackNumber.isEmpty { newComments.append("TRACKNUMBER=\(payload.trackNumber)") }

        let newVCData = buildVorbisComment(vendor: origVC.vendor, comments: newComments)

        var newBlocks: [(type: UInt8, data: Data)] = []
        var coverEdited = false
        var newPictureData: Data?

        switch payload.coverChange {
        case .keep:
            break
        case .remove:
            coverEdited = true
        case .replace(let rawData, let format, let maxDim):
            coverEdited = true
            if let processed = processCoverImage(data: rawData, format: format, maxDimension: maxDim) {
                newPictureData = buildFLACPictureBlock(imageData: processed, mimeType: format.mimeType)
            }
        }

        var pictureHandled = false
        for block in info.blocks {
            if block.type == 4 {
                newBlocks.append((type: 4, data: newVCData))
            } else if block.type == 6 {
                switch payload.coverChange {
                case .keep:
                    newBlocks.append((type: 6, data: block.data))
                case .remove:
                    break
                case .replace:
                    if !pictureHandled, let picData = newPictureData {
                        newBlocks.append((type: 6, data: picData))
                        pictureHandled = true
                    }
                }
            } else {
                newBlocks.append((type: block.type, data: block.data))
            }
        }

        if case .replace = payload.coverChange, !pictureHandled, let picData = newPictureData {
            if let padIndex = newBlocks.lastIndex(where: { $0.type == 1 }) {
                newBlocks.insert((type: 6, data: picData), at: padIndex)
            } else {
                newBlocks.append((type: 6, data: picData))
            }
        }

        var resultData = Data()
        resultData.append(contentsOf: [0x66, 0x4C, 0x61, 0x43])

        for (index, block) in newBlocks.enumerated() {
            let isLast = index == newBlocks.count - 1
            let typeByte = (isLast ? 0x80 : 0x00) | (block.type & 0x7F)
            let len = block.data.count
            resultData.append(contentsOf: [
                typeByte,
                UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF),
                UInt8(len & 0xFF)
            ])
            resultData.append(block.data)
        }

        resultData.append(originalData[info.audioStart...])

        try safeWrite(
            resultData,
            originalData: originalData,
            to: url,
            basicValidator: validateFLAC,
            deepVerifier: { orig, updated in
                try verifyFLACRewrite(
                    original: orig,
                    updated: updated,
                    ignoredCommentKeys: editedKeys,
                    coverEdited: coverEdited
                )
            }
        )
    }

    // MARK: - OGG / Opus Tag Writer

    nonisolated private static func writeOGGTags(_ payload: TagEditPayload, to url: URL) throws {
        let originalData = try Data(contentsOf: url, options: .alwaysMapped)
        guard validateOGG(originalData) else { throw WriteError.notFormat("Ogg") }

        let origPages = try parseOggPages(originalData, validateCRC: false)
        guard !origPages.isEmpty else {
            throw WriteError.corrupted("Ogg: не найдено ни одной страницы")
        }

        let firstBody = origPages[0].body
        let isOpus = firstBody.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3

        let headerEndPage = try findHeaderEndPage(pages: origPages, targetCount: headerPacketCount)
        let allHeaderPackets = extractPackets(pages: origPages, from: 0, to: headerEndPage)
        guard allHeaderPackets.count >= headerPacketCount else {
            throw WriteError.corrupted("Ogg: не найдены header-пакеты")
        }

        let (comments, vendor, prefix) = try parseCommentPacket(allHeaderPackets[1], isOpus: isOpus)

        let editedKeys: Set<String> = [
            "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "ALBUM ARTIST", "DATE", "YEAR", "GENRE", "TRACKNUMBER", "TRACK",
            "METADATA_BLOCK_PICTURE", "COVERART"
        ]

        var newComments = comments.filter { c in
            let key = c.split(separator: "=", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
            return !editedKeys.contains(key)
        }

        if !payload.title.isEmpty { newComments.append("TITLE=\(payload.title)") }
        if !payload.artist.isEmpty { newComments.append("ARTIST=\(payload.artist)") }
        if !payload.album.isEmpty { newComments.append("ALBUM=\(payload.album)") }
        if !payload.albumArtist.isEmpty { newComments.append("ALBUMARTIST=\(payload.albumArtist)") }
        if !payload.year.isEmpty { newComments.append("DATE=\(payload.year)") }
        if !payload.genre.isEmpty { newComments.append("GENRE=\(payload.genre)") }
        if !payload.trackNumber.isEmpty { newComments.append("TRACKNUMBER=\(payload.trackNumber)") }

        switch payload.coverChange {
        case .keep:
            for c in comments {
                let u = c.uppercased()
                if u.hasPrefix("METADATA_BLOCK_PICTURE=") || u.hasPrefix("COVERART=") {
                    newComments.append(c)
                }
            }
        case .remove:
            break
        case .replace(let rawData, let format, let maxDim):
            if let processed = processCoverImage(data: rawData, format: format, maxDimension: maxDim) {
                let flacPic = buildFLACPictureBlock(imageData: processed, mimeType: format.mimeType)
                let b64 = flacPic.base64EncodedString()
                newComments.append("METADATA_BLOCK_PICTURE=\(b64)")
                newComments.append("COVERART=\(processed.base64EncodedString())")
            }
        }

        let newCommentPacket = buildCommentPacket(
            prefix: prefix,
            vendor: vendor,
            comments: newComments,
            isOpus: isOpus
        )

        var newHeaderPackets = allHeaderPackets
        newHeaderPackets[1] = newCommentPacket

        let serial = origPages[0].serial
        let bosFlag: UInt8 = (origPages[0].headerType & 0x02)
        let newHeaderPages = buildOggHeaderPages(
            packets: newHeaderPackets,
            startingSequence: 0,
            serial: serial,
            bosFlag: bosFlag
        )

        var resultData = Data()
        for p in newHeaderPages {
            resultData.append(p)
        }

        var nextSeq = UInt32(newHeaderPages.count)
        if headerEndPage + 1 < origPages.count {
            for i in (headerEndPage + 1)..<origPages.count {
                let oldPage = origPages[i]
                let rebuilt = buildOggPageRaw(
                    headerType: oldPage.headerType,
                    granule: oldPage.granule,
                    serial: oldPage.serial,
                    sequence: nextSeq,
                    lacing: oldPage.lacing,
                    body: oldPage.body
                )
                resultData.append(rebuilt)
                nextSeq += 1
            }
        }

        try safeWrite(
            resultData,
            originalData: originalData,
            to: url,
            basicValidator: validateOGG,
            deepVerifier: { orig, updated in
                try verifyOGGRewrite(original: orig, updated: updated, ignoredCommentKeys: editedKeys)
            }
        )
    }

    // MARK: - M4A Tag Writer

    nonisolated private static func writeM4ATags(_ payload: TagEditPayload, to url: URL) async throws {
        let originalData = try Data(contentsOf: url, options: .alwaysMapped)
        let asset = AVURLAsset(url: url)
        let existingItems = try await asset.load(.metadata)

        let editedM4AKeys: Set<String> = [
            "©nam", "©art", "©alb", "aart", "©day", "©gen", "trkn", "covr",
            "title", "artist", "album", "albumartist", "album artist", "date", "year", "genre", "tracknumber", "track",
            "itsk/%a9nam", "itsk/%a9art", "itsk/%a9alb", "itsk/aart", "itsk/%a9day", "itsk/%a9gen", "itsk/trkn", "itsk/covr",
            "itsk/©nam", "itsk/©art", "itsk/©alb", "itsk/©day", "itsk/©gen",
            "itsk/yr", "itsk/com.apple.itunes.year", "itsk/gnre",
            "----:com.apple.itunes:albumartist", "itsk/----:com.apple.itunes:albumartist",
            "itsk/track", "itsk/tracknumber",
            "common/title", "common/artist", "common/albumname", "common/type", "common/creationdate", "common/artwork",
            "mdta/com.apple.quicktime.title", "mdta/com.apple.quicktime.artist", "mdta/com.apple.quicktime.album",
            "mdta/com.apple.quicktime.creationdate", "mdta/com.apple.quicktime.genre",
            "udta/©nam", "udta/©art", "udta/©alb", "udta/aart", "udta/©day", "udta/©gen", "udta/trkn", "udta/covr"
        ]

        var newItems: [AVMetadataItem] = []
        for item in existingItems {
            let key = (item.key as? String)?.lowercased() ?? ""
            let id = item.identifier?.rawValue.lowercased() ?? ""
            if editedM4AKeys.contains(key) || editedM4AKeys.contains(id) {
                continue
            }
            if let commonKey = item.commonKey {
                switch commonKey {
                case .commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName, .commonKeyArtwork, .commonKeyType:
                    continue
                default:
                    break
                }
            }
            if let copy = item.mutableCopy() as? AVMutableMetadataItem {
                newItems.append(copy)
            }
        }

        func makeItem(key: String, value: String) -> AVMutableMetadataItem {
            let item = AVMutableMetadataItem()
            item.keySpace = .iTunes
            item.key = key as NSString
            if let ident = AVMetadataItem.identifier(forKey: key as NSString, keySpace: .iTunes) {
                item.identifier = ident
            }
            item.value = value as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.extendedLanguageTag = "und"
            return item
        }

        if !payload.title.isEmpty {
            newItems.append(makeItem(key: "©nam", value: payload.title))
        }
        if !payload.artist.isEmpty {
            newItems.append(makeItem(key: "©ART", value: payload.artist))
        }
        if !payload.album.isEmpty {
            newItems.append(makeItem(key: "©alb", value: payload.album))
        }
        if !payload.albumArtist.isEmpty {
            newItems.append(makeItem(key: "aART", value: payload.albumArtist))
        }
        if !payload.year.isEmpty {
            newItems.append(makeItem(key: "©day", value: payload.year))
        }
        if !payload.genre.isEmpty {
            newItems.append(makeItem(key: "©gen", value: payload.genre))
        }
        if !payload.trackNumber.isEmpty {
            let trkStr = payload.trackNumber.split(separator: "/").first.map(String.init) ?? payload.trackNumber
            if let trk = Int(trkStr.trimmingCharacters(in: .whitespaces)) {
                let item = AVMutableMetadataItem()
                item.keySpace = .iTunes
                item.key = "trkn" as NSString
                item.identifier = .iTunesMetadataTrackNumber
                var trknBytes = [UInt8](repeating: 0, count: 8)
                trknBytes[4] = UInt8((trk >> 8) & 0xFF)
                trknBytes[5] = UInt8(trk & 0xFF)
                if let totalPart = payload.trackNumber.split(separator: "/").dropFirst().first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                    trknBytes[6] = UInt8((totalPart >> 8) & 0xFF)
                    trknBytes[7] = UInt8(totalPart & 0xFF)
                }
                item.value = Data(trknBytes) as NSData
                item.dataType = kCMMetadataBaseDataType_RawData as String
                newItems.append(item)
            }
        }

        switch payload.coverChange {
        case .keep:
            for item in existingItems {
                let key = (item.key as? String)?.lowercased() ?? ""
                let id = item.identifier?.rawValue.lowercased() ?? ""
                if key == "covr" || id == "itsk/covr" || item.commonKey == .commonKeyArtwork {
                    if let copy = item.mutableCopy() as? AVMutableMetadataItem {
                        newItems.append(copy)
                    }
                }
            }
        case .remove:
            break
        case .replace(let rawData, let format, let maxDim):
            if let processed = processCoverImage(data: rawData, format: format, maxDimension: maxDim) {
                let item = AVMutableMetadataItem()
                item.keySpace = .iTunes
                item.key = "covr" as NSString
                item.identifier = .iTunesMetadataCoverArt
                item.value = processed as NSData
                item.dataType = (format == .png ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String
                newItems.append(item)
            }
        }

        let temp = tempURL(for: url).deletingPathExtension().appendingPathExtension("m4a")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw WriteError.io("не удалось создать AVAssetExportSession")
        }

        exportSession.metadata = newItems
        exportSession.shouldOptimizeForNetworkUse = false

        do {
            try await exportSession.export(to: temp, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }

        let updatedData = try Data(contentsOf: temp)
        let newAsset = AVURLAsset(url: temp)
        let newMetadata = try await newAsset.load(.metadata)

        do {
            try await verifyM4ARewrite(
                originalData: originalData,
                updatedData: updatedData,
                originalItems: existingItems,
                updatedItems: newMetadata,
                ignoredKeys: editedM4AKeys
            )
        } catch {
            try? FileManager.default.removeItem(at: temp)
            if let we = error as? WriteError { throw we }
            throw WriteError.verificationFailed(error.localizedDescription)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: temp.path)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw WriteError.io("не удалось заменить M4A: \(error.localizedDescription)")
        }
    }
}
