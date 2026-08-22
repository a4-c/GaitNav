import Foundation

protocol StepDistanceConverting: AnyObject {
    func distanceToSteps(_ distance: Float) -> Int
    func distanceToStableSteps(_ distance: Float) -> Int
}

final class StepLengthResolver {
    
    // which tier the current effectiveStepLength comes from, for UI
    enum Source {
        case dynamic, calibrated, defaultValue
    }
    
    private let dynamicEstimator: DynamicStepEstimator
    private let calibrator: Calibrator
    
    private let defaultStepLength: Float
    
    init(dynamicEstimator: DynamicStepEstimator, calibrator: Calibrator, defaultStepLength: Float = 0.65) {
        self.dynamicEstimator = dynamicEstimator
        self.calibrator = calibrator
        self.defaultStepLength = defaultStepLength
    }
    
    // dynamic -> calibrated -> default (0.65m)
    // uncalibrated users always get default, skipping dynamic entirely
    var effectiveStepLength: Float {
        guard let calibrated = calibrator.effectiveStepLength else {
            return defaultStepLength
        }
        if let dynamic = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return dynamic
        }
        return calibrated
    }
    
    // calibrated -> default only
    var stableStepLength: Float {
        return calibrator.effectiveStepLength ?? defaultStepLength
    }
    
    var stepLengthSource: Source {
        guard calibrator.effectiveStepLength != nil else {
            return .defaultValue
        }
        if let _ = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return .dynamic
        }
        if calibrator.effectiveStepLength != nil {
            return .calibrated
        }
        return .defaultValue
    }
    
    var isDynamicActive: Bool {
        return calibrator.effectiveStepLength != nil && dynamicEstimator.isActive
    }
    
    // distance -> steps (using effective)
    func distanceToSteps(_ distance: Float) -> Int {
        let steps = distance / effectiveStepLength
        return Int(ceil(steps))
    }
    
    // distance -> steps (using stable)
    func distanceToStableSteps(_ distance: Float) -> Int {
        return Int(ceil(distance / stableStepLength))
    }
}
