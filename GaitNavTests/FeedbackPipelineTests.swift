import XCTest
@testable import GaitNav

// FeedbackPipeline 单元测试
// 测试对象：焦点获取→首报、侧边过滤、突然出现警告、倒数逻辑、米数模式阈值
//
// 测试策略：
//   使用 MockSpeechManager 子类拦截所有 speak/speakInterrupting 调用
//   记录播报内容，验证播报时机和文案是否正确
//   通过 update(with:) 和 handleStep(with:) 公共接口驱动测试

// MockSpeechManager：拦截语音输出，记录播报内容
// 覆写 speak / speakInterrupting，不实际播放语音
// final 修饰：满足 Sendable 协议对类类型的要求（非 final 类无法保证不被子类破坏线程安全）
// nonisolated(unsafe)：告诉编译器这些可变属性仅在测试的单线程环境中使用，跳过 Sendable 检查
final class MockSpeechManager: SpeechManager {
    
    // 记录所有普通播报的文本
    nonisolated(unsafe) var spokenTexts: [String] = []
    // 记录所有打断式播报的文本
    nonisolated(unsafe) var interruptedTexts: [String] = []
    // 合并的播报记录（按顺序）
    nonisolated(unsafe) var allTexts: [String] = []
    
    override func speak(_ text: String) {
        spokenTexts.append(text)
        allTexts.append(text)
    }
    
    override func speakInterrupting(_ text: String) {
        interruptedTexts.append(text)
        allTexts.append(text)
    }
    
    // 清除记录
    func reset() {
        spokenTexts.removeAll()
        interruptedTexts.removeAll()
        allTexts.removeAll()
    }
}

final class FeedbackPipelineTests: XCTestCase {
    
    private var mockSpeech: MockSpeechManager!
    private var gaitPipeline: GaitPipeline!
    private var feedbackPipeline: FeedbackPipeline!
    
