import ARKit
import Combine

// 步态流水线：步伐检测 → 步长标定和动态步长估算
// 当前类型作为步态协调器存在：负责连接子模块、切换模式并分发确认步伐事件
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
//
// 拆分说明：
//   GaitCoordinator 现在只负责协调子模块；CoreMotion、检测算法和步长解析分别下沉到独立类型。
//   这样外部调用方式保持不变，同时每个子模块都可以单独测试。
class GaitCoordinator: ObservableObject, StepDistanceConverting {
    
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
    // 确保 ContentView 持有的 GaitCoordinator 也能感知到变化
    @Published var calibrator = Calibrator()
    
    // 动态步长估算器：实时逐步计算步长
    private let dynamicEstimator = DynamicStepEstimator()
    
    // 步伐检测参数：统一提供采样间隔、阈值比率和 EMA 默认值
    private let stepDetectionConfiguration = StepDetectionConfiguration()
    
    // 加速度计：只负责 CoreMotion 采样和合加速度计算
    private lazy var accelerometer = Accelerometer(updateInterval: stepDetectionConfiguration.accelerometerUpdateInterval)
    
    // 自适应步伐检测器：只负责根据合加速度确认有效步伐
    private lazy var stepDetector = AdaptiveStepDetector(configuration: stepDetectionConfiguration)
    
    // 步长解析器：统一处理动态、标定、默认步长的三级优先级
    private lazy var stepLengthResolver = StepLengthResolver(dynamicEstimator: dynamicEstimator, calibrator: calibrator)
    
    // =====================================================================
    // 模式管理
    // =====================================================================
    
    // 当前的步伐分发模式
    //   .profiling：确认的步伐发给 GaitProfiler（EMA 从初始值开始收敛）
    //   .live：步伐事件发给 DynamicStepEstimator + FeedbackEngine
    //   .calibration：步伐事件发给 Calibrator
    private enum Mode {
        case profiling
        case live
        case calibration
    }
    
    // 默认使用 live 模式，让 app 启动后可以直接进行导航
    private var currentMode: Mode = .live
    
    // =====================================================================
    // Combine 订阅
    // =====================================================================
    
    // 存储 Combine 订阅，防止被提前释放
    private var cancellables = Set<AnyCancellable>()
    
    // 步伐事件回调：每检测到一步就触发
    // FeedbackEngine 通过这个回调来同步倒数播报和实际步伐
    // 只在 .live 模式下触发（标定模式下步伐由 Calibrator 处理）
    var onStepDetected: (() -> Void)?
    
    // =====================================================================
    // 初始化
    // =====================================================================
    
