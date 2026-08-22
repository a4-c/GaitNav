import Foundation

// parameters for the adaptive step detector
struct StepDetectionConfiguration {
    
    // 20Hz = one sample every 50ms, gives 8-13 samples per step at normal pace
    let accelerometerUpdateInterval: TimeInterval = 1.0 / 20.0
    
    let gravityBaseline: Double = 1.0
    
    // after 5 steps: (0.8)^5 = 0.33 initial weight, after 10: (0.8)^10 = 0.11
    let emaAlpha: Double = 0.2
    
    // TH_HIGH = gravity + peakEMA * 0.7
    // 70% of recent average peak
    let peakThresholdRatio: Double = 0.7
    
    // standard Schmitt trigger hysteresis band (40-60%)
    let hysteresisRatio: Double = 0.6
    
    // min step interval = intervalEMA * 0.7
    // rejects same-step bounce while allowing slightly faster pace
    let intervalGuardRatio: Double = 0.7
    
    // absolute floor for step interval
    // 0.2s = 5 steps/sec, beyond human limit
    let minAbsoluteInterval: TimeInterval = 0.2
    
    // start decaying EMA toward default after 2s with no accepted step
    // 2s is about 4 normal steps
    let decayTimeout: TimeInterval = 2.0
    
    // conservative defaults for first-time use before profiling
    let defaultPeakDevEma: Double = 0.05
    let defaultIntervalEma: TimeInterval = 0.5
}
