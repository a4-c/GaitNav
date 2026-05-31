import XCTest
@testable import GaitNav

// Calibrator 单元测试
// 测试对象：handleStep 计数、标定状态机、数据验证
//
// 测试策略：
//   Calibrator 的标定流程依赖 ARSession（起点/终点位置）
//   但 handleStep 的计数逻辑和状态管理可以独立测试
//   stopCalibration 中的验证条件也可以间接测试
final class CalibratorTests: XCTestCase {
    
    private var calibrator: Calibrator!
    
    override func setUp() {
        super.setUp()
        // 清除之前的标定数据
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        calibrator = Calibrator()
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        super.tearDown()
    }
    
    // MARK: - 初始状态
    
    // 初始状态：不在标定、步数为 0
    func testInitialState() {
        XCTAssertFalse(calibrator.isCalibrating, "初始不应在标定中")
        XCTAssertEqual(calibrator.calibrationSteps, 0, "初始步数应为 0")
        XCTAssertNil(calibrator.calibrationDistance, "初始距离应为 nil")
    }
    
    // 从未标定时，effectiveStepLength 应为 nil
    func testEffectiveStepLength_neverCalibrated() {
        XCTAssertNil(calibrator.effectiveStepLength, "从未标定时 effectiveStepLength 应为 nil")
    }
    
    // 从未标定时，hasEverCalibrated 应为 false
    func testHasEverCalibrated_initiallyFalse() {
        XCTAssertFalse(calibrator.hasEverCalibrated)
    }
    
    // MARK: - handleStep 计数
    
    // 标定状态下，handleStep 应递增步数
    func testHandleStep_incrementsWhenCalibrating() {
        // 手动设置为标定状态（绕过 startCalibration 的 ARSession 依赖）
        calibrator.isCalibrating = true
        
        calibrator.handleStep()
        XCTAssertEqual(calibrator.calibrationSteps, 1)
        
        calibrator.handleStep()
        XCTAssertEqual(calibrator.calibrationSteps, 2)
        
        calibrator.handleStep()
        XCTAssertEqual(calibrator.calibrationSteps, 3)
    }
    
    // 非标定状态下，handleStep 不应改变步数
    func testHandleStep_ignoredWhenNotCalibrating() {
        XCTAssertFalse(calibrator.isCalibrating)
        
        calibrator.handleStep()
        calibrator.handleStep()
        calibrator.handleStep()
        
        XCTAssertEqual(calibrator.calibrationSteps, 0, "非标定状态下 handleStep 不应计数")
    }
    
    // 标定过程中，statusMessage 应显示步数
    func testHandleStep_updatesStatusMessage() {
        calibrator.isCalibrating = true
        
        calibrator.handleStep()
        XCTAssertEqual(calibrator.statusMessage, "1 steps...")
        
        calibrator.handleStep()
        XCTAssertEqual(calibrator.statusMessage, "2 steps...")
    }
    
    // MARK: - stopCalibration 验证
    
    // 没有 ARSession 时停止标定 → 应显示错误且通知 GaitCoordinator
    func testStopCalibration_noARSession_showsError() {
        calibrator.isCalibrating = true
        calibrator.arSession = nil
        
        var stoppedCallbackCalled = false
        calibrator.onCalibrationStopped = {
            stoppedCallbackCalled = true
        }
        
        calibrator.stopCalibration()
        
        XCTAssertFalse(calibrator.isCalibrating, "停止后应不再标定")
        // 没有 startPosition → "Error: no start position."
        XCTAssertTrue(calibrator.statusMessage.contains("Error"),
                      "没有起点位置应显示错误信息")
        XCTAssertTrue(stoppedCallbackCalled, "应通知 GaitCoordinator 恢复动态模式")
    }
    
    // 步数不足 5 步时停止 → 应提示步数不够
    func testStopCalibration_tooFewSteps() {
        // 这个测试验证：即使有 startPosition，步数不足也会被拒绝
        // 但由于 startPosition 是 private，且需要 ARSession 来设置
        // 这里主要验证 stopCalibration 不会崩溃，并会正确清理状态
        calibrator.isCalibrating = true
        calibrator.calibrationSteps = 3
        
        calibrator.stopCalibration()
        
        XCTAssertFalse(calibrator.isCalibrating, "停止后应退出标定状态")
    }
    
    // MARK: - 回调机制
    
    // startCalibration 应触发 onCalibrationStarted 回调
    func testStartCalibration_triggersCallback() {
        // 注意：startCalibration 需要 ARSession
        // 没有 ARSession 时会 guard return，不触发回调
        // 这里验证的是"没有 ARSession 时的安全行为"
        calibrator.arSession = nil
        
        var startedCalled = false
        calibrator.onCalibrationStarted = {
            startedCalled = true
        }
        
        calibrator.startCalibration()
        
        // 没有 ARSession → 应该 guard return，回调不触发
        XCTAssertFalse(startedCalled, "没有 ARSession 时不应触发 onCalibrationStarted")
        XCTAssertFalse(calibrator.isCalibrating, "没有 ARSession 时不应进入标定状态")
    }
}
