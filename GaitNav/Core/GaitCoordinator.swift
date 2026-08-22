import ARKit
import Combine

// top-level coordinator for the gait module
// 1. owns all sub-modules (accelerometer, step detector, profiler, calibrator, dynamic estimator, resolver)
// 2. manages mode switching (profiling / calibration / live)
// 3. dispatches confirmed step events to the right sub-module
// 4. exposes distance-to-steps via StepDistanceConverting protocol
class GaitCoordinator: ObservableObject, StepDistanceConverting {
    
    @Published var gaitProfiler = GaitProfiler()
    @Published var calibrator = Calibrator()
    private let dynamicEstimator = DynamicStepEstimator()
    private let stepDetectionConfiguration = StepDetectionConfiguration()
    private lazy var accelerometer = Accelerometer(updateInterval: stepDetectionConfiguration.accelerometerUpdateInterval)
    private lazy var stepDetector = AdaptiveStepDetector(configuration: stepDetectionConfiguration)
    private lazy var stepLengthResolver = StepLengthResolver(dynamicEstimator: dynamicEstimator, calibrator: calibrator)
    
    private enum Mode {
        case profiling
        case live
        case calibration
    }
    
    private var currentMode: Mode = .live
    
    private var cancellables = Set<AnyCancellable>()
    
    // build profile from saved profiling results, or fall back to defaults
    private var savedDetectionProfile: StepDetectionProfile {
        return StepDetectionProfile(
            peakDevEma: gaitProfiler.effectivePeakDevEma ?? stepDetectionConfiguration.defaultPeakDevEma,
            intervalEma: gaitProfiler.effectiveIntervalEma ?? stepDetectionConfiguration.defaultIntervalEma
        )
    }
    
    // FeedbackEngine listens to this for step-synchronised countdown
    var onStepDetected: (() -> Void)?
    
    init() {
        
        stepDetector.applyProfile(savedDetectionProfile)
        
        gaitProfiler.onProfilingStarted = { [weak self] in
            self?.switchToProfilingMode()
        }
        gaitProfiler.onProfilingStopped = { [weak self] in
            guard let self = self else { return }
            let currentProfile = self.stepDetector.currentProfile
            self.gaitProfiler.saveProfile(
                peakDevEma: currentProfile.peakDevEma,
                intervalEma: currentProfile.intervalEma
            )
            self.switchToLiveMode()
        }
        
        calibrator.onCalibrationStarted = { [weak self] in
            self?.switchToCalibrationMode()
        }
        calibrator.onCalibrationStopped = { [weak self] in
            self?.switchToLiveMode()
        }
        
        // for UI
        gaitProfiler.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        calibrator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func setARSession(_ session: ARSession) {
        calibrator.arSession = session
        dynamicEstimator.arSession = session
    }
    
    typealias StepLengthSource = StepLengthResolver.Source
    
    var effectiveStepLength: Float {
        return stepLengthResolver.effectiveStepLength
    }
    
    var stableStepLength: Float {
        return stepLengthResolver.stableStepLength
    }
    
    var stepLengthSource: StepLengthSource {
        return stepLengthResolver.stepLengthSource
    }
    
    var hasEverCalibrated: Bool {
        calibrator.hasEverCalibrated
    }
    
    func clearCalibratedStepLength() {
        calibrator.clearCalibratedStepLength()
        dynamicEstimator.reset()
    }
    
    var hasEverProfiled: Bool {
        gaitProfiler.hasEverProfiled
    }
    
    var isDynamicActive: Bool {
        return stepLengthResolver.isDynamicActive
    }
    
    // visual countdown fallback waits one step interval + one sample period
    var visualCountdownFallbackDelay: TimeInterval {
        let currentStepInterval = stepDetector.currentProfile.intervalEma
        return currentStepInterval + stepDetectionConfiguration.accelerometerUpdateInterval
    }
    
    func distanceToSteps(_ distance: Float) -> Int {
        return stepLengthResolver.distanceToSteps(distance)
    }
    
    func distanceToStableSteps(_ distance: Float) -> Int {
        return stepLengthResolver.distanceToStableSteps(distance)
    }
    
    func start() {
        currentMode = .live
        startStepDetection()
    }
    
    func stop() {
        stopStepDetection()
    }
    
    // profiling: reset EMAs to defaults so they converge fresh
    private func switchToProfilingMode() {
        stopStepDetection()
        dynamicEstimator.reset()
        stepDetector.resetToDefaultProfile()
        currentMode = .profiling
        startStepDetection()
    }
    
    // calibration: load saved profile so step counting is accurate
    private func switchToCalibrationMode() {
        stopStepDetection()
        dynamicEstimator.reset()
        stepDetector.applyProfile(savedDetectionProfile)
        currentMode = .calibration
        startStepDetection()
    }
    
    // live: load saved profile and resume normal navigation
    private func switchToLiveMode() {
        stopStepDetection()
        stepDetector.applyProfile(savedDetectionProfile)
        currentMode = .live
        startStepDetection()
    }
    
    private func startStepDetection() {
        guard !accelerometer.isRunning else { return }
        guard accelerometer.isAvailable else { return }
        stepDetector.resetDetectionState()
        accelerometer.start { [weak self] magnitude, timestamp in
            guard let self = self else { return }
            guard self.stepDetector.process(magnitude: magnitude, at: timestamp) else { return }
            self.dispatchConfirmedStep()
        }
    }
    
    private func stopStepDetection() {
        accelerometer.stop()
    }
    
    // route step events based on current mode
    private func dispatchConfirmedStep() {
        
        switch currentMode {
            
            case .profiling:
                gaitProfiler.handleStep()
                
            case .calibration:
                calibrator.handleStep()
                
            case .live:
                // only feed dynamic estimator if calibrated, keeping uncalibrated users on fixed 0.65m
                if hasEverCalibrated {
                    dynamicEstimator.handleStep()
                    objectWillChange.send()
                }
                onStepDetected?()
        }
    }
}