    init() {
        // 从 GaitProfiler 加载已保存的 EMA 值（如果做过 profiling）
        // 否则使用保守默认值，系统会在前几步内自动收敛
        stepDetector.applyProfile(savedDetectionProfile)
        
        // 设置 GaitProfiler 的回调
        // 分析开始时：切换到 profiling 模式（重置 EMA）
        // 分析结束时：将已收敛的 EMA 传给 GaitProfiler 保存，恢复 live 模式
        gaitProfiler.onProfilingStarted = { [weak self] in
            self?.switchToProfilingMode()
        }
        gaitProfiler.onProfilingStopped = { [weak self] in
            guard let self = self else { return }
            // 将当前已收敛的 EMA 值传给 GaitProfiler 保存到 UserDefaults
            let currentProfile = self.stepDetector.currentProfile
            // 将检测器当前的波峰 EMA 和步间隔 EMA 一并持久化
            self.gaitProfiler.saveProfile(
                peakDevEma: currentProfile.peakDevEma,
                intervalEma: currentProfile.intervalEma
            )
            // profiling 结束后恢复 live 模式，继续正常导航
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
        // GaitCoordinator 自己的 objectWillChange 也会触发
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
    
    // 对外保留原有嵌套类型名称，避免调用方感知步长解析器的内部拆分
    typealias StepLengthSource = StepLengthResolver.Source

    // 每次访问时实时计算，不存储值
    // 外部模块（比如 DetectionOverlay）不需要关心步长是怎么来的
    // 只需要调用 gaitCoordinator.effectiveStepLength，总能拿到一个合理的值
    var effectiveStepLength: Float {
        // 委托给步长解析器，统一应用动态、标定和默认值三级优先级
        return stepLengthResolver.effectiveStepLength
    }
    
    // 稳定引导步长：用于保持倒数前的语音距离一致。
    // 这里刻意忽略短时间内波动较大的动态步长估计。
    var stableStepLength: Float {
        // 委托给步长解析器，确保稳定路径不读取动态步长
        return stepLengthResolver.stableStepLength
    }
    
    // 当前 effectiveStepLength 的值从哪一级取到的
    // SettingsView 用它来高亮对应的优先级行和徽章
    var stepLengthSource: StepLengthSource {
        // 委托给步长解析器，确保展示状态和实际计算使用同一套规则
        return stepLengthResolver.stepLengthSource
    }
    
    // 用户是否曾经成功标定过（本次内存中有值，或磁盘上有历史记录）
    // SettingsView 用它来决定按钮文案是 "Recalibrate" 还是 "Calibrate Now"
    var hasEverCalibrated: Bool {
        calibrator.hasEverCalibrated
    }
    
    // 清除已经保存的标定步长，并同步停用依赖标定结果的动态步长估算
    func clearCalibratedStepLength() {
        // 删除持久化标定结果并同步清空 Calibrator 的界面状态
        calibrator.clearCalibratedStepLength()
        // 清除已经积累的动态步长，确保 baseline 立即恢复为固定 0.65 米默认值
        dynamicEstimator.reset()
    }
    
    // 用户是否曾经成功做过步态分析
    // SettingsView 用它来决定按钮文案是 "Re-profile" 还是 "Profile Now"
    var hasEverProfiled: Bool {
        gaitProfiler.hasEverProfiled
    }
    
    // 动态步长当前是否处于活跃状态
    // ContentView 用它来决定是否显示 ⚡ 标记
    var isDynamicActive: Bool {
        // 委托给步长解析器，确保 UI 和距离换算使用同一个动态活跃判定
        return stepLengthResolver.isDynamicActive
    }
    
    // 视觉倒数兜底等待时间：使用当前步间隔 EMA 加一个加速度计采样周期作为余量
    var visualCountdownFallbackDelay: TimeInterval {
        // 读取步伐检测器当前学习到的步间隔 EMA，让等待窗口跟随用户实际步频变化
        let currentStepInterval = stepDetector.currentProfile.intervalEma
        // 在一个步周期后再多等一个采样周期，降低视觉兜底抢在确认步伐前播报的概率
        return currentStepInterval + stepDetectionConfiguration.accelerometerUpdateInterval
    }
    
    // 距离 → 步数转换
    func distanceToSteps(_ distance: Float) -> Int {
        // 委托给步长解析器，继续使用向上取整的安全策略
        return stepLengthResolver.distanceToSteps(distance)
    }
    
    // 使用稳定的标定/默认步长换算距离。
    // FeedbackEngine 在倒数前使用它，避免剩余步数反向增加造成混乱。
    func distanceToStableSteps(_ distance: Float) -> Int {
        // 委托给步长解析器，确保倒数前的语音距离尺度保持稳定
        return stepLengthResolver.distanceToStableSteps(distance)
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
        stepDetector.resetToDefaultProfile()
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
        stepDetector.applyProfile(savedDetectionProfile)
        // 以标定模式重新启动加速度计
        currentMode = .calibration
        startStepDetection()
    }
    
    // 标定结束时调用：恢复动态检测模式
    private func switchToLiveMode() {
        // 先停掉标定模式的加速度计
        stopStepDetection()
        // 从 UserDefaults 加载个性化 EMA
        stepDetector.applyProfile(savedDetectionProfile)
        // 以动态模式重新启动加速度计
        currentMode = .live
        startStepDetection()
    }
    
    // 从 GaitProfiler 的持久化结果构建检测器需要的 EMA 档案
    private var savedDetectionProfile: StepDetectionProfile {
        // 没有 profiling 数据时分别回退到配置提供的保守默认值
        return StepDetectionProfile(
            peakDevEma: gaitProfiler.effectivePeakDevEma ?? stepDetectionConfiguration.defaultPeakDevEma,
            intervalEma: gaitProfiler.effectiveIntervalEma ?? stepDetectionConfiguration.defaultIntervalEma
        )
    }

    // =====================================================================
    // 开启 / 关闭 步伐检测
    // =====================================================================
    
    // 启动加速度计并开始步伐检测
    private func startStepDetection() {
        
        // 防止重复启动
        guard !accelerometer.isRunning else { return }
        
        // 检查设备是否有加速度计
        guard accelerometer.isAvailable else { return }
        
        // 重置状态机，避免上一个模式的残留状态影响新模式
        stepDetector.resetDetectionState()
        
        // 开始接收合加速度，并把每次采样交给自适应步伐检测器
        accelerometer.start { [weak self] magnitude, timestamp in
            // pipeline 已经释放时忽略后续采样，避免闭包延长生命周期
            self?.handleAccelerationMagnitude(magnitude, at: timestamp)
        }
    }
    
    // 停止加速度计
    private func stopStepDetection() {
        // 委托采集层停止 CoreMotion，并清除采集器内部运行标记
        accelerometer.stop()
    }
    
    // 接收采集层计算好的合加速度，并在确认一步后触发模式分发
    private func handleAccelerationMagnitude(_ magnitude: Double, at timestamp: Date) {
        // 没有确认有效步伐时保持安静，等待后续采样
        guard stepDetector.process(magnitude: magnitude, at: timestamp) else { return }
        // 确认有效步伐后，根据当前模式交给对应子模块处理
        dispatchConfirmedStep()
    }
    
    // 根据当前模式分发步伐事件
    private func dispatchConfirmedStep() {
        // 根据当前模式分发步伐事件
        switch currentMode {
            
        case .profiling:
            // 步态分析模式：通知 GaitProfiler 计数
            gaitProfiler.handleStep()
            
        case .calibration:
            // 标定模式：步伐由 Calibrator 处理
            calibrator.handleStep()
            
        case .live:
            // 只有完成标定后才收集动态步长，让默认模式保持固定 0.65 米 baseline
            // 标定结果存在时才启用完整 gait-adaptive 管线
            if calibrator.effectiveStepLength != nil {
                // 动态模式：步伐由 DynamicStepEstimator 处理
                // 将当前确认步伐交给动态估算器，用于近场实时修正
                dynamicEstimator.handleStep()
                // 动态步长更新后，通知 SwiftUI 刷新界面
                // 因为 effectiveStepLength 可能变了
                // 动态值变化后刷新步长展示和来源标签
                objectWillChange.send()
            } // 结束已标定状态下的动态步长采集
            // 通知 FeedbackEngine：用户走了一步
            // FeedbackEngine 会据此决定是否播报倒数数字
            onStepDetected?()
        }
    }
}
