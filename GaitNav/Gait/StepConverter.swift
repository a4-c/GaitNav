import CoreMotion
import ARKit
import Combine

// 步长转换器：步伐检测 → 步长标定和动态步长估算
//
// 职责：
//   1. 拥有 CMMotionManager，运行自适应步伐检测算法（共享基础设施）
//   2. 根据当前模式，把"检测到一步"的事件分发给 GaitProfiler / Calibrator / DynamicStepEstimator
//   3. 提供三级优先级的 effectiveStepLength 和 distanceToSteps() 对外接口
//   4. 协调步态分析、标定和动态检测的模式切换
//
// 步伐检测算法：双阈值迟滞状态机 + EMA 动态阈值
//   核心思想：
//     - 用指数移动平均（EMA）持续追踪近期波峰的强度，从中推导出自适应阈值
//     - 用双阈值迟滞（Schmitt trigger）防止信号在阈值附近抖动造成重复计数
//     - 用 EMA 追踪步间隔，动态调整最小步间隔（防抖）
//   所有检测参数都是信号处理比率，不依赖特定个体的步态特征
//   详见 "信号处理参数" 区域的注释
//
// 三级优先级：
//   动态步长（用户正在走，实时测量）> 标定步长（用户静止，但之前标定过）> 默认步长（从未标定，兜底值）
class StepConverter: ObservableObject {
    
    // =====================================================================
    // 子模块
    // =====================================================================
    
    // 步态分析器：让自适应状态机收敛到个性化参数
    // 必须在 Calibrator 之前运行 —— Calibrator 的计步依赖准确的检测参数
    // GaitProfilerView 需要观察它，所以是 @Published
    @Published var gaitProfiler = GaitProfiler()
    
    // 标定器：管理标定流程和 UI 状态
    // CalibrationView 需要观察它，所以是 @Published
    // 当 Calibrator 内部的 @Published 属性变化时
    // objectWillChange 会沿着 @Published 链条冒泡上来
    // 确保 ContentView 持有的 StepConverter 也能感知到变化
    @Published var calibrator = Calibrator()
    
    // 动态步长估算器：实时逐步计算步长
    private let dynamicEstimator = DynamicStepEstimator()
    
    // =====================================================================
    // [实验] 距离日志（Distance Estimation Accuracy 实验用）
    // 每次点击 Log Distance 时，读取最近检测物体的 stableDistance，实验结束后删除
    // =====================================================================
    
    // 单条距离记录
    struct DistanceLogEntry {
        // 试验编号（自动递增）
        let trialID: Int
        // 系统估计距离（stableDistance）
        let estimatedDistance: Float
        // 检测到的物体标签
        let objectLabel: String
        // 记录时间
        let timestamp: Date
    }
    
    // 距离日志数组
    private(set) var distanceLog: [DistanceLogEntry] = []
    
    // 已记录的距离数量（@Published 驱动 UI 实时显示计数）
    @Published var distanceLogCount: Int = 0
    
    // =====================================================================
    // 加速度计
    // =====================================================================
    
    // CMMotionManager：运动传感器管理器
    // 它是访问加速度计的入口
    private let motionManager = CMMotionManager()
    
    // =====================================================================
    // 自适应步伐检测：状态机
    // =====================================================================
    //
    // 双阈值迟滞（Schmitt trigger）状态机
    //   比简单的"local max > threshold"更鲁棒
    //   信号必须先升至 TH_HIGH 以上，再回落至 TH_LOW 以下，才算确认一个波峰
    //   这天然防止了信号在阈值附近的小幅抖动造成的重复计数
    //
    //   状态转换：
    //     waitingPeak -> (偏差 > TH_HIGH) -> peakTracking
    //     peakTracking -> (偏差 < TH_LOW) -> waitingPeak（确认一步）
    //     peakTracking 期间持续追踪最大偏差值，用于更新 EMA
    
    // 状态机的两个状态
    private enum PeakDetectionState {
        case waitingPeak   // 等待信号升至上阈值
        case peakTracking  // 正在追踪一个波峰，记录最大偏差
    }
    
