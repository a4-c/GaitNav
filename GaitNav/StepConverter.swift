import CoreMotion
import ARKit
import Combine

// 步长转换器：步伐检测 → 步长标定和动态步长估算
//
// 职责：
//   1. 拥有 CMMotionManager，运行波峰检测算法（共享基础设施）
//   2. 根据当前模式，把"检测到一步"的事件分发给 Calibrator 或 DynamicStepEstimator
//   3. 提供三级优先级的 effectiveStepLength 和 distanceToSteps() 对外接口
//   4. 协调标定和动态检测的模式切换
//
// 三级优先级：
//   动态步长（用户正在走，实时测量）> 标定步长（用户静止，但之前标定过）> 默认步长（从未标定，兜底值）
class StepConverter: ObservableObject {
    
    // =====================================================================
    // 子模块
    // =====================================================================
    
    // 标定器：管理标定流程和 UI 状态
    // CalibrationView 需要观察它，所以是 @Published
    // 当 Calibrator 内部的 @Published 属性变化时
    // objectWillChange 会沿着 @Published 链条冒泡上来
    // 确保 ContentView 持有的 StepConverter 也能感知到变化
    @Published var calibrator = Calibrator()
    
    // 动态步长估算器：实时逐步计算步长
    private let dynamicEstimator = DynamicStepEstimator()
    
    // =====================================================================
    // 加速度计 & 波峰检测
    // =====================================================================
    
    // CMMotionManager：运动传感器管理器
    // 它是访问加速度计的入口
    private let motionManager = CMMotionManager()
    
    // 每次新数据到来时，用当前值和这个值比较：
    //   当前值 > lastAcceleration → 加速度在增大，正在往波峰走
    //   当前值 < lastAcceleration → 加速度在减小，正在往波谷走
    //   当前值 == lastAcceleration → 平稳（实际很少发生）
    private var lastAcceleration: Double = 0
    
    // 当前加速度是否处于上升趋势
    // 这个标志用来判断"波峰"：
    //   波峰的定义 = 值先上升（isRising = true），然后开始下降
    //   所以当 isRising == true 且当前值 < 上一次的值时 → 刚过了一个波峰
    // 初始值 false：
    //   第一次采样前不认为在上升，需要看到至少一次"值变大"才开始
    private var isRising = false
    
    // 波峰检测阈值
    // 只有合加速度超过这个值的波峰才算"走了一步"
    // 低于这个值的波峰被认为是噪声（手抖、呼吸等微小振动）
    private let stepThreshold: Double = 1.1
    
    // 上一次成功检测到步伐的时间
    // 用于防抖机制
    // .distantPast 代表一个极其遥远的过去时间
    //   这样第一步检测时：
    //     now.timeIntervalSince(.distantPast) = 一个巨大的正数
    //     肯定 > 0.3 秒
    //     所以第一步不会被误拦
    private var lastStepTime: Date = .distantPast
    
    // 两步之间的最短时间间隔（秒）
    // 这是防抖机制的参数
    // 如果两个波峰之间的间隔 < 0.3 秒，第二个波峰会被忽略
    private let minStepInterval: TimeInterval = 0.3
    
    // =====================================================================
    // 模式管理
    // =====================================================================
    
    // 当前加速度计是否在运行
    private var isAccelerometerRunning = false
    
    // 当前的步伐分发模式
    //   .live：步伐事件发给 DynamicStepEstimator
    //   .calibration：步伐事件发给 Calibrator
    private enum Mode {
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
        // 设置 Calibrator 的回调
        // 标定开始时：切换到标定模式
        // 标定结束时：恢复动态检测模式
        calibrator.onCalibrationStarted = { [weak self] in
            self?.switchToCalibrationMode()
        }
        calibrator.onCalibrationStopped = { [weak self] in
            self?.switchToLiveMode()
        }
        
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
    //   2. 标定步长
    //   3. 默认步长
    var effectiveStepLength: Float {
        // 1. 动态步长（实时）
        if let dynamic = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return dynamic
        }
        // 2. 本次内存中的标定值
        if let cal = calibrator.calibratedStepLength {
            return cal
        }
        // 3. UserDefaults 里的历史标定值
        let saved = UserDefaults.standard.float(forKey: "calibratedStepLength")
        if saved > 0 { return saved }
        // 4. 默认值
        return defaultStepLength
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
    
