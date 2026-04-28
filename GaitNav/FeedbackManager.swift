import Foundation
import ARKit

// 语音反馈管理器：决定"什么时候说什么"
//
// 设计原则（来自倒车雷达模型）：
//   1. 漏斗原则：一次只关注一个障碍物（最危险的那个）
//      等它被绕过或消失后，再切到下一个。避免"报菜名"。
//   2. 语音只负责"定性"：告诉用户"是什么、在哪里"
//      初次发现时播报一次完整信息（"chair, 12 o'clock, 7 steps"）
//      之后只在状态有意义地变化时才再开口
//   3. 状态变化驱动，而不是定时驱动：
//      只在步数跨过阈值（7, 5, 3, 1）、方位改变、或新物体突然出现时播报
//      其余时间保持安静
//   4. 优先级过滤：
//      路径中央 + 近距离 > 侧边 + 远距离
//      突然出现的近距离物体 → 打断一切
//
// 每帧由 ContentView 的 .onChange 调用 update(with:)
class FeedbackManager {
    
    // 语音引擎：负责实际的 TTS 播报
    private let speech: SpeechManager
    
    // 步长转换器：把距离（米）转成步数
    // weak 防止循环引用
    private weak var stepConverter: StepConverter?
    
    // =====================================================================
    // 漏斗状态：一次只聚焦一个物体
    // =====================================================================
    
    // 当前聚焦的物体 ID
    // 只有这个物体的距离/方位变化才会触发播报
    // 其他物体暂时忽略，等这个被绕过或消失后再轮到下一个
    private var focusedObjectID: UUID? = nil
    
    // 聚焦物体上次播报时的步数
    // 用于判断是否跨过了阈值
    private var lastAnnouncedSteps: Int? = nil
    
    // 聚焦物体上次播报时的时钟方位
    // 用于检测方位是否发生了变化（比如物体从正前方移到了右侧）
    private var lastAnnouncedDirection: String? = nil
    
    // =====================================================================
    // 帧间比较：检测"突然出现"的物体
    // =====================================================================
    
    // 上一帧存在的所有物体 ID
    // 不在这个集合里的物体 = 这帧刚出现（可能是突然冒出来的行人或车辆）
    private var previousIDs: Set<UUID> = []
    
    // =====================================================================
    // 阈值配置
    // =====================================================================
    
    // 步数阈值：只在步数从上方跨过这些值时触发播报
    // 比如用户从 8 步走到 7 步 → 跨过 7 → 播报 "chair, 7 steps"
    // 从 7 步走到 6 步 → 没有跨过任何阈值 → 安静
    // 从 6 步走到 5 步 → 跨过 5 → 播报 "chair, 5 steps"
    //
    // 这样走完全程（10 步到 0 步），用户大约只听到 4 句话
    // 而不是每走一步都被念一次
    private let stepThresholds: [Int] = [7, 5, 3, 1]
    
    // 1 步以内 = 紧急，使用打断式播报
    private let urgentStepThreshold = 1
    
    // 突然出现的物体在这个步数以内时，才触发紧急首报
    // 远处新出现的物体不需要紧急打断，等它成为焦点时正常播报就行
    private let suddenAppearanceThreshold = 3
    
    // =====================================================================
    // 过滤配置
    // =====================================================================
    
    // 侧边判定：boundingBox 水平中心点在这个范围外视为"侧边"
    // 0.15 ~ 0.85 = 中间 70% 是"行走路径"
    // 两侧各 15% 是"侧边"
    private let sideMargin: CGFloat = 0.15
    
    // 侧边物体超过这个步数就直接忽略
    // 不在行走路线上、又离得远的物体，不值得播报
    private let sideIgnoreSteps = 5
    
    // =====================================================================
    // 焦点释放
    // =====================================================================
    
    // 步数比上次播报增加超过这个值 → 释放焦点
    // 步数增加说明用户正在远离这个物体（走过了、转向了、或者物体自己移开了）
    // 释放焦点后，系统会自动选下一个最近的物体
    private let releaseStepIncrease = 3
    
    // =====================================================================
    // 防抖
    // =====================================================================
    
    // 两次播报之间的最短间隔
    // 防止在阈值边界上因为距离抖动而反复触发
    // 1.5 秒足够短，不会让用户觉得反应迟钝
    // 又足够长，过滤掉帧间的距离波动
    private let minAnnouncementInterval: TimeInterval = 1.5
    
    // 上次播报的时间
    private var lastAnnouncementTime: Date = .distantPast
    
    // =====================================================================
    // 候选物体
    // =====================================================================
    
