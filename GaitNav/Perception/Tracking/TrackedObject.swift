import Foundation

// a single object tracked across frames
// holds label history and distance history
struct TrackedObject {
    
    let id: UUID
    var boundingBox: CGRect
    var labelHistory: [String]
    var confidence: Float
    var distanceHistory: [Float]
    
    // how many consecutive frames this object was not matched
    var missedFrames: Int
    
    // total frames this object has existed, must reach minAgeToShow before being displayed
    var age: Int
    
    // most frequent label in recent history
    var stableLabel: String {
        let counts = Dictionary(grouping: labelHistory, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key ?? "?"
    }
    
    // median of recent distance values
    var stableDistance: Float? {
        guard !distanceHistory.isEmpty else { return nil }
        let sorted = distanceHistory.sorted()
        return sorted[sorted.count / 2]
    }
}
