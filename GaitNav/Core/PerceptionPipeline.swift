import ARKit
import Combine

// top-level coordinator for the perception system
// 1. manages ARSession
// 2. detect -> estimate distance -> track on each frame
// 3. publishes stable results to UI
class PerceptionPipeline: NSObject, ObservableObject {
    
    let session = ARSession()
    
    // background queue for inference + distance estimation so they don't block UI
    private let frameProcessingQueue = DispatchQueue(label: "com.gaitnav.perception.frameProcessing", qos: .userInitiated)
    
    @Published var detections: [Detection] = []
    
    private var detector: Detector?
    private let distanceEstimator = DistanceEstimator()
    private let tracker = ObjectTracker()
    
    // only read/written on frameProcessingQueue to avoid races
    private var isProcessing = false
    
    @Published var fps: Double = 0
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    func start() {
        
        startSession()
        
        // detector loaded on background thread, frames are skipped until ready
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loadedDetector = Detector()
            self?.frameProcessingQueue.async {
                self?.detector = loadedDetector
            }
        }
    }
    
    private func startSession() {
        
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
            print("LiDAR available, depth capture enabled.")
        } else {
            print("This device does not support LiDAR.")
        }
        
        // frame callbacks go to background queue, not main thread
        session.delegateQueue = frameProcessingQueue
        session.delegate = self
        session.run(config)
    }
}

extension PerceptionPipeline: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        guard !isProcessing else { return }
        guard let detector = self.detector else { return }
        
        isProcessing = true
        
        let image = frame.capturedImage
        let depthMap = frame.sceneDepth?.depthMap
        let confidenceMap = frame.sceneDepth?.confidenceMap
        let intrinsics = frame.camera.intrinsics
        let cameraTransform = frame.camera.transform
        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        
        detector.detect(pixelBuffer: image) { [weak self] detections in
            
            guard let self = self else { return }
            
            // raw detections (no distance)
            var results = detections
            
            // attach distance to each raw detection -> complete raw detection
            if let depthMap = depthMap {
                for i in results.indices {
                    results[i].distance = self.distanceEstimator.getDistance(
                        boundingBox: results[i].boundingBox,
                        depthMap: depthMap,
                        confidenceMap: confidenceMap,
                        intrinsics: intrinsics,
                        cameraTransform: cameraTransform,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                }
            }
            
            // back to main thread for tracking + UI update
            DispatchQueue.main.async {
                // raw detections -> stable detections
                self.tracker.update(with: results)
                self.detections = self.tracker.stableDetections
                self.updateFPS()
                self.frameProcessingQueue.async {
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSUpdate = now
        }
    }
}
