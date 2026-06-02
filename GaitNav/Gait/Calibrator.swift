import ARKit
import Combine

// 步长标定器：引导用户走一段路来测量个人步长
//
// 流程：
//   用户点 Start → 记录手机当前位置（ARKit）+ 开始数步数
//   用户直线走路 → 每走一步，步数 +1（步伐检测由 GaitCoordinator 负责）
//   用户点 Stop → 记录手机终点位置 → 算出走了多远
//   步长 = 总距离 / 总步数 → 存入本地存储
//
// ObservableObject 是因为 CalibrationView 需要观察它的 @Published 属性
class Calibrator: ObservableObject {
    
    // ARSession 的引用，用于读取起点和终点的位置
    // weak 防止循环引用
    weak var arSession: ARSession?
    
    // 这次标定完成后计算出的步长，单位：米
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
    
    // UserDefaults 的 key
    private let stepLengthKey = "calibratedStepLength"
    
    // 标定开始 / 结束时通知 GaitCoordinator
    // GaitCoordinator 需要知道标定状态，以便切换加速度计的模式
    //   onCalibrationStarted：标定开始 → GaitCoordinator 暂停动态检测，切换到标定模式
    //   onCalibrationStopped：标定结束 → GaitCoordinator 恢复动态检测
    var onCalibrationStarted: (() -> Void)?
    var onCalibrationStopped: (() -> Void)?
    
    // 当前可用的标定步长
    // 没有返回 nil，由 GaitCoordinator 决定用默认值
    var effectiveStepLength: Float? {
        let saved = UserDefaults.standard.float(forKey: stepLengthKey)
        return saved > 0 ? saved : nil
    }
    
    // 用户是否曾经成功标定过
    // 判断依据是 UserDefaults 中有没有保存过步长
    var hasEverCalibrated: Bool {
        UserDefaults.standard.float(forKey: stepLengthKey) > 0
    }
    
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
            statusMessage = "Not calibrated. Using default: 0.65m"
        }
    }
    
    // GaitCoordinator 在检测到一步时调用
    // 只在 isCalibrating == true 时有意义，否则忽略
    func handleStep() {
        guard isCalibrating else { return }
        // 步数 +1
        calibrationSteps += 1
        // 更新界面上的步数显示
        statusMessage = "\(calibrationSteps) steps..."
    }

    // 清除已经保存的标定步长，让后续稳定步长计算回退到默认值
    func clearCalibratedStepLength() {
        // 从 UserDefaults 中删除持久化的标定步长，避免下次启动 app 时重新加载旧值
        UserDefaults.standard.removeObject(forKey: stepLengthKey)
        // 同步清除内存中的标定步长，让设置页立刻刷新为未标定状态
        calibratedStepLength = nil
        // 同步清除上一次标定距离，避免界面继续保留已经失效的标定结果
        calibrationDistance = nil
        // 同步清除上一次标定步数，确保下一次打开标定页时不展示旧进度
        calibrationSteps = 0
        // 更新状态提示，明确告知用户当前稳定步长已经回退到默认值
        statusMessage = "Calibration cleared. Using default: 0.65m"
    }
    
    // 用户点击 CalibrationView 上的 "Start" 按钮时调用
    func startCalibration() {
        
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
        
        // =============================================================
        // 第三步：通知 GaitCoordinator 切换到标定模式
        // =============================================================
        
        // GaitCoordinator 收到后会：
        //   暂停动态检测 → 重置波峰检测状态 → 开始把步伐事件分发给 Calibrator
        onCalibrationStarted?()
    }
    
    // 用户点击 CalibrationView 上的 "Stop" 按钮时调用
    func stopCalibration() {
        
        // 更新标定状态
        isCalibrating = false
        
        // =============================================================
        // 第一步：验证前置条件
        // =============================================================
        
        // 确保有起点位置
        // 如果 startPosition 是 nil，说明 startCalibration 失败了或者没被调用
        guard let startPos = startPosition else {
            statusMessage = "Error: no start position."
            // 标定失败，通知 GaitCoordinator 恢复动态检测
            onCalibrationStopped?()
            return
        }
        
        // 确保能从 ARKit 拿到当前帧（包含终点位置）
        guard let frame = arSession?.currentFrame else {
            statusMessage = "Error: ARKit not available."
            onCalibrationStopped?()
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
            onCalibrationStopped?()
            return
        }
        
        // =============================================================
        // 第二步：计算行走距离
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
            onCalibrationStopped?()
            return
        }
        
        // =============================================================
        // 第三步：计算步长
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
            onCalibrationStopped?()
            return
        }
        
        // =============================================================
        // 第四步：保存结果
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
        
        // =============================================================
        // 第五步：通知 GaitCoordinator 恢复动态检测
        // =============================================================
        
        onCalibrationStopped?()
    }
}
