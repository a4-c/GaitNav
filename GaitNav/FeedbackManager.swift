import Foundation
import ARKit

// 语音反馈管理器：决定"什么时候说什么"
//
// 职责：
//   1. 跟踪每个物体的播报状态（上次播报的步数、时间）
//   2. 按距离排序，只关注最近的 1-2 个物体（最危险的优先）
//   3. 判断是否需要播报（新物体、步数变化、进入危险距离）
//   4. 组装播报文案（"person, 12 o'clock, 4 steps"）
//   5. 按优先级调用 SpeechManager 的不同接口
//
// 每帧由 CameraManager 或 ContentView 调用 update(with:)
class FeedbackManager {
    
    // 语音引擎：负责实际的 TTS 播报
    private let speech: SpeechManager
    
    // 步长转换器：把距离转成步数
    // 用 weak 避免循环引用（StepConverter 是 ContentView 的 @StateObject）
    private weak var stepConverter: StepConverter?
    
    // 危险距离阈值（米）
    // 物体距离低于这个值时，触发紧急打断式播报
    // 1.0 米 ≈ 一大步，是"需要立刻反应"的距离
    private let urgentDistance: Float = 1.0
    
    // 普通播报冷却时间（秒）
    // 同一个物体在这个时间内不会重复播报
    // 太短（1-2s）：语音会很密集，用户听不过来
    // 太长（8-10s）：距离变化了很久才通知，信息滞后
    // 4 秒是一个折中：大约走 5-6 步的时间，距离会有明显变化
    private let normalCooldown: TimeInterval = 4.0
    
    // 紧急播报冷却时间（秒）
    // 比普通冷却短，因为危险情况下需要更频繁的更新
    // 但也不能太短，否则会变成"warning warning warning"的轰炸
    private let urgentCooldown: TimeInterval = 2.0
    
    // 每次 update 最多播报几个物体
    // 设为 1：每次只播报最危险的那一个，用户听完一条完整信息再接收下一条
    // 因为 update 每帧都会被调用，下一帧自然会轮到第二危险的物体
    // 设为 2 或更大：理论上可以连续播报多个，但实际效果是用户只听到碎片
    private let maxAnnouncementsPerUpdate = 1
    
    // 优先考虑的候选物体数量
    // 从按距离排序后的列表里取前 N 个来评估是否需要播报
    // 远处的物体直接跳过，不浪费判断逻辑
    // 2 个是因为：最近的可能刚播报过（在冷却中），第二近的可以补上
    private let maxCandidates = 2
    
    // 用 UUID 作为 key，追踪每个物体的播报历史
    // UUID 来自 ObjectTracker 分配的稳定 ID，跨帧不变
    private var objectStates: [UUID: FeedbackState] = [:]
    
    // 记录一个物体的播报状态
    private struct FeedbackState {
        
        // 上次播报时告诉用户的步数
        // 用于判断步数是否发生了有意义的变化
        // nil 表示这个物体还没被播报过（刚出现）
        var lastAnnouncedSteps: Int? = nil
        
        // 上次播报的时间
        // 用于冷却机制：距离上次播报不够久就不再播报
        var lastAnnounceTime: Date = .distantPast
    }
    
    init(speech: SpeechManager, stepConverter: StepConverter) {
        self.speech = speech
        self.stepConverter = stepConverter
    }
    
