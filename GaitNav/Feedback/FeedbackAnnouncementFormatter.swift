import Foundation
import CoreGraphics

struct FeedbackAnnouncementFormatter {
    
    // bbox midX -> clock direction
    // boundaries come from configuration to stay consistent with centre-path check
    func clockDirection(from boundingBox: CGRect, configuration: FeedbackConfiguration) -> String {
        let centerX = boundingBox.midX
        let hour: Int
        if centerX < configuration.centerLowerBound {
            hour = 11
        } else if centerX < configuration.centerUpperBound {
            hour = 12
        } else {
            hour = 1
        }
        return "\(hour) o'clock"
    }
    
    // first detection, full spatial info
    func fullText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "\(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate, mode: mode))"
    }
    
    // distance update (threshold), direction already known
    func briefText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "\(candidate.detection.label), \(formatDistance(candidate, mode: mode))"
    }
    
    // urgent close-range, with warning
    func urgentText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "warning, \(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate, mode: mode))"
    }
    
    // correction when step count drifts
    func correctionText(steps: Int) -> String {
        let stepWord = steps == 1 ? "step" : "steps"
        return "about \(steps) \(stepWord)"
    }
    
    private func formatDistance(_ candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        switch mode {
        case .steps:
            let stepWord = candidate.steps == 1 ? "step" : "steps"
            return "\(candidate.steps) \(stepWord)"
        case .meters:
            let rounded = (candidate.distance * 10).rounded() / 10
            let meterWord = rounded == 1.0 ? "meter" : "meters"
            return "\(String(format: "%.1f", rounded)) \(meterWord)"
        }
    }
}
