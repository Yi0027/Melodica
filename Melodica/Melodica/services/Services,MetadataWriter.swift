// Services,MetadataWriter.swift
import Foundation
import AVFoundation

// MARK: - Ogg Page model

private struct OggPage {
    let rawData: Data
    let headerType: UInt8
    let granule: UInt64
    let serial: UInt32
    let sequence: UInt32
    let lacing: [UInt8]
    let body: Data
}

enum MetadataWriter {

    // MARK: - Write Serializer

    /// Сериализует все записи: три быстрых клика по звёздам не пишут файл одновременно.
    private actor WriteSerializer {
        static let shared = WriteSerializer()
        private var tail: Task<Void, Never>?

        func enqueue<T>(_ block: @escaping () async -> T) async -> T {
            let prev = tail
            let task = Task<T, Never> {
                await prev?.value
                return await block()
            }
            tail = Task { _ = await task.value }
            return await task.value
        }
    }

    // MARK: - Temp folder & cleanup

    static var tmpFolderURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
            .appendingPathComponent("tmp")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Удаляет все файлы в tmp-папке (вызывать при старте приложения).
    /// Удаляет мусор из временных папок.
    /// - Своя `Melodica/tmp` — чистится полностью.
    /// - Переданные `extraFolders` (watched-папки) — только файлы `.melodica_tmp_*` в корне.
    /// Выполняется в фоне, не блокирует UI.
    static func cleanupTmpFolder(extraFolders: [URL] = []) {
        Task.detached(priority: .background) {
            // 1. Своя папка — целиком
            cleanDirectory(tmpFolderURL)

            // 2. Watched-папки — только наши временные файлы
            for folder in extraFolders {
                removeMelodicaTmpFiles(in: folder)
            }
        }
    }

