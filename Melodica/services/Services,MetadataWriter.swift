// Services,MetadataWriter.swift
import Foundation
import AVFoundation

// MARK: - Ogg Page model

struct OggPage {
    let rawData: Data
    let headerType: UInt8
    let granule: UInt64
    let serial: UInt32
    let sequence: UInt32
    let lacing: [UInt8]
    let body: Data
}

nonisolated enum MetadataWriter {

    // MARK: - Errors

    enum WriteError: LocalizedError {
        case unsupported(String)
        case tooSmall
        case notFormat(String)
        case corrupted(String)
        case verificationFailed(String)
        case io(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext):
                return "Формат .\(ext) не поддерживает запись рейтинга"
            case .tooSmall:
                return "Файл слишком мал"
            case .notFormat(let f):
                return "Файл не является \(f)"
            case .corrupted(let d):
                return "Повреждённый файл: \(d)"
            case .verificationFailed(let d):
                return "Проверка после записи не прошла: \(d). Оригинал не тронут."
            case .io(let d):
                return "Ошибка ввода-вывода: \(d)"
            }
        }
    }

    // MARK: - Write Serializer

    actor WriteSerializer {
        static let shared = WriteSerializer()
        private var tail: Task<Void, Error>?
        private var activeCount: Int = 0

        func enqueue(_ block: @escaping @Sendable () async throws -> Void) async throws {
            let prev = tail
            activeCount += 1
            let task = Task<Void, Error> {
                _ = try? await prev?.value
                try await block()
            }
            tail = task
            defer {
                activeCount -= 1
                if activeCount == 0 {
                    tail = nil
                }
            }
            try await task.value
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

    static func cleanupTmpFolder(extraFolders: [URL] = []) {
        Task.detached(priority: .background) {
            cleanDirectory(tmpFolderURL)
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

    static func tempURL(for target: URL) -> URL {
        let preferred = tmpFolderURL.appendingPathComponent(
            "\(UUID().uuidString)_\(target.lastPathComponent)"
        )
        let preferredVolume = (try? preferred.resourceValues(forKeys: [.volumeURLKey]).volume)?.absoluteString
        let targetVolume = (try? target.resourceValues(forKeys: [.volumeURLKey]).volume)?.absoluteString

        if let pv = preferredVolume, let tv = targetVolume, pv == tv {
            return preferred
        }
        return target.deletingLastPathComponent()
            .appendingPathComponent(".melodica_tmp_\(UUID().uuidString)_\(target.lastPathComponent)")
    }

    // MARK: - safeWrite

    /// Пишет `newData` во временный файл, валидирует и атомарно заменяет оригинал.
    /// `deepVerifier` вызывается на готовом temp-файле; если он бросает —
    /// оригинал остаётся нетронутым, temp удаляется.
    static func safeWrite(
        _ newData: Data,
        originalData: Data?,
        to originalURL: URL,
        basicValidator: ((Data) -> Bool)? = nil,
        deepVerifier: ((_ original: Data, _ updated: Data) throws -> Void)? = nil
    ) throws {
        let resolvedURL = originalURL.resolvingSymlinksInPath()
        let temp = tempURL(for: resolvedURL)

        // 1. Пишем во временный файл
        do {
            try? FileManager.default.removeItem(at: temp)
            try newData.write(to: temp, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw WriteError.io("не удалось записать temp-файл: \(error.localizedDescription)")
        }

        // 2. Базовая проверка (сигнатура формата)
        if let basicValidator {
            let check: Data
            do {
                check = try Data(contentsOf: temp)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.io("не читается temp-файл: \(error.localizedDescription)")
            }
            guard basicValidator(check) else {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.verificationFailed("не пройдена базовая валидация формата")
            }
        }

        // 3. Глубокая проверка (сравнение тегов и аудио)
        if let deepVerifier, let originalData {
            do {
                let check = try Data(contentsOf: temp)
                try deepVerifier(originalData, check)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                if let we = error as? WriteError { throw we }
                throw WriteError.verificationFailed(error.localizedDescription)
            }
        }

        // 4. Сохраняем атрибуты оригинала
        if let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: temp.path)
        }

        // 5. Атомарная замена с безопасным fallback для внешних томов (exFAT/SMB)
        do {
            _ = try FileManager.default.replaceItemAt(resolvedURL, withItemAt: temp)
        } catch {
            let backup = resolvedURL.appendingPathExtension("melodica_bak")
            do {
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: resolvedURL, to: backup)
                do {
                    try FileManager.default.moveItem(at: temp, to: resolvedURL)
                    try? FileManager.default.removeItem(at: backup)
                } catch {
                    try? FileManager.default.moveItem(at: backup, to: resolvedURL)
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.io("не удалось заменить оригинал: \(error.localizedDescription)")
            }
        }
    }

    static func safeWriteAsync(
        _ newData: Data,
        originalData: Data?,
        to originalURL: URL,
        basicValidator: ((Data) -> Bool)? = nil,
        deepVerifier: ((_ original: Data, _ updated: Data) async throws -> Void)? = nil
    ) async throws {
        let resolvedURL = originalURL.resolvingSymlinksInPath()
        let temp = tempURL(for: resolvedURL)

        // 1. Пишем во временный файл
        do {
            try? FileManager.default.removeItem(at: temp)
            try newData.write(to: temp, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw WriteError.io("не удалось записать temp-файл: \(error.localizedDescription)")
        }

        // 2. Базовая проверка (сигнатура формата)
        if let basicValidator {
            let check: Data
            do {
                check = try Data(contentsOf: temp)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.io("не читается temp-файл: \(error.localizedDescription)")
            }
            guard basicValidator(check) else {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.verificationFailed("не пройдена базовая валидация формата")
            }
        }

        // 3. Глубокая проверка (сравнение тегов и аудио)
        if let deepVerifier, let originalData {
            do {
                let check = try Data(contentsOf: temp)
                try await deepVerifier(originalData, check)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                if let we = error as? WriteError { throw we }
                throw WriteError.verificationFailed(error.localizedDescription)
            }
        }

        // 4. Сохраняем атрибуты оригинала
        if let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: temp.path)
        }

        // 5. Атомарная замена с безопасным fallback для внешних томов (exFAT/SMB)
        do {
            _ = try FileManager.default.replaceItemAt(resolvedURL, withItemAt: temp)
        } catch {
            let backup = resolvedURL.appendingPathExtension("melodica_bak")
            do {
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: resolvedURL, to: backup)
                do {
                    try FileManager.default.moveItem(at: temp, to: resolvedURL)
                    try? FileManager.default.removeItem(at: backup)
                } catch {
                    try? FileManager.default.moveItem(at: backup, to: resolvedURL)
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw WriteError.io("не удалось заменить оригинал: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Validators

    static func validateMP3(_ data: Data) -> Bool {
        guard data.count >= 10 else { return false }
        if data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 { return true }
        return data[0] == 0xFF && (data[1] & 0xE0) == 0xE0
    }

    static func validateFLAC(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43
    }

    static func validateOGG(_ data: Data) -> Bool {
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
        do {
            try await WriteSerializer.shared.enqueue {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }

                let ext = url.pathExtension.lowercased()
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
                    throw WriteError.unsupported(ext)
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - MP3

    struct MP3Structure {
        let majorVersion: UInt8
        let tagFlags: UInt8
        let frames: [(id: String, data: Data)]
        let audioStart: Int
    }

    /// Разбирает ID3v2-тег (если есть) и возвращает все фреймы + смещение аудио.
    /// Один и тот же код используется и при записи, и при верификации.
    static func parseMP3Structure(_ data: Data) throws -> MP3Structure {
        guard data.count >= 10 else { throw WriteError.tooSmall }

        let hasID3 = data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33
        guard hasID3 else {
            // Чистый MP3 без тега — фреймов нет, аудио с начала.
            return MP3Structure(majorVersion: 3, tagFlags: 0, frames: [], audioStart: 0)
        }

        let majorVersion = data[3]
        let tagFlags = data[5]
        let isUnsynchronised = (tagFlags & 0x80) != 0
        let hasExtendedHeader = (tagFlags & 0x40) != 0

        let tagSize = (Int(data[6] & 0x7F) << 21) |
                      (Int(data[7] & 0x7F) << 14) |
                      (Int(data[8] & 0x7F) << 7) |
                      Int(data[9] & 0x7F)

        var offset = 10

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
        let audioStart = tagEnd

        guard offset <= tagEnd else {
            throw WriteError.corrupted("ID3: offset > tagEnd")
        }

        var tagData = data.subdata(in: offset..<tagEnd)
        if isUnsynchronised {
            tagData = removeUnsynchronisation(tagData)
        }

        var frames: [(id: String, data: Data)] = []
        var frameOffset = 0
        while frameOffset + 10 <= tagData.count {
            let idData = tagData.subdata(in: frameOffset..<frameOffset+4)
            if idData.allSatisfy({ $0 == 0 }) { break }

            let frameID = String(data: idData, encoding: .isoLatin1) ?? ""
            guard !frameID.isEmpty,
                  frameID.allSatisfy({ $0.isLetter || $0.isNumber }) else { break }

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

        return MP3Structure(
            majorVersion: majorVersion,
            tagFlags: tagFlags,
            frames: frames,
            audioStart: audioStart
        )
    }

    private static func writeMP3Rating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let info = try parseMP3Structure(data)

        // Собираем новый набор фреймов: сохраняем все не-POPM как есть,
        // при необходимости добавляем новый POPM.
        var frames = info.frames.filter { $0.id != "POPM" }

        if let rating, (1...5).contains(rating) {
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

        // Небольшой запас под возможные будущие правки.
        framesData.append(Data(count: 128))

        var newTag = Data()
        newTag.append(contentsOf: [0x49, 0x44, 0x33])
        newTag.append(contentsOf: [3, 0])
        newTag.append(contentsOf: [0x00])
        let totalSize = framesData.count
        newTag.append(contentsOf: [
            UInt8((totalSize >> 21) & 0x7F),
            UInt8((totalSize >> 14) & 0x7F),
            UInt8((totalSize >> 7) & 0x7F),
            UInt8(totalSize & 0x7F)
        ])
        newTag.append(framesData)

        var result = newTag
        if info.audioStart < data.count {
            result.append(data.subdata(in: info.audioStart..<data.count))
        }

        try safeWrite(
            result,
            originalData: data,
            to: url,
            basicValidator: validateMP3,
            deepVerifier: verifyMP3Rewrite
        )
    }

    static func removeUnsynchronisation(_ data: Data) -> Data {
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

    // MARK: - MP3 verification

    static func verifyMP3Rewrite(original: Data, updated: Data) throws {
        try verifyMP3Rewrite(original: original, updated: updated, ignoredFrameIDs: ["POPM"])
    }

    static func verifyMP3Rewrite(
        original: Data,
        updated: Data,
        ignoredFrameIDs: Set<String>
    ) throws {
        let origInfo = try parseMP3Structure(original)
        let newInfo  = try parseMP3Structure(updated)

        // Аудио должно совпасть побайтово.
        let origAudio = original[origInfo.audioStart...]
        let newAudio  = updated[newInfo.audioStart...]
        guard origAudio.count == newAudio.count, origAudio == newAudio else {
            throw WriteError.verificationFailed(
                "аудиоданные MP3 изменились (было \(origAudio.count) Б, стало \(newAudio.count) Б)"
            )
        }

        if !ignoredFrameIDs.contains("POPM") {
            let origPOPM = origInfo.frames.filter { $0.id == "POPM" }
            let newPOPM  = newInfo.frames.filter { $0.id == "POPM" }
            guard origPOPM.map(\.data) == newPOPM.map(\.data) else {
                throw WriteError.verificationFailed("POPM рейтинг был изменён или потерян")
            }
        }

        // Все фреймы, кроме игнорируемых, должны сохраниться 1-в-1.
        try compareID3Frames(
            original: origInfo.frames.filter { !ignoredFrameIDs.contains($0.id) },
            updated:  newInfo.frames.filter  { !ignoredFrameIDs.contains($0.id) }
        )
    }

    /// Сравнение ID3-фреймов как мультимножества (порядок не важен, дубликаты учитываются).
    static func compareID3Frames(
        original: [(id: String, data: Data)],
        updated:  [(id: String, data: Data)]
    ) throws {
        let origGrouped = Dictionary(grouping: original, by: { $0.id })
        let newGrouped  = Dictionary(grouping: updated,  by: { $0.id })

        let origKeys = Set(origGrouped.keys)
        let newKeys  = Set(newGrouped.keys)

        if origKeys != newKeys {
            let missing = origKeys.subtracting(newKeys)
            let added   = newKeys.subtracting(origKeys)
            var parts: [String] = []
            if !missing.isEmpty { parts.append("потеряны фреймы: \(missing.sorted().joined(separator: ", "))") }
            if !added.isEmpty   { parts.append("появились лишние фреймы: \(added.sorted().joined(separator: ", "))") }
            throw WriteError.verificationFailed(parts.joined(separator: "; "))
        }

        for id in origKeys {
            let origValues = origGrouped[id]!.map(\.data).sorted { $0.lexicographicallyPrecedes($1) }
            let newValues  = newGrouped[id]!.map(\.data).sorted  { $0.lexicographicallyPrecedes($1) }
            guard origValues == newValues else {
                throw WriteError.verificationFailed("фрейм \(id) изменил содержимое")
            }
        }
    }

    // MARK: - FLAC

    struct FLACStructure {
        let blocks: [(type: UInt8, data: Data)]
        let audioStart: Int
    }

    static func parseFLACStructure(_ data: Data) throws -> FLACStructure {
        guard data.count >= 4,
              data[0] == 0x66, data[1] == 0x4C, data[2] == 0x61, data[3] == 0x43 else {
            throw WriteError.notFormat("FLAC")
        }

        var blocks: [(type: UInt8, data: Data)] = []
        var offset = 4
        var lastBlock = false

        while !lastBlock {
            guard offset + 4 <= data.count else {
                throw WriteError.corrupted("FLAC: обрыв на заголовке блока")
            }
            let header = data[offset]
            lastBlock = (header & 0x80) != 0
            let blockType = header & 0x7F
            let blockLength = (Int(data[offset+1]) << 16) |
                              (Int(data[offset+2]) << 8) |
                              Int(data[offset+3])
            offset += 4
            guard offset + blockLength <= data.count else {
                throw WriteError.corrupted("FLAC: блок выходит за пределы файла")
            }
            let blockData = data.subdata(in: offset..<(offset+blockLength))
            blocks.append((blockType, blockData))
            offset += blockLength
        }

        return FLACStructure(blocks: blocks, audioStart: offset)
    }

    private static func writeFLACRating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let info = try parseFLACStructure(data)

        guard let vcIndex = info.blocks.firstIndex(where: { $0.type == 4 }) else {
            throw WriteError.corrupted("FLAC: нет Vorbis Comment блока")
        }

        guard let parsed = parseVorbisComment(info.blocks[vcIndex].data) else {
            throw WriteError.corrupted("FLAC: повреждён Vorbis Comment")
        }

        var comments = parsed.comments
        comments.removeAll {
            let u = $0.uppercased()
            return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
        }

        if let rating, (1...5).contains(rating) {
            comments.append("RATING=\(rating * 20)")
        }

        var blocks = info.blocks
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

        if info.audioStart < data.count {
            out.append(data.subdata(in: info.audioStart..<data.count))
        }

        try safeWrite(
            out,
            originalData: data,
            to: url,
            basicValidator: validateFLAC,
            deepVerifier: verifyFLACRewrite
        )
    }

    static func verifyFLACRewrite(original: Data, updated: Data) throws {
        try verifyFLACRewrite(original: original, updated: updated, ignoredCommentKeys: ["RATING", "FMPS_RATING"], coverEdited: false)
    }

    static func verifyFLACRewrite(
        original: Data,
        updated: Data,
        ignoredCommentKeys: Set<String>,
        coverEdited: Bool
    ) throws {
        let origInfo = try parseFLACStructure(original)
        let newInfo  = try parseFLACStructure(updated)

        // Аудио совпадает побайтово.
        let origAudio = original[origInfo.audioStart...]
        let newAudio  = updated[newInfo.audioStart...]
        guard origAudio.count == newAudio.count, origAudio == newAudio else {
            throw WriteError.verificationFailed(
                "аудиоданные FLAC изменились (было \(origAudio.count) Б, стало \(newAudio.count) Б)"
            )
        }

        // Vorbis Comment: теги, кроме игнорируемых, должны сохраниться.
        guard let origVC = origInfo.blocks.first(where: { $0.type == 4 }).flatMap({ parseVorbisComment($0.data) }),
              let newVC  = newInfo.blocks.first(where:  { $0.type == 4 }).flatMap({ parseVorbisComment($0.data) }) else {
            throw WriteError.verificationFailed("FLAC: не читается Vorbis Comment после записи")
        }

        if !ignoredCommentKeys.contains("RATING") && !ignoredCommentKeys.contains("FMPS_RATING") {
            let origRating = origVC.comments.filter {
                let u = $0.uppercased()
                return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
            }
            let newRating = newVC.comments.filter {
                let u = $0.uppercased()
                return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
            }
            guard origRating == newRating else {
                throw WriteError.verificationFailed("FLAC рейтинг был изменён или потерян")
            }
        }

        try compareStringTags(
            original: origVC.comments,
            updated:  newVC.comments,
            ignoringPrefixes: Array(ignoredCommentKeys)
        )

        // Vendor должен совпасть.
        guard origVC.vendor == newVC.vendor else {
            throw WriteError.verificationFailed("FLAC: vendor Vorbis Comment изменился")
        }

        if !coverEdited {
            let origTypes = origInfo.blocks.map(\.type)
            let newTypes  = newInfo.blocks.map(\.type)
            guard origTypes == newTypes else {
                throw WriteError.verificationFailed(
                    "FLAC: набор блоков изменился (\(origTypes) → \(newTypes))"
                )
            }
        } else {
            if let origStream = origInfo.blocks.first(where: { $0.type == 0 }),
               let newStream = newInfo.blocks.first(where: { $0.type == 0 }) {
                guard origStream.data == newStream.data else {
                    throw WriteError.verificationFailed("FLAC: STREAMINFO изменился")
                }
            }
        }
    }

    // MARK: - M4A

    private static func writeM4ARating(_ rating: Int?, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existingItems = try await asset.load(.metadata)

        var newItems: [AVMetadataItem] = []
        for item in existingItems {
            if isM4ARatingItem(item) { continue }
            if let copy = item.mutableCopy() as? AVMutableMetadataItem {
                newItems.append(copy)
            }
        }

        if let rating, (1...5).contains(rating) {
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
            throw WriteError.io("не удалось создать AVAssetExportSession")
        }

        exportSession.metadata = newItems
        exportSession.shouldOptimizeForNetworkUse = false

        do {
            try await exportSession.export(to: tempURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        // Верифицируем: перечитываем метаданные из temp и сравниваем с исходными.
        do {
            let newAsset = AVURLAsset(url: tempURL)
            let newMetadata = try await newAsset.load(.metadata)
            try await verifyM4ARewrite(originalItems: existingItems, updatedItems: newMetadata)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            if let we = error as? WriteError { throw we }
            throw WriteError.verificationFailed(error.localizedDescription)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            try? FileManager.default.setAttributes(attrs, ofItemAtPath: tempURL.path)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw WriteError.io("не удалось заменить M4A: \(error.localizedDescription)")
        }
    }

    // MARK: - M4A helpers

    /// Возвращает true, если элемент метаданных — это rating-тег (в любой известной форме).
    static func isM4ARatingItem(_ item: AVMetadataItem) -> Bool {
        let id = item.identifier?.rawValue ?? ""
        let key = (item.key as? String)?.lowercased() ?? ""

        return id == "itsk/rating" ||
               id == "itsk/com.apple.iTunes.rating" ||
               id == "----:com.apple.iTunes:rating" ||
               id == "----:com.apple.iTunes:RATING" ||
               (item.keySpace == .iTunes && (key == "rating" || key == "content rating"))
    }

    /// Строковое представление значения метаданных — для сравнения.
    /// Асинхронно, потому что `AVMetadataItem.value` устарел в macOS 13.
    static func m4aValueString(_ item: AVMetadataItem) async throws -> String {
        let v = try await item.load(.value)
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        guard let v else { return "" }
        return String(describing: v)
    }

    static func extractM4AAudioData(_ data: Data) -> Data? {
        var offset = 0
        var mdatBodies: [Data] = []
        while offset + 8 <= data.count {
            let size32 = (UInt32(data[offset]) << 24) |
                         (UInt32(data[offset+1]) << 16) |
                         (UInt32(data[offset+2]) << 8) |
                         UInt32(data[offset+3])
            let typeData = data.subdata(in: offset+4..<offset+8)
            guard let type = String(data: typeData, encoding: .isoLatin1) else { break }
            var headerSize = 8
            var atomSize = Int(size32)
            if size32 == 1 {
                guard offset + 16 <= data.count else { break }
                var s: UInt64 = 0
                for i in 0..<8 { s = (s << 8) | UInt64(data[offset + 8 + i]) }
                atomSize = Int(s)
                headerSize = 16
            } else if size32 == 0 {
                atomSize = data.count - offset
            }
            guard atomSize >= headerSize, offset + atomSize <= data.count else { break }
            if type == "mdat" {
                mdatBodies.append(data.subdata(in: (offset + headerSize)..<(offset + atomSize)))
            }
            offset += atomSize
        }
        if mdatBodies.isEmpty { return nil }
        var combined = Data()
        for b in mdatBodies { combined.append(b) }
        return combined
    }

    static func verifyM4ARewrite(
        originalItems: [AVMetadataItem],
        updatedItems:  [AVMetadataItem]
    ) async throws {
        try await verifyM4ARewrite(originalData: nil, updatedData: nil, originalItems: originalItems, updatedItems: updatedItems, ignoredKeys: ["rating", "itsk/rating"])
    }

    static func verifyM4ARewrite(
        originalData: Data?,
        updatedData: Data?,
        originalItems: [AVMetadataItem],
        updatedItems:  [AVMetadataItem],
        ignoredKeys: Set<String>
    ) async throws {
        if let originalData, let updatedData,
           let origAudio = extractM4AAudioData(originalData),
           let newAudio = extractM4AAudioData(updatedData) {
            guard origAudio.count == newAudio.count, origAudio == newAudio else {
                throw WriteError.verificationFailed(
                    "аудиоданные M4A изменились (было \(origAudio.count) Б, стало \(newAudio.count) Б)"
                )
            }
        }

        let isRatingIgnored = ignoredKeys.contains("rating") || ignoredKeys.contains("itsk/rating")
        if !isRatingIgnored {
            let origRating = originalItems.filter { isM4ARatingItem($0) }
            let newRating  = updatedItems.filter  { isM4ARatingItem($0) }
            guard origRating.count == newRating.count else {
                throw WriteError.verificationFailed("M4A рейтинг был изменён или потерян")
            }
        }

        // Сравниваем все не-rating / не-edited метаданные по (keySpace, key, value).
        func signature(_ items: [AVMetadataItem]) async throws -> [String] {
            var out: [String] = []
            out.reserveCapacity(items.count)
            for item in items {
                if isRatingIgnored && isM4ARatingItem(item) { continue }
                let keySpace = item.keySpace?.rawValue ?? ""
                let key = (item.key as? String) ?? ""
                let id = item.identifier?.rawValue ?? ""
                let lowKey = key.lowercased()
                let lowId = id.lowercased()
                if ignoredKeys.contains(lowKey) || ignoredKeys.contains(lowId) { continue }
                let value = try await m4aValueString(item)
                out.append("\(keySpace)|\(key)|\(value)")
            }
            return out.sorted()
        }

        let origSig = try await signature(originalItems)
        let newSig  = try await signature(updatedItems)

        if origSig != newSig {
            let missing = Set(origSig).subtracting(newSig)
            let added   = Set(newSig).subtracting(origSig)
            var parts: [String] = []
            if !missing.isEmpty { parts.append("потеряны: \(missing)") }
            if !added.isEmpty   { parts.append("появились: \(added)") }
            throw WriteError.verificationFailed(
                "M4A: метаданные изменились (\(parts.joined(separator: "; ")))"
            )
        }
    }

    // MARK: - OGG / Opus

    private static func writeOGGRating(_ rating: Int?, to url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard validateOGG(data) else { throw WriteError.notFormat("Ogg") }

        let pages = try parseOggPages(data, validateCRC: false)
        guard !pages.isEmpty else {
            throw WriteError.corrupted("Ogg: не найдено ни одной страницы")
        }

        let firstBody = pages[0].body
        let isOpus = firstBody.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3

        let headerEndPage = try findHeaderEndPage(pages: pages, targetCount: headerPacketCount)
        let allHeaderPackets = extractPackets(pages: pages, from: 0, to: headerEndPage)
        guard allHeaderPackets.count >= headerPacketCount else {
            throw WriteError.corrupted("Ogg: не найдены header-пакеты")
        }

        let oldComment = allHeaderPackets[1]
        let (comments, vendor, prefix) = try parseCommentPacket(oldComment, isOpus: isOpus)

        var newComments = comments
        newComments.removeAll {
            let u = $0.uppercased()
            return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
        }
        if let rating, (1...5).contains(rating) {
            newComments.append("RATING=\(rating * 20)")
        }

        let newCommentPacket = buildCommentPacket(
            prefix: prefix, vendor: vendor, comments: newComments, isOpus: isOpus
        )

        var newHeaderPackets = allHeaderPackets
        newHeaderPackets[1] = newCommentPacket

        let serial = pages[0].serial
        let bosFlag: UInt8 = (pages[0].headerType & 0x02)
        let newHeaderPages = buildOggHeaderPages(
            packets: newHeaderPackets,
            startingSequence: 0,
            serial: serial,
            bosFlag: bosFlag
        )

        var result = Data()
        for p in newHeaderPages { result.append(p) }

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

        try safeWrite(
            result,
            originalData: data,
            to: url,
            basicValidator: validateOGG,
            deepVerifier: verifyOGGRewrite
        )
    }

    // MARK: - Ogg helpers

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

    static func parseOggPages(_ data: Data, validateCRC: Bool) throws -> [OggPage] {
        var pages: [OggPage] = []
        var offset = 0
        while offset + 27 <= data.count {
            guard data[offset] == 0x4F, data[offset+1] == 0x67,
                  data[offset+2] == 0x67, data[offset+3] == 0x53 else {
                throw WriteError.corrupted("Ogg: ожидался заголовок страницы на offset \(offset)")
            }

            let headerType = data[offset + 5]
            let granule = readUInt64LE(data, offset + 6)
            let serial = readUInt32LE(data, offset + 14)
            let sequence = readUInt32LE(data, offset + 18)
            let numSegments = Int(data[offset + 26])
            let segTableStart = offset + 27
            guard segTableStart + numSegments <= data.count else {
                throw WriteError.corrupted("Ogg: таблица сегментов выходит за файл")
            }

            let lacing = [UInt8](data[segTableStart..<segTableStart + numSegments])
            var bodySize = 0
            for v in lacing { bodySize += Int(v) }

            let bodyStart = segTableStart + numSegments
            guard bodyStart + bodySize <= data.count else {
                throw WriteError.corrupted("Ogg: тело страницы выходит за файл")
            }

            let body = data.subdata(in: bodyStart..<bodyStart + bodySize)
            let rawData = data.subdata(in: offset..<bodyStart + bodySize)

            if validateCRC {
                let stored = readUInt32LE(data, offset + 22)
                var zeroed = rawData
                zeroed[22] = 0
                zeroed[23] = 0
                zeroed[24] = 0
                zeroed[25] = 0
                let computed = oggCRC32(zeroed)
                guard stored == computed else {
                    throw WriteError.corrupted("Ogg: неверная CRC на странице seq=\(sequence)")
                }
            }

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

    static func findHeaderEndPage(pages: [OggPage], targetCount: Int) throws -> Int {
        var count = 0
        for (pi, page) in pages.enumerated() {
            for segLen in page.lacing {
                if segLen < 255 {
                    count += 1
                    if count >= targetCount { return pi }
                }
            }
        }
        throw WriteError.corrupted("Ogg: header-пакеты не найдены")
    }

    static func extractPackets(pages: [OggPage], from: Int, to: Int) -> [Data] {
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

    static func buildOggHeaderPages(
        packets: [Data],
        startingSequence: UInt32,
        serial: UInt32,
        bosFlag: UInt8
    ) -> [Data] {
        var pages: [Data] = []
        var sequence = startingSequence
        var isFirstPage = true

        for packet in packets {
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
                if idx > 0 { headerType |= 0x01 }
                if isFirstPage { headerType |= bosFlag }

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

    static func buildOggPageRaw(
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

        page.append(contentsOf: [0, 0, 0, 0])
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

    // MARK: - OGG verification

    static func verifyOGGRewrite(original: Data, updated: Data) throws {
        try verifyOGGRewrite(original: original, updated: updated, ignoredCommentKeys: ["RATING", "FMPS_RATING"])
    }

    static func verifyOGGRewrite(
        original: Data,
        updated: Data,
        ignoredCommentKeys: Set<String>
    ) throws {
        // CRC теперь обязана быть корректной в новом файле.
        let newPages = try parseOggPages(updated, validateCRC: true)
        let origPages = try parseOggPages(original, validateCRC: false)

        guard !newPages.isEmpty, !origPages.isEmpty else {
            throw WriteError.verificationFailed("Ogg: не удалось разобрать страницы")
        }

        // Аудио: склеенные тела страниц после header-части.
        let origAudio = try oggAudioBody(origPages)
        let newAudio  = try oggAudioBody(newPages)
        guard origAudio.count == newAudio.count, origAudio == newAudio else {
            throw WriteError.verificationFailed(
                "аудиоданные Ogg изменились (было \(origAudio.count) Б, стало \(newAudio.count) Б)"
            )
        }

        // Теги комментариев.
        let origComments = try oggCommentTags(origPages)
        let newComments  = try oggCommentTags(newPages)

        if !ignoredCommentKeys.contains("RATING") && !ignoredCommentKeys.contains("FMPS_RATING") {
            let origRating = origComments.filter {
                let u = $0.uppercased()
                return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
            }
            let newRating = newComments.filter {
                let u = $0.uppercased()
                return u.hasPrefix("RATING=") || u.hasPrefix("FMPS_RATING=")
            }
            guard origRating == newRating else {
                throw WriteError.verificationFailed("OGG рейтинг был изменён или потерян")
            }
        }

        try compareStringTags(
            original: origComments,
            updated:  newComments,
            ignoringPrefixes: Array(ignoredCommentKeys)
        )

        // Первая страница должна сохранить BOS.
        guard (newPages[0].headerType & 0x02) == (origPages[0].headerType & 0x02) else {
            throw WriteError.verificationFailed("Ogg: изменился флаг BOS первой страницы")
        }
    }

    static func oggAudioBody(_ pages: [OggPage]) throws -> Data {
        let isOpus = pages[0].body.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3
        let headerEndPage = try findHeaderEndPage(pages: pages, targetCount: headerPacketCount)

        var out = Data()
        if headerEndPage + 1 < pages.count {
            for i in (headerEndPage + 1)..<pages.count {
                out.append(pages[i].body)
            }
        }
        return out
    }

    private static func oggCommentTags(_ pages: [OggPage]) throws -> [String] {
        let isOpus = pages[0].body.prefix(8) == Data("OpusHead".utf8)
        let headerPacketCount = isOpus ? 2 : 3
        let headerEndPage = try findHeaderEndPage(pages: pages, targetCount: headerPacketCount)
        let packets = extractPackets(pages: pages, from: 0, to: headerEndPage)
        guard packets.count >= 2 else { return [] }
        let (comments, _, _) = try parseCommentPacket(packets[1], isOpus: isOpus)
        return comments
    }

    // MARK: - Comment packet (OGG/Opus)

    static func parseCommentPacket(
        _ packet: Data,
        isOpus: Bool
    ) throws -> (comments: [String], vendor: String, prefix: Data) {
        if isOpus {
            guard packet.count > 8, packet.prefix(8) == Data("OpusTags".utf8) else {
                throw WriteError.corrupted("Ogg/Opus: нет OpusTags")
            }
            let prefix = Data("OpusTags".utf8)
            let rest = packet.dropFirst(8)
            guard let parsed = parseVorbisComment(Data(rest)) else {
                throw WriteError.corrupted("Ogg/Opus: повреждён Vorbis Comment")
            }
            return (parsed.comments, parsed.vendor, prefix)
        } else {
            guard packet.count > 7, packet[0] == 0x03,
                  packet[1..<7] == Data("vorbis".utf8) else {
                throw WriteError.corrupted("Ogg/Vorbis: нет comment header")
            }
            let prefix = Data([0x03]) + Data("vorbis".utf8)
            var rest = packet.dropFirst(7)
            if rest.last == 0x01 { rest = rest.dropLast() }
            guard let parsed = parseVorbisComment(Data(rest)) else {
                throw WriteError.corrupted("Ogg/Vorbis: повреждён Vorbis Comment")
            }
            return (parsed.comments, parsed.vendor, prefix)
        }
    }

    static func buildCommentPacket(
        prefix: Data,
        vendor: String,
        comments: [String],
        isOpus: Bool
    ) -> Data {
        var packet = prefix
        packet.append(buildVorbisComment(vendor: vendor, comments: comments))
        if !isOpus { packet.append(0x01) }
        return packet
    }

    // MARK: - Vorbis Comment helpers (shared by FLAC & OGG)

    static func parseVorbisComment(_ data: Data) -> (vendor: String, comments: [String])? {
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
        guard commentCount <= 10_000,
              Int(commentCount) <= (data.count - offset) / 4 else { return nil }
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

    static func buildVorbisComment(vendor: String, comments: [String]) -> Data {
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

    // MARK: - String tag comparison (FLAC/OGG)

    /// Сравнивает Vorbis-комментарии по ключам (регистронезависимо), значения — точно.
    /// Теги с указанными префиксами игнорируются (это наши RATING-подобные).
    static func compareStringTags(
        original: [String],
        updated:  [String],
        ignoringPrefixes: [String]
    ) throws {
        let ignored = ignoringPrefixes.map { $0.uppercased() + "=" }

        func key(_ s: String) -> String {
            if let eq = s.firstIndex(of: "=") {
                return String(s[..<eq]).uppercased()
            }
            return s.uppercased()
        }

        func isIgnored(_ s: String) -> Bool {
            let u = s.uppercased()
            return ignored.contains { u.hasPrefix($0) }
        }

        let origFiltered = original.filter { !isIgnored($0) }.sorted()
        let newFiltered  = updated.filter  { !isIgnored($0) }.sorted()

        guard origFiltered == newFiltered else {
            let origSet = Set(origFiltered)
            let newSet  = Set(newFiltered)
            let missing = origSet.subtracting(newSet)
            let added   = newSet.subtracting(origSet)

            var parts: [String] = []
            if !missing.isEmpty { parts.append("потеряны: \(missing.sorted().joined(separator: ", "))") }
            if !added.isEmpty   { parts.append("появились: \(added.sorted().joined(separator: ", "))") }

            // Диагностика по "дубликатам" ключей.
            let origCounts = Dictionary(grouping: origFiltered, by: key).mapValues(\.count)
            let newCounts  = Dictionary(grouping: newFiltered,  by: key).mapValues(\.count)
            for (k, v) in origCounts where newCounts[k] != v {
                parts.append("ключ \(k): было \(v), стало \(newCounts[k] ?? 0)")
            }

            throw WriteError.verificationFailed(parts.joined(separator: "; "))
        }
    }
}

