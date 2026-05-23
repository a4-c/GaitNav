import Foundation

// =====================================================================
// 步数模式：聚焦物体更新逻辑
// =====================================================================
struct StepsFeedbackPolicy {
    
    // 由 update() 第五步时调用
    func updateInStepsMode(
        candidate: FeedbackCandidate,
        now: Date,
        isConfirmedStepUpdate: Bool,
        distanceMode: FeedbackDistanceMode,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter,
        countdownController: CountdownController,
        speech: SpeechManager
    ) -> Bool {
        
        let steps = candidate.steps
        let direction = candidate.direction
        
        // "是否在倒数模式"以 focusState.lastAnnouncedSteps 为准：
        // 只要语音已经说过 5 或更小，就认为用户正在听倒数。
        // 这时普通 update() 要尽量安静，避免完整句打断数字节奏。
        let isInCountdown = (focusState.lastAnnouncedSteps ?? Int.max) <= configuration.countdownThreshold
        
        // ----- 最后一步 / 紧急警告（绕过防抖，立刻触发）-----
        // 1 步以内是"必须立刻反应"的距离
        // 不能等步伐事件——万一用户没在走路（物体在朝用户移动），
        // handleStep() 永远不会被调用，用户就听不到警告
        if steps <= configuration.urgentStepThreshold,
           let lastSteps = focusState.lastAnnouncedSteps,
           lastSteps > configuration.urgentStepThreshold {
            let text = isInCountdown ? configuration.finalCountdownText : formatter.urgentText(for: candidate, mode: distanceMode)
            speech.speakInterrupting(text)
            focusState.lastAnnouncedSteps = steps
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // 视觉兜底放在普通播报规则之前。
        // 原因：如果屏幕步数已经从 5 到 4，但加速度计漏检，
        // 我们宁愿补一个短数字，也不要继续等待或说完整句。
        if countdownController.tryVisualCountdownFallback(
            now: now,
            isConfirmedStepUpdate: isConfirmedStepUpdate,
            distanceMode: distanceMode,
            focusState: &focusState,
            configuration: configuration,
            speech: speech
        ) {
            return true
        }
        
        // ----- 防抖 -----
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval else {
            return true
        }
        
        // ----- 方位变化检测 -----
        // 倒数期间保持安静，避免方向短句打断数字节奏。
        if !isInCountdown && direction != focusState.lastAnnouncedDirection {
            let text = "\(candidate.detection.label), \(direction)"
            speech.speak(text)
            focusState.lastAnnouncedDirection = direction
            focusState.lastAnnouncedSteps = steps
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // ----- 远距离：阈值播报 -----
        // 倒数入口已经由 tryVisualCountdownFallback() 统一处理：
        // confirmed step 可以立刻说 "5"，普通视觉帧只在步伐漏检后兜底说 "5"。
        // 这里保留的只是 7 步这类远距离简短更新。
        if !isInCountdown, let lastSteps = focusState.lastAnnouncedSteps, steps < lastSteps {
            
            // 检查是否刚跨入倒数范围（从 6+ 步降到 5 步以下）
            let enteredCountdown = lastSteps > configuration.countdownThreshold && steps <= configuration.countdownThreshold
            
            // 检查是否跨过远距离阈值
            let crossedThreshold = configuration.stepThresholds.first { threshold in
                lastSteps > threshold && steps <= threshold
            }
            
            if crossedThreshold != nil && !enteredCountdown {
                // 跨过远距离阈值 → 简短播报
                // 如果这次同时跨进 5 步倒数范围，就不说 "chair, 5 steps"；
                // 留给数字倒数说 "5"，避免完整句打断。
                let text = formatter.briefText(for: candidate, mode: distanceMode)
                speech.speak(text)
                focusState.lastAnnouncedSteps = steps
                focusState.lastAnnouncementTime = now
            }
        }
        
        return false
    }
}