    // 接收最新的检测结果，判断是否需要播报
    // 这个方法应该在主线程调用（和 UI 更新同步）
    //
    // 流程：
    //   1. 收集所有物体 ID（用于清理已消失物体）
    //   2. 过滤掉没有距离的物体
    //   3. 按距离排序（最近的最危险，优先处理）
    //   4. 只取最近的 maxCandidates 个作为候选
    //   5. 对候选物体逐个判断是否需要播报
    //   6. 播报了 maxAnnouncementsPerUpdate 个就停止
    func update(with detections: [Detection]) {
        
        // 如果没有 stepConverter，无法算步数，不播报
        guard let stepConverter = stepConverter else { return }
        
        let now = Date()
        
        // 记录这一帧里存在的所有物体 ID（包括远处的、没距离的）
        // 用于最后清理已消失物体的状态
        let currentIDs = Set(detections.map { $0.id })
        
        // 过滤 + 排序：只保留有距离信息的物体，按距离从近到远排列
        // 没有距离的物体无法判断危险程度，直接跳过
        // 最近的物体排在前面，优先获得播报机会
        let candidates = detections
            .filter { $0.distance != nil }
            .sorted { $0.distance! < $1.distance! }
            .prefix(maxCandidates)
        
        // 这次 update 已经播报了几个物体
        var announcementsMade = 0
        
        for detection in candidates {
            
            // 已经播报够了，剩下的等下一帧
            if announcementsMade >= maxAnnouncementsPerUpdate { break }
            
            let distance = detection.distance!
            let steps = stepConverter.distanceToSteps(distance)
            
            // 获取或创建这个物体的播报状态
            let state = objectStates[detection.id] ?? FeedbackState()
            
            // 判断播报类型
            let isUrgent = distance <= urgentDistance
            let cooldown = isUrgent ? urgentCooldown : normalCooldown
            let timeSinceLastAnnounce = now.timeIntervalSince(state.lastAnnounceTime)
            
            // 判断是否需要播报
            let shouldAnnounce: Bool
            
            if state.lastAnnouncedSteps == nil {
                // 情况1：这个物体从未被播报过（刚出现）
                // 无条件播报，让用户知道有新物体进入视野
                shouldAnnounce = true
                
            } else if isUrgent && timeSinceLastAnnounce >= urgentCooldown {
                // 情况2：物体在危险距离内，且紧急冷却时间已过
                // 紧急播报，即使步数没变也要提醒
                shouldAnnounce = true
                
            } else if timeSinceLastAnnounce >= cooldown,
                      let lastSteps = state.lastAnnouncedSteps,
                      steps != lastSteps {
                // 情况3：冷却时间已过 + 步数发生了变化
                // 常规更新播报
                // 步数没变就不播报（用户不需要听到重复的"person, 4 steps"）
                shouldAnnounce = true
                
            } else {
                shouldAnnounce = false
            }
            
            // 执行播报 
            if shouldAnnounce {
                
                let text = buildText(
                    label: detection.label,
                    steps: steps,
                    boundingBox: detection.boundingBox,
                    isUrgent: isUrgent
                )
                
                if isUrgent {
                    // 紧急：打断当前播报，立刻说
                    speech.speakInterrupting(text)
                } else {
                    // 普通：不打断，如果正在说就跳过
                    speech.speak(text)
                }
                
                // 更新播报状态
                objectStates[detection.id] = FeedbackState(
                    lastAnnouncedSteps: steps,
                    lastAnnounceTime: now
                )
                
                announcementsMade += 1
            }
        }
        
        // 清理已消失物体的状态
        // 物体离开画面后，删除它的播报状态
        // 这样如果它重新出现，会被当作新物体播报
        for id in objectStates.keys {
            if !currentIDs.contains(id) {
                objectStates.removeValue(forKey: id)
            }
        }
    }
    
    // 把物体在画面中的水平位置转换成时钟方位
    //
    // 映射关系：
    //   iPhone 竖屏时水平视野（FOV）大约 60°
    //   时钟上每小时 = 30°，所以 60° = 中心两侧各 1 小时
    //   覆盖范围：11 点钟 ~ 1 点钟，正好三个位置
    //
    //   归一化 x 坐标：
    //     0.0 ──── 0.25 ──────── 0.75 ──── 1.0
    //         11点      12点（正前方）    1点
    private func clockDirection(from boundingBox: CGRect) -> String {
        
        // 取检测框的水平中心点
        let centerX = boundingBox.midX
        
        // 分区映射
        // 12 点钟占中间 50%（0.25-0.75），因为正前方的物体最重要
        let hour: Int
        if centerX < 0.25 {
            hour = 11
        } else if centerX < 0.75 {
            hour = 12
        } else {
            hour = 1
        }
        
        return "\(hour) o'clock"
    }
    
    // 生成播报文案
    // 格式：[警告] + 物体名 + 方位 + 步数
    //
    // 示例：
    //   普通："person, 12 o'clock, 4 steps"
    //   紧急："warning, chair, 1 o'clock, 1 step"
    private func buildText(label: String, steps: Int, boundingBox: CGRect, isUrgent: Bool) -> String {
        
        let stepWord = steps == 1 ? "step" : "steps"
        let direction = clockDirection(from: boundingBox)
        
        if isUrgent {
            return "warning, \(label), \(direction), \(steps) \(stepWord)"
        } else {
            return "\(label), \(direction), \(steps) \(stepWord)"
        }
    }
}