    // 当前状态
    private var peakState: PeakDetectionState = .waitingPeak
    
    // peakTracking 状态下追踪到的最大偏差（重力基线以上的部分）
    // 当信号回落至 TH_LOW 以下时，这个值就是本次波峰的确认偏差
    private var trackingMaxDev: Double = 0
    
    // =====================================================================
    // 自适应步伐检测：EMA 动态阈值
    // =====================================================================
    //
    // 指数移动平均（EMA）持续追踪两个量：
    //   1. peakDevEma：近期步伐波峰的平均偏差（合加速度超过重力基线的部分）
    //      → 从中推导出 TH_HIGH 和 TH_LOW
    //   2. intervalEma：近期步伐的平均时间间隔
    //      → 从中推导出最小步间隔（防抖）
    //
    // EMA 更新公式：ema = α × 新值 + (1−α) × 旧值
    // 其中 α = 0.2，代表最近 ~5 次观测贡献约 63% 的权重
    //
    // 初始值来自 GaitProfiler 的保存结果（如果做过 profiling）
    // 否则使用保守的默认值，系统会在用户走的前几步内自动收敛
    
    // 波峰偏差的 EMA（单位：g，相对于重力基线）
    // 代表"用户近期步伐波峰的平均强度"
    private var peakDevEma: Double = 0.05
    
    // 步伐间隔的 EMA（单位：秒）
    // 代表"用户近期步伐的平均周期"
    private var intervalEma: TimeInterval = 0.5
    
    // 上一次成功检测到步伐的时间
    // 用于计算步间隔和防抖
    // .distantPast 代表一个极其遥远的过去时间
    //   这样第一步检测时：
    //     now.timeIntervalSince(.distantPast) = 一个巨大的正数
    //     肯定 > 最小步间隔
    //     所以第一步不会被误拦
    private var lastStepTime: Date = .distantPast
    
    // 上一次确认波峰的时间（用于静止衰减判断）
    private var lastPeakConfirmTime: Date = .distantPast
    
    // =====================================================================
    // 信号处理参数（比率，非绝对值）
    // =====================================================================
    //
    // 以下参数全部是信号处理领域的标准比率
    // 它们相对于用户自身的信号，不依赖任何特定个体的步态特征
    // 因此不需要通过实验来确定，可以直接引用信号处理文献
    
    // 重力基线：静止时合加速度的值
    // 这是物理常数（1g），不是可调参数
    private let gravityBaseline: Double = 1.0
    
    // EMA 平滑因子：每次更新时新值的权重
    // α = 0.2 是指数平滑的标准选择
    // 含义：初始值的残余权重 = (1−α)^n
    //   5 步后：(0.8)^5 = 0.33 → 初始值只剩 33% 影响
    //   10 步后：(0.8)^10 = 0.11 → 基本收敛
    // 平衡了响应速度（快速适应步态变化）和稳定性（不因单步异常而跳变）
    private let emaAlpha: Double = 0.2
    
    // 阈值比率：TH_HIGH = gravityBaseline + peakDevEma × peakThresholdRatio
    // 将检测阈值设为近期平均波峰强度的 70%
    // 含义：步伐加速度的步间变异系数约 20-30%
    //   阈值设在均值的 70%，大约位于均值 − 1σ
    //   理论上能捕获 ~84% 的步伐（单侧正态分布）
    //   加上 EMA 持续适应，实际捕获率更高
    // 参考：Pan & Tompkins (1985) 使用同族方法设定自适应阈值
    private let peakThresholdRatio: Double = 0.7
    
    // 迟滞比率：TH_LOW = TH_HIGH × hysteresisRatio
    // 标准 Schmitt trigger 设计使用 40-60% 的迟滞带
    // 0.6 意味着信号必须回落到 TH_HIGH 的 60% 以下才确认波峰结束
    // 这保证了一个完整的"升—降"起伏，避免小幅抖动重复触发
    private let hysteresisRatio: Double = 0.6
    
