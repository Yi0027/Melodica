import Foundation
import os

struct WaveformCacheEntry: Codable, Sendable {
    let url: String
    let samples: [Float]
    let duration: TimeInterval
    let sampleCount: Int
}

actor WaveformCache {
    static let shared = WaveformCache()

    private final class Storage: @unchecked Sendable {
        let lock = OSAllocatedUnfairLock()
        var memoryCache: [String: WaveformCacheEntry] = [:]
        var isLoaded = false
        var isDirty = false
    }

    private let storage = Storage()
    private var saveTask: Task<Void, Never>?

    private nonisolated static var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("waveform_cache.json")
    }

    private func cacheKey(for url: URL) -> String {
        if let fragment = url.fragment, !fragment.isEmpty {
            return "\(url.path)#\(fragment)"
        }
        return url.path
    }

    private func loadIfNeeded() {
        storage.lock.withLock {
            guard !storage.isLoaded else { return }
            storage.isLoaded = true
            let url = Self.cacheURL
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([WaveformCacheEntry].self, from: data) else {
                storage.memoryCache = [:]
                return
            }
            storage.memoryCache = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0) })
        }
    }

    private func scheduleSave(debounce: TimeInterval = 1.0) {
        storage.lock.withLock { storage.isDirty = true }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            if !Task.isCancelled {
                await self?.flush()
            }
        }
    }

    private nonisolated static func writeStorageToDisk(_ storage: Storage) {
        let entries: [WaveformCacheEntry]? = storage.lock.withLock {
            guard storage.isDirty else { return nil }
            storage.isDirty = false
            return Array(storage.memoryCache.values)
        }
        guard let entries, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.cacheURL, options: .atomicWrite)
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        Self.writeStorageToDisk(storage)
    }

    nonisolated func flushSync() {
        Self.writeStorageToDisk(storage)
    }

    func get(for url: URL) -> WaveformCacheEntry? {
        loadIfNeeded()
        let key = cacheKey(for: url)
        return storage.lock.withLock {
            storage.memoryCache[key] ?? storage.memoryCache[url.path]
        }
    }

    func set(for url: URL, samples: [Float], duration: TimeInterval) {
        loadIfNeeded()
        let key = cacheKey(for: url)
        let entry = WaveformCacheEntry(
            url: key,
            samples: samples,
            duration: duration,
            sampleCount: samples.count
        )
        storage.lock.withLock {
            storage.memoryCache[key] = entry
        }
        scheduleSave()
    }

    func remove(for url: URL) {
        loadIfNeeded()
        let key = cacheKey(for: url)
        storage.lock.withLock {
            storage.memoryCache.removeValue(forKey: key)
            storage.memoryCache.removeValue(forKey: url.path)
        }
        scheduleSave()
    }

    func clearAll() {
        saveTask?.cancel()
        saveTask = nil
        storage.lock.withLock {
            storage.isDirty = false
            storage.memoryCache = [:]
        }
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    func cacheSize() -> Int {
        loadIfNeeded()
        return storage.lock.withLock {
            storage.memoryCache.count
        }
    }
}
