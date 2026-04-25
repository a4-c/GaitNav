import CoreMotion
import ARKit
import Combine

// 步长标定器：
//   1. 引导用户走一段路，利用 CMPedometer 计步 + ARKit 测距
//   2. 计算个人步长 = 距离 / 步数
//   3. 把结果存入 UserDefaults，下次打开 app 直接加载
//   4. 提供 distanceToSteps() 方法，供其他模块把米转成步数
class Calibrator: ObservableObject {
    
    // CMPedometer：Apple 提供的计步器
    // 步数非常准确，但有几秒的延迟（攒一批再推送）
    // 对标定来说延迟无所谓，我们只需要"走完之后的总步数"
    private let pedometer = CMPedometer()
    
    // ARSession 的引用，从 CameraManager 传进来
    // 用来在标定开始和结束时读取手机在 3D 空间中的位置
    // weak 防止循环引用（PedometerManager 不拥有 ARSession）
    weak var arSession: ARSession?
    
    // 标定完成后计算出的步长（米）
    // nil = 还没标定过，或者标定失败了
    // 有值 = 标定成功，比如 0.68 表示一步走 0.68 米
    @Published var calibratedStepLength: Float? = nil
    
    // 当前是否正在标定
    // true = 用户已经点了"开始"，正在走路中
    // false = 还没开始，或者已经结束
    @Published var isCalibrating: Bool = false
    
    // 标定过程中的累计步数
    // 标定开始时重置为 0，走的过程中实时增加
    @Published var calibrationSteps: Int = 0
    
    // 标定时走过的总距离（米）
    @Published var calibrationDistance: Float? = nil
    
    // 状态提示信息，显示在界面上指导用户
    // 不同阶段会显示不同的文字
    @Published var statusMessage: String = ""
    
    // 标定开始时手机在 ARKit 世界坐标系中的位置
    //
    // SIMD3<Float> 是一个三维向量 (x, y, z)：
    //   x = 左右方向的位置
    //   y = 上下方向的位置（垂直高度）
    //   z = 前后方向的位置
    //
    // 工作流程：
    //   用户点"开始" → 记录当前位置到 startPosition
    //   用户走路...
    //   用户点"结束" → 再取一次当前位置
    //   两个位置之间的水平距离 = 走过的总距离
    //
    // Optional 因为标定还没开始时没有起点
    private var startPosition: SIMD3<Float>? = nil
    
    // UserDefaults 是 iOS 提供的轻量级持久化存储
    // 数据以 key-value（键值对）的形式存在磁盘上
    // app 关掉再打开，数据还在
    //
    // 基本用法：
    //   存：UserDefaults.standard.set(0.68, forKey: "myKey")
    //   取：UserDefaults.standard.float(forKey: "myKey")
    //   删：UserDefaults.standard.removeObject(forKey: "myKey")
    private let stepLengthKey = "calibratedStepLength"
    
    // 默认步长：0.65米（成年人平均单步步长的保守估计）
    // 如果用户还没做过标定，就用这个值来换算步数
    private let defaultStepLength: Float = 0.65
    
    init() {
        // 尝试从 UserDefaults 读取之前标定过的步长
        // float(forKey:) 的行为：
        //   如果这个 key 存在且值是数字 → 返回那个数字
        //   如果这个 key 不存在（从没标定过）→ 返回 0.0（Float 的默认值）
        // 所以用 > 0 来判断是否标定过
        let saved = UserDefaults.standard.float(forKey: stepLengthKey)
        if saved > 0 {
            calibratedStepLength = saved
            statusMessage = "Saved step length: \(String(format: "%.2f", saved))m"
        } else {
            statusMessage = "Not calibrated. Using default: \(defaultStepLength)m"
        }
    }
    
    // 这是外部模块应该调用的属性（调用方不需要关心"有没有标定过"，直接用这个值就行）
    // 优先返回标定过的值，没标定过就返回默认值
    var effectiveStepLength: Float {
        calibratedStepLength ?? defaultStepLength
    }
    
