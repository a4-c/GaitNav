import Foundation
import ARKit

// 语音反馈管理器：决定"什么时候说什么"
//
// 职责：
//   1. 跟踪每个物体的播报状态（上次播报的步数、时间）
//   2. 判断是否需要播报（新物体、步数变化、进入危险距离）
//   3. 组装播报文案（"person, 12 o'clock, 4 steps"）
//   4. 按优先级调用 SpeechManager 的不同接口
//
// 每帧由 CameraManager 或 ContentView 调用 update(with:)
// 内部判断后决定是否触发语音
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
    func update(with detections: [Detection]) {
        
        // 如果没有 stepConverter，无法算步数，不播报
        guard let stepConverter = stepConverter else { return }
        
        let now = Date()
        
        // 记录这一帧里存在的物体 ID
        // 用于之后清理已消失物体的状态
        var currentIDs = Set<UUID>()
        
        for detection in detections {
            currentIDs.insert(detection.id)
            
            // 没有距离信息的物体不播报
            // 因为"person, unknown distance"对用户没有实际帮助
            guard let distance = detection.distance else { continue }
            
            // 算出当前步数
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
        // 12 点钟占中间 50%（0.25-0.75）
        // 因为正前方的物体最重要，给它更宽的判定范围
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