    // 把 Detection 和计算出的附加信息打包在一起
    // 只在 FeedbackManager 内部使用
    private struct Candidate {
        let detection: Detection
        let steps: Int
        // 时钟方位（"12 o'clock"）
        let direction: String
        // 是否在行走路径中央（midX 在 0.15~0.85 之间）
        let isCenter: Bool
        // 是否这帧刚出现（上一帧不存在）
        let isNew: Bool
    }
    
    init(speech: SpeechManager, stepConverter: StepConverter) {
        self.speech = speech
        self.stepConverter = stepConverter
    }
    
    // 接收最新的检测结果，决定是否需要播报
    //
    // 流程：
    //   1. 构建候选列表：过滤无距离的、侧边远处的物体
    //   2. 检查聚焦物体是否还存在、是否已被绕过
    //   3. 检查是否有突然出现的近距离危险物体 → 打断
    //   4. 如果没有聚焦物体 → 选一个新的，首次播报
    //   5. 更新聚焦物体的状态：方位变化 → 播报；步数跨过阈值 → 播报
    func update(with detections: [Detection]) {
        
        guard let stepConverter = stepConverter else { return }
        
        let now = Date()
        let currentIDs = Set(detections.map { $0.id })
        
        // =================================================================
        // 第一步：构建候选列表
        // =================================================================
        
        // 把每个检测结果转成候选物体，附加步数、方位、位置分类等信息
        // 同时过滤掉不值得关注的物体（无距离、侧边远处）
        let candidates: [Candidate] = detections
            .compactMap { detection -> Candidate? in
                
                // 没有距离信息的物体无法判断危险程度，跳过
                guard let distance = detection.distance else { return nil }
                
                let steps = stepConverter.distanceToSteps(distance)
                let direction = clockDirection(from: detection.boundingBox)
                let midX = detection.boundingBox.midX
                let isCenter = midX >= sideMargin && midX <= (1.0 - sideMargin)
                let isNew = !previousIDs.contains(detection.id)
                
                // 过滤：侧边 + 超过 5 步 → 不在行走路线上的远处物体，忽略
                if !isCenter && steps > sideIgnoreSteps { return nil }
                
                return Candidate(
                    detection: detection,
                    steps: steps,
                    direction: direction,
                    isCenter: isCenter,
                    isNew: isNew
                )
            }
            .sorted { $0.steps < $1.steps }  // 最近的排前面
        
        // =================================================================
        // 第二步：检查聚焦物体是否还有效
        // =================================================================
        
        if let focusID = focusedObjectID {
            
            if !currentIDs.contains(focusID) {
                // 物体从画面中消失了（用户走过了它，或者它离开了视野）
                // 释放焦点，让系统选下一个
                releaseFocus()
                
            } else if let focused = candidates.first(where: { $0.detection.id == focusID }),
                      let lastSteps = lastAnnouncedSteps,
                      focused.steps > lastSteps + releaseStepIncrease {
                // 用户在远离这个物体（步数在增加）
                // 可能是用户绕过了它，或者转向走了别的方向
                releaseFocus()
            }
        }
        
        // =================================================================
        // 第三步：检查突然出现的近距离危险物体
        // =================================================================
        
        // 遍历候选物体，找是否有"这帧刚出现 + 很近 + 在路径中央"的物体
        // 这种情况可能是突然冒出来的行人、小孩、或者用户转了个弯
        // 需要立刻警告用户
        for candidate in candidates {
            if candidate.isNew
                && candidate.steps <= suddenAppearanceThreshold
                && candidate.isCenter {
                
                // 构建播报文案 & 播报
                let text: String
                if candidate.steps <= urgentStepThreshold {
                    // 1 步以内 → 带 warning 前缀
                    text = buildUrgentText(candidate)
                    // 打断式播报（最紧急）
                    speech.speakInterrupting(text)
                } else {
                    // 2-3 步 → 完整播报但不带 warning
                    text = buildFullText(candidate)
                    // 普通播报，但仍然抢占焦点
                    speech.speak(text)
                }
                
                // 切换焦点到这个物体
                focusedObjectID = candidate.detection.id
                lastAnnouncedSteps = candidate.steps
                lastAnnouncedDirection = candidate.direction
                lastAnnouncementTime = now
                
                previousIDs = currentIDs
                return
            }
        }
        
        // =================================================================
        // 第四步：如果没有聚焦物体，选一个新的
        // =================================================================
        
        if focusedObjectID == nil {
            
            // 选择策略：
            //   优先选路径中央最近的物体（最挡路的那个）
            //   如果中央没有，选侧边但很近（3 步以内）的物体
            //   如果都没有，保持安静（前方一片空旷，不需要播报）
            let best = candidates.first(where: { $0.isCenter })
                ?? candidates.first(where: { $0.steps <= 3 })
            
            if let candidate = best {
                // 首次播报：完整信息（物体名 + 方位 + 步数）
                // 建立用户的空间映射
                let text = buildFullText(candidate)
                speech.speak(text)
                
                focusedObjectID = candidate.detection.id
                lastAnnouncedSteps = candidate.steps
                lastAnnouncedDirection = candidate.direction
                lastAnnouncementTime = now
                
                previousIDs = currentIDs
                return
            }
        }
        
        // =================================================================
        // 第五步：更新聚焦物体——只在状态有意义变化时播报
        // =================================================================
        
        if let focusID = focusedObjectID,
           let candidate = candidates.first(where: { $0.detection.id == focusID }) {
            
            let steps = candidate.steps
            let direction = candidate.direction
            
            // 防抖：距上次播报不够久就先不说
            // 过滤距离在阈值边界上来回抖动导致的重复触发
            guard now.timeIntervalSince(lastAnnouncementTime) >= minAnnouncementInterval else {
                previousIDs = currentIDs
                return
            }
            
            // ----- 方位变化检测 -----
            // 物体从 12 点移到 1 点 → 说明用户走偏了，或者物体在移动
            // 需要简短提醒用户：方位变了，注意调整
            if direction != lastAnnouncedDirection {
                let text = "\(candidate.detection.label), \(direction)"
                speech.speak(text)
                lastAnnouncedDirection = direction
                lastAnnouncedSteps = steps
                lastAnnouncementTime = now
                
                previousIDs = currentIDs
                return
            }
            
            // ----- 步数阈值检测 -----
            // 只在步数从上方跨过阈值时才播报
            // "跨过"的定义：上次播报时的步数 > 阈值，当前步数 <= 阈值
            // 用 .first 找到最高的那个被跨过的阈值
            //
            // 举例：lastAnnouncedSteps = 8, steps = 4
            //   检查 7: 8 > 7 && 4 <= 7 → true → 跨过了 7
            //   （.first 命中，不再检查后面的）
            //   播报 "chair, 4 steps"，记 lastAnnouncedSteps = 4
            //   下次 steps = 2 时：
            //     检查 7: 4 > 7 → false
            //     检查 5: 4 > 5 → false
            //     检查 3: 4 > 3 && 2 <= 3 → true → 跨过了 3
            //     播报 "chair, 2 steps"
            if let lastSteps = lastAnnouncedSteps {
                let crossedThreshold = stepThresholds.first { threshold in
                    lastSteps > threshold && steps <= threshold
                }
                
                if crossedThreshold != nil {
                    if steps <= urgentStepThreshold {
                        // 进入 1 步危险范围 → 打断式警告
                        let text = buildUrgentText(candidate)
                        speech.speakInterrupting(text)
                    } else {
                        // 普通阈值更新 → 简短播报（物体名 + 步数）
                        // 用户已经知道方位了，不重复
                        let text = buildBriefText(candidate)
                        speech.speak(text)
                    }
                    lastAnnouncedSteps = steps
                    lastAnnouncementTime = now
                }
            }
        }
        
        // =================================================================
        // 更新帧间状态
        // =================================================================
        previousIDs = currentIDs
    }
    
