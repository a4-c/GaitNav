import Foundation

// saved when focus is released, used to recover if it's the same object with a new ID
struct FeedbackFocusMetadata {
    let label: String
    // lastAnnouncedSteps at release
    let steps: Int
    // lastAnnouncedDirection at release
    let direction: String?
    // lastAnnouncedDistance at release
    let distance: Float?
    // when focus was released
    let time: Date
    let lastAnnouncedTime: Date
}

// tracks the single obstacle the feedback engine is currently following
struct FeedbackFocusState {
    
    var focusedObjectID: UUID? = nil
    var focusedObjectLabel: String? = nil
    
    // what was last spoken (for threshold/direction change checks)
    var lastAnnouncedSteps: Int? = nil
    var lastAnnouncedDirection: String? = nil
    var lastAnnouncedDistance: Float? = nil
    var lastAnnouncementTime: Date = .distantPast
    
    // refreshed by update() every frame
    var focusedCurrentSteps: Int? = nil
    var focusedCurrentDistance: Float? = nil
    
    // visual fallback checks this to decide whether to wait for a step event
    var lastConfirmedStepTime: Date = .distantPast
    
    // IDs from last frame, used to detect newly appeared objects
    var previousIDs: Set<UUID> = []
    
    // metadata from the most recently released focus
    var lastFocusMetadata: FeedbackFocusMetadata? = nil
    
    // save metadata snapshot before clearing, for recovery matching
    mutating func releaseFocus() {
        
        if let label = focusedObjectLabel, let steps = lastAnnouncedSteps {
            lastFocusMetadata = FeedbackFocusMetadata(
                label: label,
                steps: steps,
                direction: lastAnnouncedDirection,
                distance: lastAnnouncedDistance,
                time: Date(),
                lastAnnouncedTime: lastAnnouncementTime
            )
        }
        
        focusedObjectID = nil
        focusedObjectLabel = nil
        lastAnnouncedSteps = nil
        lastAnnouncedDirection = nil
        focusedCurrentSteps = nil
        focusedCurrentDistance = nil
        lastAnnouncedDistance = nil
    }
    
    // new focus acquired, record initial state
    mutating func focus(on candidate: FeedbackCandidate, now: Date) {
        focusedObjectID = candidate.detection.id
        focusedObjectLabel = candidate.detection.label
        lastAnnouncedSteps = candidate.steps
        lastAnnouncedDirection = candidate.direction
        focusedCurrentSteps = candidate.steps
        focusedCurrentDistance = candidate.distance
        lastAnnouncedDistance = candidate.distance
        lastAnnouncementTime = now
    }
    
    // matched as the same object that was just released (same label, similar steps, within 1s)
    // restore previous announcement state so it continues without a new first announcement
    mutating func recoverFocus(on recovered: FeedbackCandidate) {
        guard let metadata = lastFocusMetadata else { return }
        focusedObjectID = recovered.detection.id
        focusedObjectLabel = recovered.detection.label
        lastAnnouncedSteps = metadata.steps
        lastAnnouncedDirection = metadata.direction
        lastAnnouncedDistance = metadata.distance
        lastAnnouncementTime = metadata.lastAnnouncedTime
        lastFocusMetadata = nil
    }
    
    mutating func refreshCurrentFocus(_ candidate: FeedbackCandidate) {
        focusedCurrentSteps = candidate.steps
        focusedCurrentDistance = candidate.distance
    }
}
