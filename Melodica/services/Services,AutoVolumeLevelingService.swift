//
//  AutoVolumeLevelingService.swift
//  Melodica
//
//  Created for Melodica - High-accuracy native audio loudness analyzer
//  conforming to ITU-R BS.1770-4 / EBU R128 standards for ReplayGain 2.0.
//

import Foundation
import AVFoundation
import Accelerate

nonisolated struct AutoVolumeLevelingResult: Codable, Sendable {
    let gain: Float           // ReplayGain in dB (-18.0 - LUFS)
    let peak: Float           // Maximum linear peak amplitude (0.0 ... 1.0+)
    let integratedLUFS: Float // Integrated loudness in LUFS
    
    nonisolated init(gain: Float, peak: Float, integratedLUFS: Float) {
        self.gain = gain
        self.peak = peak
        self.integratedLUFS = integratedLUFS
    }
}

private struct AutoVolumeCacheEntry: Codable, Sendable {
    let gain: Float
    let peak: Float
    let integratedLUFS: Float
    let modificationDate: TimeInterval?
    let fileSize: Int64?
}

private struct BiquadFilter: Sendable {
    var s1: Double = 0
    var s2: Double = 0
    
    @inline(__always)
    nonisolated mutating func process(sample: Float, b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) -> Float {
        let x = Double(sample)
        let y = b0 * x + s1
        s1 = b1 * x - a1 * y + s2
        s2 = b2 * x - a2 * y
        return Float(y)
    }
}

private struct ChannelFilters: Sendable {
    var stage1 = BiquadFilter()
    var stage2 = BiquadFilter()
}

/// Native loudness analyzer using AVFoundation and Accelerate (vDSP)
/// implementing ITU-R BS.1770-4 standard with K-weighting and dual-stage gating.
@MainActor
final class AutoVolumeLevelingService {
    static let shared = AutoVolumeLevelingService()
    
    private var memoryCache: [String: AutoVolumeCacheEntry] = [:]
    private var inFlightTasks: [String: Task<AutoVolumeLevelingResult?, Never>] = [:]
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private var isLoaded = false
    
