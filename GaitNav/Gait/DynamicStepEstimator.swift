import ARKit

// estimates step length in real time during walking
class DynamicStepEstimator {
    
    weak var arSession: ARSession?
    
    private var lastStepPosition: SIMD3<Float>? = nil
    private var recentStepLengths: [Float] = []
    
    // ~3-4 seconds of walking data at normal pace
    private let windowSize = 6
    
    // if no valid step length produced within this time, dynamic value expires
    let timeout: TimeInterval = 3.0
    var lastUpdateTime: Date = .distantPast
    
    private(set) var currentStepLength: Float? = nil
    
    var isActive: Bool {
        currentStepLength != nil && Date().timeIntervalSince(lastUpdateTime) < timeout
    }
    
    // called by GaitCoordinator on each detected step
    func handleStep() {
        
        let now = Date()
        // if expired, clear old window before processing new step
        resetIfNeeded(now: now)
        
        guard let frame = arSession?.currentFrame else { return }
        
        let pos = frame.camera.transform.columns.3
        let currentPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        
        if let lastPos = lastStepPosition {
            
            // horizontal displacement
            let dx = currentPosition.x - lastPos.x
            let dz = currentPosition.z - lastPos.z
            let stepDist = sqrtf(dx * dx + dz * dz)
            
            // 0.2-1.2m validity range (single-step measurements have more variance)
            if stepDist > 0.2 && stepDist < 1.2 {
                recentStepLengths.append(stepDist)
                if recentStepLengths.count > windowSize {
                    recentStepLengths.removeFirst()
                }
                // need at least 2 steps before outputting
                if recentStepLengths.count >= 2 {
                    let avg = recentStepLengths.reduce(0, +) / Float(recentStepLengths.count)
                    currentStepLength = avg
                    lastUpdateTime = now
                }
            }
        }
        
        lastStepPosition = currentPosition
    }
    
    // if dynamic value has expired, clear the window so resumed walking starts fresh
    private func resetIfNeeded(now: Date) {
        // still in cold start, don't clear
        guard currentStepLength != nil else { return }
        guard now.timeIntervalSince(lastUpdateTime) >= timeout else { return }
        reset()
    }
    
    func reset() {
        lastStepPosition = nil
        recentStepLengths = []
        currentStepLength = nil
        lastUpdateTime = .distantPast
    }
    
    // For testing
    #if DEBUG
    func _setForTesting(stepLength: Float) {
        currentStepLength = stepLength
        lastUpdateTime = Date()
    }
    #endif
}
