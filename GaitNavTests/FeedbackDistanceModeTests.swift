import XCTest
@testable import GaitNav

// FeedbackDistanceMode 单元测试
// 测试对象：label 属性、UserDefaults 持久化
final class FeedbackDistanceModeTests: XCTestCase {
    
    private let storageKey = "feedbackDistanceMode"
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }
    
    // MARK: - label 属性
    
    func testLabel_steps() {
        XCTAssertEqual(FeedbackDistanceMode.steps.label, "Steps")
    }
    
    func testLabel_meters() {
        XCTAssertEqual(FeedbackDistanceMode.meters.label, "Meters")
    }
    
    // MARK: - 持久化
    
    // 默认值应为 .steps
    func testSaved_defaultIsSteps() {
        XCTAssertEqual(FeedbackDistanceMode.saved, .steps, "默认模式应为 steps")
    }
    
    // 保存后应能正确读取
    func testSaveAndLoad_meters() {
        FeedbackDistanceMode.meters.save()
        XCTAssertEqual(FeedbackDistanceMode.saved, .meters, "保存 meters 后应能读取到 meters")
    }
    
    func testSaveAndLoad_steps() {
        // 先设为 meters
        FeedbackDistanceMode.meters.save()
        // 再切回 steps
        FeedbackDistanceMode.steps.save()
        XCTAssertEqual(FeedbackDistanceMode.saved, .steps, "重新保存 steps 后应能读取到 steps")
    }
    
    // UserDefaults 中存储了非法值时应回退到默认
    func testSaved_invalidRawValue_fallbackToSteps() {
        UserDefaults.standard.set("invalid_mode", forKey: storageKey)
        XCTAssertEqual(FeedbackDistanceMode.saved, .steps, "非法值应回退到 .steps")
    }
    
    // MARK: - Identifiable
    
    // id 应等于 rawValue
    func testId_equalsRawValue() {
        XCTAssertEqual(FeedbackDistanceMode.steps.id, "steps")
        XCTAssertEqual(FeedbackDistanceMode.meters.id, "meters")
    }
    
    // MARK: - CaseIterable
    
    // 应有两种模式
    func testAllCases() {
        XCTAssertEqual(FeedbackDistanceMode.allCases.count, 2)
        XCTAssertTrue(FeedbackDistanceMode.allCases.contains(.steps))
        XCTAssertTrue(FeedbackDistanceMode.allCases.contains(.meters))
    }
}
