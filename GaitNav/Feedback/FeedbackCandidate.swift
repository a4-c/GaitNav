import Foundation

// 把 Detection 和计算出的附加信息打包在一起
// 只在 FeedbackPipeline 内部使用
struct FeedbackCandidate {
    let detection: Detection
    let distance: Float
    let steps: Int
    let stableSteps: Int
    let adaptiveSteps: Int
    // 时钟方位（"12 o'clock"）
    let direction: String
    // 是否在行走路径中央（midX 在 0.35~0.65 之间）
    let isCenter: Bool
    // 是否这帧刚出现（上一帧不存在）
    let isNew: Bool
}
