// Services,WaveformCache.swift
import Foundation

struct WaveformCacheEntry: Codable {
    let url: String
    let samples: [Float]
    let duration: TimeInterval
    let sampleCount: Int
}

enum WaveformCache {
    private static var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("waveform_cache.json")
    }
    
    private static var memoryCache: [String: WaveformCacheEntry] = [:]
    private static var isLoaded = false
    
    static func loadCache() {
        guard !isLoaded else { return }
        isLoaded = true
        
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let entries = try? JSONDecoder().decode([WaveformCacheEntry].self, from: data) else {
            memoryCache = [:]
            return
        }
        
        memoryCache = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0) })
    }
    
    static func saveCache() {
        let entries = Array(memoryCache.values)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheURL, options: .atomicWrite)
    }
    
    static func get(for url: URL) -> WaveformCacheEntry? {
        loadCache()
        return memoryCache[url.path]
    }
    
    static func set(for url: URL, samples: [Float], duration: TimeInterval) {
        loadCache()
        let entry = WaveformCacheEntry(
            url: url.path,
            samples: samples,
            duration: duration,
            sampleCount: samples.count
        )
        memoryCache[url.path] = entry
        
        DispatchQueue.global(qos: .background).async {
            saveCache()
        }
    }
    
    static func remove(for url: URL) {
        loadCache()
        memoryCache.removeValue(forKey: url.path)
        DispatchQueue.global(qos: .background).async {
            saveCache()
        }
    }
    
    static func clearAll() {
        memoryCache = [:]
        try? FileManager.default.removeItem(at: cacheURL)
    }
    
    static var cacheSize: Int {
        loadCache()
        return memoryCache.count
    }
}
