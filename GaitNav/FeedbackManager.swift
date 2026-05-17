import Foundation
import ARKit

// 语音反馈管理器：决定"什么时候说什么"
//
// 设计原则（来自倒车雷达模型）：
//   1. 漏斗原则：一次只关注一个障碍物（最危险的那个）
//      等它被绕过或消失后，再切到下一个。避免"报菜名"。
//   2. 两段式反馈：
//      远距离（> 5 步）→ 语音播报物体名 + 方位 + 步数，只在关键阈值时触发
//      近距离（≤ 5 步）→ 步伐同步倒数，用户每走一步说一个数字
//      1 步 → 最后一句短促行动提示（"Stop"）
//   3. 倒数与步伐同步：
//      倒数模式下的数字播报由 StepConverter 的步伐检测事件驱动
//      用户走一步 → 加速度计检测到 → handleStep() 被调用 → 读取 LiDAR 最新距离
//      每个确认步伐推进一个数字；如果动态步长偏差变大，就先播报修正值。
//      这样倒数节奏和用户的步伐完全同步，而不是按帧率随机触发。
//   4. 优先级过滤：
//      路径中央 + 近距离 > 侧边 + 远距离
//      突然出现的近距离物体 → 打断一切
//
// 典型播报流程（用户向 10 步外的椅子走去）：
//   "chair, 12 o'clock, 10 steps"  ← 首次发现，完整播报
//   "chair, 7 steps"               ← 跨过阈值 7，简短更新
//   "5"                            ← 进入倒数模式（用户走了一步，距离到 5 步）
//   "4"                            ← 用户又走了一步
//   "3"                            ← ...
//   "2"
//   "Stop"                          ← 最后一步，不再使用 warning 长句
//
// 全程 7 句话，中间大量安静时间。用户不需要自己记步数。
//
// 两个入口：
//   update(with:) — 每帧调用，处理焦点管理、首报、方位变化、阈值跨越、紧急警告
//   handleStep()  — 每走一步调用，处理倒数模式下的数字播报
//
// 两种反馈模式（用于 user study 对比实验）：
//
// 步数模式（gait-adaptive，实验组）：
//   以上"倒车雷达"模型的完整实现。
//   核心特征：近距离时步伐同步倒数，节奏跟用户脚步绑定。
//
// 米数模式（传统基线，对照组）：
//   首次发现时完整播报一次（"chair, 12 o'clock, 3.2 meters"）。
//   之后只在距离跨过关键阈值时简短更新（3m → 2m → 1m）。
//   不做步伐同步倒数，不和加速度计联动。
//
//   这样实验比较的是"步态自适应反馈 vs 传统距离反馈"，
//   而不是"同一套机制换个单位念"。
//
// 典型播报流程（米数模式，用户向 5m 外的椅子走去）：
//   "chair, 12 o'clock, 5 meters"   ← 首次发现
//   "chair, 3 meters"               ← 跨过 3m 阈值
//   "chair, 2 meters"               ← 跨过 2m 阈值
//   "chair, 1 meter"                ← 跨过 1m 阈值
//   "Stop"                           ← 距离 < 0.5m
//
// 全程 5 句话，没有倒数，没有步伐同步。和传统导航系统的行为一致。
class FeedbackManager {
    
    // 语音引擎：负责实际的 TTS 播报
    private let speech: SpeechManager
    
    // 步长转换器：把距离（米）转成步数
    // weak 防止循环引用
    private weak var stepConverter: StepConverter?
    
    // 反馈距离单位：步数 or 米数
    var distanceMode: FeedbackDistanceMode
    
    // =====================================================================
    // 漏斗状态：一次只聚焦一个物体
    // =====================================================================
    
    // 当前聚焦的物体 ID
    // 只有 this 物体的距离/方位变化才会触发播报
    // 其他物体暂时忽略，等这个被绕过或消失后再轮到下一个
    private var focusedObjectID: UUID? = nil
    
