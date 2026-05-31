import Foundation
import ARKit

// RawDetection：Detector 单帧输出的原始检测结果
// 它还没有经过追踪系统，所以不带稳定 ID；只描述"这一帧看到了什么"。
struct RawDetection {
    
    // 物体名称
    let label: String
    
    // 模型有多确定这是这个物体，0.0 到 1.0，越高越确定
    let confidence: Float
    
    // 物体在画面中的矩形区域（x, y, 宽, 高）
    let boundingBox: CGRect
    
    // 物体到摄像头的距离，单位是米
    // nil 表示"没有距离信息"
    var distance: Float? = nil
}

// Identifiable 协议要求有一个 id 属性，SwiftUI 的 ForEach 需要它来区分每个元素
struct Detection: Identifiable {
    
    // 唯一标识符，SwiftUI 的 ForEach 用它来区分每个元素
    // 默认自动生成，但也可以从外部传入
    let id: UUID
    
    // 物体名称
    let label: String
    
    // 模型有多确定这是这个物体，0.0 到 1.0，越高越确定
    let confidence: Float
    
    // 物体在画面中的矩形区域（x, y, 宽, 高）
    let boundingBox: CGRect
    
    // 物体到摄像头的距离，单位是米
    // 用 var 而不是 let，因为我们先创建检测结果，之后再补上距离
    // Optional 类型（Float?），因为有时候深度数据可能无效或不可用
    // nil 表示"没有距离信息"
    var distance: Float? = nil
    
    // 自定义构造函数
    // id 参数有默认值 UUID()，所以：
    //   - Detector 里创建时不传 id → 自动生成新的（和之前一样）
    //   - 追踪系统创建时传入稳定 id → SwiftUI 能识别出是同一个物体
    init(id: UUID = UUID(), label: String, confidence: Float, boundingBox: CGRect, distance: Float? = nil) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.distance = distance
    }
    
    // 当一个大检测框里有若干小检测框，且距离相似时，小框是冗余的
    // 餐桌检测框里套着杯子、盘子、碗，距离都差不多，
    // 全部播报就变成报菜名，只报餐桌就够了。
    //
    // suppressedIDs()  → 返回应被抑制的小框 ID 集合（DetectionOverlay 用于降低透明度）
    // suppressContained() → 返回过滤后的数组（FeedbackEngine 用于语音管道）
    //
    // 三个条件同时满足才抑制：
    //   1. 大框面积 > 小框面积
    //   2. 小框 75%+ 的面积在大框内部（空间包含）
    //   3. 两者距离差 < 0.5m（距离相似 → 同一区域的物体）
    
    // 小框面积被大框覆盖超过这个比例，就认为被包含
    private static let containmentOverlapThreshold: CGFloat = 0.75
    
    // 距离差异在这个范围内才认为距离相似
    private static let containmentDistanceTolerance: Float = 0.5
    
    // 返回应被抑制的小框 ID 集合
    static func suppressedIDs(in detections: [Detection]) -> Set<UUID> {
        
        // 少于 2 个检测不需要做包含检查
        guard detections.count >= 2 else { return [] }
        
        // 记录需要被抑制的 ID
        var ids = Set<UUID>()
        
        for small in detections {
            let smallArea = small.boundingBox.width * small.boundingBox.height
            // 面积为 0 的框跳过（退化情况）
            guard smallArea > 0 else { continue }
            
            for large in detections {
                // 不和自己比较
                guard large.id != small.id else { continue }
                // 已经被抑制的框不能作为大框去抑制别人
                guard !ids.contains(large.id) else { continue }
                
                // 条件 1：大框确实比小框大
                let largeArea = large.boundingBox.width * large.boundingBox.height
                guard largeArea > smallArea else { continue }
                
                // 条件 2：空间包含：小框大部分面积在大框内
                let intersection = small.boundingBox.intersection(large.boundingBox)
                guard !intersection.isNull else { continue }
                let overlapRatio = (intersection.width * intersection.height) / smallArea
                guard overlapRatio >= containmentOverlapThreshold else { continue }
                
                // 条件 3：距离相似
                // 两者都有距离信息，且差值在容忍范围内
                if let sd = small.distance, let ld = large.distance,
                   abs(sd - ld) <= containmentDistanceTolerance {
                    // 所有条件满足：小框被大框包含且距离相似 → 抑制小框
                    ids.insert(small.id)
                    // 已经被抑制了，不用再找其他大框
                    break
                }
                // 如果某一方没有距离信息，保守起见不抑制（宁可多报也不漏报）
            }
        }
        return ids
    }
    
    // 返回过滤后的数组（移除被抑制的小框）
    static func suppressContained(_ detections: [Detection]) -> [Detection] {
        let ids = suppressedIDs(in: detections)
        return ids.isEmpty ? detections : detections.filter { !ids.contains($0.id) }
    }
}
