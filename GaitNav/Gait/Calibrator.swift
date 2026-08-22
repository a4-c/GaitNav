import ARKit
import Combine

// guided calibration:
// user walks a straight line, system measures horizontal displacement and divides by step count
class Calibrator: ObservableObject {
    
    weak var arSession: ARSession?
    
    @Published var calibratedStepLength: Float? = nil
    @Published var isCalibrating: Bool = false
    @Published var calibrationSteps: Int = 0
    @Published var calibrationDistance: Float? = nil
    @Published var statusMessage: String = ""
    
    private var startPosition: SIMD3<Float>? = nil
    private let stepLengthKey = "calibratedStepLength"
    
    // notify GaitCoordinator of mode changes
    var onCalibrationStarted: (() -> Void)?
    var onCalibrationStopped: (() -> Void)?
    
    // returns saved step length, or nil if never calibrated
    var effectiveStepLength: Float? {
        let saved = UserDefaults.standard.float(forKey: stepLengthKey)
        return saved > 0 ? saved : nil
    }
    
    var hasEverCalibrated: Bool {
        UserDefaults.standard.float(forKey: stepLengthKey) > 0
    }
    
    init() {
        let saved = UserDefaults.standard.float(forKey: stepLengthKey)
        if saved > 0 {
            calibratedStepLength = saved
            statusMessage = "Saved step length: \(String(format: "%.2f", saved))m"
        } else {
            statusMessage = "Not calibrated. Using default: 0.65m"
        }
    }
    
    // called by GaitCoordinator on each detected step during calibration
    func handleStep() {
        guard isCalibrating else { return }
        calibrationSteps += 1
        statusMessage = "\(calibrationSteps) steps..."
    }
    
    func clearCalibratedStepLength() {
        UserDefaults.standard.removeObject(forKey: stepLengthKey)
        calibratedStepLength = nil
        calibrationDistance = nil
        calibrationSteps = 0
        statusMessage = "Calibration cleared. Using default: 0.65m"
    }
    
    func startCalibration() {
        
        guard let frame = arSession?.currentFrame else {
            statusMessage = "ARKit not ready. Please wait."
            return
        }
        
        // record start position
        let pos = frame.camera.transform.columns.3
        startPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        
        calibrationSteps = 0
        calibrationDistance = nil
        calibratedStepLength = nil
        isCalibrating = true
        statusMessage = "Walk now..."
        
        onCalibrationStarted?()
    }
    
    func stopCalibration() {
        
        isCalibrating = false
        
        guard let startPos = startPosition else {
            statusMessage = "Error: no start position."
            onCalibrationStopped?()
            return
        }
        
        guard let frame = arSession?.currentFrame else {
            statusMessage = "Error: ARKit not available."
            onCalibrationStopped?()
            return
        }
        
        let finalSteps = calibrationSteps
        
        // need at least 5 steps for a reliable average
        guard finalSteps >= 5 else {
            statusMessage = "Too few steps (\(finalSteps)). Walk at least 5 steps."
            onCalibrationStopped?()
            return
        }
        
        // horizontal distance
        let endPos = frame.camera.transform.columns.3
        let endPosition = SIMD3<Float>(endPos.x, endPos.y, endPos.z)
        let dx = endPosition.x - startPos.x
        let dz = endPosition.z - startPos.z
        let distance = sqrtf(dx * dx + dz * dz)
        
        // too short might mean walking in circles or standing in place
        guard distance > 1.0 else {
            statusMessage = "Distance too short (\(String(format: "%.1f", distance))m). Walk in a straight line."
            onCalibrationStopped?()
            return
        }
        
        let stepLength = distance / Float(finalSteps)
        
        // outside 0.2-1.0m means something went wrong
        guard stepLength > 0.2 && stepLength < 1.0 else {
            statusMessage = "Result unreasonable (\(String(format: "%.2f", stepLength))m/step). Please retry."
            onCalibrationStopped?()
            return
        }
        
        // save result
        calibratedStepLength = stepLength
        calibrationDistance = distance
        UserDefaults.standard.set(stepLength, forKey: stepLengthKey)
        statusMessage = "Done! \(finalSteps) steps, \(String(format: "%.1f", distance))m → step: \(String(format: "%.2f", stepLength))m"
        startPosition = nil
        
        onCalibrationStopped?()
    }
}
