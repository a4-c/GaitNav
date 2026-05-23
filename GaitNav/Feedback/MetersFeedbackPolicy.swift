import Foundation

// =====================================================================
// 米数模式：聚焦物体更新逻辑
// =====================================================================
struct MetersFeedbackPolicy {
    
    // 由 update() 第五步在 distanceMode == .meters 时调用
    // 紧急距离 → 方位变化 → 距离阈值
    // 所有播报纯粹由 LiDAR 距离的阈值跨越驱动
    func updateInMetersMode(
        candidate: FeedbackCandidate,
        direction: String,
        now: Date,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter,
        speech: SpeechManager,
        distanceMode: FeedbackDistanceMode
    ) {
        
        let currentDistance = candidate.distance
        
        // 紧急距离（< 0.5m）：立刻播报 Stop
        // 不受防抖限制，因为用户可能没在走路（物体在靠近用户）
        if currentDistance <= configuration.urgentMeterThreshold,
           let lastDist = focusState.lastAnnouncedDistance,
           lastDist > configuration.urgentMeterThreshold {
            speech.speakInterrupting(configuration.finalCountdownText)
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncementTime = now
            return
        }
        
        // 防抖
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval else { return }
        
        // 方位变化
        if direction != focusState.lastAnnouncedDirection {
            let text = "\(candidate.detection.label), \(direction)"
            speech.speak(text)
            focusState.lastAnnouncedDirection = direction
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncementTime = now
            return
        }
        
        // 距离阈值跨越
        // 从 meterThresholds 中找到刚被跨过的最大阈值
        // 当我们在 3.5m 首报后，focusState.lastAnnouncedDistance = 3.5m
        // 距离降到 2.8m 时：
        //   3.0m：3.5 > 3.0 且 2.8 <= 3.0 → 匹配！播报，focusState.lastAnnouncedDistance = 2.8m
        // 距离降到 1.9m 时：
        //   3.0m：2.8 > 3.0？不满足 → 跳过（3m 阈值不会再触发）
        //   2.0m：2.8 > 2.0 且 1.9 <= 2.0 → 匹配！播报，focusState.lastAnnouncedDistance = 1.9m
        if let _ = configuration.meterThresholds.first(where: { threshold in
            (focusState.lastAnnouncedDistance ?? Float.greatestFiniteMagnitude) > threshold
                && currentDistance <= threshold
        }) {
            let text = formatter.briefText(for: candidate, mode: distanceMode)
            speech.speak(text)
            focusState.lastAnnouncedSteps = candidate.steps
            focusState.lastAnnouncedDistance = currentDistance
            focusState.lastAnnouncementTime = now
        }
    }
}
