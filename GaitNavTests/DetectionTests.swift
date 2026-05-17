import XCTest
@testable import GaitNav

// Detection 单元测试
// 测试对象：suppressedIDs / suppressContained（嵌套框抑制逻辑）
//
// 抑制规则：
//   当小框 75%+ 面积在大框内，且两者距离差 < 0.5m 时，小框被抑制
//   被抑制的框不会作为大框去抑制其他框
//   缺少距离信息时保守不抑制
final class DetectionTests: XCTestCase {
    
    // MARK: - suppressedIDs 基本测试
    
    // 单个检测不需要抑制
    func testSuppressedIDs_singleDetection() {
        let d = makeDetection(box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), distance: 2.0)
        let ids = Detection.suppressedIDs(in: [d])
        XCTAssertTrue(ids.isEmpty, "单个检测不应有抑制")
    }
    
    // 空数组
    func testSuppressedIDs_emptyArray() {
        let ids = Detection.suppressedIDs(in: [])
        XCTAssertTrue(ids.isEmpty)
    }
    
    // 两个完全不重叠的框：不抑制
    func testSuppressedIDs_noOverlap() {
        let large = makeDetection(box: CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3), distance: 2.0)
        let small = makeDetection(box: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1), distance: 2.0)
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.isEmpty, "不重叠的框不应被抑制")
    }
    
    // 小框完全在大框内 + 距离接近 → 小框被抑制
    func testSuppressedIDs_fullContainment_similarDistance() {
        // 大框：占据 (0.1, 0.1) ~ (0.9, 0.9)
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: 3.0)
        // 小框：完全在大框内
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: 3.2)
        
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.contains(small.id), "完全包含且距离相近的小框应被抑制")
        XCTAssertFalse(ids.contains(large.id), "大框不应被抑制")
    }
    
    // 距离差 > 0.5m → 不抑制（可能是不同深度层的物体）
    func testSuppressedIDs_distanceTooFar() {
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: 2.0)
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: 3.0)
        
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.isEmpty, "距离差 > 0.5m 时不应抑制")
    }
    
    // 重叠不足 75% → 不抑制
    func testSuppressedIDs_insufficientOverlap() {
        // 大框和小框只有部分重叠（小框一半在大框外）
        let large = makeDetection(box: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5), distance: 2.0)
        let small = makeDetection(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), distance: 2.0)
        // 交集 = (0.4,0.4)~(0.5,0.5) = 0.1×0.1 = 0.01
        // 小框面积 = 0.2×0.2 = 0.04
        // 重叠比 = 0.01/0.04 = 0.25 < 0.75
        
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.isEmpty, "重叠 < 75% 时不应抑制")
    }
    
    // 小框缺少距离信息 → 保守不抑制
    func testSuppressedIDs_nilDistance_noSuppression() {
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: 2.0)
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: nil)
        
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.isEmpty, "缺少距离信息时应保守不抑制")
    }
    
    // 大框缺少距离信息 → 保守不抑制
    func testSuppressedIDs_largeBoxNilDistance() {
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: nil)
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: 2.0)
        
        let ids = Detection.suppressedIDs(in: [large, small])
        XCTAssertTrue(ids.isEmpty, "大框缺少距离时应保守不抑制")
    }
    
    // 被抑制的框不能反过来抑制别人
    func testSuppressedIDs_suppressedBoxCannotSuppressOthers() {
        // 大 > 中 > 小，全部嵌套，距离接近
        let large = makeDetection(box: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0), distance: 2.0)
        let medium = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6), distance: 2.1)
        let small = makeDetection(box: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2), distance: 2.0)
        
        let ids = Detection.suppressedIDs(in: [large, medium, small])
        // medium 被 large 抑制后，不能再用来抑制 small
        // 但 small 可以被 large 直接抑制
        XCTAssertFalse(ids.contains(large.id), "最大框不应被抑制")
        XCTAssertTrue(ids.contains(medium.id), "中框应被大框抑制")
        // small 是否被大框抑制取决于实现：如果遍历时 medium 已被标记，large 可以直接抑制 small
        // 验证小框也被正确处理（被 large 抑制）
        XCTAssertTrue(ids.contains(small.id), "小框应被大框抑制")
    }
    
    // 距离恰好在边界：差值 == 0.5m
    func testSuppressedIDs_distanceExactlyAtBoundary() {
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: 2.0)
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: 2.5)
        
        let ids = Detection.suppressedIDs(in: [large, small])
        // abs(2.0 - 2.5) = 0.5，<= 0.5 → 应该被抑制
        XCTAssertTrue(ids.contains(small.id), "距离差恰好 0.5m 时应抑制（<= 判定）")
    }
    
    // MARK: - suppressContained 测试
    
    // suppressContained 返回过滤后的数组
    func testSuppressContained_filtersCorrectly() {
        let large = makeDetection(box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), distance: 3.0)
        let small = makeDetection(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), distance: 3.1)
        
        let result = Detection.suppressContained([large, small])
        XCTAssertEqual(result.count, 1, "应过滤掉被抑制的小框")
        XCTAssertEqual(result.first?.id, large.id, "保留的应是大框")
    }
    
    // 无抑制时返回原数组
    func testSuppressContained_noSuppression_returnsAll() {
        let a = makeDetection(box: CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3), distance: 1.0)
        let b = makeDetection(box: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3), distance: 5.0)
        
        let result = Detection.suppressContained([a, b])
        XCTAssertEqual(result.count, 2)
    }
    
    // MARK: - 辅助方法
    
    // 快速创建 Detection
    private func makeDetection(box: CGRect, distance: Float?) -> Detection {
        return Detection(
            label: "object",
            confidence: 0.85,
            boundingBox: box,
            distance: distance
        )
    }
}
