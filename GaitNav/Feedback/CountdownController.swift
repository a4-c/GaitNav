import Foundation

// handles step-synchronised countdown (5, 4, 3, 2, Stop)
// two paths in: handleConfirmedStep (step event) and tryVisualCountdownFallback (frame update)
struct CountdownController {
    
    // step event arrived -> advance countdown by one
    func handleConfirmedStep(
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter,
        speech: SpeechManager
    ) {
        
        guard focusState.focusedObjectID != nil else { return }
        guard let currentSteps = focusState.focusedCurrentSteps else { return }
        guard let lastSteps = focusState.lastAnnouncedSteps else { return }
        
        let now = Date()
        
        let expectedNextSteps = max(lastSteps - 1, configuration.urgentStepThreshold)
        let drift = abs(currentSteps - expectedNextSteps)
        
        // large drift -> correction prompt instead of normal countdown
        if drift >= configuration.correctionStepDelta,
           currentSteps > configuration.urgentStepThreshold,
           now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval {
            speech.speak(formatter.correctionText(steps: currentSteps))
            focusState.lastAnnouncedSteps = currentSteps
            focusState.lastAnnouncementTime = now
            return
        }
        
        // only proceed if already in countdown range
        guard lastSteps <= configuration.countdownThreshold else { return }
        
        // prevent update() and handleStep() from both speaking in the same event chain
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.countdownMinInterval else { return }
        
        speakCountdownStep(expectedNextSteps, configuration: configuration, speech: speech)
        focusState.lastAnnouncedSteps = expectedNextSteps
        focusState.lastAnnouncementTime = now
    }
    
    // step detector missed a step, but LiDAR shows distance has decreased
    // wait for fallback delay (one step interval + one sample period) before speaking so a late step event can still take priority
    func tryVisualCountdownFallback(
        now: Date,
        isConfirmedStepUpdate: Bool,
        distanceMode: FeedbackDistanceMode,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        visualCountdownFallbackDelay: TimeInterval,
        speech: SpeechManager
    ) -> Bool {
        
        if distanceMode == .meters { return false }
        
        guard let currentSteps = focusState.focusedCurrentSteps else { return false }
        guard let lastSteps = focusState.lastAnnouncedSteps else { return false }
        
        let canEnterCountdown = isConfirmedStepUpdate || now.timeIntervalSince(focusState.lastConfirmedStepTime) >= visualCountdownFallbackDelay
        
        // not yet in countdown, but step count just dropped to 5 or below
        if lastSteps > configuration.countdownThreshold && currentSteps <= configuration.countdownThreshold {
            let minInterval = isConfirmedStepUpdate ? configuration.countdownMinInterval : configuration.visualCountdownMinInterval
            guard canEnterCountdown else { return false }
            guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= minInterval else { return false }
            speakCountdownStep(currentSteps, configuration: configuration, speech: speech)
            focusState.lastAnnouncedSteps = max(currentSteps, configuration.urgentStepThreshold)
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // already in countdown, step count dropped below last announced
        guard lastSteps <= configuration.countdownThreshold else { return false }
        guard currentSteps < lastSteps else { return false }
        guard now.timeIntervalSince(focusState.lastConfirmedStepTime) >= visualCountdownFallbackDelay else { return false }
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.visualCountdownMinInterval else { return false }
        speakCountdownStep(currentSteps, configuration: configuration, speech: speech)
        focusState.lastAnnouncedSteps = max(currentSteps, configuration.urgentStepThreshold)
        focusState.lastAnnouncementTime = now
        return true
    }
    
    // countdown is considered active if either the speech or the visual step count is at 5 or below
    // checking both -> countdown protection kicks in slightly early
    func isCountdownActive(
        focusState: FeedbackFocusState,
        distanceMode: FeedbackDistanceMode,
        configuration: FeedbackConfiguration
    ) -> Bool {
        if distanceMode == .meters { return false }
        if let lastSteps = focusState.lastAnnouncedSteps, lastSteps <= configuration.countdownThreshold {
            return true
        }
        if let currentSteps = focusState.focusedCurrentSteps, currentSteps <= configuration.countdownThreshold {
            return true
        }
        return false
    }
    
    // say the number, or Stop if at urgent threshold
    private func speakCountdownStep(_ steps: Int, configuration: FeedbackConfiguration, speech: SpeechManager) {
        if steps <= configuration.urgentStepThreshold {
            speech.speakInterrupting(configuration.finalCountdownText)
        } else {
            speech.speak("\(steps)")
        }
    }
}
