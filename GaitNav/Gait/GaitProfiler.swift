import Foundation
import Combine

// lets the adaptive step detector converge to the user's gait
// does no signal processing itself, just manages start/stop and saves the converged EMAs
class GaitProfiler: ObservableObject {
    
    @Published var isProfiling = false
    @Published var profilingSteps = 0
    @Published var profilingSeconds = 0
    @Published var statusMessage = ""
    @Published var profiledPeakDevEma: Double? = nil
    @Published var profiledIntervalEma: TimeInterval? = nil
    
    private var timer: Timer?
    
    private let peakDevEmaKey = "profiledPeakDevEma"
    private let intervalEmaKey = "profiledIntervalEma"
    
    // saved profiling results, nil if never profiled
    var effectivePeakDevEma: Double? {
        let saved = UserDefaults.standard.double(forKey: peakDevEmaKey)
        return saved > 0 ? saved : nil
    }
    
    var effectiveIntervalEma: TimeInterval? {
        let saved = UserDefaults.standard.double(forKey: intervalEmaKey)
        return saved > 0 ? saved : nil
    }
    
    var hasEverProfiled: Bool {
        UserDefaults.standard.double(forKey: peakDevEmaKey) > 0
    }
    
    // notify GaitCoordinator of mode changes
    var onProfilingStarted: (() -> Void)?
    var onProfilingStopped: (() -> Void)?
    
    init() {
        let savedPeakDev = UserDefaults.standard.double(forKey: peakDevEmaKey)
        let savedInterval = UserDefaults.standard.double(forKey: intervalEmaKey)
        if savedPeakDev > 0 {
            profiledPeakDevEma = savedPeakDev
            profiledIntervalEma = savedInterval > 0 ? savedInterval : nil
            let intervalStr = savedInterval > 0
                ? ", interval: \(String(format: "%.2f", savedInterval))s"
                : ""
            statusMessage = "Saved peak EMA: \(String(format: "%.3f", savedPeakDev))g\(intervalStr)"
        } else {
            statusMessage = "Not profiled. Using defaults."
        }
    }
    
    // called by GaitCoordinator on each step during profiling
    func handleStep() {
        guard isProfiling else { return }
        profilingSteps += 1
    }
    
    func startProfiling() {
        
        profilingSteps = 0
        profilingSeconds = 0
        profiledPeakDevEma = nil
        profiledIntervalEma = nil
        isProfiling = true
        statusMessage = "Walk now..."
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.profilingSeconds += 1
        }
        
        onProfilingStarted?()
    }
    
    func stopProfiling() {
        isProfiling = false
        timer?.invalidate()
        timer = nil
        onProfilingStopped?()
    }
    
    // called by GaitCoordinator with the detector's converged EMAs after profiling
    func saveProfile(peakDevEma: Double, intervalEma: TimeInterval) {
        
        // need 8+ steps so EMA has converged
        guard profilingSteps >= 8 else {
            statusMessage = "Too few steps (\(profilingSteps)). Walk more actively."
            return
        }
        
        // reject if either EMA is outside reasonable range
        guard peakDevEma > 0.02 && peakDevEma < 1.0 else {
            statusMessage = "Result unreasonable. Please retry."
            return
        }
        
        guard intervalEma > 0.2 && intervalEma < 2.0 else {
            statusMessage = "Result unreasonable. Please retry."
            return
        }
        
        // save result
        profiledPeakDevEma = peakDevEma
        UserDefaults.standard.set(peakDevEma, forKey: peakDevEmaKey)
        profiledIntervalEma = intervalEma
        UserDefaults.standard.set(intervalEma, forKey: intervalEmaKey)
        
        let intervalStr = profiledIntervalEma != nil
            ? ", interval: \(String(format: "%.2f", profiledIntervalEma!))s"
            : ""
        statusMessage = "Done! \(profilingSteps) steps → peak EMA: \(String(format: "%.3f", peakDevEma))g\(intervalStr)"
    }
}