    // =====================================================================
    // 焦点管理
    // =====================================================================
    
    // 释放当前聚焦的物体
    // 下一帧 update 时，第四步会自动选一个新的物体
    private func releaseFocus() {
        focusedObjectID = nil
        lastAnnouncedSteps = nil
        lastAnnouncedDirection = nil
    }
    
    // =====================================================================
    // 方位计算
    // =====================================================================
    
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
        let centerX = boundingBox.midX
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
    
    // =====================================================================
    // 播报文案生成
    // =====================================================================
    
    // 完整播报：物体名 + 方位 + 步数
    // 用于首次发现物体时，建立用户的空间映射
    // 示例："chair, 12 o'clock, 7 steps"
    private func buildFullText(_ candidate: Candidate) -> String {
        let stepWord = candidate.steps == 1 ? "step" : "steps"
        return "\(candidate.detection.label), \(candidate.direction), \(candidate.steps) \(stepWord)"
    }
    
    // 简短播报：物体名 + 步数（省略方位）
    // 用于步数阈值更新，用户已经知道方位了，只需要更新距离
    // 示例："chair, 3 steps"
    private func buildBriefText(_ candidate: Candidate) -> String {
        let stepWord = candidate.steps == 1 ? "step" : "steps"
        return "\(candidate.detection.label), \(candidate.steps) \(stepWord)"
    }
    
    // 紧急播报：warning + 物体名 + 方位 + 步数
    // 用于物体进入 1 步危险范围，或突然出现的近距离威胁
    // 示例："warning, chair, 12 o'clock, 1 step"
    private func buildUrgentText(_ candidate: Candidate) -> String {
        let stepWord = candidate.steps == 1 ? "step" : "steps"
        return "warning, \(candidate.detection.label), \(candidate.direction), \(candidate.steps) \(stepWord)"
    }
}