    private var cacheFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Melodica")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("auto_volume_cache.json")
    }
    
    private init() {
        loadCache()
    }
    
    // MARK: - Cache Management
    
    private func cacheKey(for track: Track) -> String {
        if let fragment = track.url.fragment, !fragment.isEmpty {
            return "\(track.url.path)#\(fragment)"
        }
        return track.url.path
    }
    
    private func loadCache() {
        guard !isLoaded else { return }
        isLoaded = true
        
        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: AutoVolumeCacheEntry].self, from: data) else {
            return
        }
        memoryCache = decoded
    }
    
    private func scheduleSave(debounce: TimeInterval = 1.0) {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            if !Task.isCancelled {
                self?.flush()
            }
        }
    }
    
    func flush() {
        guard isDirty else { return }
        isDirty = false
        let snapshot = memoryCache
        let url = cacheFileURL
        
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomicWrite)
            }
        }
    }

    func flushSync() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        isDirty = false
        let snapshot = memoryCache
        let url = cacheFileURL
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomicWrite)
        }
    }
    
    // MARK: - Synchronous In-Memory Query
    
    func getCachedLoudness(for track: Track) -> AutoVolumeLevelingResult? {
        let key = cacheKey(for: track)
        guard let entry = memoryCache[key] else { return nil }
        
        // Validate file attributes if present
        if let modTime = entry.modificationDate, let size = entry.fileSize {
            let realPath: String = {
                if track.url.fragment?.hasPrefix("cue_") == true {
                    var comp = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                    comp?.fragment = nil
                    return comp?.url?.path ?? track.url.path
                }
                return track.url.path
            }()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: realPath),
               let currentMod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
               let currentSize = attrs[.size] as? Int64 {
                if abs(currentMod - modTime) > 1.0 || currentSize != size {
                    memoryCache.removeValue(forKey: key)
                    return nil
                }
            }
        }
        
        return AutoVolumeLevelingResult(
            gain: entry.gain,
            peak: entry.peak,
            integratedLUFS: entry.integratedLUFS
        )
    }
    
    // MARK: - Asynchronous Analysis Request
    
    func requestLoudness(
        for track: Track,
        completion: @escaping (AutoVolumeLevelingResult?) -> Void
    ) {
        if let cached = getCachedLoudness(for: track) {
            completion(cached)
            return
        }
        
        let key = cacheKey(for: track)
        if let existingTask = inFlightTasks[key] {
            Task {
                let result = await existingTask.value
                completion(result)
            }
            return
        }
        
        let task = Task.detached(priority: .userInitiated) { () -> AutoVolumeLevelingResult? in
            return await Self.calculateLoudness(for: track)
        }
        
        inFlightTasks[key] = task
        
        Task {
            let result = await task.value
            self.inFlightTasks.removeValue(forKey: key)
            if let res = result {
                let realPath: String = {
                    if track.url.fragment?.hasPrefix("cue_") == true {
                        var comp = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                        comp?.fragment = nil
                        return comp?.url?.path ?? track.url.path
                    }
                    return track.url.path
                }()
                var modTime: TimeInterval? = nil
                var fileSize: Int64? = nil
                if let attrs = try? FileManager.default.attributesOfItem(atPath: realPath) {
                    modTime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
                    fileSize = attrs[.size] as? Int64
                }
                self.memoryCache[key] = AutoVolumeCacheEntry(
                    gain: res.gain,
                    peak: res.peak,
                    integratedLUFS: res.integratedLUFS,
                    modificationDate: modTime,
                    fileSize: fileSize
                )
                self.scheduleSave()
            }
            completion(result)
        }
    }
    
    // MARK: - ITU-R BS.1770-4 Loudness Algorithm
    
    nonisolated static func calculateLoudness(for track: Track) async -> AutoVolumeLevelingResult? {
        let realURL: URL = {
            if track.url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? track.url
            }
            return track.url
        }()
        
        guard let file = try? AVAudioFile(forReading: realURL) else {
            return nil
        }
        
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard sampleRate > 8000, channelCount > 0 else { return nil }
        
        let totalFrames = file.length
        let cueStart = track.cueStartTime ?? 0
        let startFrame = AVAudioFramePosition(cueStart * sampleRate)
        guard startFrame < totalFrames else { return nil }
        
        let framesToAnalyze: AVAudioFramePosition
        if track.duration > 0 {
            let durFrames = AVAudioFramePosition(track.duration * sampleRate)
            framesToAnalyze = min(durFrames, totalFrames - startFrame)
        } else {
            framesToAnalyze = totalFrames - startFrame
        }
        guard framesToAnalyze > 0 else { return nil }
        
        // 1. Compute ITU-R BS.1770-4 filter coefficients for sample rate
        // Stage 1: High shelf filter (head acoustics simulation)
        let db1: Double = 3.999843853973347
        let f0_1: Double = 1681.974450955533
        let q1: Double = 0.7071752369554196
        let k1 = tan(.pi * f0_1 / sampleRate)
        let vh = pow(10.0, db1 / 20.0)
        let vb = pow(vh, 0.4996667741545416)
        let a0_1 = 1.0 + k1 / q1 + k1 * k1
        let b0_1 = (vh + vb * k1 / q1 + k1 * k1) / a0_1
        let b1_1 = 2.0 * (k1 * k1 - vh) / a0_1
        let b2_1 = (vh - vb * k1 / q1 + k1 * k1) / a0_1
        let a1_1 = 2.0 * (k1 * k1 - 1.0) / a0_1
        let a2_1 = (1.0 - k1 / q1 + k1 * k1) / a0_1
        
        // Stage 2: RLB weighting (high-pass filter)
        let f0_2: Double = 38.13547087602444
        let q2: Double = 0.5003270373238773
        let k2 = tan(.pi * f0_2 / sampleRate)
        let a0_2 = 1.0 + k2 / q2 + k2 * k2
        let b0_2 = 1.0 / a0_2
        let b1_2 = -2.0 / a0_2
        let b2_2 = 1.0 / a0_2
        let a1_2 = 2.0 * (k2 * k2 - 1.0) / a0_2
        let a2_2 = (1.0 - k2 / q2 + k2 * k2) / a0_2
        
        // Channel weights Gi according to ITU-R BS.1770-4
        // Channel 0: Left (1.0), Channel 1: Right (1.0), Channel 2: Center (1.0),
        // Channel 3: LFE (0.0), Channel 4: Ls (1.41), Channel 5: Rs (1.41)
        var channelWeights = [Double](repeating: 1.0, count: channelCount)
        if channelCount >= 6 {
            channelWeights[3] = 0.0 // LFE
            channelWeights[4] = 1.41 // Ls
            channelWeights[5] = 1.41 // Rs
        }
        
        var filters = [ChannelFilters](repeating: ChannelFilters(), count: channelCount)
        
        // 100 ms sub-block sample count for 75% overlapping 400 ms gating blocks
        let subBlockSize = max(1, Int((0.100 * sampleRate).rounded()))
        var subBlockSums = [[Double]](repeating: [], count: channelCount)
        var currentSubBlockSamples = 0
        var currentSubBlockSums = [Double](repeating: 0.0, count: channelCount)
        
        var maxPeak: Float = 0.0
        
        let chunkFrames: AVAudioFrameCount = 16384
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return nil
        }
        
        file.framePosition = startFrame
        var framesRemaining = framesToAnalyze
        
        while framesRemaining > 0 {
            if Task.isCancelled { return nil }
            
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), framesRemaining))
            do {
                try file.read(into: pcmBuffer, frameCount: framesToRead)
            } catch {
                break
            }
            
            let actualFrames = Int(pcmBuffer.frameLength)
            guard actualFrames > 0 else { break }
            framesRemaining -= AVAudioFramePosition(actualFrames)
            
            guard let channelData = pcmBuffer.floatChannelData else { break }
            
            // Peak calculation using Accelerate vDSP
            for ch in 0..<channelCount {
                var chPeak: Float = 0.0
                vDSP_maxmgv(channelData[ch], 1, &chPeak, vDSP_Length(actualFrames))
                if chPeak > maxPeak { maxPeak = chPeak }
            }
            
            // Filter samples and accumulate in 100 ms intervals
            for frame in 0..<actualFrames {
                for ch in 0..<channelCount {
                    let inSample = channelData[ch][frame]
                    let y1 = filters[ch].stage1.process(
                        sample: inSample,
                        b0: b0_1, b1: b1_1, b2: b2_1,
                        a1: a1_1, a2: a2_1
                    )
                    let y2 = filters[ch].stage2.process(
                        sample: y1,
                        b0: b0_2, b1: b1_2, b2: b2_2,
                        a1: a1_2, a2: a2_2
                    )
                    let y2d = Double(y2)
                    currentSubBlockSums[ch] += y2d * y2d
                }
                
                currentSubBlockSamples += 1
                if currentSubBlockSamples >= subBlockSize {
                    for ch in 0..<channelCount {
                        subBlockSums[ch].append(currentSubBlockSums[ch])
                        currentSubBlockSums[ch] = 0.0
                    }
                    currentSubBlockSamples = 0
                }
            }
        }
        
        // Handle final partial sub-block if substantial (> 25% of subBlockSize)
        if currentSubBlockSamples > subBlockSize / 4 {
            let scale = Double(subBlockSize) / Double(currentSubBlockSamples)
            for ch in 0..<channelCount {
                subBlockSums[ch].append(currentSubBlockSums[ch] * scale)
            }
        }
        
        let numSubBlocks = subBlockSums.first?.count ?? 0
        guard numSubBlocks > 0 else {
            return AutoVolumeLevelingResult(gain: 0.0, peak: max(0.0001, maxPeak), integratedLUFS: -70.0)
        }
        
        // Compute 400 ms blocks (4 sub-blocks of 100 ms) with 75% overlap
        var blockLoudness: [Double] = []
        var blockMeanSquares: [Double] = []
        
        if numSubBlocks < 4 {
            // Track is very short (< 400 ms): compute loudness over available sub-blocks
            let totalSamples = Double(numSubBlocks * subBlockSize)
            var z: Double = 0.0
            for ch in 0..<channelCount {
                let sumSq = subBlockSums[ch].reduce(0.0, +)
                z += channelWeights[ch] * (sumSq / totalSamples)
            }
            let lufs: Double = z > 0 ? -0.691 + 10.0 * log10(z) : -70.0
            let targetGain = max(-24.0, min(18.0, -18.0 - lufs))
            return AutoVolumeLevelingResult(
                gain: Float(targetGain),
                peak: max(0.0001, maxPeak),
                integratedLUFS: Float(lufs)
            )
        }
        
        let numBlocks = numSubBlocks - 3
        let blockSampleCount = Double(4 * subBlockSize)
        
        for j in 0..<numBlocks {
            var z_j: Double = 0.0
            for ch in 0..<channelCount {
                let sum4 = subBlockSums[ch][j] + subBlockSums[ch][j+1] + subBlockSums[ch][j+2] + subBlockSums[ch][j+3]
                z_j += channelWeights[ch] * (sum4 / blockSampleCount)
            }
            blockMeanSquares.append(z_j)
            let l_j: Double = z_j > 1e-12 ? -0.691 + 10.0 * log10(z_j) : -100.0
            blockLoudness.append(l_j)
        }
        
        // ITU-R BS.1770-4 Dual-stage Gating:
        // Stage 1: Absolute threshold at -70 LKFS
        var passAbsIndices: [Int] = []
        for i in 0..<numBlocks {
            if blockLoudness[i] > -70.0 {
                passAbsIndices.append(i)
            }
        }
        
        guard !passAbsIndices.isEmpty else {
            // Signal is silence
            return AutoVolumeLevelingResult(gain: 0.0, peak: max(0.0001, maxPeak), integratedLUFS: -70.0)
        }
        
        // Calculate ungated loudness of absolute-threshold-passed blocks
        var sumUngatedZ: Double = 0.0
        for idx in passAbsIndices {
            sumUngatedZ += blockMeanSquares[idx]
        }
        let avgUngatedZ = sumUngatedZ / Double(passAbsIndices.count)
        let ungatedLoudness = -0.691 + 10.0 * log10(avgUngatedZ)
        
        // Stage 2: Relative threshold at -10 LU below ungated loudness
        let relativeThreshold = ungatedLoudness - 10.0
        var passRelIndices: [Int] = []
        for idx in passAbsIndices {
            if blockLoudness[idx] > relativeThreshold {
                passRelIndices.append(idx)
            }
        }
        
        let finalLoudness: Double
        if passRelIndices.isEmpty {
            finalLoudness = ungatedLoudness
        } else {
            var sumGatedZ: Double = 0.0
            for idx in passRelIndices {
                sumGatedZ += blockMeanSquares[idx]
            }
            let avgGatedZ = sumGatedZ / Double(passRelIndices.count)
            finalLoudness = -0.691 + 10.0 * log10(avgGatedZ)
        }
        
        // ReplayGain 2.0 reference target: -18.0 LUFS
        let gain_dB = -18.0 - finalLoudness
        let clampedGain = max(-24.0, min(18.0, gain_dB))
        
        return AutoVolumeLevelingResult(
            gain: Float(clampedGain),
            peak: max(0.0001, maxPeak),
            integratedLUFS: Float(finalLoudness)
        )
    }
}
