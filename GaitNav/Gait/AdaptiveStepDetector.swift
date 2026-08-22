import Foundation

// profile = peakDevEma & intervalEma
struct StepDetectionProfile {
    let peakDevEma: Double
    let intervalEma: TimeInterval
}

// dual-threshold hysteresis (Schmitt trigger) step detector with EMA-adaptive thresholds
// signal must rise above TH_HIGH then fall below TH_LOW to confirm one peak
// peaks then pass a minimum interval check before being accepted as a step
// EMA tracks recent peak strength and step interval to adapt thresholds per user
struct AdaptiveStepDetector {
    
    private let configuration: StepDetectionConfiguration
    
    private enum PeakDetectionState {
        case waitingPeak
        case trackingPeak
    }
    
    private var currentState: PeakDetectionState = .waitingPeak
    // max (acceleration magnitude) deviation above gravity during current peak
    private var trackingMaxDev: Double = 0
    
    // EMA of recent peak deviations -> derives TH_HIGH and TH_LOW
    private var peakDevEma: Double
    // EMA of recent step intervals -> derives minimum step interval
    private var intervalEma: TimeInterval
    
    // for step interval check and decay
    private var lastAcceptedStepTime: Date = .distantPast
    
    // can use learned EMAs from profiling, otherwise use defaults
    init(configuration: StepDetectionConfiguration = StepDetectionConfiguration(), profile: StepDetectionProfile? = nil) {
        self.configuration = configuration
        self.peakDevEma = profile?.peakDevEma ?? configuration.defaultPeakDevEma
        self.intervalEma = profile?.intervalEma ?? configuration.defaultIntervalEma
    }
    
    // snapshot of current EMAs for profiling to save
    var currentProfile: StepDetectionProfile {
        return StepDetectionProfile(peakDevEma: peakDevEma, intervalEma: intervalEma)
    }
    
    // TH_HIGH = gravity + peakEMA * peakRatio
    private var thresholdHigh: Double {
        configuration.gravityBaseline + peakDevEma * configuration.peakThresholdRatio
    }
    
    // TH_LOW = gravity + peakEMA * peakRatio * hysteresisRatio
    private var thresholdLow: Double {
        configuration.gravityBaseline + peakDevEma * configuration.peakThresholdRatio * configuration.hysteresisRatio
    }
    
    // dynamic min interval = max(intervalEMA * guardRatio, absolute floor)
    private var effectiveMinStepInterval: TimeInterval {
        max(intervalEma * configuration.intervalGuardRatio, configuration.minAbsoluteInterval)
    }
    
    // called on each accelerometer sample, returns true if a step is confirmed
    mutating func process(magnitude: Double, at now: Date) -> Bool {
        
        var didConfirmStep = false
        
        switch currentState {
            
            case .waitingPeak:
                if magnitude > thresholdHigh {
                    currentState = .trackingPeak
                    trackingMaxDev = magnitude - configuration.gravityBaseline
                }
                
            case .trackingPeak:
                let currentDev = magnitude - configuration.gravityBaseline
                if currentDev > trackingMaxDev {
                    trackingMaxDev = currentDev
                }
                if magnitude < thresholdLow {
                    didConfirmStep = confirmPeak(peakDeviation: trackingMaxDev, at: now)
                    currentState = .waitingPeak
                }
        }
        
        checkDecay(at: now)
        return didConfirmStep
    }
    
    // checks this peak is a new step -> if it is, updates EMAs and returns true
    private mutating func confirmPeak(peakDeviation: Double, at now: Date) -> Bool {
        
        let interval = now.timeIntervalSince(lastAcceptedStepTime)
        guard interval > effectiveMinStepInterval else { return false }
        
        peakDevEma = configuration.emaAlpha * peakDeviation + (1 - configuration.emaAlpha) * peakDevEma
        
        // only update interval EMA within normal walking range
        if interval > configuration.minAbsoluteInterval && interval < 2.0 {
            intervalEma = configuration.emaAlpha * interval + (1 - configuration.emaAlpha) * intervalEma
        }
        
        lastAcceptedStepTime = now
        return true
    }
    
    // if no step accepted for too long, decay peakEMA toward default
    // prevents threshold from staying too high after fast walking stops
    private mutating func checkDecay(at now: Date) {
        let timeSinceLastAcceptedStep = now.timeIntervalSince(lastAcceptedStepTime)
        if timeSinceLastAcceptedStep > configuration.decayTimeout && peakDevEma > configuration.defaultPeakDevEma {
            peakDevEma = max(peakDevEma * 0.998, configuration.defaultPeakDevEma)
        }
    }
    
    // clear state on mode switch
    mutating func resetDetectionState() {
        currentState = .waitingPeak
        trackingMaxDev = 0
        lastAcceptedStepTime = .distantPast
    }
    
    // apply saved profiling EMAs and reset state
    mutating func applyProfile(_ profile: StepDetectionProfile) {
        peakDevEma = profile.peakDevEma
        intervalEma = profile.intervalEma
        resetDetectionState()
    }
    
    // reset EMAs to defaults for new profiling
    mutating func resetToDefaultProfile() {
        peakDevEma = configuration.defaultPeakDevEma
        intervalEma = configuration.defaultIntervalEma
        resetDetectionState()
    }
}
