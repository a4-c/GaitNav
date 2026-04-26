import CoreMotion
import ARKit
import Combine

// 步长标定器 + 动态步长检测：
//   让用户走一段路，系统自动测量用户每一步有多长
//   测出来的步长用于后续把"障碍物距离2.1米"转换成"还有3步"
//
// 两种模式：
//   1. 静态标定模式：
//      用户点 Start → 记录手机当前位置（ARKit）+ 开始数步数（加速度计）
//      用户直线走路 → 每走一步，加速度计检测到波峰，步数 +1
//      用户点 Stop → 记录手机终点位置 → 算出走了多远
//      步长 = 总距离 / 总步数 → 存入本地存储
//
//   2. 动态检测模式：
//      app 运行时持续监测步伐，每一步实时计算步长
//      加速度计波峰检测发现一步 → 立刻从 ARKit 读取当前位置
//      和上一步的位置算距离 → 得到这一步的实际步长
//      用最近 N 步的滑动窗口平均值作为当前有效步长
//      用户走快了步长自动变大，走慢了自动变小
//
// 优先级：动态步长（走路中）> 标定步长（静止时）> 默认步长（从未标定）
class Calibrator: ObservableObject {
    
    // CMMotionManager：运动传感器管理器
    // 它是我们访问加速度计的入口
    private let motionManager = CMMotionManager()
    
    // ARSession 的引用，从 CameraManager 传过来
    weak var arSession: ARSession?
    
    // 标定完成后计算出的步长，单位：米
    @Published var calibratedStepLength: Float? = nil
    
    // 当前是否正在标定
    @Published var isCalibrating: Bool = false
    
    // 标定过程中的累计步数
    @Published var calibrationSteps: Int = 0
    
    // 标定时走过的总距离，单位：米
    @Published var calibrationDistance: Float? = nil
    
    // 状态提示信息，不同阶段显示不同的内容，引导用户操作
    @Published var statusMessage: String = ""
    
    // 标定开始时手机在 ARKit 世界坐标系中的位置
    private var startPosition: SIMD3<Float>? = nil
    
    // 是否正在运行动态检测
    // 和 isCalibrating 互斥：标定时暂停动态检测，标定完恢复
    private var isLiveDetectionRunning = false
    
    // 上一步被检测到时，手机在 ARKit 世界坐标系中的位置
    // 每检测到一个波峰，就记录当前位置，和这个值算距离
    // nil 表示还没有记录过（刚启动或刚恢复），下一步才能开始算
    private var lastStepPosition: SIMD3<Float>? = nil
    
    // 最近若干步的实测步长，用于滑动窗口平均
    // 比如最近 6 步的步长是 [0.62, 0.65, 0.63, 0.68, 0.64, 0.66]
    // 平均值 ≈ 0.65，就作为当前有效步长
    private var recentStepLengths: [Float] = []
    
    // 滑动窗口大小
    // 太小（2-3）：容易被单步异常带偏
    // 太大（15+）：步速变化时反应迟钝
    // 6 是一个折中：大约 3-4 秒的步行数据，足够平滑又不会太滞后
    private let stepLengthWindowSize = 6
    
    // 动态步长的有效期（秒）
    // 如果最后一步距离现在超过这个时间，认为用户已经停下来了
    // 停下来后动态步长不再可信（可能是站着不动的最后几步，不代表正常步态）
    // 回退到标定值或默认值
    private let dynamicStepTimeout: TimeInterval = 3.0
    
    // 最后一次成功计算出动态步长的时间
    // 非 private，因为 ContentView 需要读取它来判断是否显示动态标记
    var lastDynamicStepTime: Date = .distantPast
    
    // 当前动态计算出的步长（滑动窗口平均值）
    // 只在有足够数据且未超时时有值
    // @Published 是为了让 ContentView 右上角的步长显示能实时更新
    @Published var dynamicStepLength: Float? = nil
    
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
    
    // UserDefaults 的 key
    private let stepLengthKey = "calibratedStepLength"
    
    // 默认步长，单位：米
    // 当用户还没做过标定时，用这个值来换算步数
    // 这样即使第一次打开 app，看到障碍物也能显示"大约几步"
    private let defaultStepLength: Float = 0.65
    
