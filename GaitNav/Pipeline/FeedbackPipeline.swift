import Foundation
import ARKit

// 反馈流水线：决定"什么时候说什么"
//
// 设计原则（来自倒车雷达模型）：
//   1. 漏斗原则：一次只关注一个障碍物（最危险的那个）
//      等它被绕过或消失后，再切到下一个。避免"报菜名"。
//   2. 两段式反馈：
//      远距离（> 5 步）→ 语音播报物体名 + 方位 + 步数，只在关键阈值时触发
//      近距离（≤ 5 步）→ 步伐同步倒数，用户每走一步说一个数字
//      1 步 → 最后一句短促行动提示（"Stop"）
//   3. 倒数与步伐同步：
//      倒数模式下的数字播报由 GaitPipeline 的步伐检测事件驱动
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
class FeedbackPipeline {
    
    // 语音引擎：负责实际的 TTS 播报
    private let speech: SpeechManager
    private let configuration = FeedbackConfiguration()
    private let formatter = FeedbackAnnouncementFormatter()
    private let candidateBuilder = FeedbackCandidateBuilder()
    private let metersPolicy = MetersFeedbackPolicy()
    private let stepsPolicy = StepsFeedbackPolicy()
    private let countdownController = CountdownController()
    private var focusState = FeedbackFocusState()
    
    // 步态流水线：把距离（米）转成步数
    // weak 防止循环引用
    private weak var gaitPipeline: GaitPipeline?
    
    // 反馈距离单位：步数 or 米数
    var distanceMode: FeedbackDistanceMode
    
