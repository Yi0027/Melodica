// Services,VisualizationEngine.swift
import AVFoundation
import Accelerate
import Combine

final class VisualizationEngine: ObservableObject {
    static let shared = VisualizationEngine()
    
    @Published var isRunning = false
    @Published var mode: VisualizationMode = .off
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 32)
    @Published var waveformData: [Float] = Array(repeating: 0, count: 64)
    
    enum VisualizationMode: String, CaseIterable {
        case off = "Off"
        case spectrum = "Spectrum"
        case waveform = "Waveform"
        case circular = "Circular"
    }
    
    private var currentAudioFile: AVAudioFile?
    private var isGeneratingWaveform = false
    private var fftSetup: FFTSetup?
    private let bufferSize = 4096
    private let spectrumBands = 32
    private var generationTask: DispatchWorkItem?
    
    private init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(bufferSize))), FFTRadix(kFFTRadix2))
        if let savedMode = VisualizationMode(rawValue: SettingsManager.shared.visualizationMode) {
               self.mode = savedMode
               if savedMode != .off {
                   isRunning = true
               }
           }
        }
    
    func cancelWaveformGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
    }
    
    func stop() {
        isRunning = false
        spectrumData = Array(repeating: 0, count: spectrumBands)
        waveformData = Array(repeating: 0, count: 64)
    }

    func setMode(_ mode: VisualizationMode) {
        self.mode = mode
        SettingsManager.shared.setVisualizationMode(mode.rawValue)
        
        if mode != .off {
            start()
        } else {
            stop()
        }
        
        if mode == .waveform && waveformData.max() == 0 {
            generateWaveformForCurrentTrack(track: nil)
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("visualizationModeChanged"), object: nil)
    }
    
    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRunning, mode != .off else { return }
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var monoSamples = [Float](repeating: 0, count: min(frameLength, bufferSize))
        for i in 0..<min(frameLength, bufferSize) {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channelData[channel][i]
            }
            monoSamples[i] = sum / Float(channelCount)
        }
        
        if mode == .waveform {
            // Ничего не делаем — waveformData уже загружена из файла
        } else if mode == .circular {
            let chunkSize = monoSamples.count / 64
            var waveform = [Float](repeating: 0, count: 64)
            for i in 0..<64 {
                let start = i * chunkSize
                let end = min(start + chunkSize, monoSamples.count)
                var maxAmp: Float = 0
                for j in start..<end {
                    maxAmp = max(maxAmp, abs(monoSamples[j]))
                }
                waveform[i] = min(maxAmp * 1.5, 1.0)
            }
            DispatchQueue.main.async { [weak self] in
                self?.waveformData = waveform
            }
        }
        
        if mode == .spectrum || mode == .circular {
            processSpectrumImproved(monoSamples)
        }
    }
    
    func setAudioFile(_ file: AVAudioFile) {
        currentAudioFile = file
    }

    // MARK: - Генерация волны (с кешем)
    
    func generateWaveformForCurrentTrack(track: Track? = nil) {
        guard let file = currentAudioFile else { return }
        
        // Проверяем кеш
        if let trackURL = track?.url,
           SettingsManager.shared.waveformCacheMode != "off",
           let cached = WaveformCache.get(for: trackURL) {
            DispatchQueue.main.async {
                self.waveformData = cached.samples
            }
            return
        }
                
        let samples = generateRawWaveform(from: file, track: track)
        
        // Сохраняем в кеш
        if let trackURL = track?.url,
           SettingsManager.shared.waveformCacheMode != "off" {
            WaveformCache.set(for: trackURL, samples: samples, duration: track?.duration ?? 0)
        }
        
        DispatchQueue.main.async {
            self.waveformData = samples
        }
    }
    
    func preloadWaveform(for track: Track) {
        guard !isGeneratingWaveform else { return }
        
        // ✅ Проверяем кеш
        if SettingsManager.shared.waveformCacheMode != "off",
           let cached = WaveformCache.get(for: track.url) {
            DispatchQueue.main.async {
                self.waveformData = cached.samples
            }
            return
        }
        
        let realURL: URL = {
            if track.url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? track.url
            }
            return track.url
        }()
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let file = try? AVAudioFile(forReading: realURL) else { return }
            
            self.isGeneratingWaveform = true
            let samples = self.generateRawWaveform(from: file, track: track)
            
            // ✅ Сохраняем в кеш
            if SettingsManager.shared.waveformCacheMode != "off" {
                WaveformCache.set(for: track.url, samples: samples, duration: track.duration)
            }
            
            DispatchQueue.main.async {
                self.waveformData = samples
            }
            self.isGeneratingWaveform = false
        }
    }
    
    // MARK: - Публичный метод для активного кеширования
    
    func generateWaveformSamples(for url: URL, duration: TimeInterval) -> [Float] {
        // Проверяем кеш
        if let cached = WaveformCache.get(for: url) {
            return cached.samples
        }
        
        guard let file = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0, count: 64)
        }
        
        return generateRawWaveform(from: file, track: nil)
    }
    
    // MARK: - Сырая генерация волны (общий код)
    
    private func generateRawWaveform(from file: AVAudioFile, track: Track?) -> [Float] {
        let startTime = track?.cueStartTime ?? 0
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = file.length
        let startFrame = AVAudioFramePosition(startTime * sampleRate)
        
        let frameCount: AVAudioFrameCount
        if let duration = track?.duration, duration > 0 {
            let durFrames = AVAudioFramePosition(duration * sampleRate)
            frameCount = AVAudioFrameCount(min(durFrames, totalFrames - startFrame))
        } else {
            frameCount = AVAudioFrameCount(totalFrames - startFrame)
        }
        
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return Array(repeating: 0, count: 64)
        }
        
        file.framePosition = startFrame
        do { try file.read(into: buffer) } catch { return Array(repeating: 0, count: 64) }
        
        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: 64)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleCount = min(frameLength, 44100 * 60 * 10)
        let chunkSize = max(1, sampleCount / 64)
        
        var waveform = [Float](repeating: 0, count: 64)
        for i in 0..<64 {
            let start = i * chunkSize
            let end = min(start + chunkSize, sampleCount)
            var sumSquares: Float = 0
            var count: Float = 0
            for j in start..<end {
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channelData[channel][j]
                }
                sample /= Float(channelCount)
                sumSquares += sample * sample
                count += 1
            }
            waveform[i] = count > 0 ? sqrt(sumSquares / count) : 0
        }
        
        let minRMS = waveform.min() ?? 0
        let maxRMS = waveform.max() ?? 1.0
        if maxRMS > minRMS {
            for i in 0..<waveform.count {
                waveform[i] = (waveform[i] - minRMS) / (maxRMS - minRMS)
            }
        }
        
        return waveform
    }

    // MARK: - Спектрум
    
    private func processSpectrumImproved(_ samples: [Float]) {
        var realPart = [Float](repeating: 0, count: bufferSize / 2)
        var imagPart = [Float](repeating: 0, count: bufferSize / 2)
        
        for i in 0..<min(samples.count, bufferSize / 2) {
            let window = 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(bufferSize / 2 - 1)))
            realPart[i] = samples[i] * window
        }
        
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        
        if let fftSetup = fftSetup {
            vDSP_fft_zrip(
                fftSetup,
                &splitComplex,
                1,
                vDSP_Length(log2(Float(bufferSize))),
                FFTDirection(kFFTDirection_Forward)
            )
        }
        
        let minFrequency: Float = 30.0
        let maxFrequency: Float = 16000.0
        let nyquist: Float = 22050.0
        
        var spectrum = [Float](repeating: 0, count: spectrumBands)
        
        let logMin = log10(minFrequency)
        let logMax = log10(min(maxFrequency, nyquist))
        let logStep = (logMax - logMin) / Float(spectrumBands)
        
        let binWidth = nyquist / Float(bufferSize / 2)
        
        for i in 0..<spectrumBands {
            let freqLow = pow(10, logMin + Float(i) * logStep)
            let freqHigh = pow(10, logMin + Float(i + 1) * logStep)
            
            let binLow = Int(freqLow / binWidth)
            let binHigh = min(Int(freqHigh / binWidth), bufferSize / 2 - 1)
            
            guard binHigh > binLow else { continue }
            
            var sum: Float = 0
            var count: Float = 0
            
            for j in binLow...binHigh {
                let magnitude = sqrt(realPart[j] * realPart[j] + imagPart[j] * imagPart[j])
                sum += magnitude
                count += 1
            }
            
            let avgMagnitude = count > 0 ? sum / count : 0
            spectrum[i] = avgMagnitude / Float(bufferSize / 2)
        }

        for i in 0..<spectrumBands {
            let mult = Float(SettingsManager.shared.spectrumMultiplier)
            spectrum[i] = min(spectrum[i] * mult, 1.0)
        }
        
        if SettingsManager.shared.spectrumProcessingEnabled {
            for i in 0..<spectrumBands {
                if spectrum[i] > 0.0001 && spectrum[i] < 0.1 {
                    spectrum[i] = spectrum[i] * 1.3
                }
            }
            
            for i in 0..<spectrumBands {
                let freqLow = pow(10, logMin + Float(i) * logStep)
                let freqCenter = (freqLow + pow(10, logMin + Float(i + 1) * logStep)) / 2
                
                if freqCenter < 150 {
                    let reduction = 1.0 - (150 - freqCenter) / 150 * 0.3
                    spectrum[i] = spectrum[i] * reduction
                }
            }
            
            let multiplier: Float = 10.0
            let expectedMax: Float = 0.8
            let maxPossible = log10(1 + expectedMax * multiplier)
            
            for i in 0..<spectrumBands {
                let compressed = log10(1 + spectrum[i] * multiplier)
                spectrum[i] = min(compressed / maxPossible, 1.0)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<min(spectrum.count, self.spectrumData.count) {
                let target = spectrum[i]
                let current = self.spectrumData[i]
                
                if target > current {
                    self.spectrumData[i] = current + (target - current) * 0.7
                } else {
                    self.spectrumData[i] = current + (target - current) * 0.15
                }
            }
        }
    }
}
