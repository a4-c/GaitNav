import Foundation

// 把 Detection 和计算出的附加信息打包在一起
// 只在 FeedbackEngine 内部使用
struct FeedbackCandidate {
    let detection: Detection
    let distance: Float
    let steps: Int
    let stableSteps: Int
    let adaptiveSteps: Int
    // 时钟方位（"12 o'clock"）
    let direction: String
    // 是否在行走路径中央（midX 当前由 FeedbackConfiguration.sideMargin 控制为 0.25~0.75）
    // 该字段用于过滤远处侧边物体，保证路径中央判断与 12 点钟方位范围保持一致
    let isCenter: Bool
    // 是否这帧刚出现（上一帧不存在）
    let isNew: Bool
}
