// Services/EQPresetManager.swift
import Foundation
import Combine

struct EQPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gains: [Float]      // порядок = EqualizerManager.bands
    var genres: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        gains: [Float],
        genres: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gains = gains
        self.genres = genres
        self.createdAt = createdAt
    }
}

@MainActor
final class EQPresetManager: ObservableObject {
    static let shared = EQPresetManager()

    @Published private(set) var presets: [EQPreset] = []
    @Published var activePresetID: UUID?

    /// Автоматически применять пресет при совпадении жанра с треком.
    @Published var autoApplyByGenre: Bool = false {
        didSet {
            UserDefaults.standard.set(autoApplyByGenre, forKey: Self.autoApplyKey)
        }
    }

    private static let autoApplyKey = "melodica.eqPresets.autoApplyByGenre"

    /// Снимок gains на момент применения пресета.
    /// С ним сравниваем текущие значения EQ, чтобы понять,
    /// изменил ли пользователь что-то вручную.
    private var activePresetSnapshot: [Float] = []

    /// Снимок EQ на момент, когда автопресет применился ВПЕРВЫЕ
    /// после ручной настройки. Восстанавливается, когда трек
    /// не подходит ни под один пресет.
    private var preAutoApplySnapshot: (gains: [Float], isEnabled: Bool)?

    /// true, если текущий активный пресет поставлен автоматически
    /// (а не кликом пользователя).
    private var isAutoApplied: Bool = false

    private init() {
        autoApplyByGenre = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        load()
    }

    // MARK: - Storage

    private var presetsURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eq_presets.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: presetsURL.path),
              let data = try? Data(contentsOf: presetsURL),
              let decoded = try? JSONDecoder().decode([EQPreset].self, from: data)
        else { return }
        presets = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL, options: .atomicWrite)
    }

    // MARK: - Validation

    /// Возвращает список конфликтов: для каждого переданного жанра — пресет,
    /// за которым он уже закреплён (кроме `excluding`).
    func conflicts(
        for genres: [String],
        excluding: UUID? = nil
    ) -> [(genre: String, preset: EQPreset)] {
        var result: [(String, EQPreset)] = []
        for genre in genres {
            if let existing = presets.first(where: { p in
                p.id != excluding && p.genres.contains(genre)
            }) {
                result.append((genre, existing))
            }
        }
        return result
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, gains: [Float], genres: [String]) -> EQPreset {
        let preset = EQPreset(name: name, gains: gains, genres: genres)
        presets.append(preset)
        save()
        return preset
    }

    func delete(_ preset: EQPreset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id {
            activePresetID = nil
            activePresetSnapshot = []
            isAutoApplied = false
            preAutoApplySnapshot = nil
        }
        save()
    }

    func rename(_ preset: EQPreset, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].name = newName
        save()
    }

    func updateGenres(_ preset: EQPreset, genres: [String]) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx].genres = genres
        save()
    }

    // MARK: - Apply

    /// Ручное применение пресета (клик по нему в UI).
    /// Пользователь берёт контроль — этот пресет становится baseline
    /// для авторежима.
    func applyPreset(_ preset: EQPreset) {
        isAutoApplied = false
        preAutoApplySnapshot = nil
        applyPresetInternal(preset)
    }

    /// Внутренний apply. Не трогает флаги авто-режима —
    /// используется как ручным применением, так и авто.
    private func applyPresetInternal(_ preset: EQPreset) {
        let eq = EqualizerManager.shared

        // Снимок ДО мутации — чтобы случайный onChange слайдера
        // во время цикла не сбросил activePresetID раньше времени.
        activePresetSnapshot = preset.gains
        activePresetID = preset.id

        let count = min(preset.gains.count, eq.bands.count)
        for i in 0..<count {
            eq.bands[i].gain = preset.gains[i]
        }
        if !eq.isEnabled { eq.isEnabled = true }
        eq.save()
        NotificationCenter.default.post(name: .eqDidChange, object: nil)
    }

    /// Вызывается из UI при каждом изменении ползунка EQ.
    /// Если текущие gains не совпадают со снимком применённого пресета —
    /// снимаем галочку (пользователь подкрутил вручную).
    func syncActivePresetState() {
        guard activePresetID != nil else { return }

        let eq = EqualizerManager.shared
        let current = eq.bands.map { $0.gain }
        let snapshot = activePresetSnapshot

        // Маленький эпсилон — на случай float-погрешности слайдера.
        let epsilon: Float = 0.05
        let changed = current.count != snapshot.count
            || zip(current, snapshot).contains { abs($0 - $1) > epsilon }

        if changed {
            activePresetID = nil
            activePresetSnapshot = []
            // Пользователь взял контроль над EQ — теперь это новый baseline.
            // При следующем подходящем треке авторежим стартует с чистого листа.
            isAutoApplied = false
            preAutoApplySnapshot = nil
        }
    }

    /// Вызывается из PlayerViewModel при смене трека.
    /// Логика:
    /// - Есть пресет для жанра: применяем. При первом авто-применении
    ///   запоминаем текущее состояние EQ как baseline.
    /// - Нет пресета для жанра: если до этого играл авто-пресет —
    ///   возвращаем baseline.
    func autoApplyIfNeeded(for genre: String?) {
        guard autoApplyByGenre else { return }

        let preset: EQPreset? = {
            guard let genre, !genre.isEmpty else { return nil }
            return presetForGenre(genre)
        }()

        if let preset {
            // Уже играет этот же авто-пресет — ничего не делаем.
            if isAutoApplied && activePresetID == preset.id { return }

            // Первое авто-применение — запоминаем, что было до него.
            if !isAutoApplied {
                let eq = EqualizerManager.shared
                preAutoApplySnapshot = (eq.bands.map { $0.gain }, eq.isEnabled)
            }

            isAutoApplied = true
            applyPresetInternal(preset)
        } else {
            // Трек не подпадает ни под один пресет.
            // Если до этого играл авто-пресет — возвращаем baseline.
            if isAutoApplied, let snapshot = preAutoApplySnapshot {
                restoreFromSnapshot(snapshot)
                isAutoApplied = false
                preAutoApplySnapshot = nil
                activePresetID = nil
                activePresetSnapshot = []
            }
        }
    }

    private func restoreFromSnapshot(_ snapshot: (gains: [Float], isEnabled: Bool)) {
        let eq = EqualizerManager.shared
        let count = min(snapshot.gains.count, eq.bands.count)
        for i in 0..<count {
            eq.bands[i].gain = snapshot.gains[i]
        }
        eq.isEnabled = snapshot.isEnabled
        eq.save()
        NotificationCenter.default.post(name: .eqDidChange, object: nil)
    }

    func presetForGenre(_ genre: String) -> EQPreset? {
        let lower = genre.lowercased()
        return presets.first { p in
            p.genres.contains { $0.lowercased() == lower }
        }
    }
}
