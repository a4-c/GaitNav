import Foundation

struct StepsFeedbackPolicy {
    
    // called by update() for the focused object in steps mode
    // urgent -> visual fallback -> direction change -> threshold
    func updateInStepsMode(
        candidate: FeedbackCandidate,
        now: Date,
        isConfirmedStepUpdate: Bool,
        distanceMode: FeedbackDistanceMode,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        visualCountdownFallbackDelay: TimeInterval,
        formatter: FeedbackAnnouncementFormatter,
        countdownController: CountdownController,
        speech: SpeechManager
    ) -> Bool {
        
        let steps = candidate.steps
        let direction = candidate.direction
        
        let isInCountdown = (focusState.lastAnnouncedSteps ?? Int.max) <= configuration.countdownThreshold
        
        // urgent: 1 step or less, immediate, no debounce or fallback delay
        // placed before visual fallback so it fires on the very first frame that sees <= 1 step
        if steps <= configuration.urgentStepThreshold,
           let lastSteps = focusState.lastAnnouncedSteps,
           lastSteps > configuration.urgentStepThreshold {
            let text = isInCountdown ? configuration.finalCountdownText : formatter.urgentText(for: candidate, mode: distanceMode)
            speech.speakInterrupting(text)
            focusState.lastAnnouncedSteps = steps
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // visual fallback: step detector missed a step but LiDAR shows closer
        // runs before normal rules so a short number takes priority over a full sentence
        if countdownController.tryVisualCountdownFallback(
            now: now,
            isConfirmedStepUpdate: isConfirmedStepUpdate,
            distanceMode: distanceMode,
            focusState: &focusState,
            configuration: configuration,
            visualCountdownFallbackDelay: visualCountdownFallbackDelay,
            speech: speech
        ) {
            return true
        }
        
        // debounce
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval else {
            return true
        }
        
        // direction change, but not during countdown to protect number rhythm
        if !isInCountdown && direction != focusState.lastAnnouncedDirection {
            let text = "\(candidate.detection.label), \(direction)"
            speech.speak(text)
            focusState.lastAnnouncedDirection = direction
            focusState.lastAnnouncedSteps = steps
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // far-range threshold crossing
        // if threshold and countdown entry happen on the same frame, skip the threshold and let countdown say the number instead
        if !isInCountdown, let lastSteps = focusState.lastAnnouncedSteps, steps < lastSteps {
            
            let enteredCountdown = lastSteps > configuration.countdownThreshold && steps <= configuration.countdownThreshold
            
            let crossedThreshold = configuration.stepThresholds.first { threshold in
                lastSteps > threshold && steps <= threshold
            }
            
            if crossedThreshold != nil && !enteredCountdown {
                let text = formatter.briefText(for: candidate, mode: distanceMode)
                speech.speak(text)
                focusState.lastAnnouncedSteps = steps
                focusState.lastAnnouncementTime = now
            }
        }
        
        return false
    }
}
