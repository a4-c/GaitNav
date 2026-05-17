import XCTest
@testable import GaitNav

// TrackedObject 单元测试
// 测试对象：stableLabel（多帧投票）和 stableDistance（中位数滤波）
final class TrackedObjectTests: XCTestCase {
    
    // MARK: - stableLabel 测试
    
    // 只有一个标签时，直接返回该标签
    func testStableLabel_singleLabel() {
        let obj = makeTracked(labels: ["person"])
        XCTAssertEqual(obj.stableLabel, "person")
    }
    
    // 多个相同标签时，返回该标签
    func testStableLabel_unanimousVote() {
        let obj = makeTracked(labels: ["chair", "chair", "chair"])
        XCTAssertEqual(obj.stableLabel, "chair")
    }
    
    // 多数投票：出现最多的标签胜出
    func testStableLabel_majorityVote() {
        let obj = makeTracked(labels: ["person", "man", "person", "person", "man"])
        XCTAssertEqual(obj.stableLabel, "person")
    }
    
    // 两个标签数量相同时，只要返回其中一个即可（不要求特定偏好）
    func testStableLabel_tie() {
        let obj = makeTracked(labels: ["cat", "dog", "cat", "dog"])
        let result = obj.stableLabel
        XCTAssertTrue(result == "cat" || result == "dog",
                      "平票时应返回其中一个，实际返回: \(result)")
    }
    
    // 空历史时返回 "?"
    func testStableLabel_emptyHistory() {
        let obj = makeTracked(labels: [])
        XCTAssertEqual(obj.stableLabel, "?")
    }
    
    // 标签在后期切换时，新标签在积累足够次数后可以翻转
    func testStableLabel_labelSwitch() {
        // 前 3 帧是 "car"，后 5 帧是 "truck" → "truck" 应胜出
        let obj = makeTracked(labels: ["car", "car", "car", "truck", "truck", "truck", "truck", "truck"])
        XCTAssertEqual(obj.stableLabel, "truck")
    }
    
    // MARK: - stableDistance 测试
    
    // 单个距离值，直接返回
    func testStableDistance_singleValue() throws {
        let obj = makeTracked(distances: [2.5])
        // 先安全解包 Float?，再与 Float 字面量比较
        let distance = try XCTUnwrap(obj.stableDistance)
        XCTAssertEqual(distance, 2.5, accuracy: Float(0.001))
    }
    
    // 奇数个值：返回排序后的中间值
    func testStableDistance_oddCount() throws {
        // [1.6, 2.1, 1.6] → 排序 [1.6, 1.6, 2.1] → 中位数 = 1.6
        let obj = makeTracked(distances: [1.6, 2.1, 1.6])
        let distance = try XCTUnwrap(obj.stableDistance)
        XCTAssertEqual(distance, 1.6, accuracy: Float(0.001))
    }
    
    // 偶数个值：返回下中位数（count / 2 取整除）
    func testStableDistance_evenCount() throws {
        // [1.0, 2.0, 3.0, 4.0] → sorted[4/2] = sorted[2] = 3.0
        let obj = makeTracked(distances: [1.0, 2.0, 3.0, 4.0])
        let distance = try XCTUnwrap(obj.stableDistance)
        XCTAssertEqual(distance, 3.0, accuracy: Float(0.001))
    }
    
    // 空历史返回 nil
    func testStableDistance_empty() {
        let obj = makeTracked(distances: [])
        XCTAssertNil(obj.stableDistance)
    }
    
    // 单帧噪声被中位数过滤掉
    func testStableDistance_filtersNoise() throws {
        // [2.0, 2.1, 8.0] → 排序 [2.0, 2.1, 8.0] → 中位数 = 2.1
        // 噪声值 8.0 不会影响结果
        let obj = makeTracked(distances: [2.0, 2.1, 8.0])
        let distance = try XCTUnwrap(obj.stableDistance)
        XCTAssertEqual(distance, 2.1, accuracy: Float(0.001))
    }
    
    // 所有值相同
    func testStableDistance_allSame() throws {
        let obj = makeTracked(distances: [3.0, 3.0, 3.0])
        let distance = try XCTUnwrap(obj.stableDistance)
        XCTAssertEqual(distance, 3.0, accuracy: Float(0.001))
    }
    
    // MARK: - 辅助方法
    
    // 快速创建 TrackedObject，只设置需要测试的字段
    private func makeTracked(labels: [String] = ["test"],
                             distances: [Float] = []) -> TrackedObject {
        return TrackedObject(
            id: UUID(),
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3),
            labelHistory: labels,
            confidence: 0.9,
            distanceHistory: distances,
            missedFrames: 0,
            age: 3
        )
    }
}