    // 新增：当前聚焦物体的标签名，用于 ID 丢失后的元数据匹配
    private var focusedObjectLabel: String? = nil
    
    // 聚焦物体上次播报时的步数
    // 用于判断是否跨过了阈值
    private var lastAnnouncedSteps: Int? = nil
    
    // 聚焦物体上次播报时的时钟方位
    // 用于检测方位是否发生了变化（比如物体从正前方移到了右侧）
    private var lastAnnouncedDirection: String? = nil
    
    // 聚焦物体的实时步数（由 update() 每帧刷新）
    // handleStep() 读取这个值来决定是否播报倒数数字
    // 和 lastAnnouncedSteps 的区别：
    //   lastAnnouncedSteps = 上次播报时的步数（只在播报时更新）
    //   focusedCurrentSteps = LiDAR 测到的最新步数（每帧更新）
    // handleStep() 比较这两个值：如果 focusedCurrentSteps < lastAnnouncedSteps → 该报数字了
    private var focusedCurrentSteps: Int? = nil
    
    // 聚焦物体的实时距离（米），由 update() 每帧刷新
    // 步数模式下仅用于内部跟踪；米数模式下用于阈值判断和语音文案
    private var focusedCurrentDistance: Float? = nil
    
    // 米数模式下：上次播报时的原始距离（米）
    // 用于判断是否跨过了距离阈值
    // 步数模式下不使用
    private var lastAnnouncedDistance: Float? = nil
    
    // =====================================================================
    // 帧间比较：检测"突然出现"的物体
    // =====================================================================
    
    // 上一帧存在的所有物体 ID
    // 不在这个集合里的物体 = 这帧刚出现（可能是突然冒出来的行人或车辆）
    private var previousIDs: Set<UUID> = []
    
    // =====================================================================
    // 步数模式阈值 & 倒数配置
    // =====================================================================
    
    // 远距离阈值：步数 > countdownThreshold 时，只在跨过这些值时播报
    // 不包含 5，因为 5 是倒数模式的入口，由倒数逻辑处理
    private let stepThresholds: [Int] = [12, 9]
    
    // 倒数模式入口：步数从上方跨过这个值时，进入倒数模式
    // 进入后只说数字（"5", "4", "3", "2"），每减 1 步报一次
    // 用户已经从首报知道了"是什么、在哪里"，倒数只需要告诉"还有多远"
    private let countdownThreshold = 5
    
    // 1 步以内 = 最后一步，倒数模式下使用短促行动提示
    private let urgentStepThreshold = 1
    
    // 最后一步播报。这里没有路线转向信息，所以使用直接的行动提示 Stop
    private let finalCountdownText = "Stop"
    
    // 动态步长变化造成的估算偏差达到这个步数时，播报一次修正。
    private let correctionStepDelta = 2
    
    // 突然出现的物体在这个步数以内时，才触发紧急首报
    // 远处新出现的物体不需要紧急打断，等它成为焦点时正常播报就行
    private let suddenAppearanceThreshold = 3
    
    // =====================================================================
    // 米数模式阈值
    // =====================================================================
    
    // 距离阈值（米），从远到近排列
    // 用户接近物体时，每跨过一个阈值播报一次简短更新
    // 首报时的完整信息由焦点获取逻辑处理，这里只管后续的阈值更新
    private let meterThresholds: [Float] = [10.0, 5.0, 3.0, 2.0, 1.0]
    
    // 紧急距离（米）
    // 低于此距离 → 播报 "Stop"
    private let urgentMeterThreshold: Float = 0.5
    
    // =====================================================================
    // 过滤配置
    // =====================================================================
    
    // 侧边判定：boundingBox 水平中心点在这个范围外视为"侧边"
    // 0.35 ~ 0.65 = 中间 30% 是"行走路径"
    // 两侧各 35% 是"侧边"
    private let sideMargin: CGFloat = 0.35
    
    // 侧边物体超过这个步数就直接忽略
    // 不在行走路线上、又离得远的物体，不值得播报
    private let sideIgnoreSteps = 5
    