    // 用户点击"Start"按钮时调用
    func startCalibration() {
        
        // ===================================================================
        // 第一步：记录起点位置
        // ===================================================================
        
        // 从 ARSession 拿到最新一帧数据
        // currentFrame 是 ARSession 的属性，随时可以读取
        // 不像 session(_:didUpdate:) 那样需要等回调
        guard let frame = arSession?.currentFrame else {
            statusMessage = "ARKit not ready. Please wait."
            return
        }
        
        // 从 ARFrame 的 camera.transform 中提取手机位置
        // camera.transform 是一个 4×4 矩阵（simd_float4x4）
        // 它描述了"相机在世界中的位置和朝向"
        // columns.3 是 SIMD4<Float> 类型，包含 (x, y, z, w)
        // x, y, z = 世界坐标位置
        // w = 齐次坐标分量，永远是 1.0，可以忽略
        let pos = frame.camera.transform.columns.3
        startPosition = SIMD3<Float>(pos.x, pos.y, pos.z)
        
        // ===================================================================
        // 第二步：重置状态
        // ===================================================================
        
        calibrationSteps = 0
        calibrationDistance = nil
        calibratedStepLength = nil
        isCalibrating = true
        statusMessage = "Walk now..."
        
        // ===================================================================
        // 第三步：启动 CMPedometer
        // ===================================================================
        
        // 先检查设备是否支持计步
        guard CMPedometer.isStepCountingAvailable() else {
            statusMessage = "Step counting not available."
            isCalibrating = false
            return
        }
        
        // 开始计步
        // from: Date() → 从"现在"开始计，之前走的不算
        // handler 回调在后台线程执行
        //   data.numberOfSteps 是从 from 到现在的累计步数
        //   每次系统更新步数（大约每几秒），这个回调就会被触发
        //   不是每走一步就触发，而是攒几步一起推送
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            
            guard let self = self, let data = data, error == nil else { return }
            
            // 切回主线程更新 @Published 属性
            // SwiftUI 要求所有 UI 相关的数据修改都在主线程进行
            DispatchQueue.main.async {
                self.calibrationSteps = data.numberOfSteps.intValue
                self.statusMessage = "\(self.calibrationSteps) steps..."
            }
        }
    }
    
    // 用户点击"Stop"按钮时调用
    func stopCalibration() {
        
        // ===================================================================
        // 第一步：停止计步
        // ===================================================================
        
        pedometer.stopUpdates()
        isCalibrating = false
        
        // ===================================================================
        // 第二步：验证数据
        // ===================================================================
        
        // 确保有起点位置
        guard let startPos = startPosition else {
            statusMessage = "Error: no start position."
            return
        }
        
        // 确保能拿到当前 ARKit 帧（终点位置）
        guard let frame = arSession?.currentFrame else {
            statusMessage = "Error: ARKit not available."
            return
        }
        
        // 确保走了足够多的步数
        // 步数太少，单步误差占比太大，结果不可靠
        // 比如只走 2 步，ARKit 测量误差 0.1 米
        //   步长 = (1.3 + 0.1) / 2 = 0.70 vs 实际 0.65，差了 8%
        // 走 10 步的话：
        //   步长 = (6.5 + 0.1) / 10 = 0.66 vs 实际 0.65，只差 1.5%
        guard calibrationSteps >= 5 else {
            statusMessage = "Too few steps (\(calibrationSteps)). Walk at least 5 steps."
            return
        }
        
        // ===================================================================
        // 第三步：取终点位置
        // ===================================================================
        
        let endPos = frame.camera.transform.columns.3
        let endPosition = SIMD3<Float>(endPos.x, endPos.y, endPos.z)
        
        // ===================================================================
        // 第四步：计算水平距离
        // ===================================================================
        
        // 只算水平距离（x 和 z 方向），忽略垂直方向（y）
        // 原因：
        //   步长应该是水平面上的前进距离
        // 计算方法（勾股定理，和 CameraManager.getDistance 一样）：
        //   dx = 终点 x - 起点 x（左右方向的位移）
        //   dz = 终点 z - 起点 z（前后方向的位移）
        //   距离 = √(dx² + dz²)
        let dx = endPosition.x - startPos.x
        let dz = endPosition.z - startPos.z
        let distance = sqrtf(dx * dx + dz * dz)
        
        // 距离太短说明用户没有真正向前走
        // 可能是原地踏步、来回走、或者只挪了一小步
        // 这些情况算出的步长都不对
        guard distance > 1.0 else {
            statusMessage = "Distance too short (\(String(format: "%.1f", distance))m). Walk in a straight line."
            return
        }
        
        // ===================================================================
        // 第五步：计算步长
        // ===================================================================
        
        // 步长 = 总距离 ÷ 总步数
        let stepLength = distance / Float(calibrationSteps)
        
        // 合理性检查
        // 正常人单步步长范围：0.3 ~ 1.0 米
        //   0.3 米：非常小的碎步（比如老人缓慢行走）
        //   0.7 米：正常步速
        //   1.0 米：大步快走或跑步
        // 超出范围说明某个环节出了问题：
        //   太小：可能用户转圈走了，实际前进距离很短
        //   太大：可能 ARKit 追踪漂移了，距离被高估
        guard stepLength > 0.2 && stepLength < 1.0 else {
            statusMessage = "Result unreasonable (\(String(format: "%.2f", stepLength))m/step). Please retry."
            return
        }
        
        // ===================================================================
        // 第六步：保存结果
        // ===================================================================
        
        // 更新内存中的值（界面立刻刷新）
        calibratedStepLength = stepLength
        calibrationDistance = distance
        
        // 写入 UserDefaults（磁盘持久化）
        // 下次打开 app 时，init() 里会读取这个值
        UserDefaults.standard.set(stepLength, forKey: stepLengthKey)
        
        statusMessage = "Done! \(calibrationSteps) steps, \(String(format: "%.1f", distance))m → step: \(String(format: "%.2f", stepLength))m"
        
        // 清理起点位置，为下次标定做准备
        startPosition = nil
    }
    
    // 这是给外部调用的核心方法
    // 传入一个距离（米），返回大约还要走几步
    //
    // 举例：
    //   障碍物距离 2.1 米，effectiveStepLength = 0.68 米
    //   2.1 / 0.68 = 3.088
    //   向上取整 → 返回 4
    //
    // 为什么向上取整（ceil）而不是四舍五入（round）？
    //   这是安全考虑：
    //     向上取整：3.09 → 4 步，用户以为还有 4 步的距离
    //     四舍五入：3.09 → 3 步，用户以为还有 3 步就到了
    //   多报一步 → 用户提前减速 → 更安全
    //   少报一步 → 用户可能走多了撞上障碍物 → 危险
    func distanceToSteps(_ distance: Float) -> Int {
        let steps = distance / effectiveStepLength
        return Int(ceil(steps))
    }
}
