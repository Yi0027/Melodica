import Foundation

// MARK: - Слово с таймкодом (для пословного LRC)

struct LyricsWord: Identifiable, Hashable {
    let id = UUID()
    var time: TimeInterval
    var text: String
    var endTime: TimeInterval?   // nil только в процессе парсинга; после calculateWordDurations всегда != nil
    var textWidth: CGFloat = 0   // реальная ширина глифов (без запаса слота), для маски
    
    var duration: TimeInterval {
        guard let endTime else { return 0 }
        return max(0, endTime - time)
    }
    
    init(time: TimeInterval, text: String, endTime: TimeInterval? = nil) {
        self.time = time
        self.text = text
        self.endTime = endTime
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LyricsWord, rhs: LyricsWord) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Строка LRC

struct LyricsLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let endTime: TimeInterval?            // граница строки (время следующей строки с []); nil если следующей нет
    let text: String
    var words: [LyricsWord] = []
    let tag: String?
    let isSpecial: Bool
    var isMain: Bool = false
    var pauseUntil: TimeInterval?
    
    var hasWords: Bool { !words.isEmpty }
    
    init(
        time: TimeInterval,
        endTime: TimeInterval? = nil,
        text: String,
        words: [LyricsWord] = [],
        tag: String? = nil,
        isSpecial: Bool = false,
        isMain: Bool = false,
        pauseUntil: TimeInterval? = nil
    ) {
        self.time = time
        self.endTime = endTime
        self.text = text
        self.words = words
        self.tag = tag
        self.isSpecial = isSpecial
        self.isMain = isMain
        self.pauseUntil = pauseUntil
    }
}

// MARK: - Группировка строк с одинаковым временем

struct LyricsGroup: Identifiable {
    let id = UUID()
    let time: TimeInterval
    var lines: [LyricsLine]
    var pauseUntil: TimeInterval?
}

// MARK: - Метаданные LRC

struct LyricsMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var author: String?
    var length: TimeInterval?
}
