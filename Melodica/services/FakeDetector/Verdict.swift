import Foundation

nonisolated enum VerdictResult: String {
    case authentic
    case warning
    case suspectedDoubleEncode
    case suspicious
    case fakeCertain
    case notAssessed

    var localized: String {
        switch self {
        case .authentic:              return NSLocalizedString("verdict_short_authentic", comment: "")
        case .warning:                return NSLocalizedString("verdict_short_warning", comment: "")
        case .suspectedDoubleEncode:  return NSLocalizedString("verdict_short_suspected_double", comment: "")
        case .suspicious:             return NSLocalizedString("verdict_short_suspicious", comment: "")
        case .fakeCertain:            return NSLocalizedString("verdict_short_fake_certain", comment: "")
        case .notAssessed:            return NSLocalizedString("verdict_short_not_assessed", comment: "")
        }
    }
}

nonisolated enum Verdict {

    nonisolated static func determine(score: Int, families: Set<String>?) -> (VerdictResult, String) {
        let corroborated = families != nil && families!.count >= FLACDetectiveConstants.convictionMinFamilies

        if corroborated && score >= FLACDetectiveConstants.convictionMinScore {
            return (.fakeCertain, NSLocalizedString("verdict_fake_certain", comment: ""))
        }
        if score >= FLACDetectiveConstants.scoreSuspicious {
            if let fams = families, fams.count < FLACDetectiveConstants.convictionMinFamilies {
                return (.suspicious, NSLocalizedString("verdict_suspicious_single_family", comment: ""))
            }
            return (.suspicious, NSLocalizedString("verdict_suspicious", comment: ""))
        }
        if score >= FLACDetectiveConstants.scoreWarning {
            return (.warning, NSLocalizedString("verdict_warning", comment: ""))
        }
        return (.authentic, NSLocalizedString("verdict_authentic", comment: ""))
    }

    nonisolated static func uncorroboratedConvictionBlocked(score: Int, families: Set<String>?) -> Bool {
        if score < FLACDetectiveConstants.scoreFakeCertain { return false }
        return families == nil || families!.count < FLACDetectiveConstants.convictionMinFamilies
    }
}