    // =====================================================================
    // 焦点释放 & 失去焦点的元数据
    // =====================================================================
    
    // 步数比上次播报增加超过这个值 → 释放焦点
    // 步数增加说明用户正在远离这个物体（走过了、转向了、或者物体自己移开了）
    // 释放焦点后，系统会自动选下一个最近的物体
    private let releaseStepIncrease = 3
    
    // 记录最近一次失去焦点的元数据
    private var lastFocusMetadata: (
        label: String,
        steps: Int,
        direction: String?,
        distance: Float?,
        time: Date,
        lastAnnouncedTime: Date
    )? = nil
    
    // =====================================================================
    // 防抖
    // =====================================================================
    
    // 两次播报之间的最短间隔（远距离模式）
    // 防止在阈值边界上因为距离抖动而反复触发
    private let minAnnouncementInterval: TimeInterval = 1.5
    
    // 倒数模式下的最短间隔。
    // 步伐确认已经由 StepConverter 防抖，这里只防同一事件链里的重复播报。
    private let countdownMinInterval: TimeInterval = 0.25
    
    // 如果加速度计漏检了一步，但视觉/LiDAR 步数已经稳定下降，
    // 等待这段时间后用视觉步数兜底播报，避免倒数卡住。
    private let visualCountdownFallbackDelay: TimeInterval = 0.55
    
    // 视觉兜底倒数之间的最短间隔，防止同一段距离抖动连报。
    private let visualCountdownMinInterval: TimeInterval = 0.75
    
    // 上次播报的时间
    private var lastAnnouncementTime: Date = .distantPast
    
    // 上次 confirmed step 的时间。
    // 视觉兜底要参考它：如果刚刚才检测到一步，就让 handleStep() 负责播报；
    // 如果已经过了一小段时间还没有步伐事件，但屏幕步数下降了，再由视觉兜底接管。
    private var lastConfirmedStepTime: Date = .distantPast
    
    // =====================================================================
    // 候选物体
    // =====================================================================
    
    // 把 Detection 和计算出的附加信息打包在一起
    // 只在 FeedbackManager 内部使用
    private struct Candidate {
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
    
    init(speech: SpeechManager, stepConverter: StepConverter, distanceMode: FeedbackDistanceMode = .steps) {
        self.speech = speech
        self.stepConverter = stepConverter
        self.distanceMode = distanceMode
    }
    