    // 步间隔保护比率：minStepInterval = intervalEma × intervalGuardRatio
    // 将最小步间隔设为平均步周期的 70%
    // 含义：正常步频自然波动约 ±15%，最快步伐约为均值的 85%
    //   70% 留出了足够余量，只拦截明显的同步弹跳（bounce）
    private let intervalGuardRatio: Double = 0.7
    
    // 最小步间隔绝对下限（单位：秒）
    // 基于人类短跑的运动学数据：
    // Tyson Gay 在 2009 年世锦赛 100m 决赛中达到 4.68 步/秒（0.214 秒/步）
    // 0.2 秒略低于此极限，确保即使是顶级短跑运动员的步伐也不会被误拦
    // 数据来源：Pose Method 对 Berlin 2009 世锦赛的运动学分析
    // 这是任何步频都不可能低于的物理下限
    private let minAbsoluteInterval: TimeInterval = 0.2
    
    // 静止衰减超时（单位：秒）
    // 如果超过此时间没有确认任何波峰，开始将 EMA 向默认值衰减
    // 2 秒 ≈ 4 个正常步周期（0.5s × 4），足以确认用户已停止走路
    private let decayTimeout: TimeInterval = 2.0
    
    // EMA 默认值：未做 profiling 时的保守初始值
    // peakDevEma = 0.05g → 对应 TH_HIGH = 1.035g（能检测大多数人的步伐）
    // intervalEma = 0.5s → 对应正常步频 2 步/秒
    // defaultPeakDevEma 同时也是阈值的绝对下限：
    //   衰减逻辑确保 peakDevEma 永远不会低于此值
    //   → TH_HIGH 最低 = 1.0 + 0.05 × 0.7 = 1.035g
    //   → 远高于静止状态下的传感器噪声（约 0.01-0.02g RMS）
    //   → 不需要额外的绝对下限参数
    private let defaultPeakDevEma: Double = 0.05
    private let defaultIntervalEma: TimeInterval = 0.5
    
    // =====================================================================
    // 动态阈值（从 EMA 实时计算）
    // =====================================================================
    
    // 上阈值：信号偏差超过此值 → 进入 peakTracking 状态
    // 由于衰减逻辑保证 peakDevEma ≥ defaultPeakDevEma (0.05)
    // TH_HIGH 最低 = 1.0 + 0.05 × 0.7 = 1.035，不需要额外下限
    private var thresholdHigh: Double {
        gravityBaseline + peakDevEma * peakThresholdRatio
    }
    
    // 下阈值：信号偏差低于此值 → 确认波峰，回到 waitingPeak 状态
    private var thresholdLow: Double {
        gravityBaseline + peakDevEma * peakThresholdRatio * hysteresisRatio
    }
    
    // 动态最小步间隔：从步间隔 EMA 实时计算
    private var effectiveMinStepInterval: TimeInterval {
        max(intervalEma * intervalGuardRatio, minAbsoluteInterval)
    }
    
    // =====================================================================
    // 模式管理
    // =====================================================================
    
    // 当前加速度计是否在运行
    private var isAccelerometerRunning = false
    
    // 当前的步伐分发模式
    //   .profiling：确认的步伐发给 GaitProfiler（EMA 从初始值开始收敛）
    //   .live：步伐事件发给 DynamicStepEstimator + FeedbackManager
    //   .calibration：步伐事件发给 Calibrator
    private enum Mode {
        case profiling
        case live
        case calibration
    }
    
    private var currentMode: Mode = .live
    
    // =====================================================================
    // 默认值
    // =====================================================================
    
    // 默认步长，单位：米
    // 当用户还没做过标定时，用这个值来换算步数
    // 这样即使第一次打开 app，看到障碍物也能显示"大约几步"
    private let defaultStepLength: Float = 0.65
    
    // =====================================================================
    // Combine 订阅
    // =====================================================================
    
    // 存储 Combine 订阅，防止被提前释放
    private var cancellables = Set<AnyCancellable>()
    
