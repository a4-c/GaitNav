import XCTest
// ARKit 用于验证协调器会把同一个 ARSession 传递给需要定位能力的子模块
import ARKit
@testable import GaitNav

// GaitCoordinator 单元测试
// 当前可执行测试只覆盖协调器仍然拥有的 facade 和接线职责
// 检测算法和步长优先级的细节已经分别下沉到 AdaptiveStepDetectorTests 与 StepLengthResolverTests
@MainActor
final class GaitCoordinatorTests: XCTestCase {
    
    // 每个测试持有独立协调器，验证公开接口转发不会依赖其他测试留下的状态
    private var gaitCoordinator: GaitCoordinator!
    
    override func setUp() {
        // 先执行 XCTestCase 的通用初始化
        super.setUp()
        // 清除历史标定步长，确保默认路径从 0.65 米开始
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        // 清除历史波峰 EMA，确保 profiling 状态从未完成开始
        UserDefaults.standard.removeObject(forKey: "profiledPeakDevEma")
        // 清除历史步间隔 EMA，避免其他测试留下不完整档案
        UserDefaults.standard.removeObject(forKey: "profiledIntervalEma")
        // 创建待测协调器；初始化不会主动启动 CoreMotion 采样
        gaitCoordinator = GaitCoordinator()
    }
    
    override func tearDown() {
        // 释放协调器引用，确保每个测试使用独立模块图
        gaitCoordinator = nil
        // 清除测试期间写入的标定步长
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        // 清除测试期间写入的波峰 EMA
        UserDefaults.standard.removeObject(forKey: "profiledPeakDevEma")
        // 清除测试期间写入的步间隔 EMA
        UserDefaults.standard.removeObject(forKey: "profiledIntervalEma")
        // 最后执行 XCTestCase 的通用清理
        super.tearDown()
    }
    
    // 默认状态应把步长解析器的兜底值和来源原样暴露给调用方
    func testStepLengthFacade_withoutMeasurements_usesDefault() {
        // 没有动态和标定数据时，公开有效步长应为默认值 0.65 米
        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.65, accuracy: 0.0001)
        // 稳定引导路径在默认状态下也应使用同一个默认值
        XCTAssertEqual(gaitCoordinator.stableStepLength, 0.65, accuracy: 0.0001)
        // 来源标识应与公开步长保持一致
        XCTAssertEqual(gaitCoordinator.stepLengthSource, .defaultValue)
        // 没有动态估算结果时，公开活跃状态应为 false
        XCTAssertFalse(gaitCoordinator.isDynamicActive)
    }
    
    // 已有标定结果时，协调器应把个性化步长和来源原样暴露给调用方
    func testStepLengthFacade_withCalibration_usesSavedValue() {
        // 模拟用户完成标定后持久化 0.80 米步长
        UserDefaults.standard.set(Float(0.80), forKey: "calibratedStepLength")
        
        // 常规有效步长应读取保存后的个性化值
        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.80, accuracy: 0.0001)
        // 稳定引导路径也应读取同一个标定值
        XCTAssertEqual(gaitCoordinator.stableStepLength, 0.80, accuracy: 0.0001)
        // 来源标识应同步切换为标定值
        XCTAssertEqual(gaitCoordinator.stepLengthSource, .calibrated)
        // 标定状态转发应反映持久化结果
        XCTAssertTrue(gaitCoordinator.hasEverCalibrated)
    }
    
    // 协调器应通过窄接口向 feedback 和 overlay 提供一致的距离换算能力
    func testStepDistanceConvertingFacade_forwardsConversions() {
        // 使用协议类型持有协调器，验证调用方不需要知道具体实现
        let converter: StepDistanceConverting = gaitCoordinator
        
        // 2.0 / 0.65 = 3.076...，常规路径应向上取整为 4 步
        XCTAssertEqual(converter.distanceToSteps(2.0), 4)
        // 默认状态下稳定路径使用同一兜底步长，因此也应返回 4 步
        XCTAssertEqual(converter.distanceToStableSteps(2.0), 4)
    }
    
    // profiling 状态应通过协调器公开属性反映持久化档案是否存在
    func testHasEverProfiled_withSavedPeakEma_returnsTrue() {
        // 初始状态没有保存过 profiling 档案
        XCTAssertFalse(gaitCoordinator.hasEverProfiled)
        // 模拟 profiling 完成后保存合理的波峰 EMA
        UserDefaults.standard.set(Double(0.12), forKey: "profiledPeakDevEma")
        // 协调器应将 GaitProfiler 的持久化状态转发给设置页
        XCTAssertTrue(gaitCoordinator.hasEverProfiled)
    }
    
    // ARSession 设置入口应把会话传给负责标定的子模块
    func testSetARSession_forwardsSessionToCalibrator() {
        // 创建独立会话对象，模拟 PerceptionPipeline 提供的 ARSession
        let session = ARSession()
        // 通过协调器统一设置需要定位能力的子模块
        gaitCoordinator.setARSession(session)
        // 标定器应持有同一个会话实例，而不是新建或丢失引用
        XCTAssertTrue(gaitCoordinator.calibrator.arSession === session)
    }
}
