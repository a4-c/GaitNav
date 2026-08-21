import Foundation
import ARKit

// matches raw detections to existing tracked objects via IoU
// stabilises labels and distances
class ObjectTracker {
    
    private var trackedObjects: [TrackedObject] = []
    
    // 0.3 is loose enough to tolerate camera shake during walking
    private let iouThreshold: CGFloat = 0.3
    
    private let maxMissedFrames = 3
    let minAgeToShow = 2
    private let maxLabelHistory = 10
    // 3-frame median: filters single-frame noise with only 1 frame of lag
    private let maxDistanceHistory = 3
    
    // only output objects that have existed for at least minAgeToShow frames
    var stableDetections: [Detection] {
        trackedObjects
            .filter { $0.age >= minAgeToShow }
            .map { tracked in
                Detection(
                    id: tracked.id,
                    label: tracked.stableLabel,
                    confidence: tracked.confidence,
                    boundingBox: tracked.boundingBox,
                    distance: tracked.stableDistance
                )
            }
    }
    
    // match -> update -> create new -> remove missing
    func update(with rawDetections: [RawDetection]) {
        
        var matchedTrackedIDs = Set<UUID>()
        var matchedDetectionIndices = Set<Int>()
        
        // 1. find best IoU match for each detection (greedy, one-to-one)
        for (detIndex, rawDetection) in rawDetections.enumerated() {
            
            var bestIoU: CGFloat = 0
            var bestTrackedIndex: Int? = nil
            
            for (trackedIndex, tracked) in trackedObjects.enumerated() {
                if matchedTrackedIDs.contains(tracked.id) { continue }
                let overlap = iou(rawDetection.boundingBox, tracked.boundingBox)
                if overlap > bestIoU {
                    bestIoU = overlap
                    bestTrackedIndex = trackedIndex
                }
            }
            
            // 2. if matched, update tracked object
            if bestIoU > iouThreshold, let idx = bestTrackedIndex {
                
                matchedTrackedIDs.insert(trackedObjects[idx].id)
                matchedDetectionIndices.insert(detIndex)
                
                trackedObjects[idx].boundingBox = rawDetection.boundingBox
                trackedObjects[idx].confidence = rawDetection.confidence
                trackedObjects[idx].missedFrames = 0
                trackedObjects[idx].age += 1
                
                trackedObjects[idx].labelHistory.append(rawDetection.label)
                if trackedObjects[idx].labelHistory.count > maxLabelHistory {
                    trackedObjects[idx].labelHistory.removeFirst()
                }
                
                if let newDist = rawDetection.distance {
                    trackedObjects[idx].distanceHistory.append(newDist)
                    if trackedObjects[idx].distanceHistory.count > maxDistanceHistory {
                        trackedObjects[idx].distanceHistory.removeFirst()
                    }
                }
            }
        }
        
        // 3. unmatched detections become new tracked objects
        for (detIndex, rawDetection) in rawDetections.enumerated() {
            if matchedDetectionIndices.contains(detIndex) { continue }
            let initialHistory: [Float] = rawDetection.distance.map { [$0] } ?? []
            trackedObjects.append(TrackedObject(
                id: UUID(),
                boundingBox: rawDetection.boundingBox,
                labelHistory: [rawDetection.label],
                confidence: rawDetection.confidence,
                distanceHistory: initialHistory,
                missedFrames: 0,
                age: 1
            ))
        }
        
        // 4. increment missed count for unmatched tracked objects
        for i in trackedObjects.indices {
            if !matchedTrackedIDs.contains(trackedObjects[i].id) {
                trackedObjects[i].missedFrames += 1
            }
        }
        
        // 5. remove objects that have been missing too long
        // close objects get longer tolerance to survive camera shake
        trackedObjects.removeAll { tracked in
            var allowedMissed = maxMissedFrames
            if let lastDist = tracked.stableDistance, lastDist < 3.5 {
                allowedMissed = 10
            }
            return tracked.missedFrames > allowedMissed
        }
    }
    
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
