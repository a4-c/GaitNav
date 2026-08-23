import Foundation

struct MetresFeedbackPolicy {
    
    // purely distance-threshold driven, no step synchronisation
    // urgent -> direction change -> threshold crossing
    func updateInMetersMode(
        candidate: FeedbackCandidate,
        direction: String,
        now: Date,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter,
        speech: SpeechManager,
        distanceMode: FeedbackDistanceMode
    ) {
        
        let currentDistance = candidate.distance
        
        // urgent: below 0.5m, immediate Stop
        if currentDistance <= configuration.urgentMeterThreshold,
           let lastDist = focusState.lastAnnouncedDistance,
           lastDist > configuration.urgentMeterThreshold {
            speech.speakInterrupting(configuration.finalCountdownText)
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncementTime = now
            return
        }
        
        // debounce
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval else { return }
        
        // direction change
        if direction != focusState.lastAnnouncedDirection {
            let text = "\(candidate.detection.label), \(direction)"
            speech.speak(text)
            focusState.lastAnnouncedDirection = direction
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncementTime = now
            return
        }
        
        // threshold crossing
        if let _ = configuration.meterThresholds.first(where: { threshold in
            (focusState.lastAnnouncedDistance ?? Float.greatestFiniteMagnitude) > threshold
                && currentDistance <= threshold
        }) {
            let text = formatter.briefText(for: candidate, mode: distanceMode)
            speech.speak(text)
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncementTime = now
        }
    }
}
