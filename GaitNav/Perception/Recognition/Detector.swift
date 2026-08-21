import Vision
import CoreML
import UIKit

class Detector {
    
    private var vnModel: VNCoreMLModel?
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            // let the system pick the fastest compute unit
            config.computeUnits = .all
            // yolov8s class is auto-generated from the .mlpackage
            let coreMLModel = try yolov8s(configuration: config).model
            vnModel = try VNCoreMLModel(for: coreMLModel)
        } catch {
            print("Failed to load model: \(error)")
        }
    }
    
    // a camera image -> raw detections (no distance)
    func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([RawDetection]) -> Void) {
        
        guard let vnModel = vnModel else {
            completion([])
            return
        }
        
        let request = VNCoreMLRequest(model: vnModel) { request, error in
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            let detections = results.compactMap { observation -> RawDetection? in
                guard let topLabel = observation.labels.first else { return nil }
                guard topLabel.confidence > 0.5 else { return nil }
                return RawDetection(
                    label: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            
            completion(detections)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        // .right because the camera captures landscape, but the app is portrait
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        
        try? handler.perform([request])
    }
}
