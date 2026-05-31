import Foundation

// 距离转步数接口：只暴露 feedback 构建候选物体所需的最小能力
protocol StepDistanceConverting: AnyObject {
    // 使用当前有效步长把米数换算成步数
    func distanceToSteps(_ distance: Float) -> Int
    // 使用稳定步长把米数换算成步数
    func distanceToStableSteps(_ distance: Float) -> Int
}

// 步长解析器：统一管理动态、标定、默认步长的三级优先级
final class StepLengthResolver {
    
    // 当前 effectiveStepLength 的值从哪一级取到的
    // SettingsView 用它来高亮对应的优先级行和徽章
    //
    // .dynamic      → 动态估算器有值且未超时
    // .calibrated   → Calibrator 有可用的标定值（本次或历史）
    // .defaultValue → 以上都没有，使用 0.65m 兜底
    enum Source {
        case dynamic, calibrated, defaultValue
    }
    
    // 动态步长估算器提供用户行走期间的实时步长
    private let dynamicEstimator: DynamicStepEstimator
    
    // 标定器提供用户历史保存的个性化步长
    private let calibrator: Calibrator
    
    // 默认步长，单位：米
    // 当用户还没做过标定时，用这个值来换算步数
    // 这样即使第一次打开 app，看到障碍物也能显示"大约几步"
    private let defaultStepLength: Float
    
    // 初始化解析器，并显式注入两个步长来源和最终兜底值
    init(dynamicEstimator: DynamicStepEstimator, calibrator: Calibrator, defaultStepLength: Float = 0.65) {
        // 保存动态估算器引用，实时查询当前步长和超时状态
        self.dynamicEstimator = dynamicEstimator
        // 保存标定器引用，每次查询时读取最新持久化标定结果
        self.calibrator = calibrator
        // 保存默认步长，在动态和标定数据都不可用时提供安全兜底
        self.defaultStepLength = defaultStepLength
    }
    
    // 每次访问时实时计算，不存储值
    // 外部模块（比如 DetectionOverlay）不需要关心步长是怎么来的
    // 只需要调用 gaitCoordinator.effectiveStepLength，总能拿到一个合理的值
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
        // 优先使用标定步长，没有标定结果时再使用固定默认值
        return calibrator.effectiveStepLength ?? defaultStepLength
    }
    
    // 当前有效步长的来源，供设置页展示三级优先级
    var stepLengthSource: Source {
        // 有活跃动态步长时优先展示动态来源
        if let _ = dynamicEstimator.currentStepLength,
           dynamicEstimator.isActive {
            return .dynamic
        }
        // 没有动态步长但有标定结果时展示标定来源
        if calibrator.effectiveStepLength != nil {
            return .calibrated
        }
        // 前两级都不可用时展示默认来源
        return .defaultValue
    }
    
    // 动态步长当前是否处于活跃状态
    var isDynamicActive: Bool {
        // 直接转发动态估算器的超时判断，确保所有调用方使用同一规则
        return dynamicEstimator.isActive
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
    // FeedbackEngine 在倒数前使用它，避免剩余步数反向增加造成混乱。
    func distanceToStableSteps(_ distance: Float) -> Int {
        // 稳定路径刻意不读取短时间内可能波动的动态步长
        return Int(ceil(distance / stableStepLength))
    }
}
