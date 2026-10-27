import Foundation

nonisolated enum LossyCodec: String {
    case mp3
    case aac          // AAC-LC, без SBR (пока не отличаем)
    case alac         // lossless в m4a контейнере
    case vorbis
    case opus
    case unknown
}

nonisolated enum LossyCodecDetector {

    /// Определяет кодек по контейнеру и магическим байтам.
    /// Расширение — только fallback, решение принимается по содержимому.
    /// Это важно: Opus часто лежит в .ogg, AAC — в .m4a или .aac.
    nonisolated static func detect(url: URL) -> LossyCodec {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 4096), head.count >= 4 else { return .unknown }

        // Ogg контейнер: "OggS"
        if head[0] == 0x4F, head[1] == 0x67, head[2] == 0x67, head[3] == 0x53 {
            return detectOggCodec(head)
        }

        // MP4 / M4A: "ftyp" на смещении 4
        if head.count >= 12,
           head[4] == 0x66, head[5] == 0x74, head[6] == 0x79, head[7] == 0x70 {
            return detectMP4Codec(first: head, fh: fh)
        }

        // MP3: ID3v2 tag или прямой frame sync
        if head.count >= 3, head[0] == 0x49, head[1] == 0x44, head[2] == 0x33 {
            return .mp3
        }
        if head[0] == 0xFF, (head[1] & 0xE0) == 0xE0 {
            return .mp3
        }

        // Fallback по расширению
        switch url.pathExtension.lowercased() {
        case "mp3", "mp2": return .mp3
        case "ogg", "oga": return .vorbis
        case "opus":       return .opus
        case "m4a", "mp4", "aac": return .aac
        default:           return .unknown
        }
    }

    /// Внутри Ogg-контейнера различаем Opus и Vorbis по строке
    /// идентификации. "OpusHead" — Opus, "\x01vorbis" — Vorbis.
    private nonisolated static func detectOggCodec(_ data: Data) -> LossyCodec {
        let scan = data.prefix(512)
        if scan.range(of: Data("OpusHead".utf8)) != nil { return .opus }
        if scan.range(of: Data("vorbis".utf8)) != nil { return .vorbis }
        return .unknown
    }

    /// Внутри MP4-контейнера ищем кодек-четырёхбуквенник.
    /// "mp4a" — AAC, "alac" — ALAC. Пробуем прочитать первые ~40 КБ,
    /// потому что moov-атом бывает и в начале (faststart), и в конце.
    private nonisolated static func detectMP4Codec(first: Data, fh: FileHandle) -> LossyCodec {
        var combined = first
        if let more = try? fh.read(upToCount: 36864) {
            combined.append(more)
        }
        if combined.range(of: Data("alac".utf8)) != nil { return .alac }
        if combined.range(of: Data("mp4a".utf8)) != nil { return .aac }
        // По умолчанию m4a = AAC
        return .aac
    }
}