    init(speech: SpeechManager, gaitPipeline: GaitPipeline, distanceMode: FeedbackDistanceMode = .steps) {
        self.speech = speech
        self.gaitPipeline = gaitPipeline
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
        
        guard let gaitPipeline = gaitPipeline else { return }
        
        let now = Date()
        let currentIDs = Set(detections.map { $0.id })
        
        // =================================================================
        // 第一步：构建候选列表
        // =================================================================
        
        let candidates = candidateBuilder.buildCandidates(
            from: detections,
            previousIDs: focusState.previousIDs,
            gaitPipeline: gaitPipeline,
            distanceMode: distanceMode,
            isCountdownActive: isCountdownActive,
            configuration: configuration,
            formatter: formatter
        )
        
        // =================================================================
        // 第二步：检查聚焦物体是否还有效
        // =================================================================
        
        // 先记录进入 update() 时是否已经在倒数模式。
        // 注意这里要在刷新 focusState.focusedCurrentSteps 之前判断：
        // 如果已经进入倒数，就不要因为动态步长抖动导致"步数变大"而释放焦点。
        let wasInCountdown = isCountdownActive
        
        if let focusID = focusState.focusedObjectID {
            
            if !currentIDs.contains(focusID) {
                // 物体从画面中消失了（用户走过了它，或者它离开了视野）
                // 释放焦点，让系统选下一个
                focusState.releaseFocus()
            
            } else if let focused = candidates.first(where: { $0.detection.id == focusID }),
                      let lastSteps = focusState.lastAnnouncedSteps,
                      !wasInCountdown,
                      focused.steps > lastSteps + configuration.releaseStepIncrease {
                // 用户在远离这个物体（步数在增加）
                // 可能是用户绕过了它，或者转向走了别的方向
                // 但倒数模式中不做这个判断，避免 5、4、3 时突然切物体并插入完整句。
                focusState.releaseFocus()
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
                && candidate.steps <= configuration.suddenAppearanceThreshold
                && candidate.isCenter {
                
                // 倒数期间不要让 2-3 步的新物体完整句打断节奏；
                // 只有真正 1 步以内的危险仍然允许打断。
                if isCountdownActive && candidate.steps > configuration.urgentStepThreshold {
                    continue
                }
                
                // 构建播报文案 & 播报
                let text: String
                if candidate.steps <= configuration.urgentStepThreshold {
                    // 1 步以内 → 带 warning 前缀
                    text = formatter.urgentText(for: candidate, mode: distanceMode)
                    // 打断式播报（最紧急）
                    speech.speakInterrupting(text)
                } else {
                    // 2-3 步 → 完整播报但不带 warning
                    text = formatter.fullText(for: candidate, mode: distanceMode)
                    // 普通播报，但仍然抢占焦点
                    speech.speak(text)
                }
                
                focusState.focus(on: candidate, now: now)
                
                focusState.previousIDs = currentIDs
                return
            }
        }
        
        // =================================================================
        // 第四步：如果没有聚焦物体，选一个新的
        // =================================================================
        
        if focusState.focusedObjectID == nil {
            
            // 策略：优先寻找匹配刚丢失焦点的“新”物体，防止 ID 闪烁打断
            if let metadata = focusState.lastFocusMetadata, now.timeIntervalSince(metadata.time) < 1.0 {
                if let recovered = candidates.first(where: {
                    $0.detection.label == metadata.label &&
                    abs($0.steps - metadata.steps) <= 2
                }) {
                    focusState.recoverFocus(on: recovered)
                }
            }
            
            // 如果上述匹配失败，则按常规逻辑选一个
            if focusState.focusedObjectID == nil {
                // 选择策略：
                //   优先选路径中央最近的物体（最挡路的那个）
                //   如果中央没有，选侧边但很近（3 步以内）的物体
                //   如果都没有，保持安静（前方一片空旷，不需要播报）
                let best = candidates.first(where: { $0.isCenter })
                    ?? candidates.first(where: { $0.steps <= 3 })
                
                if let candidate = best {
                    // 首次播报：完整信息（物体名 + 方位 + 步数）
                    // 建立用户的空间映射
                    let text = formatter.fullText(for: candidate, mode: distanceMode)
                    speech.speak(text)
                    
                    focusState.focus(on: candidate, now: now)
                    
                    focusState.previousIDs = currentIDs
                    return
                }
            }
        }
        
        // =================================================================
        // 第五步：更新聚焦物体
        // =================================================================
        //
        // update() 在这一步负责：
        //   - 每帧刷新 focusState.focusedCurrentSteps（给 handleStep 用）
        //   - 检测方位变化
        //   - 远距离阈值播报
        //   - 倒数模式入口（说 "5"）
        //   - 紧急警告（1 步以内，不能等步伐事件，必须立刻触发）
        //
        // update() 不负责：
        //   - 倒数模式下的数字播报（4, 3, 2）→ 由 handleStep() 处理
        
        if let focusID = focusState.focusedObjectID,
           let candidate = candidates.first(where: { $0.detection.id == focusID }) {
            
            // 每帧刷新实时步数，供 handleStep() 读取
            // 这是 update() 和 handleStep() 之间的数据桥梁
            focusState.refreshCurrentFocus(candidate)
            
            // 米数模式：
            //   只看距离阈值：跨过 10m/5m/3m/2m/1m 时简短更新，< 0.5m 时说 Stop
            //   所有播报由画面帧的距离变化驱动，和用户步伐无关
            if distanceMode == .meters {
                metersPolicy.updateInMetersMode(
                    candidate: candidate,
                    direction: candidate.direction,
                    now: now,
                    focusState: &focusState,
                    configuration: configuration,
                    formatter: formatter,
                    speech: speech,
                    distanceMode: distanceMode
                )
                focusState.previousIDs = currentIDs
                return
            }
            
            if stepsPolicy.updateInStepsMode(
                candidate: candidate,
                now: now,
                isConfirmedStepUpdate: isConfirmedStepUpdate,
                distanceMode: distanceMode,
                focusState: &focusState,
                configuration: configuration,
                formatter: formatter,
                countdownController: countdownController,
                speech: speech
            ) {
                focusState.previousIDs = currentIDs
                return
            }
        }
        
        // =================================================================
        // 更新帧间状态
        // =================================================================
        focusState.previousIDs = currentIDs
    }
    
    // 步伐同步倒数
    //
    // 由 GaitPipeline 在检测到一步时调用（通过 onStepDetected 回调）
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
    func handleStep(with detections: [Detection]) {
        
        // 米数模式不做步伐同步倒数
        // 所有播报由 update() 里的距离阈值驱动
        // 这是和步数模式最本质的区别：步伐事件不触发语音
        if distanceMode == .meters { return }
        
        // 这代表"主路"事件：加速度计已经确认用户迈了一步。
        // 记录时间后，视觉兜底会短暂让路，避免同一步被说两次。
        focusState.lastConfirmedStepTime = Date()
        
        // 先用这一次确认步伐时的最新感知结果刷新焦点和实时步数。
        // 这样语音倒数和屏幕步数都来自同一条：confirmed step -> latest distance -> current step estimate。
        update(with: detections, isConfirmedStepUpdate: true)
        
        countdownController.handleConfirmedStep(
            focusState: &focusState,
            configuration: configuration,
            formatter: formatter,
            speech: speech
        )
    }
    
    // 倒数模式的判定比 focusState.lastAnnouncedSteps 略宽：
    // - focusState.lastAnnouncedSteps <= 5：语音已经进入倒数
    // - focusState.focusedCurrentSteps <= 5：画面已经进入近距离，即使语音还没来得及说 5
    // 这样可以更早压制完整句，保护倒数体验。
    private var isCountdownActive: Bool {
        countdownController.isCountdownActive(
            focusState: focusState,
            distanceMode: distanceMode,
            configuration: configuration
        )
    }
}
