import Foundation

nonisolated final class ScoringContext {
    let fileURL: URL
    let sampleRate: Int
    let bitDepth: Int
    let channels: Int
    let duration: Double
    let realBitrate: Double
    let apparentBitrate: Int
    let variance: Double?
    let ratioMeasured: Bool

    let cutoffHz: Double
    let cutoffStdHz: Double
    let energyRatio: Double
    let residualFloorDb: Double
    let edgeStepDb: Double
    let floorAboveDb: Double
    let isLowWall: Bool
    let lowWallHz: Double
    
    var forceNotAssessed: Bool = false
    var currentScore: Int = 0
    var reasons: [String] = []
    var ruleScores: [String: Int] = [:]
    var witnessFamilies: Set<String> = []

    var mp3BitrateDetected: Int? = nil
    var silenceRatio: Double? = nil
    var cassetteScore: Int = 0
    var mdctPeakRatio: Double = .nan
    var temporalSeam: Double = .nan
    var stereoDeadRun: Double = .nan
    var mp3GridRatio: Double = .nan
    var sbrCoherence: Double = .nan         // Rule 17
    var sideStepDb: Double = .nan           // Rule 18
    var vorbisSwitchRatio: Double = .nan    // Rule 13 codec-grids
    var celtRatio: Double = .nan            // Rule 13 codec-grids

    var activeRule: String? = nil

    var loadedAudio: [Float]? = nil
    var loadedAudioSampleRate: Int? = nil

    init(
        fileURL: URL, sampleRate: Int, bitDepth: Int, channels: Int,
        duration: Double, realBitrate: Double, apparentBitrate: Int,
        variance: Double?, ratioMeasured: Bool,
        cutoffHz: Double, cutoffStdHz: Double, energyRatio: Double,
        residualFloorDb: Double, edgeStepDb: Double, floorAboveDb: Double,
        isLowWall: Bool, lowWallHz: Double
    ) {
        self.fileURL = fileURL
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.duration = duration
        self.realBitrate = realBitrate
        self.apparentBitrate = apparentBitrate
        self.variance = variance
        self.ratioMeasured = ratioMeasured
        self.cutoffHz = cutoffHz
        self.cutoffStdHz = cutoffStdHz
        self.energyRatio = energyRatio
        self.residualFloorDb = residualFloorDb
        self.edgeStepDb = edgeStepDb
        self.floorAboveDb = floorAboveDb
        self.isLowWall = isLowWall
        self.lowWallHz = lowWallHz
    }

    func addScore(_ score: Int, _ newReasons: [String]) {
        let key = activeRule ?? "_calculator"
        ruleScores[key, default: 0] += score
        currentScore += score
        reasons.append(contentsOf: newReasons)
    }
}