    // 接收最新的检测结果，决定是否需要播报
    //
    // 流程：
    //   1. 构建候选列表：过滤无距离的、侧边远处的物体
    //   2. 检查聚焦物体是否还存在、是否已被绕过
    //   3. 检查是否有突然出现的近距离危险物体 → 打断
    //   4. 如果没有聚焦物体 → 选一个新的，首次播报
    //   5. 更新聚焦物体的状态：方位变化 → 播报；步数跨过阈值 → 播报
    func update(with detections: [Detection], isConfirmedStepUpdate: Bool = false) {
        
        guard let stepConverter = stepConverter else { return }
        
        let now = Date()
        let currentIDs = Set(detections.map { $0.id })
        
        // 大框里的小框（距离相似）不进入语音候选
        // currentIDs 仍然用原始 detections 构建，保证 previousIDs 跟踪不受影响
        let filteredDetections = Detection.suppressContained(detections)
        
        // 步数模式在倒数前使用稳定引导；米数模式保持原来的自适应路径。
        let shouldUseAdaptiveSteps = distanceMode == .meters || isCountdownActive
        
        // =================================================================
        // 第一步：构建候选列表
        // =================================================================
        
        // 把每个检测结果转成候选物体，附加步数、方位、位置分类等信息
        // 同时过滤掉不值得关注的物体（无距离、侧边远处）
        let candidates: [Candidate] = filteredDetections
            .compactMap { detection -> Candidate? in
                
                // 没有距离信息的物体无法判断危险程度，跳过
                guard let distance = detection.distance else { return nil }
                
                let stableSteps = stepConverter.distanceToStableSteps(distance)
                let adaptiveSteps = stepConverter.distanceToSteps(distance)
                // 倒数前使用标定/默认步长，保持用户已经听到的空间尺度稳定。
                // 倒数激活后允许现有自适应估计修正近距离反馈。
                let steps = shouldUseAdaptiveSteps ? adaptiveSteps : stableSteps
                
                let direction = clockDirection(from: detection.boundingBox)
                let midX = detection.boundingBox.midX
                let isCenter = midX >= sideMargin && midX <= (1.0 - sideMargin)
                let isNew = !previousIDs.contains(detection.id)
                
                // 过滤：侧边 + 超过 5 步 → 不在行走路线上的远处物体，忽略
                if !isCenter && steps > sideIgnoreSteps { return nil }
                
                return Candidate(
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
        
        // =================================================================
        // 第二步：检查聚焦物体是否还有效
        // =================================================================
        
        // 先记录进入 update() 时是否已经在倒数模式。
        // 注意这里要在刷新 focusedCurrentSteps 之前判断：
        // 如果已经进入倒数，就不要因为动态步长抖动导致"步数变大"而释放焦点。
        let wasInCountdown = isCountdownActive
        
        if let focusID = focusedObjectID {
            
            if !currentIDs.contains(focusID) {
                // 物体从画面中消失了（用户走过了它，或者它离开了视野）
                // 释放焦点，让系统选下一个
                releaseFocus()
            
            } else if let focused = candidates.first(where: { $0.detection.id == focusID }),
                      let lastSteps = lastAnnouncedSteps,
                      !wasInCountdown,
                      focused.steps > lastSteps + releaseStepIncrease {
                // 用户在远离这个物体（步数在增加）
                // 可能是用户绕过了它，或者转向走了别的方向
                // 但倒数模式中不做这个判断，避免 5、4、3 时突然切物体并插入完整句。
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
                
                // 倒数期间不要让 2-3 步的新物体完整句打断节奏；
                // 只有真正 1 步以内的危险仍然允许打断。
                if isCountdownActive && candidate.steps > urgentStepThreshold {
                    continue
                }
                
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
                focusedObjectLabel = candidate.detection.label
                lastAnnouncedSteps = candidate.steps
                lastAnnouncedDirection = candidate.direction
                focusedCurrentSteps = candidate.steps
                focusedCurrentDistance = candidate.distance
                lastAnnouncedDistance = candidate.distance
                lastAnnouncementTime = now
                
                previousIDs = currentIDs
                return
            }
        }
        
        // =================================================================
        // 第四步：如果没有聚焦物体，选一个新的
        // =================================================================
        
        if focusedObjectID == nil {
            
            // 策略：优先寻找匹配刚丢失焦点的“新”物体，防止 ID 闪烁打断
            if let metadata = lastFocusMetadata, now.timeIntervalSince(metadata.time) < 1.0 {
                if let recovered = candidates.first(where: {
                    $0.detection.label == metadata.label &&
                    abs($0.steps - metadata.steps) <= 2
                }) {
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
            }
            
            // 如果上述匹配失败，则按常规逻辑选一个
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
                    focusedObjectLabel = candidate.detection.label
                    lastAnnouncedSteps = candidate.steps
                    lastAnnouncedDirection = candidate.direction
                    focusedCurrentSteps = candidate.steps
                    focusedCurrentDistance = candidate.distance
                    lastAnnouncedDistance = candidate.distance
                    lastAnnouncementTime = now
                    
                    previousIDs = currentIDs
                    return
                }
            }
        }
        
        // =================================================================
        // 第五步：更新聚焦物体
        // =================================================================
        //
        // update() 在这一步负责：
        //   - 每帧刷新 focusedCurrentSteps（给 handleStep 用）
        //   - 检测方位变化
        //   - 远距离阈值播报
        //   - 倒数模式入口（说 "5"）
        //   - 紧急警告（1 步以内，不能等步伐事件，必须立刻触发）
        //
        // update() 不负责：
        //   - 倒数模式下的数字播报（4, 3, 2）→ 由 handleStep() 处理
        
        if let focusID = focusedObjectID,
           let candidate = candidates.first(where: { $0.detection.id == focusID }) {
            
            let steps = candidate.steps
            let direction = candidate.direction
            
            // 每帧刷新实时步数，供 handleStep() 读取
            // 这是 update() 和 handleStep() 之间的数据桥梁
            focusedCurrentSteps = steps
            focusedCurrentDistance = candidate.distance
            
            // 米数模式：
            //   只看距离阈值：跨过 10m/5m/3m/2m/1m 时简短更新，< 0.5m 时说 Stop
            //   所有播报由画面帧的距离变化驱动，和用户步伐无关
            if distanceMode == .meters {
                updateFocusedMetersMode(candidate: candidate, direction: direction, now: now)
                previousIDs = currentIDs
                return
            }
            
            // 步数模式：
            
            // "是否在倒数模式"以 lastAnnouncedSteps 为准：
            // 只要语音已经说过 5 或更小，就认为用户正在听倒数。
            // 这时普通 update() 要尽量安静，避免完整句打断数字节奏。
            let isInCountdown = (lastAnnouncedSteps ?? Int.max) <= countdownThreshold
            
            // ----- 最后一步 / 紧急警告（绕过防抖，立刻触发）-----
            // 1 步以内是"必须立刻反应"的距离
            // 不能等步伐事件——万一用户没在走路（物体在朝用户移动），
            // handleStep() 永远不会被调用，用户就听不到警告
            if steps <= urgentStepThreshold,
               let lastSteps = lastAnnouncedSteps,
               lastSteps > urgentStepThreshold {
                let text = isInCountdown ? finalCountdownText : buildUrgentText(candidate)
                speech.speakInterrupting(text)
                lastAnnouncedSteps = steps
                lastAnnouncementTime = now
                previousIDs = currentIDs
                return
            }
            
            // 视觉兜底放在普通播报规则之前。
            // 原因：如果屏幕步数已经从 5 到 4，但加速度计漏检，
            // 我们宁愿补一个短数字，也不要继续等待或说完整句。
            if tryVisualCountdownFallback(now: now, isConfirmedStepUpdate: isConfirmedStepUpdate) {
                previousIDs = currentIDs
                return
            }
            
            // ----- 防抖 -----
            guard now.timeIntervalSince(lastAnnouncementTime) >= minAnnouncementInterval else {
                previousIDs = currentIDs
                return
            }
            
            // ----- 方位变化检测 -----
            // 倒数期间保持安静，避免方向短句打断数字节奏。
            if !isInCountdown && direction != lastAnnouncedDirection {
                let text = "\(candidate.detection.label), \(direction)"
                speech.speak(text)
                lastAnnouncedDirection = direction
                lastAnnouncedSteps = steps
                lastAnnouncementTime = now
                previousIDs = currentIDs
                return
            }
            
            // ----- 远距离：阈值播报 -----
            // 倒数入口已经由 tryVisualCountdownFallback() 统一处理：
            // confirmed step 可以立刻说 "5"，普通视觉帧只在步伐漏检后兜底说 "5"。
            // 这里保留的只是 7 步这类远距离简短更新。
            if !isInCountdown, let lastSteps = lastAnnouncedSteps, steps < lastSteps {
                
                // 检查是否刚跨入倒数范围（从 6+ 步降到 5 步以下）
                let enteredCountdown = lastSteps > countdownThreshold && steps <= countdownThreshold
                
                // 检查是否跨过远距离阈值
                let crossedThreshold = stepThresholds.first { threshold in
                    lastSteps > threshold && steps <= threshold
                }
                
                if crossedThreshold != nil && !enteredCountdown {
                    // 跨过远距离阈值 → 简短播报
                    // 如果这次同时跨进 5 步倒数范围，就不说 "chair, 5 steps"；
                    // 留给数字倒数说 "5"，避免完整句打断。
                    let text = buildBriefText(candidate)
                    speech.speak(text)
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
    
    // 步伐同步倒数
    //
    // 由 StepConverter 在检测到一步时调用（通过 onStepDetected 回调）
    //
    // 只在倒数模式下推进数字：
    //   读取 focusedCurrentSteps（update() 刷新的 LiDAR 最新距离）
    //   每个 confirmed step 推进一个倒数刻度
    //   如果实时估算和倒数刻度偏差很大 → 先说 "about N steps"
    //
    // 这样倒数节奏完全跟随用户的脚步：
    //   用户走得快 → 倒数快（因为步伐事件频率高）
    //   用户走得慢 → 倒数慢
    //   用户停下 → 倒数暂停（没有步伐事件触发）
    func handleStep(with detections: [Detection]) {
        
        // 米数模式不做步伐同步倒数
        // 所有播报由 update() 里的距离阈值驱动
        // 这是和步数模式最本质的区别：步伐事件不触发语音
        if distanceMode == .meters { return }
        
        // 这代表"主路"事件：加速度计已经确认用户迈了一步。
        // 记录时间后，视觉兜底会短暂让路，避免同一步被说两次。
        lastConfirmedStepTime = Date()
        
        // 先用这一次确认步伐时的最新感知结果刷新焦点和实时步数。
        // 这样语音倒数和屏幕步数都来自同一条：confirmed step -> latest distance -> current step estimate。
        update(with: detections, isConfirmedStepUpdate: true)
        
        // 前置条件检查
        guard focusedObjectID != nil else { return }
        guard let currentSteps = focusedCurrentSteps else { return }
        guard let lastSteps = lastAnnouncedSteps else { return }
        
        let now = Date()
        
        // 倒数模式下，语音遵守用户的心理预期：
        // 上次说 5，这次确认一步后默认应该说 4。
        // 不直接读 currentSteps，是为了避免 LiDAR/步长抖动让语音倒数跳来跳去。
        let expectedNextSteps = max(lastSteps - 1, urgentStepThreshold)
        let drift = abs(currentSteps - expectedNextSteps)
        
        // 如果动态步长让剩余步数发生明显修正，优先播报 "about N steps"。
        // 例如用户从快走突然放慢，系统估算从 5 修正到 8，就不要硬倒数到 4。
        if drift >= correctionStepDelta,
           currentSteps > urgentStepThreshold,
           now.timeIntervalSince(lastAnnouncementTime) >= minAnnouncementInterval {
            speech.speak(buildCorrectionText(steps: currentSteps))
            lastAnnouncedSteps = currentSteps
            lastAnnouncementTime = now
            return
        }
        
        // 只在倒数模式下生效（lastAnnouncedSteps <= 5）
        guard lastSteps <= countdownThreshold else { return }
        
        // 防抖：如果 update() 已经在本次 confirmed step 链路中播报，避免 handleStep() 立刻再播一次
        guard now.timeIntervalSince(lastAnnouncementTime) >= countdownMinInterval else { return }
        
        // confirmed step 正常推进倒数。
        // 这里不重复写 speech.speak / speakInterrupting 的细节，统一交给 helper。
        speakCountdownStep(expectedNextSteps)
        
        lastAnnouncedSteps = expectedNextSteps
        lastAnnouncementTime = now
    }
    
    // 当步伐检测漏掉，但视觉步数已经下降时，用视觉结果兜底推进倒数。
    //
    // 为什么需要这个函数？
    //   屏幕步数来自 LiDAR + 动态步长，所以它可能已经准确显示 4；
    //   但如果加速度计没有检测到那一步，handleStep() 不会被调用，语音就会卡在 5。
    //
    // 这个函数做的事情：
    //   1. 只在没有近期 confirmed step 时介入，避免和主路重复播报。
    //   2. 只在 currentSteps 真的比 lastAnnouncedSteps 小时播报，避免距离抖动。
    //   3. 只说短数字或 Stop，不说完整物体句。
    private func tryVisualCountdownFallback(now: Date, isConfirmedStepUpdate: Bool) -> Bool {
        
        // 米数模式没有倒数机制，不需要视觉兜底
        if distanceMode == .meters { return false }
        
        guard let currentSteps = focusedCurrentSteps else { return false }
        guard let lastSteps = lastAnnouncedSteps else { return false }
        
        // confirmed step 路径可以立即进入倒数；
        // 普通画面帧必须先等一小段时间，确认不是步伐事件马上要来了。
        let canEnterCountdown = isConfirmedStepUpdate || now.timeIntervalSince(lastConfirmedStepTime) >= visualCountdownFallbackDelay
        
        // 情况 A：还没正式进入倒数，但视觉步数已经从 6+ 变成 5 或更小。
        // 如果这是 confirmed step 路径，直接说 "5"；
        // 如果这是普通画面帧，只有在步伐漏检延迟后才兜底说 "5"。
        if lastSteps > countdownThreshold && currentSteps <= countdownThreshold {
            let minInterval = isConfirmedStepUpdate ? countdownMinInterval : visualCountdownMinInterval
            guard canEnterCountdown else { return false }
            guard now.timeIntervalSince(lastAnnouncementTime) >= minInterval else { return false }
            speakCountdownStep(currentSteps)
            lastAnnouncedSteps = max(currentSteps, urgentStepThreshold)
            lastAnnouncementTime = now
            return true
        }
        
        // 情况 B：已经在倒数中了，比如上次说了 5。
        // 只有屏幕步数真的降到 4、3、2、1 时才兜底播报。
        guard lastSteps <= countdownThreshold else { return false }
        guard currentSteps < lastSteps else { return false }
        guard now.timeIntervalSince(lastConfirmedStepTime) >= visualCountdownFallbackDelay else { return false }
        guard now.timeIntervalSince(lastAnnouncementTime) >= visualCountdownMinInterval else { return false }
        
        speakCountdownStep(currentSteps)
        lastAnnouncedSteps = max(currentSteps, urgentStepThreshold)
        lastAnnouncementTime = now
        return true
    }
    
    // 倒数模式的判定比 lastAnnouncedSteps 略宽：
    // - lastAnnouncedSteps <= 5：语音已经进入倒数
    // - focusedCurrentSteps <= 5：画面已经进入近距离，即使语音还没来得及说 5
    // 这样可以更早压制完整句，保护倒数体验。
    private var isCountdownActive: Bool {
        // 米数模式没有倒数概念，永远返回 false
        if distanceMode == .meters { return false }
        
        if let lastSteps = lastAnnouncedSteps, lastSteps <= countdownThreshold {
            return true
        }
        if let currentSteps = focusedCurrentSteps, currentSteps <= countdownThreshold {
            return true
        }
        return false
    }
    
    // 数字倒数统一从这里播，避免多个地方各自处理 "Stop"。
    private func speakCountdownStep(_ steps: Int) {
        if steps <= urgentStepThreshold {
            speech.speakInterrupting(finalCountdownText)
        } else {
            speech.speak("\(steps)")
        }
    }
    
    // =====================================================================
    // 米数模式：聚焦物体更新逻辑
    // =====================================================================
    
    // 由 update() 第五步在 distanceMode == .meters 时调用
    // 紧急距离 → 方位变化 → 距离阈值
    // 所有播报纯粹由 LiDAR 距离的阈值跨越驱动
    private func updateFocusedMetersMode(candidate: Candidate, direction: String, now: Date) {
        
        let currentDistance = candidate.distance
        
        // 紧急距离（< 0.5m）：立刻播报 Stop
        // 不受防抖限制，因为用户可能没在走路（物体在靠近用户）
        if currentDistance <= urgentMeterThreshold,
           let lastDist = lastAnnouncedDistance,
           lastDist > urgentMeterThreshold {
            speech.speakInterrupting(finalCountdownText)
            lastAnnouncedDistance = currentDistance
            lastAnnouncedSteps = candidate.steps
            lastAnnouncementTime = now
            return
        }
        
        // 防抖
        guard now.timeIntervalSince(lastAnnouncementTime) >= minAnnouncementInterval else { return }
        
        // 方位变化
        if direction != lastAnnouncedDirection {
            let text = "\(candidate.detection.label), \(direction)"
            speech.speak(text)
            lastAnnouncedDirection = direction
            lastAnnouncedSteps = candidate.steps
            lastAnnouncedDistance = currentDistance
            lastAnnouncementTime = now
            return
        }
        
        // 距离阈值跨越
        // 从 meterThresholds 中找到刚被跨过的最大阈值
        // 当我们在 3.5m 首报后，lastAnnouncedDistance = 3.5m
        // 距离降到 2.8m 时：
        //   3.0m：3.5 > 3.0 且 2.8 <= 3.0 → 匹配！播报，lastAnnouncedDistance = 2.8m
        // 距离降到 1.9m 时：
        //   3.0m：2.8 > 3.0？不满足 → 跳过（3m 阈值不会再触发）
        //   2.0m：2.8 > 2.0 且 1.9 <= 2.0 → 匹配！播报，lastAnnouncedDistance = 1.9m
        if let _ = meterThresholds.first(where: { threshold in
            (lastAnnouncedDistance ?? Float.greatestFiniteMagnitude) > threshold
                && currentDistance <= threshold
        }) {
            let text = buildBriefText(candidate)
            speech.speak(text)
            lastAnnouncedSteps = candidate.steps
            lastAnnouncedDistance = currentDistance
            lastAnnouncementTime = now
        }
    }
    
    // =====================================================================
    // 焦点管理
    // =====================================================================
    
    // 释放当前聚焦的物体
    // 下一帧 update 时，第四步会自动选一个新的物体
    private func releaseFocus() {
        
        // 在清空前保存快照，用于匹配可能由于 ID 重置而产生的“新”物体
        if let label = focusedObjectLabel, let steps = lastAnnouncedSteps {
            lastFocusMetadata = (
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
        return "\(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate))"
    }
    
    // 简短播报：物体名 + 步数（省略方位）
    // 用于步数阈值更新，用户已经知道方位了，只需要更新距离
    // 示例："chair, 3 steps"
    private func buildBriefText(_ candidate: Candidate) -> String {
        return "\(candidate.detection.label), \(formatDistance(candidate))"
    }
    
    // 紧急播报：warning + 物体名 + 方位 + 步数
    // 用于物体进入 1 步危险范围，或突然出现的近距离威胁
    // 示例："warning, chair, 12 o'clock, 1 step"
    private func buildUrgentText(_ candidate: Candidate) -> String {
        return "warning, \(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate))"
    }
    
    // 修正播报：动态步长发生明显变化时使用
    // 示例："about 8 steps"
    private func buildCorrectionText(steps: Int) -> String {
        let stepWord = steps == 1 ? "step" : "steps"
        return "about \(steps) \(stepWord)"
    }
    
    // =====================================================================
    // 距离格式化（根据当前模式返回步数或米数文本）
    // =====================================================================
    
    // 统一的距离文本生成器
    // 步数模式 → "7 steps"、"1 step"
    // 米数模式 → "3 meters"、"1.5 meters"、"1 meter"
    private func formatDistance(_ candidate: Candidate) -> String {
        switch distanceMode {
        case .steps:
            let stepWord = candidate.steps == 1 ? "step" : "steps"
            return "\(candidate.steps) \(stepWord)"
        case .meters:
            let rounded = (candidate.distance * 10).rounded() / 10
            let meterWord = rounded == 1.0 ? "meter" : "meters"
            return "\(String(format: "%.1f", rounded)) \(meterWord)"
        }
    }
}
