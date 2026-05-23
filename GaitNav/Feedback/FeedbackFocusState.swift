import Foundation

struct FeedbackFocusMetadata {
    let label: String
    let steps: Int
    let direction: String?
    let distance: Float?
    let time: Date
    let lastAnnouncedTime: Date
}

struct FeedbackFocusState {
    
    // =====================================================================
    // 漏斗状态：一次只聚焦一个物体
    // =====================================================================
    
    // 当前聚焦的物体 ID
    // 只有这个物体的距离/方位变化才会触发播报
    // 其他物体暂时忽略，等这个被绕过或消失后，再轮到下一个
    var focusedObjectID: UUID? = nil
    
    // 当前聚焦物体的标签名，用于 ID 丢失后的元数据匹配
    var focusedObjectLabel: String? = nil
    
    // 聚焦物体上次播报时的步数
    // 用于判断是否跨过了阈值
    var lastAnnouncedSteps: Int? = nil
    
    // 聚焦物体上次播报时的时钟方位
    // 用于检测方位是否发生了变化（比如物体从正前方移到了右侧）
    var lastAnnouncedDirection: String? = nil
    
    // 聚焦物体的实时步数（由 update() 每帧刷新）
    // handleStep() 读取这个值来决定是否播报倒数数字
    // 和 lastAnnouncedSteps 的区别：
    //   lastAnnouncedSteps = 上次播报时的步数（只在播报时更新）
    //   focusedCurrentSteps = LiDAR 测到的最新步数（每帧更新）
    // handleStep() 比较这两个值：如果 focusedCurrentSteps < lastAnnouncedSteps → 该报数字了
    var focusedCurrentSteps: Int? = nil
    
    // 聚焦物体的实时距离（米），由 update() 每帧刷新
    // 步数模式下仅用于内部跟踪；米数模式下用于阈值判断和语音文案
    var focusedCurrentDistance: Float? = nil
    
    // 米数模式下：上次播报时的原始距离（米）
    // 用于判断是否跨过了距离阈值
    // 步数模式下不使用
    var lastAnnouncedDistance: Float? = nil
    
    // 上次播报的时间
    var lastAnnouncementTime: Date = .distantPast
    
    // 上次 confirmed step 的时间。
    // 视觉兜底要参考它：如果刚刚才检测到一步，就让 handleStep() 负责播报；
    // 如果已经过了一小段时间还没有步伐事件，但屏幕步数下降了，再由视觉兜底接管。
    var lastConfirmedStepTime: Date = .distantPast
    
    // =====================================================================
    // 帧间比较：检测"突然出现"的物体
    // =====================================================================
    
    // 上一帧存在的所有物体 ID
    // 不在这个集合里的物体 = 这帧刚出现（可能是突然冒出来的行人或车辆）
    var previousIDs: Set<UUID> = []
    
    // =====================================================================
    // 失去焦点的元数据
    // =====================================================================
    
    // 记录最近一次失去焦点的元数据
    var lastFocusMetadata: FeedbackFocusMetadata? = nil
    
    // =====================================================================
    // 焦点管理
    // =====================================================================
    
    // 释放当前聚焦的物体
    // 下一帧 update 时，第四步会自动选一个新的物体
    mutating func releaseFocus() {
        
        // 在清空前保存快照，用于匹配可能由于 ID 重置而产生的“新”物体
        if let label = focusedObjectLabel, let steps = lastAnnouncedSteps {
            lastFocusMetadata = FeedbackFocusMetadata(
                label: label,
                steps: steps,
                direction: lastAnnouncedDirection,
                distance: lastAnnouncedDistance,
                // 消失的时间
                time: Date(),
                // 继承冷却时间
                lastAnnouncedTime: lastAnnouncementTime
            )
        }
        
        focusedObjectID = nil
        focusedObjectLabel = nil
        lastAnnouncedSteps = nil
        lastAnnouncedDirection = nil
        focusedCurrentSteps = nil
        focusedCurrentDistance = nil
        lastAnnouncedDistance = nil
    }
    
    // 切换焦点到这个物体
    mutating func focus(on candidate: FeedbackCandidate, now: Date) {
        focusedObjectID = candidate.detection.id
        focusedObjectLabel = candidate.detection.label
        lastAnnouncedSteps = candidate.steps
        lastAnnouncedDirection = candidate.direction
        focusedCurrentSteps = candidate.steps
        focusedCurrentDistance = candidate.distance
        lastAnnouncedDistance = candidate.distance
        lastAnnouncementTime = now
    }
    
    mutating func recoverFocus(on recovered: FeedbackCandidate) {
        guard let metadata = lastFocusMetadata else { return }
        
        focusedObjectID = recovered.detection.id
        focusedObjectLabel = recovered.detection.label
        
        // 状态全量继承
        lastAnnouncedSteps = metadata.steps
        lastAnnouncedDirection = metadata.direction
        lastAnnouncedDistance = metadata.distance
        lastAnnouncementTime = metadata.lastAnnouncedTime
        
        // 匹配成功，清除记忆
        lastFocusMetadata = nil
        // 匹配成功后直接进入第五步更新状态，不进行首报
    }
    
    mutating func refreshCurrentFocus(_ candidate: FeedbackCandidate) {
        focusedCurrentSteps = candidate.steps
        focusedCurrentDistance = candidate.distance
    }
}
