// Services,VisualizationEngine.swift
import AVFoundation
import Accelerate
import QuartzCore
import Combine

@MainActor
final class VisualizationEngine: ObservableObject {
    static let shared = VisualizationEngine()

    @Published var isRunning = false
    @Published var mode: VisualizationMode = .off
    @Published var waveformData: [Float] = Array(repeating: 0, count: 64)

    @MainActor
    final class SpectrumHolder: ObservableObject {
        @Published var data: [Float] = Array(repeating: 0, count: 32)
    }
    let spectrumHolder = SpectrumHolder()

    var spectrumData: [Float] {
        get { spectrumHolder.data }
        set { spectrumHolder.data = newValue }
    }

    enum VisualizationMode: String, CaseIterable {
        case off = "Off"
        case spectrum = "Spectrum"
        case waveform = "Waveform"
        case circular = "Circular"
    }

    private(set) var currentTrack: Track? = nil
    private var currentAudioFile: AVAudioFile?
    var currentSampleRate: Double = 44100.0
    nonisolated(unsafe) private var fftSetup: FFTSetup?
    private let bufferSize = 2048
    private let spectrumBands = 32
    private var sampleRingBuffer = [Float]()
    private var lastProcessTime: Double = 0
    nonisolated(unsafe) private var observerTokens: [any NSObjectProtocol] = []

    // Scratch buffers to avoid repeated heap reallocations during FFT
    private var windowedBuffer = [Float](repeating: 0, count: 2048)
    private var realPartBuffer = [Float](repeating: 0, count: 1024)
    private var imagPartBuffer = [Float](repeating: 0, count: 1024)
    private var magnitudesBuffer = [Float](repeating: 0, count: 1024)
    private var spectrumBuffer = [Float](repeating: 0, count: 32)
    
