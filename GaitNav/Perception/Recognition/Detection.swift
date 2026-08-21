import Foundation
import ARKit

// no ID yet
struct RawDetection {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    var distance: Float? = nil
}

// tracked detection with ID
struct Detection: Identifiable {
    
    let id: UUID
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    var distance: Float? = nil
    
    init(id: UUID = UUID(), label: String, confidence: Float, boundingBox: CGRect, distance: Float? = nil) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.distance = distance
    }
    
    // when a large bbox encloses a smaller one at similar distance, the smaller one is redundant (e.g cup on a table)
    // 3 conditions to suppress:
    // 1. large area > small area
    // 2. small bbox 75%+ covered by large bbox
    // 3. distance difference < 0.5m
    
    private static let containmentOverlapThreshold: CGFloat = 0.75
    private static let containmentDistanceTolerance: Float = 0.5
    
    // returns IDs of suppressed (inner) detections
    static func suppressedIDs(in detections: [Detection]) -> Set<UUID> {
        
        guard detections.count >= 2 else { return [] }
        
        var ids = Set<UUID>()
        
        for small in detections {
            
            let smallArea = small.boundingBox.width * small.boundingBox.height
            guard smallArea > 0 else { continue }
            
            for large in detections {
                
                guard large.id != small.id else { continue }
                // already suppressed detections can't suppress others
                guard !ids.contains(large.id) else { continue }
                
                let largeArea = large.boundingBox.width * large.boundingBox.height
                guard largeArea > smallArea else { continue }
                
                let intersection = small.boundingBox.intersection(large.boundingBox)
                guard !intersection.isNull else { continue }
                let overlapRatio = (intersection.width * intersection.height) / smallArea
                guard overlapRatio >= containmentOverlapThreshold else { continue }
                
                // both must have distance
                // if either is nil, keep both to be safe
                if let sd = small.distance, let ld = large.distance,
                   abs(sd - ld) <= containmentDistanceTolerance {
                    ids.insert(small.id)
                    break
                }
            }
        }
        
        return ids
    }
    
    // returns filtered detections with suppressed ones removed
    static func suppressContained(_ detections: [Detection]) -> [Detection] {
        let ids = suppressedIDs(in: detections)
        return ids.isEmpty ? detections : detections.filter { !ids.contains($0.id) }
    }
}