    // 步伐事件回调：每检测到一步就触发
    // FeedbackManager 通过这个回调来同步倒数播报和实际步伐
    // 只在 .live 模式下触发（标定模式下步伐由 Calibrator 处理）
    var onStepDetected: (() -> Void)?
    
    // =====================================================================
    // 初始化
    // =====================================================================
    
    init() {
        // 从 GaitProfiler 加载已保存的 EMA 值（如果做过 profiling）
        // 否则使用保守默认值，系统会在前几步内自动收敛
        peakDevEma = gaitProfiler.effectivePeakDevEma ?? defaultPeakDevEma
        intervalEma = gaitProfiler.effectiveIntervalEma ?? defaultIntervalEma
        
        // 设置 GaitProfiler 的回调
        // 分析开始时：切换到 profiling 模式（重置 EMA）
        // 分析结束时：将已收敛的 EMA 传给 GaitProfiler 保存，恢复 live 模式
        gaitProfiler.onProfilingStarted = { [weak self] in
            self?.switchToProfilingMode()
        }
        gaitProfiler.onProfilingStopped = { [weak self] in
            guard let self = self else { return }
            // 将当前已收敛的 EMA 值传给 GaitProfiler 保存到 UserDefaults
            self.gaitProfiler.saveProfile(
                peakDevEma: self.peakDevEma,
                intervalEma: self.intervalEma
            )
            self.switchToLiveMode()
        }
        
        // 设置 Calibrator 的回调
        // 标定开始时：切换到标定模式
        // 标定结束时：恢复动态检测模式
        calibrator.onCalibrationStarted = { [weak self] in
            self?.switchToCalibrationMode()
        }
        calibrator.onCalibrationStopped = { [weak self] in
            self?.switchToLiveMode()
        }
        
        // 订阅 GaitProfiler 的 objectWillChange
        // 确保 SwiftUI 界面能感知到 GaitProfiler 的变化
        gaitProfiler.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // 订阅 Calibrator 的 objectWillChange
        // 这样当 Calibrator 内部的 @Published 属性变化时
        // StepConverter 自己的 objectWillChange 也会触发
        // 确保 SwiftUI 界面能感知到 Calibrator 的变化
        calibrator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // =====================================================================
    // ARSession 设置
    // =====================================================================
    
    // 把 ARSession 传递给需要它的子模块
    func setARSession(_ session: ARSession) {
        calibrator.arSession = session
        dynamicEstimator.arSession = session
    }
    
    // =====================================================================
    // 对外接口
    // =====================================================================
    
    // 每次访问时实时计算，不存储值
    // 外部模块（比如 DetectionOverlay）不需要关心步长是怎么来的
    // 只需要调用 stepConverter.effectiveStepLength，总能拿到一个合理的值
    //
    // 三级优先级：
    //   1. 动态步长
    //   2. 标定步长（本次或历史）
    //   3. 默认步长
    var effectiveStepLength: Float {
        // 检查动态步长是否有效（有值 + 未超时）
        if let dynamic = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return dynamic
        }
        // 动态步长无效，回退到标定值
        // 都没有则使用默认值
        return calibrator.effectiveStepLength ?? defaultStepLength
    }
    
    // 稳定引导步长：用于保持倒数前的语音距离一致。
    // 这里刻意忽略短时间内波动较大的动态步长估计。
    var stableStepLength: Float {
        return calibrator.effectiveStepLength ?? defaultStepLength
    }
    
    // 当前 effectiveStepLength 的值从哪一级取到的
    // SettingsView 用它来高亮对应的优先级行和徽章
    //
    // .dynamic      → 动态估算器有值且未超时
    // .calibrated   → Calibrator 有可用的标定值（本次或历史）
    // .defaultValue → 以上都没有，使用 0.65m 兜底
    enum StepLengthSource {
        case dynamic, calibrated, defaultValue
    }
    