    private lazy var hannWindow: [Float] = {
        var window = [Float](repeating: 0, count: bufferSize)
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_DENORM))
        return window
    }()

    private init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(bufferSize))), FFTRadix(kFFTRadix2))

        let t1 = NotificationCenter.default.addObserver(
            forName: .trackChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let track = notification.object as? Track
            MainActor.assumeIsolated {
                if let track {
                    self?.loadWaveformForTrack(track)
                }
            }
        }
        observerTokens.append(t1)

        let t2 = NotificationCenter.default.addObserver(
            forName: .waveformCacheModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if let track = self.currentTrack {
                    self.loadWaveformForTrack(track)
                }
            }
        }
        observerTokens.append(t2)
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    /// Вызывается один раз при старте приложения (из MainActor).
    /// Читаем настройку здесь, а не в init — из-за изоляции.
    func syncModeWithSettings() {
        if let savedMode = VisualizationMode(rawValue: SettingsManager.shared.visualizationMode) {
            self.mode = savedMode
            if savedMode != .off {
                isRunning = true
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() {
        isRunning = false
        currentAudioFile = nil
        sampleRingBuffer.removeAll()
        spectrumData = Array(repeating: 0, count: spectrumBands)
        waveformData = Array(repeating: 0, count: 64)
        lastProcessTime = 0
    }

    func setMode(_ mode: VisualizationMode) {
        self.mode = mode
        SettingsManager.shared.setVisualizationMode(mode.rawValue)

        if mode != .off {
            start()
        } else {
            stop()
        }

        if mode == .waveform {
            let targetTrack = currentTrack ?? PlayerViewModel.shared?.currentTrack
            if let track = targetTrack {
                loadWaveformForTrack(track)
            }
        }

        NotificationCenter.default.post(name: NSNotification.Name("visualizationModeChanged"), object: nil)
    }

    func processSamples(_ samples: [Float]) {
        guard isRunning, mode != .off else { return }
        guard mode == .spectrum || mode == .circular else { return }

        let fpsLimit = SettingsManager.shared.spectrumFPSLimit
        if fpsLimit > 0 {
            let now = CACurrentMediaTime()
            let minInterval = 1.0 / Double(fpsLimit)
            guard now - lastProcessTime >= minInterval else { return }
            lastProcessTime = now
        }

        // Replenish buffer avoiding expensive removeFirst array memory shifting
        if samples.count >= bufferSize {
            sampleRingBuffer = Array(samples.suffix(bufferSize))
        } else {
            sampleRingBuffer.append(contentsOf: samples)
            if sampleRingBuffer.count > bufferSize {
                sampleRingBuffer = Array(sampleRingBuffer.suffix(bufferSize))
            }
        }
        guard sampleRingBuffer.count >= bufferSize else { return }

        let monoSamples = sampleRingBuffer

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
            self.waveformData = waveform
        }

        if mode == .spectrum || mode == .circular {
            processSpectrumImproved(monoSamples)
        }
    }

    func setAudioFile(_ file: AVAudioFile) {
        currentAudioFile = file
    }

    // MARK: - Загрузка волны (с кэшем)

    func loadWaveformForTrack(_ track: Track) {
        self.currentTrack = track
        let cacheMode = SettingsManager.shared.waveformCacheMode

        guard cacheMode != "off" || mode == .waveform else { return }

        let trackURL = track.url
        let duration = track.duration
        let trackID = track.id

        Task { [weak self] in
            // 1. Проверяем кэш
            if cacheMode != "off",
               let cached = await WaveformCache.shared.get(for: trackURL) {
                await MainActor.run {
                    guard self?.currentTrack?.id == trackID else { return }
                    self?.waveformData = cached.samples
                }
                return
            }

            // 2. Расчет в фоне без блокировки MainActor и без вмешательства в поток воспроизведения
            let samples = await Task.detached(priority: .utility) {
                await Self.computeWaveform(for: track)
            }.value

            // 3. Сохраняем в кэш если кэширование включено (passive или active)
            if cacheMode != "off" {
                await WaveformCache.shared.set(
                    for: trackURL,
                    samples: samples,
                    duration: duration
                )
            }

            // 4. Обновляем отображение, если трек всё ещё воспроизводится
            await MainActor.run {
                guard self?.currentTrack?.id == trackID else { return }
                self?.waveformData = samples
            }
        }
    }

    func generateWaveformForCurrentTrack(track: Track? = nil) {
        if let target = track ?? currentTrack ?? PlayerViewModel.shared?.currentTrack {
            loadWaveformForTrack(target)
        }
    }

    /// Вызывается из PlayerViewModel при подготовке следующего трека.
    /// Предварительно кэширует волну следующего трека в фоне, НЕ затирая текущую волну на экране.
    func preloadWaveform(for track: Track) {
        let cacheMode = SettingsManager.shared.waveformCacheMode
        guard cacheMode != "off" else { return }

        let trackURL = track.url
        let duration = track.duration

        Task.detached(priority: .utility) {
            if await WaveformCache.shared.get(for: trackURL) != nil {
                return
            }

            let samples = await Self.computeWaveform(for: track)

            await WaveformCache.shared.set(
                for: trackURL,
                samples: samples,
                duration: duration
            )
        }
    }

    // MARK: - Публичный метод для активного кеширования

    nonisolated func generateWaveformSamples(for url: URL, duration: TimeInterval, track: Track? = nil) async -> [Float] {
        if let cached = await WaveformCache.shared.get(for: url) {
            return cached.samples
        }

        let realURL: URL = {
            if url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? url
            }
            return url
        }()

        guard let file = try? AVAudioFile(forReading: realURL) else {
            return Array(repeating: 0, count: 64)
        }

        return Self.generateRawWaveform(from: file, track: track)
    }

    // MARK: - Чистые вычисления (nonisolated static)

    nonisolated private static func computeWaveform(for track: Track) async -> [Float] {
        let realURL: URL = {
            if track.url.fragment?.hasPrefix("cue_") == true {
                var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false)
                components?.fragment = nil
                return components?.url ?? track.url
            }
            return track.url
        }()

        guard let file = try? AVAudioFile(forReading: realURL) else {
            return Array(repeating: 0, count: 64)
        }
        return generateRawWaveform(from: file, track: track)
    }

    /// Не трогает self, работает только с переданным AVAudioFile и Track.
    nonisolated private static func generateRawWaveform(from file: AVAudioFile, track: Track?) -> [Float] {
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

        var sumSquares = [Float](repeating: 0, count: 64)
        var sampleCounts = [Float](repeating: 0, count: 64)

        for channel in 0..<channelCount {
            let channelPtr = channelData[channel]
            for i in 0..<64 {
                let start = i * chunkSize
                let end = min(start + chunkSize, sampleCount)
                let length = end - start
                guard length > 0 else { continue }

                var channelSumOfSquares: Float = 0
                vDSP_svesq(channelPtr.advanced(by: start), 1, &channelSumOfSquares, vDSP_Length(length))

                sumSquares[i] += channelSumOfSquares
                sampleCounts[i] += Float(length)
            }
        }

        var waveform = [Float](repeating: 0, count: 64)
        for i in 0..<64 {
            waveform[i] = sampleCounts[i] > 0 ? sqrt(sumSquares[i] / sampleCounts[i]) : 0
        }

        let minRMS = waveform.min() ?? 0
        let maxRMS = waveform.max() ?? 1.0
        if maxRMS > minRMS {
            let range = maxRMS - minRMS
            for i in 0..<waveform.count {
                waveform[i] = (waveform[i] - minRMS) / range
            }
        }

        return waveform
    }

    // MARK: - Спектрум

    private func processSpectrumImproved(_ samples: [Float]) {
        guard samples.count >= bufferSize else { return }
        let halfSize = bufferSize / 2

        // 1. Окно Ханна (Hann Window)
        vDSP_vmul(samples, 1, hannWindow, 1, &windowedBuffer, 1, vDSP_Length(bufferSize))

        // 2. Упаковка вещественного сигнала в комплексную четно-нечетную структуру (even-odd split) для vDSP_fft_zrip
        for i in 0..<halfSize {
            realPartBuffer[i] = windowedBuffer[2 * i]
            imagPartBuffer[i] = windowedBuffer[2 * i + 1]
        }

        // 3. Вычисление прямого вещественного FFT
        realPartBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagPartBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                if let fftSetup = fftSetup {
                    vDSP_fft_zrip(
                        fftSetup,
                        &splitComplex,
                        1,
                        vDSP_Length(log2(Float(bufferSize))),
                        FFTDirection(kFFTDirection_Forward)
                    )
                }
            }
        }

        // 4. Расчет амплитуд (векторная магнитуда sqrt(re^2 + im^2))
        realPartBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagPartBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
                vDSP_zvabs(&splitComplex, 1, &magnitudesBuffer, 1, vDSP_Length(halfSize))
            }
        }

        let normFactor = Float(bufferSize)
        for i in 0..<halfSize {
            magnitudesBuffer[i] /= normFactor
        }

        // 5. Логарифмическое распределение по 32 полосам частот (от 30 Гц до 16 кГц)
        let minFrequency: Float = 30.0
        let maxFrequency: Float = 16000.0
        let nyquist: Float = Float(currentSampleRate > 0 ? currentSampleRate / 2.0 : 22050.0)
        let binWidth = nyquist / Float(halfSize)

        for i in 0..<spectrumBands {
            spectrumBuffer[i] = 0
        }

        let logMin = log10(minFrequency)
        let logMax = log10(min(maxFrequency, nyquist))
        let logStep = (logMax - logMin) / Float(spectrumBands)

        for i in 0..<spectrumBands {
            let freqLow = pow(10, logMin + Float(i) * logStep)
            let freqHigh = pow(10, logMin + Float(i + 1) * logStep)

            let rawBinLow = max(1, Int(freqLow / binWidth))
            let binLow = min(halfSize - 1, rawBinLow)
            let binHigh = min(halfSize - 1, max(binLow, Int(freqHigh / binWidth)))

            guard binLow <= binHigh else { continue }

            var maxMag: Float = 0
            var sumMag: Float = 0
            var count: Float = 0

            for j in binLow...binHigh {
                let m = magnitudesBuffer[j]
                if m > maxMag { maxMag = m }
                sumMag += m
                count += 1
            }

            let avgMag = count > 0 ? sumMag / count : 0
            // Баланс пикового значения и среднего: обеспечивает чуткую реакцию на отдельные ноты
            // и убирает искусственное затухание широких высокочастотных полос
            let bandVal = maxMag * 0.7 + avgMag * 0.3

            // Частотная компенсация естественного розового шума (на высоких частотах энергия музыки в среднем ниже)
            let centerFreq = sqrt(freqLow * freqHigh)
            let tilt = pow(centerFreq / 1000.0, 0.35)

            spectrumBuffer[i] = bandVal * tilt
        }

        // 6. Множитель чувствительности из настроек пользователя
        let mult = Float(SettingsManager.shared.spectrumMultiplier)
        for i in 0..<spectrumBands {
            spectrumBuffer[i] = spectrumBuffer[i] * mult
        }

        // 7. Динамическая логарифмическая компрессия (эмуляция шкалы дБ для естественного визуального движения)
        if SettingsManager.shared.spectrumProcessingEnabled {
            let compMultiplier: Float = 9.0
            let maxPossible = log10(1 + compMultiplier)
            for i in 0..<spectrumBands {
                let compressed = log10(1 + min(spectrumBuffer[i], 1.5) * compMultiplier) / maxPossible
                spectrumBuffer[i] = min(max(compressed, 0.0), 1.0)
            }
        }

        // 8. Плавное сглаживание: подъем и спад (0.15 как в бэкапе при включенном режиме, 0.7 при выключенном)
        let smoothDecay = SettingsManager.shared.spectrumSmoothDecayEnabled
        let decayFactor: Float = smoothDecay ? 0.15 : 0.7

        var newSpectrumData = self.spectrumData
        for i in 0..<min(spectrumBands, newSpectrumData.count) {
            let target = spectrumBuffer[i]
            let current = newSpectrumData[i]

            if target > current {
                newSpectrumData[i] = current + (target - current) * 0.7
            } else {
                newSpectrumData[i] = current + (target - current) * decayFactor
            }
        }
        self.spectrumData = newSpectrumData
    }
}
