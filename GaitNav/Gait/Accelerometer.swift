import CoreMotion
import Foundation

// samples acceleration at fixed rate & computes magnitude -> passes it to step detector
final class Accelerometer {
    
    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval
    private(set) var isRunning = false
    
    var isAvailable: Bool {
        return motionManager.isAccelerometerAvailable
    }
    
    init(updateInterval: TimeInterval) {
        self.updateInterval = updateInterval
    }
    
    func start(onMagnitudeReceived: @escaping (_ magnitude: Double, _ timestamp: Date) -> Void) {
        
        guard !isRunning else { return }
        guard motionManager.isAccelerometerAvailable else { return }
        isRunning = true
        
        motionManager.accelerometerUpdateInterval = updateInterval
        
        motionManager.startAccelerometerUpdates(to: .main) { data, error in
            
            guard let data = data else { return }
            
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let magnitude = sqrt(x * x + y * y + z * z)
            
            onMagnitudeReceived(magnitude, Date())
        }
    }
    
    func stop() {
        guard isRunning else { return }
        motionManager.stopAccelerometerUpdates()
        isRunning = false
    }
}