    var stepLengthSource: StepLengthSource {
        if let _ = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return .dynamic
        }
        if calibrator.effectiveStepLength != nil {
            return .calibrated
        }
        return .defaultValue
    }
    
    // 用户是否曾经成功标定过（本次内存中有值，或磁盘上有历史记录）
    // SettingsView 用它来决定按钮文案是 "Recalibrate" 还是 "Calibrate Now"
    var hasEverCalibrated: Bool {
        calibrator.hasEverCalibrated
    }
    
    // 用户是否曾经成功做过步态分析
    // SettingsView 用它来决定按钮文案是 "Re-profile" 还是 "Profile Now"
    var hasEverProfiled: Bool {
        gaitProfiler.hasEverProfiled
    }
    
    // 动态步长当前是否处于活跃状态
    // ContentView 用它来决定是否显示 ⚡ 标记
    var isDynamicActive: Bool {
        dynamicEstimator.isActive
    }
    
    // 距离 → 步数转换
    func distanceToSteps(_ distance: Float) -> Int {
        
        // 步数 = 距离 / 步长
        let steps = distance / effectiveStepLength
        
        // 为什么向上取整而不是四舍五入（round）？
        //
        //   四舍五入：3.088 → 3 步
        //     用户以为还有 3 步就到了
        //     实际可能 3 步走完还差一点点，但用户已经放松了
        //
        //   向上取整：3.088 → 4 步
        //     用户以为还有 4 步
        //     多报一步 → 用户会走得更谨慎 → 更安全
        //
        //   对于视障辅助来说，"安全"比"精确"更重要
        //   多走一步没事，少走一步可能撞上障碍物
        return Int(ceil(steps))
    }
    
    // 使用稳定的标定/默认步长换算距离。
    // FeedbackManager 在倒数前使用它，避免剩余步数反向增加造成混乱。
    func distanceToStableSteps(_ distance: Float) -> Int {
        return Int(ceil(distance / stableStepLength))
    }
    
    // =====================================================================
    // 启动 / 停止
    // =====================================================================
    
    // 由 ContentView.onAppear 调用，启动动态步长检测
    func start() {
        currentMode = .live
        startStepDetection()
    }
    
    // 由 ContentView.onDisappear 调用，停止加速度计
    // app 进后台或视图消失时应当停止，避免白费电
    func stop() {
        stopStepDetection()
    }
    
    // =====================================================================
    // 模式切换
    // =====================================================================
    
    // 步态分析开始时调用：重置 EMA 到默认值，切换到 profiling 模式
    // EMA 重置是因为 profiling 的目的是从零开始学习用户的步态特征
    // 如果保留旧 EMA，profiling 就失去了意义
    private func switchToProfilingMode() {
        stopStepDetection()
        dynamicEstimator.reset()
        // 重置 EMA 到保守初始值，让自适应算法从零开始收敛
        peakDevEma = defaultPeakDevEma
        intervalEma = defaultIntervalEma
        currentMode = .profiling
        startStepDetection()
    }
    
    // 标定开始时调用：暂停动态检测，切换到标定模式
    private func switchToCalibrationMode() {
        // 先停掉当前的加速度计
        stopStepDetection()
        // 重置动态估算器的状态（标定结束后会从零开始重新积累）
        dynamicEstimator.reset()
        // 从 UserDefaults 加载个性化 EMA
        peakDevEma = gaitProfiler.effectivePeakDevEma ?? defaultPeakDevEma
        intervalEma = gaitProfiler.effectiveIntervalEma ?? defaultIntervalEma
        // 以标定模式重新启动加速度计
        currentMode = .calibration
        startStepDetection()
    }
    
    // 标定结束时调用：恢复动态检测模式
    private func switchToLiveMode() {
        // 先停掉标定模式的加速度计
        stopStepDetection()
        // 从 UserDefaults 加载个性化 EMA
        peakDevEma = gaitProfiler.effectivePeakDevEma ?? defaultPeakDevEma
        intervalEma = gaitProfiler.effectiveIntervalEma ?? defaultIntervalEma
        // 以动态模式重新启动加速度计
        currentMode = .live
        startStepDetection()
    }
    
    // =====================================================================
    // 开启 / 关闭 步伐检测
    // =====================================================================
    
    // 启动加速度计并开始步伐检测
    private func startStepDetection() {
        
        // 防止重复启动
        guard !isAccelerometerRunning else { return }
        
        // 检查设备是否有加速度计
        guard motionManager.isAccelerometerAvailable else { return }
        
        isAccelerometerRunning = true
        
        // 重置状态机，避免上一个模式的残留状态影响新模式
        resetDetectionState()
        
        // 设置采样间隔：每次读取加速度数据的时间间隔
        // 1.0 / 20.0 = 0.05 秒 = 50 毫秒
        // 也就是每秒采样 20 次（20Hz）
        motionManager.accelerometerUpdateInterval = 1.0 / 20.0
        
        // 开始接收加速度计数据，直到调用 stopAccelerometerUpdates() 为止
        // to: .main：指定回调在主线程执行
        // withHandler: { data, error in ... }：
        //   这个闭包每 0.05 秒被调用一次
        //   data：CMAccelerometerData 类型，包含本次采样的加速度值
        //     data.acceleration.x / .y / .z 分别是三个方向的加速度（单位是 g）
        //   error：如果出错，这里不是 nil
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.checkForStep(data: data)
        }
    }
    
    // 停止加速度计
    private func stopStepDetection() {
        guard isAccelerometerRunning else { return }
        // 加速度计停止采集数据，之前注册的回调闭包不再被触发
        motionManager.stopAccelerometerUpdates()
        isAccelerometerRunning = false
    }
    
    // =====================================================================
    // 自适应步伐检测算法
    // =====================================================================
    
    // 每个加速度计采样到达时调用
    // 实现双阈值迟滞状态机 + EMA 动态阈值
    private func checkForStep(data: CMAccelerometerData) {
        
        // 计算合加速度（magnitude）
        // 它表示三个方向加速度的总和
        // 不管手机怎么放，合加速度都只反映"总加速度的大小"
        // 静止时始终 ≈ 1.0（因为重力），走路时 > 1.0
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        let magnitude = sqrt(x * x + y * y + z * z)
        
        // 双阈值迟滞状态机
        switch peakState {
            
        case .waitingPeak:
            // 等待信号升至上阈值（TH_HIGH）
            // 合加速度超过 thresholdHigh → 进入 peakTracking 状态
            if magnitude > thresholdHigh {
                peakState = .peakTracking
                trackingMaxDev = magnitude - gravityBaseline
            }
            
        case .peakTracking:
            // 正在追踪波峰，持续记录最大偏差
            let currentDev = magnitude - gravityBaseline
            if currentDev > trackingMaxDev {
                trackingMaxDev = currentDev
            }
            
            // 信号回落至下阈值（TH_LOW）以下 → 确认一个完整的波峰
            // trackingMaxDev 就是这次波峰的峰值偏差
            if magnitude < thresholdLow {
                confirmPeak(peakDeviation: trackingMaxDev)
                peakState = .waitingPeak
            }
        }
        
        // 静止衰减：长时间没有确认波峰 → 缓慢降低 EMA
        // 防止高强度走路后突然放慢导致阈值过高，新的轻步伐无法被检测到
        checkDecay()
    }
    
    // 波峰确认后的处理：更新 EMA、检查步间隔、分发步伐事件
    private func confirmPeak(peakDeviation: Double) {
        let now = Date()
        
        // 更新波峰偏差 EMA：追踪近期步伐的平均强度
        // EMA 公式：ema = α × 新值 + (1−α) × 旧值
        peakDevEma = emaAlpha * peakDeviation + (1 - emaAlpha) * peakDevEma
        
        // 记录波峰确认时间（用于静止衰减判断）
        lastPeakConfirmTime = now
        
        // 最小步间隔检查（防抖）
        // 如果距上一步时间太短，这个波峰是同一步的弹跳而非新步伐
        let interval = now.timeIntervalSince(lastStepTime)
        guard interval > effectiveMinStepInterval else { return }
        
        // 更新步间隔 EMA（仅在合理范围内更新，防止停顿期间的超长间隔污染 EMA）
        if interval > minAbsoluteInterval && interval < 2.0 {
            intervalEma = emaAlpha * interval + (1 - emaAlpha) * intervalEma
        }
        
        // 记录这一步的时间
        lastStepTime = now
        
        // 根据当前模式分发步伐事件
        switch currentMode {
            
        case .profiling:
            // 步态分析模式：通知 GaitProfiler 计数
            gaitProfiler.handleStep()
            
        case .calibration:
            // 标定模式：步伐由 Calibrator 处理
            calibrator.handleStep()
            
        case .live:
            // 动态模式：步伐由 DynamicStepEstimator 处理
            dynamicEstimator.handleStep()
            // 动态步长更新后，通知 SwiftUI 刷新界面
            // 因为 effectiveStepLength 可能变了
            objectWillChange.send()
            // 通知 FeedbackManager：用户走了一步
            // FeedbackManager 会据此决定是否播报倒数数字
            onStepDetected?()
        }
    }
    
    // 静止衰减：防止高阈值锁死
    // 场景：用户快走（EMA 升高 → 阈值升高）→ 突然慢走或停下
    //   如果 EMA 不衰减，阈值会卡在高位，轻步伐永远达不到阈值
    //   → EMA 永远不更新 → 系统锁死
    // 衰减机制打破这个死锁：超时后将 EMA 缓慢向默认值靠拢
    private func checkDecay() {
        let timeSinceLastPeak = Date().timeIntervalSince(lastPeakConfirmTime)
        // 超过静止超时且 EMA 仍高于默认值 → 逐步衰减
        // 每个采样周期衰减 0.2%（与 EMA α = 0.2 对应的每采样微调）
        // 在 20Hz 采样率下：
        //   1 秒后（20 采样）：0.998^20 = 0.961 → 衰减 4%
        //   5 秒后（100 采样）：0.998^100 = 0.819 → 衰减 18%
        //   足够缓慢，不会在短暂停顿时破坏已收敛的 EMA
        if timeSinceLastPeak > decayTimeout && peakDevEma > defaultPeakDevEma {
            peakDevEma = max(peakDevEma * 0.998, defaultPeakDevEma)
        }
    }
    
    // 重置状态机
    // 在模式切换时调用，避免上一个模式的残留状态影响新模式
    private func resetDetectionState() {
        peakState = .waitingPeak
        trackingMaxDev = 0
        lastStepTime = .distantPast
        lastPeakConfirmTime = .distantPast
    }
    
    // =====================================================================
    // [实验] 距离日志控制方法（实验结束后删除）
    // =====================================================================
    
    // 从当前检测列表中找到最近的物体，记录一条距离日志
    // 返回记录成功与否（没有可用检测时返回 false）
    @discardableResult
    func logDistance(from detections: [Detection]) -> Bool {
        // 找到有距离信息的最近物体
        guard let nearest = detections
            .filter({ $0.distance != nil })
            .min(by: { $0.distance! < $1.distance! }),
              let distance = nearest.distance
        else { return false }
        
        let entry = DistanceLogEntry(
            trialID: distanceLog.count + 1,
            estimatedDistance: distance,
            objectLabel: nearest.label,
            timestamp: Date()
        )
        distanceLog.append(entry)
        distanceLogCount = distanceLog.count
        return true
    }
    
    // 导出距离日志为 CSV 字符串
    // target_distance 留空，实验后在 CSV 中手动填入真实距离
    func exportDistanceLogCSV() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var csv = "trial_id,target_distance,estimated_distance,object_label,timestamp\n"
        for entry in distanceLog {
            let ts = formatter.string(from: entry.timestamp)
            let line = "\(entry.trialID),,\(String(format: "%.4f", entry.estimatedDistance)),\(entry.objectLabel),\(ts)"
            csv += line + "\n"
        }
        return csv
    }
    
    // 清空距离日志
    func clearDistanceLog() {
        distanceLog.removeAll()
        distanceLogCount = 0
    }
}