    override func setUp() {
        super.setUp()
        // 清除标定数据，使用默认步长 0.65m
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        
        mockSpeech = MockSpeechManager()
        gaitPipeline = GaitPipeline()
        feedbackPipeline = FeedbackPipeline(speech: mockSpeech, gaitPipeline: gaitPipeline, distanceMode: .steps)
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "calibratedStepLength")
        super.tearDown()
    }
    
    // MARK: - 焦点获取 & 首次播报
    
    // 第一次看到物体时应完整播报：label + 方位 + 步数
    func testFirstDetection_fullAnnouncement() {
        let detection = makeDetection(
            midX: 0.5,      // 中央 → 12 o'clock
            distance: 3.0   // 3.0m / 0.65m ≈ 5 步
        )
        
        feedbackPipeline.update(with: [detection])
        
        XCTAssertFalse(mockSpeech.allTexts.isEmpty, "首次看到物体应触发播报")
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("test"), "应包含物体标签")
            XCTAssertTrue(text.contains("12 o'clock"), "中央物体应报 12 o'clock")
            XCTAssertTrue(text.contains("step"), "应包含步数信息")
        }
    }
    
    // MARK: - 方位判断（通过首报间接测试 clockDirection）
    
    // 物体在左侧（midX < 0.25）→ 11 o'clock
    func testDirection_left() {
        let detection = makeDetection(midX: 0.1, distance: 2.0)
        feedbackPipeline.update(with: [detection])
        
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("11 o'clock"), "左侧物体应报 11 o'clock，实际: \(text)")
        }
    }
    
    // 物体在中央（0.25 ≤ midX < 0.75）→ 12 o'clock
    func testDirection_center() {
        let detection = makeDetection(midX: 0.5, distance: 2.0)
        feedbackPipeline.update(with: [detection])
        
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("12 o'clock"), "中央物体应报 12 o'clock，实际: \(text)")
        }
    }
    
    // 物体在右侧（midX ≥ 0.75）→ 1 o'clock
    func testDirection_right() {
        let detection = makeDetection(midX: 0.9, distance: 2.0)
        feedbackPipeline.update(with: [detection])
        
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("1 o'clock"), "右侧物体应报 1 o'clock，实际: \(text)")
        }
    }
    
    // MARK: - 侧边过滤
    
    // 侧边 + 远距离物体（> 5 步）应被忽略
    func testSideFilter_farSideObject_ignored() {
        // midX = 0.1 → 左侧边（< 0.35）
        // distance = 5.0m → 约 8 步（> sideIgnoreSteps=5）
        let detection = makeDetection(midX: 0.1, distance: 5.0)
        feedbackPipeline.update(with: [detection])
        
        XCTAssertTrue(mockSpeech.allTexts.isEmpty, "侧边远处物体不应触发播报")
    }
    
    // 侧边 + 近距离物体（≤ 3 步）应被播报（安全优先）
    func testSideFilter_closeSideObject_announced() {
        // midX = 0.1 → 左侧边
        // distance = 1.5m → 约 3 步（≤ 3 步的侧边物体仍会被关注）
        let detection = makeDetection(midX: 0.1, distance: 1.5)
        feedbackPipeline.update(with: [detection])
        
        XCTAssertFalse(mockSpeech.allTexts.isEmpty, "近距离侧边物体应触发播报")
    }
    
    // MARK: - 无距离信息
    
    // 没有距离信息的物体应被忽略
    func testNoDistance_ignored() {
        let detection = makeDetection(midX: 0.5, distance: nil)
        feedbackPipeline.update(with: [detection])
        
        XCTAssertTrue(mockSpeech.allTexts.isEmpty, "无距离信息的物体不应触发播报")
    }
    
    // MARK: - 漏斗行为：一次只关注一个物体
    
    // 两个物体同时存在时，只播报最近的
    func testFunnel_onlyClosestAnnounced() {
        let close = makeDetection(midX: 0.5, distance: 2.0, label: "chair")
        let far = makeDetection(midX: 0.5, distance: 6.0, label: "table")
        
        feedbackPipeline.update(with: [close, far])
        
        XCTAssertEqual(mockSpeech.allTexts.count, 1, "应只播报一个物体")
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("chair"), "应播报最近的物体 chair")
        }
    }
    
    // MARK: - 突然出现的近距离物体
    
    // 第二帧突然出现近距离新物体（≤ 3 步 + 中央）→ 应立刻打断
    func testSuddenAppearance_urgentAlert() {
        // 第一帧：有一个远处物体
        let far = makeDetection(midX: 0.5, distance: 6.0, label: "table")
        feedbackPipeline.update(with: [far])
        mockSpeech.reset()
        
        // 第二帧：突然出现近距离物体
        let sudden = makeDetection(midX: 0.5, distance: 0.5, label: "person")
        feedbackPipeline.update(with: [far, sudden])
        
        XCTAssertFalse(mockSpeech.allTexts.isEmpty, "突然出现的近距离物体应触发播报")
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("person"), "应播报新出现的物体")
        }
    }
    
    // MARK: - 防抖
    
    // 短时间内不应重复播报同一物体的相同状态
    func testDebounce_noRepeatWithinInterval() {
        let detection = makeDetection(midX: 0.5, distance: 4.0, label: "chair")
        
        feedbackPipeline.update(with: [detection])
        let firstCount = mockSpeech.allTexts.count
        
        // 立刻再次 update（同一物体，距离没有跨过阈值）
        feedbackPipeline.update(with: [detection])
        let secondCount = mockSpeech.allTexts.count
        
        XCTAssertEqual(firstCount, secondCount,
                       "短时间内对同一物体不应重复播报")
    }
    
    // MARK: - 物体消失后释放焦点
    
    // 物体消失 → 应释放焦点，新物体应能被播报
    func testFocusRelease_afterObjectDisappears() {
        let obj1 = makeDetection(midX: 0.5, distance: 3.0, label: "chair")
        feedbackPipeline.update(with: [obj1])
        
        // 等待足够时间让防抖冷却（minAnnouncementInterval = 1.5s）
        // 使用 Thread.sleep 而非 expectation + DispatchQueue.main.asyncAfter，
        // 因为 waitForExpectations 会阻塞主线程，导致 asyncAfter 的 block 永远无法执行（死锁）。
        // FeedbackPipeline 的防抖基于 Date() 比较，只需要实际时间流逝即可。
        Thread.sleep(forTimeInterval: 1.6)
        
        mockSpeech.reset()
        
        // 物体消失
        feedbackPipeline.update(with: [])
        
        // 新物体出现
        let obj2 = makeDetection(midX: 0.5, distance: 2.0, label: "person")
        feedbackPipeline.update(with: [obj2])
        
        XCTAssertFalse(mockSpeech.allTexts.isEmpty, "旧物体消失后新物体应能被播报")
        if let text = mockSpeech.allTexts.first {
            XCTAssertTrue(text.contains("person"), "应播报新物体 person")
        }
    }
    
    // MARK: - 辅助方法
    
    // 快速创建 Detection
    // midX 控制方位：< 0.25 → 11点, 0.25~0.75 → 12点, > 0.75 → 1点
    // 通过 boundingBox 的 x 和 width 来控制 midX
    private func makeDetection(midX: CGFloat,
                               distance: Float?,
                               label: String = "test") -> Detection {
        // midX = x + width/2，所以 x = midX - width/2
        let width: CGFloat = 0.1
        let x = midX - width / 2
        
        return Detection(
            label: label,
            confidence: 0.9,
            boundingBox: CGRect(x: x, y: 0.3, width: width, height: 0.2),
            distance: distance
        )
    }
}
