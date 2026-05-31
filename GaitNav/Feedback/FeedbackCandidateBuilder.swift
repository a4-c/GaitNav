import Foundation
import CoreGraphics

struct FeedbackCandidateBuilder {
    func buildCandidates(
        from detections: [Detection],
        previousIDs: Set<UUID>,
        // 只依赖距离转步数接口，避免反馈候选构建器感知完整的步态编排器
        stepDistanceConverter: StepDistanceConverting,
        distanceMode: FeedbackDistanceMode,
        isCountdownActive: Bool,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter
    ) -> [FeedbackCandidate] {
        
        // 大框里的小框（距离相似）不进入语音候选
        // currentIDs 仍然用原始 detections 构建，保证 previousIDs 跟踪不受影响
        let filteredDetections = Detection.suppressContained(detections)
        
        // 步数模式在倒数前使用稳定引导；米数模式保持原来的自适应路径。
        let shouldUseAdaptiveSteps = distanceMode == .meters || isCountdownActive
        
        // 把每个检测结果转成候选物体，附加步数、方位、位置分类等信息
        // 同时过滤掉不值得关注的物体（无距离、侧边远处）
        return filteredDetections
            .compactMap { detection -> FeedbackCandidate? in
                
                // 没有距离信息的物体无法判断危险程度，跳过
                guard let distance = detection.distance else { return nil }
                
                // 使用稳定步长换算倒数前的剩余步数，避免动态估计波动影响首次引导
                let stableSteps = stepDistanceConverter.distanceToStableSteps(distance)
                // 使用当前有效步长换算实时剩余步数，供倒数阶段应用动态修正
                let adaptiveSteps = stepDistanceConverter.distanceToSteps(distance)
                // 倒数前使用标定/默认步长，保持用户已经听到的空间尺度稳定。
                // 倒数激活后允许现有自适应估计修正近距离反馈。
                let steps = shouldUseAdaptiveSteps ? adaptiveSteps : stableSteps
                
                let direction = formatter.clockDirection(from: detection.boundingBox)
                let midX = detection.boundingBox.midX
                let isCenter = midX >= configuration.sideMargin && midX <= (1.0 - configuration.sideMargin)
                let isNew = !previousIDs.contains(detection.id)
                
                // 过滤：侧边 + 超过 5 步 → 不在行走路线上的远处物体，忽略
                if !isCenter && steps > configuration.sideIgnoreSteps { return nil }
                
                return FeedbackCandidate(
                    detection: detection,
                    distance: distance,
                    steps: steps,
                    stableSteps: stableSteps,
                    adaptiveSteps: adaptiveSteps,
                    direction: direction,
                    isCenter: isCenter,
                    isNew: isNew
                )
            }
            // 最近的排前面
            .sorted { $0.steps < $1.steps }
    }
}
