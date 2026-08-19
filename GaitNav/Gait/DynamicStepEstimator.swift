import ARKit

// 动态步长估算器：在用户正常走路时，逐步实时计算步长
//
// 原理：
//   每检测到一个波峰（一步）→ 从 ARKit 读取手机当前位置
//   和上一步的位置算水平距离 → 得到这一步的实际步长
//   用最近 N 步的滑动窗口平均值作为当前输出
//   用户走快了步长自动变大，走慢了自动变小
class DynamicStepEstimator {
    
    // ARSession 的引用，用于在每一步读取手机的 3D 位置
    // weak 防止循环引用
    weak var arSession: ARSession?
    
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
    private let windowSize = 6
    
    // 动态步长的有效期（秒）
    // 如果最后一次成功计算动态步长离现在超过这个时间，认为动态步长已经过期
    // 过期后动态步长不再可信（可能是站着不动的最后几步，不代表正常步态）
    // 回退到标定值或默认值
    let timeout: TimeInterval = 3.0
    
    // 最后一次成功计算出动态步长的时间
    var lastUpdateTime: Date = .distantPast
    
    // 当前动态计算出的步长（滑动窗口平均值）
    // nil 表示还没有足够数据（需要至少 2 步）
    private(set) var currentStepLength: Float? = nil
    
    // 动态步长当前是否处于活跃状态（有值 + 未超时）
    var isActive: Bool {
        currentStepLength != nil &&
        Date().timeIntervalSince(lastUpdateTime) < timeout
    }
    
    // GaitCoordinator 在检测到一步时调用这个方法
    // 记录这一步的 ARKit 位置，和上一步的位置算距离 = 这一步的步长
    func handleStep() {
        // 记录本次步伐处理的统一时间，避免同一次计算里多次读取系统时间造成细微偏差
        let now = Date()
        // 如果当前动态步长已经过期，就复用统一 reset 逻辑清空旧状态
        resetIfNeeded(now: now)
        
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
                // 始终只保留最近 windowSize 步的数据
                if recentStepLengths.count > windowSize {
                    recentStepLengths.removeFirst()
                }
                
                // 至少积累 2 步才开始输出动态步长
                // 1 步的数据太不稳定，不足以代表用户的步态
                if recentStepLengths.count >= 2 {
                    // reduce(0, +)：从 0 开始，把数组里所有元素累加
                    // 除以个数 = 平均值
                    let avg = recentStepLengths.reduce(0, +) / Float(recentStepLengths.count)
                    currentStepLength = avg
                    // 只有真正算出新的动态步长时，才刷新动态步长更新时间
                    lastUpdateTime = now
                }
            }
        }
        
        // 无论是否成功计算步长，都更新位置
        // 这样下一步就能从这个位置开始算
        lastStepPosition = currentPosition
    }
    
    // 如果已经产出过的动态步长超过有效期，就清空上一段步行留下的滑动窗口
    private func resetIfNeeded(now: Date) {
        // 如果还没有产出过动态步长，说明当前窗口还处在冷启动积累阶段，不应该被 lastUpdateTime 清掉
        guard currentStepLength != nil else { return }
        // 如果动态步长还没有超过有效期，继续沿用当前滑动窗口
        guard now.timeIntervalSince(lastUpdateTime) >= timeout else { return }
        reset()
    }
    
    // 重置所有状态
    // 在模式切换时调用
    func reset() {
        // 清除停顿前的 ARKit 位置，避免恢复行走的第一步跨越停顿前后的两个位置
        lastStepPosition = nil
        // 清空停顿前积累的步长样本，确保新的动态平均值只来自恢复后的步伐
        recentStepLengths = []
        // 作废停顿前计算出的动态步长，让解析器回退到标定值或默认值
        currentStepLength = nil
        // 重置动态步长刷新时间，确保清理后不会被误判为仍然活跃
        lastUpdateTime = .distantPast
    }
    
    // For testing
    // 供单元测试注入动态步长值（绕过 ARSession 依赖）
    #if DEBUG
    func _setForTesting(stepLength: Float) {
        currentStepLength = stepLength
        lastUpdateTime = Date()
    }
    #endif
}
