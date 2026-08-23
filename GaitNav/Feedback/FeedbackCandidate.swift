import Foundation

// Detection + computed feedback info
struct FeedbackCandidate {
    let detection: Detection
    let distance: Float
    // which step count is actually used (stable or adaptive depending on context)
    let steps: Int
    let stableSteps: Int
    let adaptiveSteps: Int
    let direction: String
    let isCenter: Bool
    // whether first appeared this frame
    let isNew: Bool
}
