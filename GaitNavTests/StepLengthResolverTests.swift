import XCTest
@testable import GaitNav

// StepLengthResolver 单元测试
// 测试对象：动态、标定、默认步长三级优先级，以及稳定步长换算
@MainActor
final class StepLengthResolverTests: XCTestCase {
    
    // 动态步长估算器：测试中通过 DEBUG 辅助接口注入实时值
    private var dynamicEstimator: DynamicStepEstimator!
    // 标定器：通过 UserDefaults 模拟历史标定结果
    private var calibrator: Calibrator!
    // 步长解析器：组合两个来源并执行优先级判断
    private var resolver: StepLengthResolver!
    
    override func setUp() {
        // 先执行 XCTestCase 的通用初始化
        super.setUp()
        // 清除历史标定值，保证每个测试从默认步长开始
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        // 创建动态估算器
        dynamicEstimator = DynamicStepEstimator()
        // 创建标定器
        calibrator = Calibrator()
        // 创建待测解析器
        resolver = StepLengthResolver(dynamicEstimator: dynamicEstimator, calibrator: calibrator)
    }
    
    override func tearDown() {
        // 清除测试期间写入的标定值，避免污染其他测试
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        // 释放解析器引用
        resolver = nil
        // 释放标定器引用
        calibrator = nil
        // 释放动态估算器引用
        dynamicEstimator = nil
        // 最后执行 XCTestCase 的通用清理
        super.tearDown()
    }
    
    // 没有动态和标定数据时，应使用默认步长
    func testEffectiveStepLength_withoutMeasurements_usesDefault() {
        // 默认值固定为 0.65 米
        XCTAssertEqual(resolver.effectiveStepLength, 0.65, accuracy: 0.0001)
        // 来源标识应同步显示默认值
        XCTAssertEqual(resolver.stepLengthSource, .defaultValue)
    }
    
    // 有标定结果但没有动态数据时，应使用标定步长
    func testEffectiveStepLength_withCalibration_usesCalibratedValue() {
        // 模拟用户完成标定后写入 0.78 米步长
        UserDefaults.standard.set(Float(0.78), forKey: "calibratedStepLength")
        
        // 有标定结果时应返回个性化步长
        XCTAssertEqual(resolver.effectiveStepLength, 0.78, accuracy: 0.0001)
        // 来源标识应同步显示标定值
        XCTAssertEqual(resolver.stepLengthSource, .calibrated)
    }
    
    // 动态步长有效时，应覆盖已有标定结果
    func testEffectiveStepLength_withDynamicValue_prefersDynamic() {
        // 先写入历史标定值
        UserDefaults.standard.set(Float(0.78), forKey: "calibratedStepLength")
        // 再模拟用户行走期间得到 0.92 米动态步长
        dynamicEstimator._setForTesting(stepLength: 0.92)
        
        // 动态步长应拥有最高优先级
        XCTAssertEqual(resolver.effectiveStepLength, 0.92, accuracy: 0.0001)
        // 来源标识应同步显示动态值
        XCTAssertEqual(resolver.stepLengthSource, .dynamic)
    }
    
    // 稳定步长应忽略动态值，继续使用标定结果
    func testStableStepLength_withDynamicValue_ignoresDynamic() {
        // 写入可用于稳定引导的标定值
        UserDefaults.standard.set(Float(0.78), forKey: "calibratedStepLength")
        // 模拟短时间内波动较大的动态步长
        dynamicEstimator._setForTesting(stepLength: 0.92)
        
        // 稳定路径必须继续使用标定值
        XCTAssertEqual(resolver.stableStepLength, 0.78, accuracy: 0.0001)
    }
    
    // 常规距离换算应使用向上取整，给导航保留安全余量
    func testDistanceToSteps_usesCeil() {
        // 2.0 / 0.65 = 3.076...，向上取整后应为 4 步
        XCTAssertEqual(resolver.distanceToSteps(2.0), 4)
    }
    
    // 稳定距离换算应使用标定值，并忽略动态值
    func testDistanceToStableSteps_usesCalibratedValue() {
        // 写入 0.80 米标定步长
        UserDefaults.standard.set(Float(0.80), forKey: "calibratedStepLength")
        // 注入不同的动态值，确保稳定路径不会误用它
        dynamicEstimator._setForTesting(stepLength: 1.00)
        
        // 4.0 / 0.80 = 5，因此稳定换算应返回 5 步
        XCTAssertEqual(resolver.distanceToStableSteps(4.0), 5)
    }
}
