import XCTest
@testable import GaitNav

// GaitCoordinator 单元测试
// 测试对象：distanceToSteps()、distanceToStableSteps()、effectiveStepLength 优先级
//
// 测试策略：
//   在未标定 / 无动态步长的初始状态下，effectiveStepLength = 默认值 0.65m
//   验证 distanceToSteps 的向上取整行为（安全优先）
//   验证 stepLengthSource 的三级优先级标识
// GaitCoordinator 的属性和嵌套类型（如 StepLengthSource）的 Equatable 一致性
// 被推断为 main-actor-isolated，测试类需要在同一隔离域内执行
//@MainActor
//final class GaitCoordinatorTests: XCTestCase {
//    
//    private var gaitCoordinator: GaitCoordinator!
//    
//    override func setUp() {
//        super.setUp()
//        // 清除之前的标定数据，确保使用默认步长
//        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
//        gaitCoordinator = GaitCoordinator()
//    }
//    
//    override func tearDown() {
//        // 清理 UserDefaults，避免影响其他测试
//        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
//        super.tearDown()
//    }
//    
//    // MARK: - effectiveStepLength 优先级
//    
//    // 初始状态（无标定、无动态）→ 默认步长 0.65m
//    func testEffectiveStepLength_defaultValue() {
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.65, accuracy: 0.001,
//                       "无标定和动态数据时应返回默认步长 0.65m")
//    }
//    
//    // 初始状态的 stepLengthSource 应为 .defaultValue
//    func testStepLengthSource_defaultInitially() {
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .defaultValue)
//    }
//    
//    // stableStepLength 初始状态也应返回默认值
//    func testStableStepLength_defaultValue() {
//        XCTAssertEqual(gaitCoordinator.stableStepLength, 0.65, accuracy: 0.001)
//    }
//    
//    // 标定后 effectiveStepLength 应返回标定值
//    func testEffectiveStepLength_afterCalibration() {
//        // 模拟标定结果写入 UserDefaults
//        // Calibrator.effectiveStepLength 是 computed property，每次实时读取 UserDefaults
//        // 所以不需要创建新的 GaitCoordinator（且重复创建会导致 CMMotionManager 冲突崩溃）
//        UserDefaults.standard.set(Float(0.72), forKey: "calibratedStepLength")
//        
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.72, accuracy: 0.001,
//                       "标定后应返回标定步长")
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .calibrated)
//    }
//    
//    // MARK: - distanceToSteps 向上取整
//    
//    // 精确整数步：2.0m / 0.65m ≈ 3.077 → ceil = 4
//    func testDistanceToSteps_ceilBehavior() {
//        let steps = gaitCoordinator.distanceToSteps(2.0)
//        // 2.0 / 0.65 = 3.076... → ceil → 4
//        XCTAssertEqual(steps, 4, "2.0m / 0.65m 应向上取整为 4 步")
//    }
//    
//    // 恰好整除：1.3m / 0.65m = 2.0 → ceil = 2
//    func testDistanceToSteps_exactDivision() {
//        let steps = gaitCoordinator.distanceToSteps(1.3)
//        XCTAssertEqual(steps, 2, "恰好整除时 ceil 应返回整数本身")
//    }
//    
//    // 很小的距离（比一步短）：0.3m / 0.65m ≈ 0.46 → ceil = 1
//    func testDistanceToSteps_lessThanOneStep() {
//        let steps = gaitCoordinator.distanceToSteps(0.3)
//        XCTAssertEqual(steps, 1, "不到一步的距离应向上取整为 1 步")
//    }
//    
//    // 零距离：0 / 0.65 = 0 → ceil = 0
//    func testDistanceToSteps_zero() {
//        let steps = gaitCoordinator.distanceToSteps(0.0)
//        XCTAssertEqual(steps, 0, "零距离应返回 0 步")
//    }
//    
//    // 较远距离：10m / 0.65m ≈ 15.38 → ceil = 16
//    func testDistanceToSteps_farDistance() {
//        let steps = gaitCoordinator.distanceToSteps(10.0)
//        XCTAssertEqual(steps, 16, "10m / 0.65m 应为 16 步")
//    }
//    
//    // MARK: - distanceToStableSteps
//    
//    // distanceToStableSteps 使用稳定步长，行为与 distanceToSteps 一致（默认状态下）
//    func testDistanceToStableSteps_sameAsDefault() {
//        let steps = gaitCoordinator.distanceToStableSteps(2.0)
//        let stepsRegular = gaitCoordinator.distanceToSteps(2.0)
//        // 在默认状态下（无动态步长），两个方法应返回相同结果
//        XCTAssertEqual(steps, stepsRegular,
//                       "无动态步长时，distanceToStableSteps 和 distanceToSteps 应一致")
//    }
//    
//    // 使用标定步长计算
//    func testDistanceToStableSteps_usesCalibrated() {
//        UserDefaults.standard.set(Float(0.80), forKey: "calibratedStepLength")
//        
//        // 4.0m / 0.80m = 5.0 → ceil = 5
//        let steps = gaitCoordinator.distanceToStableSteps(4.0)
//        XCTAssertEqual(steps, 5, "4.0m / 0.80m 应为 5 步")
//    }
//    
//    // MARK: - hasEverCalibrated
//    
//    // 初始状态应返回 false
//    func testHasEverCalibrated_initiallyFalse() {
//        XCTAssertFalse(gaitCoordinator.hasEverCalibrated, "从未标定时应返回 false")
//    }
//    
//    // 标定后应返回 true
//    func testHasEverCalibrated_afterCalibration() {
//        UserDefaults.standard.set(Float(0.70), forKey: "calibratedStepLength")
//        XCTAssertTrue(gaitCoordinator.hasEverCalibrated, "标定后应返回 true")
//    }
//    
//    // MARK: - isDynamicActive
//    
//    // 初始状态动态步长不活跃
//    func testIsDynamicActive_initiallyFalse() {
//        XCTAssertFalse(gaitCoordinator.isDynamicActive, "初始状态动态步长不应活跃")
//    }
//    
//    // MARK: - 向上取整的安全性验证（关键行为）
//    
//    // 验证向上取整比四舍五入多报一步的安全性
//    func testCeilVsRound_safetyMargin() {
//        // 3.1 步 → ceil = 4, round = 3
//        // 对视障用户来说，多报一步更安全
//        let distance: Float = 3.1 * 0.65  // 恰好 3.1 步的距离
//        let steps = gaitCoordinator.distanceToSteps(distance)
//        XCTAssertEqual(steps, 4, "3.1 步应向上取整为 4（安全优先）")
//    }
//    
//    // MARK: - 三级优先级：动态 > 标定 > 默认
//    
//    // 动态步长活跃时，应覆盖标定值
//    func testEffectiveStepLength_dynamicOverridesCalibrated() {
//        // 先设标定值
//        UserDefaults.standard.set(Float(0.72), forKey: "calibratedStepLength")
//        // 注入动态步长（模拟用户正在走路）
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.58)
//        
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.58, accuracy: 0.001,
//                       "动态步长应覆盖标定值")
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .dynamic)
//    }
//    
//    // 动态步长活跃时，应覆盖默认值
//    func testEffectiveStepLength_dynamicOverridesDefault() {
//        // 无标定，注入动态步长
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.70)
//        
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.70, accuracy: 0.001,
//                       "动态步长应覆盖默认值 0.65")
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .dynamic)
//    }
//    
//    // 动态步长超时后，应回退到标定值
//    func testEffectiveStepLength_dynamicExpired_fallsBackToCalibrated() {
//        UserDefaults.standard.set(Float(0.72), forKey: "calibratedStepLength")
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.58)
//        
//        // 手动让 lastUpdateTime 过期（超过 3 秒 timeout）
//        gaitCoordinator.dynamicEstimator.lastUpdateTime = Date().addingTimeInterval(-4.0)
//        
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.72, accuracy: 0.001,
//                       "动态步长超时后应回退到标定值")
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .calibrated)
//    }
//    
//    // 动态步长超时 + 无标定 → 回退到默认值
//    func testEffectiveStepLength_dynamicExpired_noCalibration_fallsBackToDefault() {
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.58)
//        
//        // 让动态步长过期
//        gaitCoordinator.dynamicEstimator.lastUpdateTime = Date().addingTimeInterval(-4.0)
//        
//        XCTAssertEqual(gaitCoordinator.effectiveStepLength, 0.65, accuracy: 0.001,
//                       "动态过期 + 无标定 → 应回退到默认值 0.65")
//        XCTAssertEqual(gaitCoordinator.stepLengthSource, .defaultValue)
//    }
//    
//    // 动态步长活跃时，distanceToSteps 应使用动态值
//    func testDistanceToSteps_usesDynamicWhenActive() {
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.50)
//        
//        // 2.0m / 0.50m = 4.0 → ceil = 4
//        let steps = gaitCoordinator.distanceToSteps(2.0)
//        XCTAssertEqual(steps, 4, "2.0m / 0.50m 应为 4 步")
//    }
//    
//    // distanceToStableSteps 应忽略动态值，用标定/默认值
//    func testDistanceToStableSteps_ignoresDynamic() {
//        UserDefaults.standard.set(Float(0.80), forKey: "calibratedStepLength")
//        gaitCoordinator.dynamicEstimator._setForTesting(stepLength: 0.50)
//        
//        // stableSteps 应使用标定值 0.80，而非动态值 0.50
//        // 4.0m / 0.80m = 5.0 → ceil = 5
//        let stableSteps = gaitCoordinator.distanceToStableSteps(4.0)
//        // distanceToSteps 应使用动态值 0.50
//        // 4.0m / 0.50m = 8.0 → ceil = 8
//        let dynamicSteps = gaitCoordinator.distanceToSteps(4.0)
//        
//        XCTAssertEqual(stableSteps, 5, "stableSteps 应使用标定步长")
//        XCTAssertEqual(dynamicSteps, 8, "distanceToSteps 应使用动态步长")
//        XCTAssertNotEqual(stableSteps, dynamicSteps,
//                          "两个方法在动态活跃时应返回不同结果")
//    }
//    
//    // MARK: - processAcceleration 波峰检测
//    
//    // 冷启动时，首帧低于基线不应触发上升趋势（验证 lastAcceleration = 1.0 修复）
//    func testProcessAcceleration_coldStart_belowBaseline_noRise() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // lastAcceleration 初始值 = 1.0（重力基线）
//        // 首帧 0.95 < 1.0 → 不触发 isRising
//        // 随后 1.1 > 0.95 → isRising = true
//        // 再 1.0 < 1.1 → 波峰 1.1 > 1.05 → 触发一步
//        // 如果初始值是 0，首帧 0.95 > 0 就会 isRising = true，
//        // 第二帧 0.9 < 0.95 → 假波峰 0.95 < 1.05 → 不触发（侥幸），但状态已被污染
//        gaitCoordinator.processAcceleration(0.95)
//        gaitCoordinator.processAcceleration(0.9)
//        // 此时如果初始值为 0，已经经历过一次假波峰检测
//        // 初始值为 1.0 时，这两帧全程低于基线，isRising 始终为 false
//        
//        XCTAssertEqual(stepCount, 0, "低于基线的首帧序列不应触发任何步伐")
//    }
//    
//    // 超过阈值的波峰应触发一步
//    func testProcessAcceleration_peakAboveThreshold_triggersStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 模拟加速度序列：基线 → 上升超过阈值 → 下降 = 波峰
//        // stepThreshold = 1.05
//        gaitCoordinator.processAcceleration(0.9)   // 基线，设定 lastAcceleration
//        gaitCoordinator.processAcceleration(1.1)   // 上升中（> 0.9），isRising = true
//        gaitCoordinator.processAcceleration(1.0)   // 下降（< 1.1），波峰 = 1.1 > 1.05 ✓
//        
//        XCTAssertEqual(stepCount, 1, "超过阈值的波峰应触发恰好一步")
//    }
//    
//    // 低于阈值的波峰不应触发步伐（是噪声）
//    func testProcessAcceleration_peakBelowThreshold_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 波峰值 1.02 < 阈值 1.05
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.02)  // 上升
//        gaitCoordinator.processAcceleration(0.95)  // 下降 → 波峰 = 1.02 < 1.05
//        
//        XCTAssertEqual(stepCount, 0, "低于阈值的波峰不应触发步伐")
//    }
//    
//    // 持续上升不应触发步伐（还没到波峰）
//    func testProcessAcceleration_continuousRise_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.0)
//        gaitCoordinator.processAcceleration(1.1)
//        gaitCoordinator.processAcceleration(1.2)
//        
//        XCTAssertEqual(stepCount, 0, "持续上升中不应触发步伐")
//    }
//    
//    // 持续下降不应触发步伐
//    func testProcessAcceleration_continuousDecline_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // lastAcceleration 初始值为 1.0（重力基线）
//        // 下面的序列从 0.95 开始，全程低于 1.0 且持续下降
//        // 不会触发 isRising，也就不会产生波峰
//        gaitCoordinator.processAcceleration(0.95)
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(0.85)
//        gaitCoordinator.processAcceleration(0.8)
//        
//        XCTAssertEqual(stepCount, 0, "持续下降中不应触发步伐")
//    }
//    
//    // 防抖：两个波峰间隔 < 0.3 秒时，第二个被拒绝
//    func testProcessAcceleration_debounce_rejectsFastPeaks() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 第一个有效波峰
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.2)
//        gaitCoordinator.processAcceleration(1.0)
//        XCTAssertEqual(stepCount, 1, "第一个波峰应触发")
//        
//        // 立刻来第二个波峰（间隔 << 0.3s）→ 被防抖拦截
//        gaitCoordinator.processAcceleration(1.2)
//        gaitCoordinator.processAcceleration(1.0)
//        XCTAssertEqual(stepCount, 1, "0.3 秒内的第二个波峰应被防抖拒绝")
//    }
//    
//    // 防抖：两个波峰间隔 > 0.3 秒时，都应被接受
//    func testProcessAcceleration_debounce_acceptsSeparatedPeaks() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 第一个有效波峰
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.2)
//        gaitCoordinator.processAcceleration(1.0)
//        XCTAssertEqual(stepCount, 1)
//        
//        // 等待防抖间隔过去（0.35s > minStepInterval 0.3s）
//        // 使用 RunLoop 而非 DispatchQueue.main.asyncAfter
//        // 因为测试类标注了 @MainActor，DispatchQueue.main 的回调和
//        // waitForExpectations 都在主线程上竞争，会导致死锁超时
//        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
//        
//        // 第二个波峰应被接受
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.2)
//        gaitCoordinator.processAcceleration(1.0)
//        XCTAssertEqual(stepCount, 2, "间隔足够的第二个波峰应被接受")
//    }
//    
//    // 多个连续有效波峰（间隔充足）应各触发一步
//    func testProcessAcceleration_multipleValidPeaks() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 喂入 3 个间隔足够的波峰
//        for _ in 0..<3 {
//            gaitCoordinator.processAcceleration(0.9)
//            gaitCoordinator.processAcceleration(1.2)
//            gaitCoordinator.processAcceleration(1.0)
//            
//            // 等待防抖冷却
//            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
//        }
//        
//        XCTAssertEqual(stepCount, 3, "3 个间隔充足的有效波峰应触发 3 步")
//    }
//    
//    // 恰好在阈值上的波峰不应触发（条件是 > threshold，不是 >=）
//    func testProcessAcceleration_peakExactlyAtThreshold_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 波峰恰好 = 1.05 = stepThreshold → 不触发（条件是严格 >）
//        gaitCoordinator.processAcceleration(0.9)
//        gaitCoordinator.processAcceleration(1.05)
//        gaitCoordinator.processAcceleration(0.95)
//        
//        XCTAssertEqual(stepCount, 0, "波峰恰好等于阈值时不应触发（需严格大于）")
//    }
//    
//    // MARK: - valley-to-peak 振幅过滤
//    //
//    // 检测条件：amplitude = peak - lastValley > amplitudeThreshold (0.08)
//    // 用于过滤绝对值超过阈值但振幅很小的噪声（车辆振动、手抖等）
//    // 0.08 是初始值，后续通过实验调优
//    
//    // 核心场景：波峰超过绝对阈值，但 valley-to-peak 振幅太小 → 不触发
//    // 典型场景：公交车振动，基线在 1.01~1.07 之间小幅波动
//    func testAmplitude_vehicleVibration_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 先用低于绝对阈值的小波峰建立振动基线
//        gaitCoordinator.processAcceleration(1.02)  // > 1.0 初始 → isRising = true
//        gaitCoordinator.processAcceleration(1.04)  // 继续上升
//        gaitCoordinator.processAcceleration(1.02)  // 下降 → 波峰 1.04 < 1.05 → 不触发，lastValley = 1.02
//        
//        // 这次波峰超过绝对阈值，但振幅很小（车辆振动特征）
//        gaitCoordinator.processAcceleration(1.01)  // 下降，lastValley = min(1.02, 1.01) = 1.01
//        gaitCoordinator.processAcceleration(1.06)  // 上升，isRising = true
//        gaitCoordinator.processAcceleration(1.02)  // 波峰 = 1.06 > 1.05 ✓
//                                                  // amplitude = 1.06 - 1.01 = 0.05 < 0.08 ✗ → 拒绝
//        
//        XCTAssertEqual(stepCount, 0,
//                       "波峰超过绝对阈值但振幅仅 0.05，应被拒绝（车辆振动场景）")
//    }
//    
//    // 轻脚步：振幅 ~0.12，高于 0.08 阈值 → 应触发
//    // 这是把阈值从 0.15 降到 0.08 的直接原因
//    func testAmplitude_lightFootsteps_triggersStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 模拟轻脚步：valley ~0.96, peak ~1.08
//        // amplitude = 1.08 - 0.96 = 0.12 > 0.08 ✓
//        gaitCoordinator.processAcceleration(0.97)  // 下降，lastValley = min(1.0, 0.97) = 0.97
//        gaitCoordinator.processAcceleration(0.96)  // 继续下降，lastValley = 0.96
//        gaitCoordinator.processAcceleration(1.08)  // 上升，isRising = true
//        gaitCoordinator.processAcceleration(1.02)  // 波峰 = 1.08 > 1.05 ✓, amplitude = 0.12 > 0.08 ✓
//        
//        XCTAssertEqual(stepCount, 1, "轻脚步的振幅 0.12 应满足 0.08 阈值并触发一步")
//    }
//    
//    // 正常步伐：绝对阈值和振幅都满足 → 触发
//    func testAmplitude_normalWalking_triggersStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 模拟正常步伐周期：valley ~0.85, peak ~1.2
//        // amplitude = 1.2 - 0.85 = 0.35 > 0.08 ✓
//        gaitCoordinator.processAcceleration(0.9)   // 下降，lastValley = min(1.0, 0.9) = 0.9
//        gaitCoordinator.processAcceleration(0.85)  // 继续下降，lastValley = 0.85
//        gaitCoordinator.processAcceleration(1.2)   // 上升，isRising = true
//        gaitCoordinator.processAcceleration(1.05)  // 波峰 = 1.2 > 1.05 ✓, amplitude = 0.35 > 0.08 ✓
//        
//        XCTAssertEqual(stepCount, 1, "正常步伐的振幅应满足所有条件并触发一步")
//    }
//    
//    // 持续小幅振动不应触发任何步伐（多个周期）
//    func testAmplitude_sustainedVibration_noSteps() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // 模拟 3 个周期的车辆振动，每个周期振幅 ~0.05
//        for _ in 0..<3 {
//            gaitCoordinator.processAcceleration(1.01)
//            gaitCoordinator.processAcceleration(1.03)
//            gaitCoordinator.processAcceleration(1.06)  // 小幅上升
//            gaitCoordinator.processAcceleration(1.03)  // 小幅下降 → 波峰 1.06 > 1.05，但 amplitude 极小
//            gaitCoordinator.processAcceleration(1.01)
//            
//            // 等待防抖间隔，确保不是因为防抖而被拒绝
//            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
//        }
//        
//        XCTAssertEqual(stepCount, 0, "持续小幅振动（如车辆）不应触发任何步伐")
//    }
//    
//    // 振幅略低于阈值 → 不触发
//    func testAmplitude_justBelowThreshold_noStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // valley = 0.99, peak = 1.06 → amplitude = 0.07 < 0.08
//        gaitCoordinator.processAcceleration(0.99)  // 下降，lastValley = min(1.0, 0.99) = 0.99
//        gaitCoordinator.processAcceleration(1.06)  // 上升
//        gaitCoordinator.processAcceleration(1.0)   // 波峰 = 1.06 > 1.05 ✓, amplitude = 0.07 < 0.08 ✗
//        
//        XCTAssertEqual(stepCount, 0, "振幅 0.07 低于阈值 0.08 时不应触发")
//    }
//    
//    // 振幅刚超过阈值 → 触发
//    func testAmplitude_justAboveThreshold_triggersStep() {
//        var stepCount = 0
//        gaitCoordinator.onStepDetected = { stepCount += 1 }
//        
//        // valley = 0.98, peak = 1.07 → amplitude = 0.09 > 0.08 ✓
//        gaitCoordinator.processAcceleration(0.98)  // 下降，lastValley = min(1.0, 0.98) = 0.98
//        gaitCoordinator.processAcceleration(1.07)  // 上升
//        gaitCoordinator.processAcceleration(1.0)   // 波峰 = 1.07 > 1.05 ✓, amplitude = 0.09 > 0.08 ✓
//        
//        XCTAssertEqual(stepCount, 1, "振幅 0.09 刚超过阈值 0.08 应触发步伐")
//    }
//}
