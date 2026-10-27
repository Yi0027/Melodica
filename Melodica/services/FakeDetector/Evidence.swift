import Foundation

nonisolated enum Evidence {

    static let ruleFamily: [String: String] = [
        "Rule1MP3Bitrate": "spectral",
        "Rule2Cutoff": "spectral",
        "Rule424BitSuspect": "spectral",
        "Rule5HighVariance": "container",
        "Rule7SilenceAnalysis": "silence",
        "Rule12MLClassifier": "cnn",
        "Rule13MDCTAlignment": "mdct",
        "Rule17SBRReplication": "sbr",
    ]

    static let pointlessWitnessRules: [String: String] = [
        "Rule14TemporalSeam": "temporal",
        "Rule15StereoSeam": "stereo",
        "Rule16MP3Grid": "mp3grid",
        // Rule 18 — тот же физический вопрос, что у Rule 15 (joint stereo),
        // но читается относительно самого файла. То же семейство.
        "Rule18SideStep": "stereo",
    ]

    nonisolated static func familyTotals(_ ruleScores: [String: Int]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for (rule, family) in ruleFamily {
            let points = ruleScores[rule] ?? 0
            if points > 0 {
                totals[family, default: 0] += points
            }
        }
        return totals
    }

    nonisolated static func evidenceFamilies(
        _ ruleScores: [String: Int],
        minContribution: Int = FLACDetectiveConstants.minFamilyContribution,
        witnesses: Set<String> = []
    ) -> Set<String> {
        var families = Set<String>()
        for (family, total) in familyTotals(ruleScores) where total >= minContribution {
            families.insert(family)
        }
        families.formUnion(witnesses)
        return families
    }

    nonisolated static func collapseDependentFamilies(
        _ families: Set<String>, cutoffHz: Double?
    ) -> Set<String> {
        var out = families
        if out.contains("cnn") && out.contains("spectral"),
           let cut = cutoffHz, cut.isFinite,
           cut < FLACDetectiveConstants.familyIndependenceMinCutoffHz {
            out.remove("cnn")
            out.remove("spectral")
            out.insert("cnn\(FLACDetectiveConstants.mergedFamilySeparator)spectral")
        }
        return out
    }
}