    private static func cleanDirectory(_ dir: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }
        for url in items {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func removeMelodicaTmpFiles(in folder: URL) {
        // Сканируем только верхний уровень. Если музыка лежит в подпапках,
        // то и temp-файлы создавались в этих же подпапках — но обходить их
        // целиком дорого. Поэтому в safeWrite() мы будем класть temp
        // в Melodica/tmp, даже на внешнем томе — см. п.3.
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix(".melodica_tmp_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Temp URL helper (same-volume aware)

    /// Возвращает путь для временного файла.
    /// Для атомарной замены через replaceItemAt() нужен тот же том, что и у цели.
    /// Если Melodica/tmp на том же томе — используем её, иначе папку рядом с файлом.
    private static func tempURL(for target: URL) -> URL {
        let preferred = tmpFolderURL.appendingPathComponent(
            "\(UUID().uuidString)_\(target.lastPathComponent)"
        )
        let preferredVolume = (try? preferred.resourceValues(forKeys: [.volumeURLKey]).volume)?.absoluteString
        let targetVolume = (try? target.resourceValues(forKeys: [.volumeURLKey]).volume)?.absoluteString

        if let pv = preferredVolume, let tv = targetVolume, pv == tv {
            return preferred
        }
        // Другой том — кладём рядом с целью
        return target.deletingLastPathComponent()
            .appendingPathComponent(".melodica_tmp_\(UUID().uuidString)_\(target.lastPathComponent)")
    }

    // MARK: - safeWrite

    /// Пишет data во временный файл, валидирует, атомарно заменяет оригинал.
    /// Если что-то падает — оригинал не тронут, temp удалён.
    private static func safeWrite(
        _ data: Data,
        to originalURL: URL,
        validator: ((Data) -> Bool)? = nil
    ) throws {
        let tempURL = tempURL(for: originalURL)

        // 1. Пишем во временный файл
        do {
            try data.write(to: tempURL, options: .withoutOverwriting)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        // 2. Валидация
        if let validator {
            let check: Data
            do {
                check = try Data(contentsOf: tempURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            guard validator(check) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw NSError(
                    domain: "MetadataWriter", code: 500,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Файл не прошёл проверку после записи. Оригинал не тронут."]
                )
            }
        }

        // 3. Сохраняем атрибуты оригинала
        if let attrs = try? FileManager.default.attributesOfItem(atPath: originalURL.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: tempURL.path)
        }

        // 4. Атомарная замена
        do {
            _ = try FileManager.default.replaceItemAt(originalURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - Validators

    private static func validateMP3(_ data: Data) -> Bool {
        guard data.count >= 10 else { return false }
        if data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 { return true }
        return data[0] == 0xFF && (data[1] & 0xE0) == 0xE0
    }

    private static func validateFLAC(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43
    }

    private static func validateOGG(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53
    }

    // MARK: - Sync API (mp3, flac)

    @discardableResult
    static func writeRating(_ rating: Int?, to url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "mp3":  try writeMP3Rating(rating, to: url)
            case "flac": try writeFLACRating(rating, to: url)
            default:     return false
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Async API

    static func writeRatingAsync(_ rating: Int?, to url: URL) async -> Result<Void, Error> {
        return await WriteSerializer.shared.enqueue {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            do {
                switch ext {
                case "m4a", "aac", "mp4":
                    try await writeM4ARating(rating, to: url)
                case "mp3":
                    try writeMP3Rating(rating, to: url)
                case "flac":
                    try writeFLACRating(rating, to: url)
                case "ogg", "opus":
                    try writeOGGRating(rating, to: url)
                default:
                    throw NSError(
                        domain: "MetadataWriter", code: 200,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Формат .\(ext) не поддерживает запись рейтинга"]
                    )
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - MP3

    private static func writeMP3Rating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 10 else {
            throw NSError(domain: "MetadataWriter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Файл слишком мал"])
        }

        let hasID3 = data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33

        var frames: [(id: String, data: Data)] = []
        var audioStart = 0

        if hasID3 {
            let majorVersion = data[3]
            let flags = data[5]
            let isUnsynchronised = (flags & 0x80) != 0
            let hasExtendedHeader = (flags & 0x40) != 0

            let tagSize = (Int(data[6] & 0x7F) << 21) |
                          (Int(data[7] & 0x7F) << 14) |
                          (Int(data[8] & 0x7F) << 7) |
                          Int(data[9] & 0x7F)

            var offset = 10

            // Extended header
            if hasExtendedHeader, offset + 4 <= data.count {
                let extSize: Int
                if majorVersion >= 4 {
                    extSize = (Int(data[offset] & 0x7F) << 21) |
                              (Int(data[offset+1] & 0x7F) << 14) |
                              (Int(data[offset+2] & 0x7F) << 7) |
                              Int(data[offset+3] & 0x7F)
                } else {
                    extSize = (Int(data[offset]) << 24) |
                              (Int(data[offset+1]) << 16) |
                              (Int(data[offset+2]) << 8) |
                              Int(data[offset+3])
                }
                offset += 4 + extSize
            }

            let tagEnd = min(offset + tagSize, data.count)
            audioStart = tagEnd

            guard offset <= tagEnd else {
                throw NSError(domain: "MetadataWriter", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "Повреждён ID3 (offset > tagEnd)"])
            }

            var tagData = data.subdata(in: offset..<tagEnd)
            if isUnsynchronised {
                tagData = removeUnsynchronisation(tagData)
            }

            var frameOffset = 0
            while frameOffset + 10 <= tagData.count {
                let idData = tagData.subdata(in: frameOffset..<frameOffset+4)
                if idData.allSatisfy({ $0 == 0 }) { break }

                let frameID = String(data: idData, encoding: .isoLatin1) ?? ""
                guard !frameID.isEmpty else { break }

                let frameSize: Int
                if majorVersion >= 4 {
                    frameSize = (Int(tagData[frameOffset+4] & 0x7F) << 21) |
                                (Int(tagData[frameOffset+5] & 0x7F) << 14) |
                                (Int(tagData[frameOffset+6] & 0x7F) << 7) |
                                Int(tagData[frameOffset+7] & 0x7F)
                } else {
                    frameSize = (Int(tagData[frameOffset+4]) << 24) |
                                (Int(tagData[frameOffset+5]) << 16) |
                                (Int(tagData[frameOffset+6]) << 8) |
                                Int(tagData[frameOffset+7])
                }

                guard frameSize > 0, frameOffset + 10 + frameSize <= tagData.count else { break }
                let frameData = tagData.subdata(in: (frameOffset+10)..<(frameOffset+10+frameSize))
                frames.append((frameID, frameData))
                frameOffset += 10 + frameSize
            }
        }

        frames.removeAll { $0.id == "POPM" }

        if let rating = rating, rating >= 1, rating <= 5 {
            let ratingByte = UInt8(starToPOPM(rating))
            var popm = Data()
            popm.append(0)
            popm.append(ratingByte)
            popm.append(contentsOf: [0, 0, 0, 0])
            frames.append(("POPM", popm))
        }

        var framesData = Data()
        for frame in frames {
            guard let idData = frame.id.data(using: .isoLatin1), idData.count == 4 else { continue }
            framesData.append(idData)
            let size = frame.data.count
            framesData.append(contentsOf: [
                UInt8((size >> 24) & 0xFF),
                UInt8((size >> 16) & 0xFF),
                UInt8((size >> 8) & 0xFF),
                UInt8(size & 0xFF)
            ])
            framesData.append(contentsOf: [0, 0])
            framesData.append(frame.data)
        }

        framesData.append(Data(count: 1024))

        var newTag = Data()
        newTag.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        newTag.append(contentsOf: [3, 0])              // v2.3 rev 0
        newTag.append(contentsOf: [0x00])              // флаги
        let totalSize = framesData.count
        newTag.append(contentsOf: [
            UInt8((totalSize >> 21) & 0x7F),
            UInt8((totalSize >> 14) & 0x7F),
            UInt8((totalSize >> 7) & 0x7F),
            UInt8(totalSize & 0x7F)
        ])
        newTag.append(framesData)

        var result = newTag
        if audioStart < data.count {
            result.append(data.subdata(in: audioStart..<data.count))
        }

        try safeWrite(result, to: url, validator: validateMP3)
    }

    private static func removeUnsynchronisation(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        var i = 0
        while i < data.count {
            let byte = data[i]
            out.append(byte)
            if byte == 0xFF, i + 1 < data.count, data[i+1] == 0x00 {
                i += 2
            } else {
                i += 1
            }
        }
        return out
    }

    private static func starToPOPM(_ star: Int) -> Int {
        switch star {
        case 1: return 1
        case 2: return 64
        case 3: return 128
        case 4: return 196
        case 5: return 255
        default: return 0
        }
    }

    // MARK: - FLAC

    private static func writeFLACRating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 4,
              data[0] == 0x66, data[1] == 0x4C, data[2] == 0x61, data[3] == 0x43 else {
            throw NSError(domain: "MetadataWriter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Не FLAC-файл"])
        }

        var blocks: [(type: UInt8, data: Data)] = []
        var offset = 4
        var lastBlock = false

        while !lastBlock && offset + 4 <= data.count {
            let header = data[offset]
            lastBlock = (header & 0x80) != 0
            let blockType = header & 0x7F
            let blockLength = (Int(data[offset+1]) << 16) |
                              (Int(data[offset+2]) << 8) |
                              Int(data[offset+3])
            offset += 4
            guard offset + blockLength <= data.count else {
                throw NSError(domain: "MetadataWriter", code: 7,
                              userInfo: [NSLocalizedDescriptionKey: "Повреждена структура FLAC-блоков"])
            }
            let blockData = data.subdata(in: offset..<(offset+blockLength))
            blocks.append((blockType, blockData))
            offset += blockLength
        }

        let audioStart = offset

        guard audioStart <= data.count else {
            throw NSError(domain: "MetadataWriter", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "audioStart за пределами файла"])
        }

        guard let vcIndex = blocks.firstIndex(where: { $0.type == 4 }) else {
            throw NSError(domain: "MetadataWriter", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Нет Vorbis Comment блока"])
        }

        let vc = blocks[vcIndex].data
        guard let parsed = parseVorbisComment(vc) else {
            throw NSError(domain: "MetadataWriter", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Повреждён Vorbis Comment"])
        }

        var comments = parsed.comments
        comments.removeAll {
            let u = $0.uppercased()
            return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
        }

        if let rating = rating, rating >= 1, rating <= 5 {
            comments.append("RATING=\(rating * 20)")
        }

        let newVC = buildVorbisComment(vendor: parsed.vendor, comments: comments)
        blocks[vcIndex] = (type: 4, data: newVC)

        var out = Data()
        out.append(contentsOf: [0x66, 0x4C, 0x61, 0x43])
        for (i, block) in blocks.enumerated() {
            let isLast = i == blocks.count - 1
            let header: UInt8 = (isLast ? 0x80 : 0x00) | (block.type & 0x7F)
            out.append(header)
            let len = block.data.count
            out.append(contentsOf: [
                UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF),
                UInt8(len & 0xFF)
            ])
            out.append(block.data)
        }

        if audioStart < data.count {
            out.append(data.subdata(in: audioStart..<data.count))
        }

        try safeWrite(out, to: url, validator: validateFLAC)
    }

    // MARK: - M4A

    private static func writeM4ARating(_ rating: Int?, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existingItems = try await asset.load(.metadata)

        var newItems: [AVMetadataItem] = []
        for item in existingItems {
            let id = item.identifier?.rawValue ?? ""
            let key = (item.key as? String)?.lowercased() ?? ""

            let isRatingTag =
                id == "itsk/rating" ||
                id == "itsk/com.apple.iTunes.rating" ||
                id == "----:com.apple.iTunes:rating" ||
                id == "----:com.apple.iTunes:RATING" ||
                (item.keySpace == .iTunes && (key == "rating" || key == "content rating"))

            if isRatingTag { continue }
            if let copy = item.mutableCopy() as? AVMutableMetadataItem {
                newItems.append(copy)
            }
        }

        if let rating = rating, rating >= 1, rating <= 5 {
            let item = AVMutableMetadataItem()
            item.keySpace = .iTunes
            item.key = "rating" as NSString
            item.value = String(rating * 20) as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.extendedLanguageTag = "und"
            newItems.append(item)
        }

        let tempURL = tempURL(for: url).deletingPathExtension()
            .appendingPathExtension("m4a")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw NSError(domain: "MetadataWriter", code: 100,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Не удалось создать AVAssetExportSession"])
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .m4a
        exportSession.metadata = newItems
        exportSession.shouldOptimizeForNetworkUse = false

        await exportSession.export()

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            let err = exportSession.error ?? NSError(
                domain: "MetadataWriter", code: 101,
                userInfo: [NSLocalizedDescriptionKey:
                    "Экспорт не удался: \(exportSession.status.rawValue)"]
            )
            throw err
        }

        // Валидация
        let check = (try? Data(contentsOf: tempURL)) ?? Data()
        guard check.count >= 8 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw NSError(domain: "MetadataWriter", code: 501,
                          userInfo: [NSLocalizedDescriptionKey: "M4A не прошёл проверку"])
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: tempURL.path)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    // MARK: - OGG / Opus

    private static func writeOGGRating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 4, validateOGG(data) else {
            throw NSError(domain: "MetadataWriter", code: 601,
                          userInfo: [NSLocalizedDescriptionKey: "Не Ogg-файл"])
        }

        let pages = try parseOggPages(data)
        guard !pages.isEmpty else {
            throw NSError(domain: "MetadataWriter", code: 602,
                          userInfo: [NSLocalizedDescriptionKey: "Ogg: не найдено ни одной страницы"])
        }

        let firstBody = pages[0].body
        let isOpus = firstBody.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3

        // Сколько всего header-пакетов: извлекаем ВСЕ с page 0 до конца header-части
        let headerEndPage = try findHeaderEndPage(pages: pages, targetCount: headerPacketCount)
        let allHeaderPackets = extractPackets(pages: pages, from: 0, to: headerEndPage)
        guard allHeaderPackets.count >= headerPacketCount else {
            throw NSError(domain: "MetadataWriter", code: 603,
                          userInfo: [NSLocalizedDescriptionKey: "Ogg: не найдены header-пакеты"])
        }

        // Заменяем comment-пакет (индекс 1)
        let oldComment = allHeaderPackets[1]
        let (comments, vendor, prefix) = try parseCommentPacket(oldComment, isOpus: isOpus)

        var newComments = comments
        newComments.removeAll {
            let u = $0.uppercased()
            return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
        }
        if let rating = rating, rating >= 1, rating <= 5 {
            newComments.append("RATING=\(rating * 20)")
        }

        let newCommentPacket = buildCommentPacket(
            prefix: prefix, vendor: vendor, comments: newComments, isOpus: isOpus
        )

        var newHeaderPackets = allHeaderPackets
        newHeaderPackets[1] = newCommentPacket

        // Пересобираем ВСЕ header-страницы с нуля, сохраняя BOS на первой
        let serial = pages[0].serial
        let bosFlag: UInt8 = (pages[0].headerType & 0x02)  // 0x02 если был BOS
        let newHeaderPages = buildOggHeaderPages(
            packets: newHeaderPackets,
            startingSequence: 0,
            serial: serial,
            bosFlag: bosFlag
        )

        // Собираем результат
        var result = Data()
        for p in newHeaderPages { result.append(p) }

        // Аудио-страницы: перенумеровываем sequence, но сохраняем granule / lacing / body / flags
        var nextSeq = UInt32(newHeaderPages.count)
        if headerEndPage + 1 < pages.count {
            for i in (headerEndPage + 1)..<pages.count {
                let oldPage = pages[i]
                let rebuilt = buildOggPageRaw(
                    headerType: oldPage.headerType,
                    granule: oldPage.granule,
                    serial: oldPage.serial,
                    sequence: nextSeq,
                    lacing: oldPage.lacing,
                    body: oldPage.body
                )
                result.append(rebuilt)
                nextSeq += 1
            }
        }

        try safeWrite(result, to: url, validator: validateOGG)
    }

    // MARK: - Ogg helpers
    // Безопасное чтение little-endian без проблем с выравниванием.
    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) |
               (UInt32(data[offset+1]) << 8) |
               (UInt32(data[offset+2]) << 16) |
               (UInt32(data[offset+3]) << 24)
    }

    private static func readUInt64LE(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[offset + i]) << (8 * i)
        }
        return v
    }
    private static func parseOggPages(_ data: Data) throws -> [OggPage] {
        var pages: [OggPage] = []
        var offset = 0
        while offset + 27 <= data.count {
            guard data[offset] == 0x4F, data[offset+1] == 0x67,
                  data[offset+2] == 0x67, data[offset+3] == 0x53 else { break }

            let headerType = data[offset + 5]
            let granule = readUInt64LE(data, offset + 6)
            let serial = readUInt32LE(data, offset + 14)
            let sequence = readUInt32LE(data, offset + 18)
            let numSegments = Int(data[offset + 26])
            let segTableStart = offset + 27
            guard segTableStart + numSegments <= data.count else { break }

            let lacing = [UInt8](data[segTableStart..<segTableStart + numSegments])
            var bodySize = 0
            for v in lacing { bodySize += Int(v) }

            let bodyStart = segTableStart + numSegments
            guard bodyStart + bodySize <= data.count else { break }

            let body = data.subdata(in: bodyStart..<bodyStart + bodySize)
            let rawData = data.subdata(in: offset..<bodyStart + bodySize)

            pages.append(OggPage(
                rawData: rawData,
                headerType: headerType,
                granule: granule,
                serial: serial,
                sequence: sequence,
                lacing: lacing,
                body: body
            ))

            offset = bodyStart + bodySize
        }
        return pages
    }

    /// Возвращает индекс страницы, на которой заканчивается N-й header-пакет.
    /// Пакеты определяются по «завершающим» сегментам (значение < 255).
    private static func findHeaderEndPage(pages: [OggPage], targetCount: Int) throws -> Int {
        var count = 0
        for (pi, page) in pages.enumerated() {
            for segLen in page.lacing {
                if segLen < 255 {
                    count += 1
                    if count >= targetCount { return pi }
                }
            }
        }
        throw NSError(domain: "MetadataWriter", code: 610,
                      userInfo: [NSLocalizedDescriptionKey: "Ogg: header-пакеты не найдены"])
    }

    /// Извлекает пакеты из страниц [from, to], склеивая пакеты, пересекающие границы страниц.
    private static func extractPackets(pages: [OggPage], from: Int, to: Int) -> [Data] {
        var packets: [Data] = []
        var current = Data()
        for pi in from...to {
            let page = pages[pi]
            var bodyOffset = 0
            for segLen in page.lacing {
                let end = bodyOffset + Int(segLen)
                guard end <= page.body.count else { break }
                current.append(page.body.subdata(in: bodyOffset..<end))
                bodyOffset = end
                if segLen < 255 {
                    packets.append(current)
                    current = Data()
                }
            }
        }
        return packets
    }

    /// Собирает Ogg-страницы из header-пакетов.
    /// Каждый пакет начинается на новой странице (требование Opus, легально для Vorbis).
    /// Флаг 0x01 (continuation) ставится только на страницах-продолжениях.
    /// Флаг 0x02 (BOS) ставится только на самой первой странице.
    private static func buildOggHeaderPages(
        packets: [Data],
        startingSequence: UInt32,
        serial: UInt32,
        bosFlag: UInt8
    ) -> [Data] {
        var pages: [Data] = []
        var sequence = startingSequence
        var isFirstPage = true

        for packet in packets {
            // Lacing для одного пакета
            var lacing: [UInt8] = []
            var remaining = packet.count
            while remaining >= 255 {
                lacing.append(255)
                remaining -= 255
            }
            lacing.append(UInt8(remaining))

            var idx = 0
            var byteOffsetInPacket = 0

            while idx < lacing.count {
                let count = min(255, lacing.count - idx)
                let pageLacing = Array(lacing[idx..<idx + count])

                var pageBodySize = 0
                for v in pageLacing { pageBodySize += Int(v) }

                let pageBody = packet.subdata(
                    in: byteOffsetInPacket..<byteOffsetInPacket + pageBodySize
                )

                var headerType: UInt8 = 0x00
                if idx > 0 { headerType |= 0x01 }        // продолжение предыдущей страницы
                if isFirstPage { headerType |= bosFlag } // BOS только на первой

                let page = buildOggPageRaw(
                    headerType: headerType,
                    granule: 0,
                    serial: serial,
                    sequence: sequence,
                    lacing: pageLacing,
                    body: pageBody
                )
                pages.append(page)

                idx += count
                byteOffsetInPacket += pageBodySize
                sequence += 1
                isFirstPage = false
            }
        }

        return pages
    }

    /// Собирает одну Ogg-страницу с корректным CRC.
    private static func buildOggPageRaw(
        headerType: UInt8,
        granule: UInt64,
        serial: UInt32,
        sequence: UInt32,
        lacing: [UInt8],
        body: Data
    ) -> Data {
        var page = Data()
        page.append(Data("OggS".utf8))
        page.append(0x00)
        page.append(headerType)

        var g = granule.littleEndian
        withUnsafeBytes(of: &g) { page.append(contentsOf: $0) }
        var s = serial.littleEndian
        withUnsafeBytes(of: &s) { page.append(contentsOf: $0) }
        var seq = sequence.littleEndian
        withUnsafeBytes(of: &seq) { page.append(contentsOf: $0) }

        page.append(contentsOf: [0, 0, 0, 0]) // CRC placeholder
        page.append(UInt8(lacing.count))
        page.append(contentsOf: lacing)
        page.append(body)

        let crc = oggCRC32(page)
        var c = crc.littleEndian
        withUnsafeBytes(of: &c) { bytes in
            for i in 0..<4 {
                page[22 + i] = bytes[i]
            }
        }
        return page
    }

    private static let oggCRCTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i) << 24
            for _ in 0..<8 {
                crc = (crc & 0x80000000) != 0 ? (crc << 1) ^ 0x04C11DB7 : crc << 1
            }
            return crc
        }
    }()

    private static func oggCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            let index = Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)
            crc = (crc << 8) ^ oggCRCTable[index]
        }
        return crc
    }

    // MARK: - Comment packet (OGG/Opus)

    private static func parseCommentPacket(
        _ packet: Data,
        isOpus: Bool
    ) throws -> (comments: [String], vendor: String, prefix: Data) {
        if isOpus {
            guard packet.count > 8, packet.prefix(8) == Data("OpusTags".utf8) else {
                throw NSError(domain: "MetadataWriter", code: 604,
                              userInfo: [NSLocalizedDescriptionKey: "Ogg/Opus: нет OpusTags"])
            }
            let prefix = Data("OpusTags".utf8)
            let rest = packet.dropFirst(8)
            guard let parsed = parseVorbisComment(Data(rest)) else {
                throw NSError(domain: "MetadataWriter", code: 605,
                              userInfo: [NSLocalizedDescriptionKey: "Ogg/Opus: повреждён Vorbis Comment"])
            }
            return (parsed.comments, parsed.vendor, prefix)
        } else {
            guard packet.count > 7, packet[0] == 0x03,
                  packet[1..<7] == Data("vorbis".utf8) else {
                throw NSError(domain: "MetadataWriter", code: 606,
                              userInfo: [NSLocalizedDescriptionKey: "Ogg/Vorbis: нет comment header"])
            }
            let prefix = Data([0x03]) + Data("vorbis".utf8)
            var rest = packet.dropFirst(7)
            if rest.last == 0x01 { rest = rest.dropLast() }
            guard let parsed = parseVorbisComment(Data(rest)) else {
                throw NSError(domain: "MetadataWriter", code: 607,
                              userInfo: [NSLocalizedDescriptionKey: "Ogg/Vorbis: повреждён Vorbis Comment"])
            }
            return (parsed.comments, parsed.vendor, prefix)
        }
    }

    private static func buildCommentPacket(
        prefix: Data,
        vendor: String,
        comments: [String],
        isOpus: Bool
    ) -> Data {
        var packet = prefix
        packet.append(buildVorbisComment(vendor: vendor, comments: comments))
        if !isOpus { packet.append(0x01) }  // Vorbis framing bit
        return packet
    }

    // MARK: - Vorbis Comment helpers (shared by FLAC & OGG)

    private static func parseVorbisComment(_ data: Data) -> (vendor: String, comments: [String])? {
        var offset = 0
        func readUInt32LE() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let v = UInt32(data[offset]) |
                    (UInt32(data[offset+1]) << 8) |
                    (UInt32(data[offset+2]) << 16) |
                    (UInt32(data[offset+3]) << 24)
            offset += 4
            return v
        }

        guard let vendorLen = readUInt32LE(), offset + Int(vendorLen) <= data.count else { return nil }
        let vendorData = data.subdata(in: offset..<(offset + Int(vendorLen)))
        let vendor = String(data: vendorData, encoding: .utf8) ?? ""
        offset += Int(vendorLen)

        guard let commentCount = readUInt32LE() else { return nil }
        var comments: [String] = []
        for _ in 0..<commentCount {
            guard let commentLen = readUInt32LE(),
                  offset + Int(commentLen) <= data.count else { break }
            let commentData = data.subdata(in: offset..<(offset + Int(commentLen)))
            offset += Int(commentLen)
            if let str = String(data: commentData, encoding: .utf8) {
                comments.append(str)
            }
        }
        return (vendor, comments)
    }

    private static func buildVorbisComment(vendor: String, comments: [String]) -> Data {
        var out = Data()
        let vendorData = vendor.data(using: .utf8) ?? Data()
        var vendorLen = UInt32(vendorData.count).littleEndian
        withUnsafeBytes(of: &vendorLen) { out.append(contentsOf: $0) }
        out.append(vendorData)

        var count = UInt32(comments.count).littleEndian
        withUnsafeBytes(of: &count) { out.append(contentsOf: $0) }

        for comment in comments {
            let cData = comment.data(using: .utf8) ?? Data()
            var cLen = UInt32(cData.count).littleEndian
            withUnsafeBytes(of: &cLen) { out.append(contentsOf: $0) }
            out.append(cData)
        }
        return out
    }
}