    // 标定开始时调用：暂停动态检测，切换到标定模式
    private func switchToCalibrationMode() {
        // 先停掉当前的加速度计
        stopStepDetection()
        // 重置动态估算器的状态（标定结束后会从零开始重新积累）
        dynamicEstimator.reset()
        // 以标定模式重新启动加速度计
        currentMode = .calibration
        startStepDetection()
    }
    
    // 标定结束时调用：恢复动态检测模式
    private func switchToLiveMode() {
        // 先停掉标定模式的加速度计
        stopStepDetection()
        // 以动态模式重新启动加速度计
        currentMode = .live
        startStepDetection()
    }
    
    // =====================================================================
    // 开启 / 关闭 步伐检测
    // =====================================================================
    
    // 启动加速度计并开始波峰检测
    private func startStepDetection() {
        
        // 防止重复启动
        guard !isAccelerometerRunning else { return }
        
        // 检查设备是否有加速度计
        guard motionManager.isAccelerometerAvailable else { return }
        
        isAccelerometerRunning = true
        
        // 重置波峰检测的内部状态
        // 避免上一个模式的残留数据影响新模式
        resetPeakDetection()
        
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
    // 波峰检测算法
    // =====================================================================
    
    // 检测到步伐后，根据 currentMode 分发给 Calibrator 或 DynamicStepEstimator
    private func checkForStep(data: CMAccelerometerData) {
        
        // 计算合加速度（magnitude）
        // 它表示三个方向加速度的总和
        // 不管手机怎么放，合加速度都只反映"总加速度的大小"
        // 静止时始终 ≈ 1.0（因为重力），走路时 > 1.0
        // 阈值只需要设一个，适用于所有姿势
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        let magnitude = sqrt(x * x + y * y + z * z)
        
        // 波峰检测算法
        if magnitude > lastAcceleration {
            
            // 当前值比上一次大 → 加速度在增大 → 标记为上升趋势
            isRising = true
        
        } else if isRising {
            
            // 当前值 ≤ 上一次 且 之前在上升 → 转折点 → 波峰
            // 此时 lastAcceleration 就是波峰的值
            // 先把 isRising 重置为 false
            isRising = false
            
            // 检查条件1：波峰够大吗？
            if lastAcceleration > stepThreshold {
                
                // 检查条件2：距上一步时间够长吗？（防抖）
                let now = Date()
                if now.timeIntervalSince(lastStepTime) > minStepInterval {
                    
                    // 两个条件都满足 → 确认这是真的一步
                    // 记录这一步的时间，供下次防抖比较
                    lastStepTime = now
                    
                    // 根据当前模式分发步伐事件
                    switch currentMode {
                    
                    case .calibration:
                        calibrator.handleStep()
                    
                    case .live:
                        dynamicEstimator.handleStep()
                        // 动态步长更新后，通知 SwiftUI 刷新界面
                        // 因为 effectiveStepLength 可能变了
                        objectWillChange.send()
                        // 通知 FeedbackManager：用户走了一步
                        // FeedbackManager 会据此决定是否播报倒数数字
                        onStepDetected?()
                    }
                
                }
                // else：时间间隔太短，这个波峰是落地振荡，忽略
            }
            // else：波峰太矮，这是噪声不是步伐，忽略
        }
        // else：值在减小且之前不是上升中 → 继续下降，什么都不做
        
        // 保存当前值，下次采样时用来比较趋势
        lastAcceleration = magnitude
    }
    
    // 重置波峰检测的内部状态
    // 在模式切换时调用，避免上一个模式的残留数据影响新模式
    private func resetPeakDetection() {
        lastAcceleration = 0
        isRising = false
        lastStepTime = .distantPast
    }
}