    init() {
        // 尝试从 UserDefaults 读取之前保存的标定结果
        // .float(forKey:)：
        //   如果 key 存在且值可以转成 Float → 返回那个 Float 值
        //   如果 key 不存在 → 返回 0.0（Float 的默认"零值"）
        //   如果 key 存在但值不是数字 → 返回 0.0
        let saved = UserDefaults.standard.float(forKey: stepLengthKey)
        if saved > 0 {
            // 之前标定过，加载保存的步长
            calibratedStepLength = saved
            // 在界面上显示已保存的步长值
            statusMessage = "Saved step length: \(String(format: "%.2f", saved))m"
        } else {
            // 从没标定过，提示用户当前使用默认值
            statusMessage = "Not calibrated. Using default: \(defaultStepLength)m"
        }
    }
    
    // 每次访问时实时计算，不存储值
    // 外部模块（比如 DetectionOverlay 的距离→步数转换）不需要关心步长是怎么来的
    // 它们只需要调用 calibrator.effectiveStepLength，总能拿到一个合理的值
    //
    // 三级优先级：
    //   1. 动态步长（用户正在走，实时测量，最准）
    //   2. 标定步长（用户静止，但之前标定过）
    //   3. 默认步长（从未标定，兜底值）
    var effectiveStepLength: Float {
        // 检查动态步长是否有效（有值 + 未超时）
        if let dynamic = dynamicStepLength,
           Date().timeIntervalSince(lastDynamicStepTime) < dynamicStepTimeout {
            return dynamic
        }
        // 动态步长无效，回退到标定值或默认值
        return calibratedStepLength ?? defaultStepLength
    }
    
    // 动态步长当前是否处于活跃状态
    // ContentView 用它来决定是否显示 ⚡ 标记
    var isDynamicActive: Bool {
        dynamicStepLength != nil &&
        Date().timeIntervalSince(lastDynamicStepTime) < dynamicStepTimeout
    }
    
