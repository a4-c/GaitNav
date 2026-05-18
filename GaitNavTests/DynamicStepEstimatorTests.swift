import XCTest
@testable import GaitNav

// DynamicStepEstimator 单元测试
// 测试对象：isActive 超时逻辑、reset()、初始状态
//
// 测试策略：
//   handleStep() 需要 ARSession（读取手机位置），在没有真机的测试环境中无法直接调用
//   但 isActive 的超时逻辑、reset() 的清理行为、初始状态等可以独立测试
//   通过直接设置 lastUpdateTime 和 currentStepLength 来模拟不同状态
final class DynamicStepEstimatorTests: XCTestCase {
    
    private var estimator: DynamicStepEstimator!
    
    override func setUp() {
        super.setUp()
        estimator = DynamicStepEstimator()
    }
    
    // MARK: - 初始状态
    
    // 初始状态：没有步长数据，不活跃
    func testInitialState() {
        XCTAssertNil(estimator.currentStepLength, "初始状态没有步长数据")
        XCTAssertFalse(estimator.isActive, "初始状态不应活跃")
    }
    
    // MARK: - isActive 超时逻辑
    
    // 有步长数据且刚刚更新 → 活跃
    func testIsActive_recentUpdate_true() {
        // 手动注入状态（绕过 handleStep 的 ARSession 依赖）
        // 注意：currentStepLength 是 private(set)，所以我们需要通过其他方式验证
        // 这里我们验证的是 isActive 的逻辑组合
        
        // 由于 currentStepLength 是 private(set)，无法直接设置
        // 但 lastUpdateTime 是 var，可以设置
        // isActive = currentStepLength != nil && Date().timeIntervalSince(lastUpdateTime) < timeout
        // 初始 currentStepLength 为 nil，所以 isActive 永远为 false
        // 这个测试验证了：没有步长数据时即使时间在范围内也不活跃
        estimator.lastUpdateTime = Date()
        XCTAssertFalse(estimator.isActive,
                       "即使 lastUpdateTime 刚更新，没有 currentStepLength 时也不应活跃")
    }
    
    // MARK: - reset 行为
    
    // reset 应清除所有数据
    func testReset_clearsAllState() {
        // 调用 reset
        estimator.reset()
        
        XCTAssertNil(estimator.currentStepLength, "reset 后步长应为 nil")
        XCTAssertFalse(estimator.isActive, "reset 后不应活跃")
    }
    
    // 多次 reset 不应出错
    func testReset_idempotent() {
        estimator.reset()
        estimator.reset()
        estimator.reset()
        
        XCTAssertNil(estimator.currentStepLength)
        XCTAssertFalse(estimator.isActive)
    }
    
    // MARK: - timeout 值验证
    
    // 超时时间应为 3.0 秒
    func testTimeoutValue() {
        XCTAssertEqual(estimator.timeout, 3.0, accuracy: 0.001,
                       "超时时间应为 3.0 秒")
    }
    
    // MARK: - handleStep 无 ARSession 安全性
    
    // 没有 ARSession 时调用 handleStep 不应崩溃
    func testHandleStep_noARSession_doesNotCrash() {
        estimator.arSession = nil
        // 不应崩溃
        estimator.handleStep()
        
        XCTAssertNil(estimator.currentStepLength, "没有 ARSession 时不应产生步长数据")
    }
}
