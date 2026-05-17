import XCTest
@testable import GaitNav

// ObjectTracker 单元测试
// 测试对象：IoU 匹配、age 门控、missedFrames 生命周期、标签投票、距离中位数
//
// 测试策略：
//   通过 update(with:) 喂入 RawDetection 序列
//   通过 stableDetections 观察输出
//   间接验证 IoU 匹配和内部状态管理
final class ObjectTrackerTests: XCTestCase {
    
    private var tracker: ObjectTracker!
    
    override func setUp() {
        super.setUp()
        tracker = ObjectTracker()
    }
    
    // MARK: - 新物体创建
    
    // 第一帧检测到物体，age=1，stableDetections 应为空（age < minAgeToShow）
    func testNewDetection_notVisibleImmediately() {
        let raw = makeRaw(box: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3))
        tracker.update(with: [raw])
        
        XCTAssertTrue(tracker.stableDetections.isEmpty,
                      "age=1 的新物体不应出现在 stableDetections 中（minAgeToShow=\(tracker.minAgeToShow)）")
    }
    
    // 连续两帧同一位置，age=2，应出现在 stableDetections
    func testDetection_visibleAfterMinAge() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        // 第 1 帧
        tracker.update(with: [makeRaw(box: box)])
        // 第 2 帧：相同位置 → IoU ≈ 1.0 → 匹配成功 → age=2
        tracker.update(with: [makeRaw(box: box)])
        
        XCTAssertEqual(tracker.stableDetections.count, 1,
                       "age=2 后物体应出现在 stableDetections 中")
    }
    
    // MARK: - IoU 匹配
    
    // 完全相同位置的框应匹配为同一物体（ID 不变）
    func testIoU_samePosition_matchesAsOneObject() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        // 喂 3 帧，让 age >= minAgeToShow
        for _ in 0..<3 {
            tracker.update(with: [makeRaw(box: box)])
        }
        
        let detections = tracker.stableDetections
        XCTAssertEqual(detections.count, 1, "应只有一个追踪物体")
    }
    
    // 完全不重叠的两个框应创建两个追踪物体
    func testIoU_noOverlap_createsTwo() {
        let box1 = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let box2 = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)
        
        for _ in 0..<3 {
            tracker.update(with: [makeRaw(box: box1), makeRaw(box: box2)])
        }
        
        XCTAssertEqual(tracker.stableDetections.count, 2, "不重叠的两个框应创建两个追踪物体")
    }
    
    // 框轻微移动（高 IoU）应保持为同一物体
    func testIoU_slightMovement_sameObject() {
        let box1 = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        let box2 = CGRect(x: 0.32, y: 0.31, width: 0.2, height: 0.3) // 轻微偏移
        
        tracker.update(with: [makeRaw(box: box1)])
        tracker.update(with: [makeRaw(box: box2)])
        tracker.update(with: [makeRaw(box: box2)])
        
        XCTAssertEqual(tracker.stableDetections.count, 1, "轻微移动应被匹配为同一物体")
    }
    
    // MARK: - 消失与清理
    
    // 物体消失后，经过足够帧数应被移除
    func testMissedFrames_objectRemovedAfterThreshold() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        // 使用远距离（> 3.5m），走标准的 maxMissedFrames = 3 路径
        // 如果距离 < 3.5m，ObjectTracker 会给予更长的容忍期（10 帧）
        for _ in 0..<3 {
            tracker.update(with: [makeRaw(box: box, distance: 5.0)])
        }
        XCTAssertEqual(tracker.stableDetections.count, 1, "物体应可见")
        
        // 物体消失（空帧），连续多帧
        // maxMissedFrames = 3，所以需要 > 3 帧空才能移除
        for _ in 0..<4 {
            tracker.update(with: [])
        }
        
        XCTAssertTrue(tracker.stableDetections.isEmpty, "消失足够多帧后物体应被移除")
    }
    
    // 物体消失 1 帧后，追踪记录应仍然保留（不会立刻被清理）
    func testMissedFrames_briefDisappearance_survives() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        // 存在 3 帧 → age=3, missedFrames=0
        for _ in 0..<3 {
            tracker.update(with: [makeRaw(box: box)])
        }
        XCTAssertEqual(tracker.stableDetections.count, 1, "前置条件：物体应已可见")
        
        // 消失 1 帧 → missedFrames=1, 仍 < maxMissedFrames
        // age 不变（只有匹配成功才会递增）
        // 直接断言：不重新喂入检测，确认物体靠自身的容忍帧数存活
        tracker.update(with: [])
        
        XCTAssertEqual(tracker.stableDetections.count, 1,
                       "消失仅 1 帧（missedFrames=1 < maxMissedFrames），物体应仍然保留")
    }
    
    // MARK: - 标签稳定性
    
    // 标签在多帧间保持一致时应返回该标签
    func testStableLabel_consistentLabel() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        for _ in 0..<3 {
            tracker.update(with: [makeRaw(box: box, label: "chair")])
        }
        
        let label = tracker.stableDetections.first?.label
        XCTAssertEqual(label, "chair")
    }
    
    // 标签在少数帧闪烁时，多数标签应胜出
    func testStableLabel_majorityWins() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        // 5 帧 "person"，2 帧 "man"
        for _ in 0..<5 {
            tracker.update(with: [makeRaw(box: box, label: "person")])
        }
        for _ in 0..<2 {
            tracker.update(with: [makeRaw(box: box, label: "man")])
        }
        
        let label = tracker.stableDetections.first?.label
        XCTAssertEqual(label, "person", "多数标签应胜出")
    }
    
    // MARK: - 距离平滑
    
    // 距离历史应反映中位数
    func testStableDistance_medianFiltering() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        // 喂入 3 帧距离 [2.0, 2.1, 5.0]
        // 中位数 = 2.1（排序后 [2.0, 2.1, 5.0]，取 index 1）
        tracker.update(with: [makeRaw(box: box, distance: 2.0)])
        tracker.update(with: [makeRaw(box: box, distance: 2.1)])
        tracker.update(with: [makeRaw(box: box, distance: 5.0)])
        
        let distance = tracker.stableDetections.first?.distance
        XCTAssertNotNil(distance)
        if let d = distance {
            XCTAssertEqual(d, 2.1, accuracy: 0.01, "中位数应过滤掉噪声值 5.0")
        }
    }
    
    // 无距离信息的帧不影响已有历史
    func testStableDistance_nilDistancePreservesHistory() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
        
        tracker.update(with: [makeRaw(box: box, distance: 3.0)])
        tracker.update(with: [makeRaw(box: box, distance: 3.1)])
        // 第 3 帧没有距离信息
        tracker.update(with: [makeRaw(box: box, distance: nil)])
        
        let distance = tracker.stableDetections.first?.distance
        XCTAssertNotNil(distance, "缺少距离帧不应清除已有距离历史")
    }
    
    // MARK: - 多物体同时追踪
    
    // 同时追踪多个物体时，各自独立
    func testMultipleObjects_trackedIndependently() {
        let boxA = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let boxB = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)
        
        for _ in 0..<3 {
            tracker.update(with: [
                makeRaw(box: boxA, label: "person", distance: 2.0),
                makeRaw(box: boxB, label: "chair", distance: 4.0)
            ])
        }
        
        let detections = tracker.stableDetections
        XCTAssertEqual(detections.count, 2, "应有两个独立的追踪物体")
        
        let labels = Set(detections.map { $0.label })
        XCTAssertTrue(labels.contains("person"), "应包含 person")
        XCTAssertTrue(labels.contains("chair"), "应包含 chair")
    }
    
    // MARK: - 辅助方法
    
    // 快速创建 RawDetection
    private func makeRaw(box: CGRect,
                         label: String = "object",
                         confidence: Float = 0.9,
                         distance: Float? = 2.5) -> RawDetection {
        return RawDetection(
            label: label,
            confidence: confidence,
            boundingBox: box,
            distance: distance
        )
    }
}