    // 由 ContentView.onAppear 调用，app 启动后持续运行
    func startLiveDetection() {
        
        // 防止重复启动，也防止和标定模式冲突
        guard !isLiveDetectionRunning, !isCalibrating else { return }
        
        // 检查设备是否有加速度计
        guard motionManager.isAccelerometerAvailable else { return }
        
        isLiveDetectionRunning = true
        
        // 重置动态检测的状态
        lastStepPosition = nil
        recentStepLengths = []
        dynamicStepLength = nil
        resetPeakDetection()
        
        // 设置采样间隔：每次读取加速度数据的时间间隔
        // 1.0 / 20.0 = 0.05 秒 = 50 毫秒
        // 也就是每秒采样 20 次（20Hz），和标定模式用相同的采样率
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
            self.processAcceleration(data: data, mode: .live)
        }
    }
    
    // 停止动态检测
    // 在 app 进入后台或者开始标定时调用
    func stopLiveDetection() {
        guard isLiveDetectionRunning else { return }
        // 加速度计停止采集数据，之前注册的回调闭包不再被触发
        motionManager.stopAccelerometerUpdates()
        isLiveDetectionRunning = false
    }
    
    // 检测到一步时的处理（动态模式）
    // 记录这一步的 ARKit 位置，和上一步的位置算距离 = 这一步的步长
    private func handleLiveStep() {
        
        // 从 ARKit 读取当前位置
        // .currentFrame → ARSession 的属性
        // 返回 ARKit 最新处理好的一帧数据（ARFrame 类型）
        guard let frame = arSession?.currentFrame else { return }
        
        // 从 ARFrame 提取手机在世界坐标系中的位置
        // frame.camera.transform 是一个 4×4 矩阵（simd_float4x4 类型）
        // columns.3 描述相机的位置（平移向量）→ 告诉你相机在世界中的 (x, y, z) 位置
        // columns.3 的类型是 SIMD4<Float>，包含 (x, y, z, w)
        // w 是齐次坐标的分量，在变换矩阵里始终为 1.0，我们不用它
        let pos = frame.camera.transform.columns.3
        
        // 把 SIMD4 转成 SIMD3（丢掉 w 分量，只保留 x, y, z）
        let currentPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        
        // 如果有上一步的位置，计算这一步的步长
        // if let 是 Swift 的"可选绑定"：
        //   如果 lastStepPosition 不是 nil，解包赋给 lastPos
        //   如果是 nil（第一步，没有上一步位置），跳过计算
        if let lastPos = lastStepPosition {
            
            // 计算水平距离（只算 x 和 z 方向，忽略 y 方向）
            // 因为步长的定义是"水平面上一步的前进距离"
            // 如果把 y 也算进去，距离会被略微高估
            let dx = currentPosition.x - lastPos.x
            let dz = currentPosition.z - lastPos.z
            let stepDist = sqrtf(dx * dx + dz * dz)
            
            // 合理性过滤：单步步长应该在 0.2 ~ 1.2 米之间
            // 超出范围说明可能是：
            //   太小（< 0.2m）：原地踏步 / ARKit 漂移
            //   太大（> 1.2m）：漏检了中间的步 / ARKit 跳变
            // 不合理的值直接丢弃，不影响窗口里的历史数据
            if stepDist > 0.2 && stepDist < 1.2 {
                recentStepLengths.append(stepDist)
                
                // 窗口满了，移除最旧的
                // 始终只保留最近 stepLengthWindowSize 步的数据
                if recentStepLengths.count > stepLengthWindowSize {
                    recentStepLengths.removeFirst()
                }
                
                // 至少积累 2 步才开始输出动态步长
                // 1 步的数据太不稳定，不足以代表用户的步态
                if recentStepLengths.count >= 2 {
                    // reduce(0, +)：从 0 开始，把数组里所有元素累加
                    // 除以个数 = 平均值
                    let avg = recentStepLengths.reduce(0, +) / Float(recentStepLengths.count)
                    dynamicStepLength = avg
                    lastDynamicStepTime = Date()
                }
            }
        }
        
        // 无论是否成功计算步长，都更新位置
        // 这样下一步就能从这个位置开始算
        lastStepPosition = currentPosition
    }
    
    // 用户点击 CalibrationView 上的 "Start" 按钮时调用
    func startCalibration() {
        
        // 标定开始前，暂停动态检测
        // 因为 CMMotionManager 的加速度计同一时间只能有一个 handler
        // 启动新的 startAccelerometerUpdates 会覆盖掉之前的回调
        // 标定结束后会自动恢复动态检测
        if isLiveDetectionRunning {
            stopLiveDetection()
        }
        
        // =============================================================
        // 第一步：记录起点位置
        // =============================================================
        
        // .currentFrame → ARSession 的属性
        // 返回 ARKit 最新处理好的一帧数据（ARFrame 类型）
        guard let frame = arSession?.currentFrame else {
            statusMessage = "ARKit not ready. Please wait."
            return
        }
        
        // 从 ARFrame 提取手机在世界坐标系中的位置
        // frame.camera.transform 是一个 4×4 矩阵（simd_float4x4 类型）
        // columns.3 描述相机的位置（平移向量）→ 告诉你相机在世界中的 (x, y, z) 位置
        // columns.3 的类型是 SIMD4<Float>，包含 (x, y, z, w)
        // w 是齐次坐标的分量，在变换矩阵里始终为 1.0，我们不用它
        let pos = frame.camera.transform.columns.3
        
        // 把 SIMD4 转成 SIMD3（丢掉 w 分量，只保留 x, y, z）
        startPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        
        // =============================================================
        // 第二步：重置所有状态
        // =============================================================
        
        // 步数归零
        calibrationSteps = 0
        // 清除上一次的标定距离
        calibrationDistance = nil
        // 清除上一次的标定步长
        // 这样 CalibrationView 的结果区域会隐藏
        calibratedStepLength = nil
        // 标记为正在标定
        isCalibrating = true
        // 更新状态提示
        statusMessage = "Walk now..."
        
        // 重置波峰检测的内部状态
        resetPeakDetection()
        
        // =============================================================
        // 第三步：启动加速度计
        // =============================================================
        
        // 检查设备是否有加速度计
        guard motionManager.isAccelerometerAvailable else {
            statusMessage = "Accelerometer not available."
            isCalibrating = false
            return
        }
        
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
            self.processAcceleration(data: data, mode: .calibration)
        }
    }
    
    // 用户点击 CalibrationView 上的 "Stop" 按钮时调用
    func stopCalibration() {
        
        // =============================================================
        // 第一步：停止加速度计
        // =============================================================
        
        // 加速度计停止采集数据，之前注册的回调闭包不再被触发
        motionManager.stopAccelerometerUpdates()
        
        // 更新标定状态
        isCalibrating = false
        
        // =============================================================
        // 第二步：验证前置条件
        // =============================================================
        
        // 确保有起点位置
        // 如果 startPosition 是 nil，说明 startCalibration 失败了或者没被调用
        guard let startPos = startPosition else {
            statusMessage = "Error: no start position."
            // 标定失败，恢复动态检测
            startLiveDetection()
            return
        }
        
        // 确保能从 ARKit 拿到当前帧（包含终点位置）
        guard let frame = arSession?.currentFrame else {
            statusMessage = "Error: ARKit not available."
            startLiveDetection()
            return
        }
        
        // 读取最终步数
        // 用 let 存成常量，后面多次使用
        let finalSteps = calibrationSteps
        
        // 验证步数是否足够
        // 步长 = 总距离 / 总步数
        // 总步数越少，每一步的误差对结果的影响越大
        // 5 步是一个最低要求，实际上建议走 10 步以上
        guard finalSteps >= 5 else {
            statusMessage = "Too few steps (\(finalSteps)). Walk at least 5 steps."
            startLiveDetection()
            return
        }
        
        // =============================================================
        // 第三步：计算行走距离
        // =============================================================
        
        // 取终点位置
        let endPos = frame.camera.transform.columns.3
        let endPosition = SIMD3<Float>(endPos.x, endPos.y, endPos.z)
        
        // 计算水平距离（只算 x 和 z 方向，忽略 y 方向）
        // 因为步长的定义是"水平面上一步的前进距离"
        // 如果把 y 也算进去，距离会被略微高估
        let dx = endPosition.x - startPos.x
        let dz = endPosition.z - startPos.z
        let distance = sqrtf(dx * dx + dz * dz)
        
        // 验证距离是否合理
        // 如果距离 < 1 米，可能的原因：
        //   用户在原地踏步（脚在动但没有向前移动）
        //   用户走了一个圈回到起点附近（距离是直线距离，不是路程）
        //   ARKit 追踪丢失（位置数据不准）
        // 这些情况下算出来的步长都没有意义
        guard distance > 1.0 else {
            statusMessage = "Distance too short (\(String(format: "%.1f", distance))m). Walk in a straight line."
            startLiveDetection()
            return
        }
        
        // =============================================================
        // 第四步：计算步长
        // =============================================================
        
        // 步长 = 总距离 / 总步数
        let stepLength = distance / Float(finalSteps)
        
        // 步长合理性检查
        // 正常人的单步步长范围：0.3 ~ 1.0 米
        //   < 0.2 米：几乎不可能，说明数据有问题
        //     可能原因：用户转圈走，直线距离很短但步数很多
        //   > 1.0 米：大步快走的极限，超过说明数据有问题
        //     可能原因：ARKit 位置漂移（追踪累积误差导致距离被高估）
        // 检测到异常就提示重试，不保存这个结果
        guard stepLength > 0.2 && stepLength < 1.0 else {
            statusMessage = "Result unreasonable (\(String(format: "%.2f", stepLength))m/step). Please retry."
            startLiveDetection()
            return
        }
        
        // =============================================================
        // 第五步：保存结果
        // =============================================================
        
        // 更新内存中的值
        // CalibrationView 会立刻显示结果区域
        calibratedStepLength = stepLength
        calibrationDistance = distance
        
        // 写入 UserDefaults，持久化到磁盘
        // 下次打开 app 时，init() 里的代码会读取这个值
        // 用户不需要每次打开 app 都重新标定
        UserDefaults.standard.set(stepLength, forKey: stepLengthKey)
        
        // 显示最终结果
        // 把所有关键数据展示给用户，让他们确认是否合理
        statusMessage = "Done! \(finalSteps) steps, \(String(format: "%.1f", distance))m → step: \(String(format: "%.2f", stepLength))m"
        
        // 清理起点位置
        startPosition = nil
        
        // 标定完成，恢复动态检测
        startLiveDetection()
    }
    
    // 两种模式的区别只在于"检测到一步后做什么"
    //   calibration：步数 +1，更新界面上的步数显示
    //   live：记录 ARKit 位置，和上一步的位置算距离
    private enum DetectionMode {
        case calibration
        case live
    }
    
    // 标定模式和动态模式共用同一套波峰检测算法
    private func processAcceleration(data: CMAccelerometerData, mode: DetectionMode) {
        
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
                    
                    // 根据模式执行不同操作
                    switch mode {
                        
                    case .calibration:
                        // 步数 +1
                        calibrationSteps += 1
                        // 更新界面上的步数显示
                        statusMessage = "\(calibrationSteps) steps..."
                        
                    case .live:
                        // 记录 ARKit 位置，计算单步步长
                        handleLiveStep()
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
    
    // 对外提供的方法，距离 → 步数
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
}
