import Foundation
import CoreGraphics

struct FeedbackCandidateBuilder {
    func buildCandidates(
        from detections: [Detection],
        previousIDs: Set<UUID>,
        stepDistanceConverter: StepDistanceConverting,
        distanceMode: FeedbackDistanceMode,
        isCountdownActive: Bool,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter
    ) -> [FeedbackCandidate] {
        
        let filteredDetections = Detection.suppressContained(detections)
        
        // before countdown: use stable steps to keep announced distances consistent
        // during countdown: use adaptive steps for real-time accuracy
        let shouldUseAdaptiveSteps = distanceMode == .meters || isCountdownActive
        
        return filteredDetections
            .compactMap { detection -> FeedbackCandidate? in
                
                guard let distance = detection.distance else { return nil }
                
                let stableSteps = stepDistanceConverter.distanceToStableSteps(distance)
                let adaptiveSteps = stepDistanceConverter.distanceToSteps(distance)
                let steps = shouldUseAdaptiveSteps ? adaptiveSteps : stableSteps
                let direction = formatter.clockDirection(from: detection.boundingBox, configuration: configuration)
                let midX = detection.boundingBox.midX
                let isCenter = midX >= configuration.centerLowerBound && midX <= configuration.centerUpperBound
                let isNew = !previousIDs.contains(detection.id)
                
                // side + far = not in walking path, skip
                if !isCenter && steps > configuration.sideIgnoreSteps { return nil }
                
                return FeedbackCandidate(
                    detection: detection,
                    distance: distance,
                    steps: steps,
                    stableSteps: stableSteps,
                    adaptiveSteps: adaptiveSteps,
                    direction: direction,
                    isCenter: isCenter,
                    isNew: isNew
                )
            }
            .sorted { $0.steps < $1.steps }
    }
}
