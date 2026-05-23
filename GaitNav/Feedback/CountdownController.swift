import Foundation

struct CountdownController {
    // 步伐同步倒数
    //
    // 只在倒数模式下推进数字：
    //   读取 focusState.focusedCurrentSteps（update() 刷新的 LiDAR 最新距离）
    //   每个 confirmed step 推进一个倒数刻度
    //   如果实时估算和倒数刻度偏差很大 → 先说 "about N steps"
    //
    // 这样倒数节奏完全跟随用户的脚步：
    //   用户走得快 → 倒数快（因为步伐事件频率高）
    //   用户走得慢 → 倒数慢
    //   用户停下 → 倒数暂停（没有步伐事件触发）
    func handleConfirmedStep(
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        formatter: FeedbackAnnouncementFormatter,
        speech: SpeechManager
    ) {
        
        // 前置条件检查
        guard focusState.focusedObjectID != nil else { return }
        guard let currentSteps = focusState.focusedCurrentSteps else { return }
        guard let lastSteps = focusState.lastAnnouncedSteps else { return }
        
        let now = Date()
        
        // 倒数模式下，语音遵守用户的心理预期：
        // 上次说 5，这次确认一步后默认应该说 4。
        // 不直接读 currentSteps，是为了避免 LiDAR/步长抖动让语音倒数跳来跳去。
        let expectedNextSteps = max(lastSteps - 1, configuration.urgentStepThreshold)
        let drift = abs(currentSteps - expectedNextSteps)
        
        // 如果动态步长让剩余步数发生明显修正，优先播报 "about N steps"。
        // 例如用户从快走突然放慢，系统估算从 5 修正到 8，就不要硬倒数到 4。
        if drift >= configuration.correctionStepDelta,
           currentSteps > configuration.urgentStepThreshold,
           now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.minAnnouncementInterval {
            speech.speak(formatter.correctionText(steps: currentSteps))
            focusState.lastAnnouncedSteps = currentSteps
            focusState.lastAnnouncementTime = now
            return
        }
        
        // 只在倒数模式下生效（focusState.lastAnnouncedSteps <= 5）
        guard lastSteps <= configuration.countdownThreshold else { return }
        
        // 防抖：如果 update() 已经在本次 confirmed step 链路中播报，避免 handleStep() 立刻再播一次
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.countdownMinInterval else { return }
        
        // confirmed step 正常推进倒数。
        // 这里不重复写 speech.speak / speakInterrupting 的细节，统一交给 helper。
        speakCountdownStep(expectedNextSteps, configuration: configuration, speech: speech)
        
        focusState.lastAnnouncedSteps = expectedNextSteps
        focusState.lastAnnouncementTime = now
    }
    
    // 当步伐检测漏掉，但视觉步数已经下降时，用视觉结果兜底推进倒数。
    //
    // 为什么需要这个函数？
    //   屏幕步数来自 LiDAR + 动态步长，所以它可能已经准确显示 4；
    //   但如果加速度计没有检测到那一步，handleStep() 不会被调用，语音就会卡在 5。
    //
    // 这个函数做的事情：
    //   1. 只在没有近期 confirmed step 时介入，避免和主路重复播报。
    //   2. 只在 currentSteps 真的比 focusState.lastAnnouncedSteps 小时播报，避免距离抖动。
    //   3. 只说短数字或 Stop，不说完整物体句。
    func tryVisualCountdownFallback(
        now: Date,
        isConfirmedStepUpdate: Bool,
        distanceMode: FeedbackDistanceMode,
        focusState: inout FeedbackFocusState,
        configuration: FeedbackConfiguration,
        speech: SpeechManager
    ) -> Bool {
        
        // 米数模式没有倒数机制，不需要视觉兜底
        if distanceMode == .meters { return false }
        
        guard let currentSteps = focusState.focusedCurrentSteps else { return false }
        guard let lastSteps = focusState.lastAnnouncedSteps else { return false }
        
        // confirmed step 路径可以立即进入倒数；
        // 普通画面帧必须先等一小段时间，确认不是步伐事件马上要来了。
        let canEnterCountdown = isConfirmedStepUpdate || now.timeIntervalSince(focusState.lastConfirmedStepTime) >= configuration.visualCountdownFallbackDelay
        
        // 情况 A：还没正式进入倒数，但视觉步数已经从 6+ 变成 5 或更小。
        // 如果这是 confirmed step 路径，直接说 "5"；
        // 如果这是普通画面帧，只有在步伐漏检延迟后才兜底说 "5"。
        if lastSteps > configuration.countdownThreshold && currentSteps <= configuration.countdownThreshold {
            let minInterval = isConfirmedStepUpdate ? configuration.countdownMinInterval : configuration.visualCountdownMinInterval
            guard canEnterCountdown else { return false }
            guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= minInterval else { return false }
            speakCountdownStep(currentSteps, configuration: configuration, speech: speech)
            focusState.lastAnnouncedSteps = max(currentSteps, configuration.urgentStepThreshold)
            focusState.lastAnnouncementTime = now
            return true
        }
        
        // 情况 B：已经在倒数中了，比如上次说了 5。
        // 只有屏幕步数真的降到 4、3、2、1 时才兜底播报。
        guard lastSteps <= configuration.countdownThreshold else { return false }
        guard currentSteps < lastSteps else { return false }
        guard now.timeIntervalSince(focusState.lastConfirmedStepTime) >= configuration.visualCountdownFallbackDelay else { return false }
        guard now.timeIntervalSince(focusState.lastAnnouncementTime) >= configuration.visualCountdownMinInterval else { return false }
        
        speakCountdownStep(currentSteps, configuration: configuration, speech: speech)
        focusState.lastAnnouncedSteps = max(currentSteps, configuration.urgentStepThreshold)
        focusState.lastAnnouncementTime = now
        return true
    }
    
    // 倒数模式的判定比 focusState.lastAnnouncedSteps 略宽：
    // - focusState.lastAnnouncedSteps <= 5：语音已经进入倒数
    // - focusState.focusedCurrentSteps <= 5：画面已经进入近距离，即使语音还没来得及说 5
    // 这样可以更早压制完整句，保护倒数体验。
    func isCountdownActive(
        focusState: FeedbackFocusState,
        distanceMode: FeedbackDistanceMode,
        configuration: FeedbackConfiguration
    ) -> Bool {
        // 米数模式没有倒数概念，永远返回 false
        if distanceMode == .meters { return false }
        
        if let lastSteps = focusState.lastAnnouncedSteps, lastSteps <= configuration.countdownThreshold {
            return true
        }
        if let currentSteps = focusState.focusedCurrentSteps, currentSteps <= configuration.countdownThreshold {
            return true
        }
        return false
    }
    
    // 数字倒数统一从这里播，避免多个地方各自处理 "Stop"。
    private func speakCountdownStep(_ steps: Int, configuration: FeedbackConfiguration, speech: SpeechManager) {
        if steps <= configuration.urgentStepThreshold {
            speech.speakInterrupting(configuration.finalCountdownText)
        } else {
            speech.speak("\(steps)")
        }
    }
}
