import Foundation
import ARKit

// decides what to say and when
// two entry points:
// 1. update(); every frame: focus management, first announcement, threshold updates, urgent warnings
// 2. handleStep(); every confirmed step: countdown progression (steps mode only)
class FeedbackEngine {
    
    private let speech: SpeechManager
    private let configuration = FeedbackConfiguration()
    private let formatter = FeedbackAnnouncementFormatter()
    private let visualCountdownFallbackDelayProvider: () -> TimeInterval
    private let candidateBuilder = FeedbackCandidateBuilder()
    private let metresPolicy = MetresFeedbackPolicy()
    private let stepsPolicy = StepsFeedbackPolicy()
    private let countdownController = CountdownController()
    private var focusState = FeedbackFocusState()
    private weak var stepDistanceConverter: StepDistanceConverting?
    private var isCountdownActive: Bool {
        countdownController.isCountdownActive(
            focusState: focusState,
            distanceMode: distanceMode,
            configuration: configuration
        )
    }
    
    var distanceMode: FeedbackDistanceMode
    
    init(
        speech: SpeechManager,
        stepDistanceConverter: StepDistanceConverting,
        distanceMode: FeedbackDistanceMode = .steps,
        visualCountdownFallbackDelayProvider: @escaping () -> TimeInterval = { FeedbackConfiguration().visualCountdownFallbackDelay }
    ) {
        self.speech = speech
        self.stepDistanceConverter = stepDistanceConverter
        self.distanceMode = distanceMode
        self.visualCountdownFallbackDelayProvider = visualCountdownFallbackDelayProvider
    }
    
    // frame-driven
    func update(with detections: [Detection], isConfirmedStepUpdate: Bool = false) {
        
        guard let stepDistanceConverter = stepDistanceConverter else { return }
        
        let now = Date()
        let currentIDs = Set(detections.map { $0.id })
        
        // 1. build candidates
        let candidates = candidateBuilder.buildCandidates(
            from: detections,
            previousIDs: focusState.previousIDs,
            stepDistanceConverter: stepDistanceConverter,
            distanceMode: distanceMode,
            isCountdownActive: isCountdownActive,
            configuration: configuration,
            formatter: formatter
        )
        
        // 2. check focus validity
        let wasInCountdown = isCountdownActive
        if let focusID = focusState.focusedObjectID {
            if !currentIDs.contains(focusID) {
                focusState.releaseFocus()
            } else if let focused = candidates.first(where: { $0.detection.id == focusID }),
                      let lastSteps = focusState.lastAnnouncedSteps,
                      !wasInCountdown,
                      focused.steps > lastSteps + configuration.releaseStepIncrease {
                // user moving away (step count increasing), release unless in countdown
                focusState.releaseFocus()
            }
        }
        
        // 3. sudden close-range appearance
        for candidate in candidates {
            
            if candidate.isNew
                && candidate.steps <= configuration.suddenAppearanceThreshold
                && candidate.isCenter {
                
                // during countdown, only <= 1 step can interrupt
                if isCountdownActive && candidate.steps > configuration.urgentStepThreshold {
                    continue
                }
                
                let text: String
                if candidate.steps <= configuration.urgentStepThreshold {
                    text = formatter.urgentText(for: candidate, mode: distanceMode)
                    speech.speakInterrupting(text)
                } else {
                    text = formatter.fullText(for: candidate, mode: distanceMode)
                    speech.speak(text)
                }
                
                focusState.focus(on: candidate, now: now)
                focusState.previousIDs = currentIDs
                return
            }
        }
        
        // 4. select new focus
        if focusState.focusedObjectID == nil {
            
            // try to recover: same label, similar steps, within 1s of release
            if let metadata = focusState.lastFocusMetadata, now.timeIntervalSince(metadata.time) < 1.0 {
                if let recovered = candidates.first(where: {
                    $0.detection.label == metadata.label &&
                    abs($0.steps - metadata.steps) <= 2
                }) {
                    focusState.recoverFocus(on: recovered)
                }
            }
            
            // if recovery failed, pick best: centre-path nearest, then side <= 3 steps
            if focusState.focusedObjectID == nil {
                let best = candidates.first(where: { $0.isCenter })
                    ?? candidates.first(where: { $0.steps <= 3 })
                if let candidate = best {
                    let text = formatter.fullText(for: candidate, mode: distanceMode)
                    speech.speak(text)
                    focusState.focus(on: candidate, now: now)
                    focusState.previousIDs = currentIDs
                    return
                }
            }
        }
        
        // 5. update focused object
        if let focusID = focusState.focusedObjectID,
           let candidate = candidates.first(where: { $0.detection.id == focusID }) {
            
            // refresh real-time steps for handleStep() to read
            focusState.refreshCurrentFocus(candidate)
            
            if distanceMode == .meters {
                metresPolicy.updateInMetersMode(
                    candidate: candidate,
                    direction: candidate.direction,
                    now: now,
                    focusState: &focusState,
                    configuration: configuration,
                    formatter: formatter,
                    speech: speech,
                    distanceMode: distanceMode
                )
                focusState.previousIDs = currentIDs
                return
            }
            
            if stepsPolicy.updateInStepsMode(
                candidate: candidate,
                now: now,
                isConfirmedStepUpdate: isConfirmedStepUpdate,
                distanceMode: distanceMode,
                focusState: &focusState,
                configuration: configuration,
                visualCountdownFallbackDelay: visualCountdownFallbackDelayProvider(),
                formatter: formatter,
                countdownController: countdownController,
                speech: speech
            ) {
                focusState.previousIDs = currentIDs
                return
            }
        }
        focusState.previousIDs = currentIDs
    }
    
    // step-driven
    // metres mode: step events don't trigger speech
    func handleStep(with detections: [Detection]) {
        
        if distanceMode == .meters { return }
        
        focusState.lastConfirmedStepTime = Date()
        
        // refresh focus with latest detections before advancing countdown
        update(with: detections, isConfirmedStepUpdate: true)
        
        countdownController.handleConfirmedStep(
            focusState: &focusState,
            configuration: configuration,
            formatter: formatter,
            speech: speech
        )
    }
}
