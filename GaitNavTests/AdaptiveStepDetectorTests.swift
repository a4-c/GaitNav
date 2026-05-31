import XCTest
@testable import GaitNav

// AdaptiveStepDetector 单元测试
// 测试对象：迟滞状态机、步间隔防抖、EMA 档案和静止衰减
//
// 测试策略：
//   直接传入合加速度和时间戳，不依赖真机 CoreMotion
//   通过公开的 currentProfile 观察可持久化 EMA 是否按预期变化
@MainActor
final class AdaptiveStepDetectorTests: XCTestCase {
    
    // 基准时间：使用固定时间戳，让每个测试都不依赖真实时钟
    private let baseTime = Date(timeIntervalSince1970: 1_000)
    
    // 高于初始高阈值后再低于低阈值，应确认一个完整步伐
    func testProcess_hysteresisCycle_confirmsStep() {
        // 使用默认配置创建一个干净的检测器
        var detector = AdaptiveStepDetector()
        
        // 波峰上升阶段只进入追踪状态，还不能立即确认一步
        XCTAssertFalse(detector.process(magnitude: 1.10, at: baseTime))
        // 波峰回落阶段完成迟滞周期，第一步不受步间隔防抖限制
        XCTAssertTrue(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.10)))
    }
    
    // 没有越过高阈值时，不应凭空确认步伐
    func testProcess_belowHighThreshold_doesNotConfirmStep() {
        // 使用默认配置创建一个干净的检测器
        var detector = AdaptiveStepDetector()
        
        // 连续输入接近重力基线的采样，始终达不到初始高阈值 1.035g
        XCTAssertFalse(detector.process(magnitude: 1.01, at: baseTime))
        // 第二个低幅采样同样不能触发状态转换
        XCTAssertFalse(detector.process(magnitude: 1.02, at: baseTime.addingTimeInterval(0.05)))
        // 回到基线也不能确认从未开始追踪的波峰
        XCTAssertFalse(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.10)))
    }
    
    // 两个确认波峰间隔过短时，第二个波峰应被防抖拒绝
    func testProcess_secondPeakInsideGuardInterval_isRejected() {
        // 使用默认配置创建一个干净的检测器
        var detector = AdaptiveStepDetector()
        
        // 第一个周期越过高阈值
        XCTAssertFalse(detector.process(magnitude: 1.10, at: baseTime))
        // 第一个周期回落后确认第一步
        XCTAssertTrue(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.05)))
        // 在最小步间隔内再次越过高阈值
        XCTAssertFalse(detector.process(magnitude: 1.10, at: baseTime.addingTimeInterval(0.10)))
        // 第二个周期虽然完整回落，但时间间隔过短，因此不能算作新一步
        XCTAssertFalse(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.15)))
    }
    
    // 合法的连续步伐应更新步间隔 EMA
    func testProcess_validSecondStep_updatesIntervalEma() {
        // 使用较慢的初始步间隔档案，便于观察第二步后的 EMA 变化
        let profile = StepDetectionProfile(peakDevEma: 0.05, intervalEma: 0.80)
        // 使用注入档案创建检测器
        var detector = AdaptiveStepDetector(profile: profile)
        
        // 完成第一步，第一步和 distantPast 的间隔不会写入 EMA
        XCTAssertFalse(detector.process(magnitude: 1.10, at: baseTime))
        XCTAssertTrue(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.05)))
        // 在一秒后开始第二个完整周期
        XCTAssertFalse(detector.process(magnitude: 1.10, at: baseTime.addingTimeInterval(1.00)))
        XCTAssertTrue(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(1.05)))
        
        // 第二步间隔为 1 秒，因此 EMA 从 0.80 更新为 0.84
        XCTAssertEqual(detector.currentProfile.intervalEma, 0.84, accuracy: 0.0001)
    }
    
    // 应用档案后，检测器应立即暴露新的个性化 EMA
    func testApplyProfile_replacesCurrentProfile() {
        // 使用默认值创建检测器
        var detector = AdaptiveStepDetector()
        // 构造一份模拟 profiling 保存结果
        let profile = StepDetectionProfile(peakDevEma: 0.22, intervalEma: 0.72)
        
        // 应用新的个性化档案
        detector.applyProfile(profile)
        
        // 波峰 EMA 应替换为注入值
        XCTAssertEqual(detector.currentProfile.peakDevEma, 0.22, accuracy: 0.0001)
        // 步间隔 EMA 应替换为注入值
        XCTAssertEqual(detector.currentProfile.intervalEma, 0.72, accuracy: 0.0001)
    }
    
    // profiling 开始前重置档案，应恢复保守默认值
    func testResetToDefaultProfile_restoresDefaults() {
        // 使用明显不同于默认值的档案创建检测器
        var detector = AdaptiveStepDetector(profile: StepDetectionProfile(peakDevEma: 0.30, intervalEma: 0.90))
        
        // 模拟 profiling 开始时恢复统一学习起点
        detector.resetToDefaultProfile()
        
        // 波峰 EMA 应恢复默认 0.05g
        XCTAssertEqual(detector.currentProfile.peakDevEma, 0.05, accuracy: 0.0001)
        // 步间隔 EMA 应恢复默认 0.5 秒
        XCTAssertEqual(detector.currentProfile.intervalEma, 0.50, accuracy: 0.0001)
    }
    
    // 超过静止超时后，波峰 EMA 应向默认值缓慢衰减
    func testProcess_afterDecayTimeout_reducesPeakEma() {
        // 使用较高波峰 EMA，模拟用户刚刚快走后的状态
        var detector = AdaptiveStepDetector(profile: StepDetectionProfile(peakDevEma: 0.30, intervalEma: 0.50))
        
        // 输入高波峰，让检测器记录最近一次确认时间
        XCTAssertFalse(detector.process(magnitude: 1.50, at: baseTime))
        // 回落后完成第一步，并把波峰 EMA 更新到 0.34
        XCTAssertTrue(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(0.05)))
        // 记录静止衰减前的波峰 EMA
        let beforeDecay = detector.currentProfile.peakDevEma
        
        // 三秒后输入静止采样，超过两秒超时并触发一次缓慢衰减
        XCTAssertFalse(detector.process(magnitude: 1.00, at: baseTime.addingTimeInterval(3.05)))
        
        // 衰减后的 EMA 应低于衰减前数值
        XCTAssertLessThan(detector.currentProfile.peakDevEma, beforeDecay)
        // 衰减逻辑不能把 EMA 降到默认下限以下
        XCTAssertGreaterThanOrEqual(detector.currentProfile.peakDevEma, 0.05)
    }
}
