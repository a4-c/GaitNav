import Foundation
import CoreGraphics

struct FeedbackConfiguration {
    
    // steps mode
    
    // far-range thresholds, announce when step count crosses these
    let stepThresholds: [Int] = [12, 9]
    
    // countdown starts at this step count
    let countdownThreshold = 5
    
    // <= 1 step = urgent, say Stop (or full warning if not in countdown)
    let urgentStepThreshold = 1
    
    let finalCountdownText = "Stop"
    
    // correction triggers when expected vs real-time steps differ by this much
    let correctionStepDelta = 2
    
    // new object within this many steps can take over focus
    let suddenAppearanceThreshold = 3
    
    // metres mode
    
    // announce when distance crosses these (far to near)
    let meterThresholds: [Float] = [5.0, 3.0, 2.0, 1.0]
    
    // below this = Stop
    let urgentMeterThreshold: Float = 0.5
    
    // filtering
    
    // outside 0.25-0.75 = side object
    let sideMargin: CGFloat = 0.25
    
    var centerLowerBound: CGFloat {
        sideMargin
    }
    var centerUpperBound: CGFloat {
        1.0 - sideMargin
    }
    
    // side objects beyond this step count are ignored
    let sideIgnoreSteps = 5
    
    // step count increased by more than this since last announcement = user moving away
    let releaseStepIncrease = 3
    
    // timing
    
    // far-range: min gap between announcements
    let minAnnouncementInterval: TimeInterval = 1.5
    
    // countdown: only prevents duplicate speech from same event chain
    let countdownMinInterval: TimeInterval = 0.25
    
    // default fallback delay when step detector misses a step
    // in practice, GaitCoordinator provides a dynamic value based on intervalEma
    let visualCountdownFallbackDelay: TimeInterval = 0.55
    
    // min gap between visual fallback announcements
    let visualCountdownMinInterval: TimeInterval = 0.75
}
