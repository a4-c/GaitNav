import Foundation
import ARKit

// 物体追踪器：把 YOLO 每帧独立的检测结果串联成连续的追踪轨迹
//
// 为什么需要追踪？
// YOLO 每一帧独立检测，不知道"这帧的人"和"上一帧的人"是同一个
// 所以每帧的检测结果 ID 都不同，标签可能在 "person" 和 "man" 之间跳来跳去
// 距离也可能因为个别帧的噪声突然跳一下
//
// 作用：
//   1. 把连续帧的检测结果匹配起来（用 IoU 判断是不是同一个物体）
//   2. 稳定标签（用最近几帧的投票结果，而不是单帧的标签）
//   3. 平滑距离（用中位数滤波，消除突然的跳变）
//   4. 防闪烁（物体消失 1-2 帧不立刻移除，新物体出现 2 帧以上才显示）
class ObjectTracker {
    
    // 当前正在追踪的所有物体
    private var trackedObjects: [TrackedObject] = []
    
    // IoU 阈值：两个框的重叠度超过这个值，才认为是同一个物体
    // IoU = 交集面积 / 并集面积，范围 0~1
    // 0.3 比较宽松，适合物体在帧间有较大移动的情况
    private let iouThreshold: CGFloat = 0.3
    
    // 物体连续消失超过这么多帧就移除
    private let maxMissedFrames = 3
    
    // 物体至少要存在这么多帧才会显示（防止误检一闪而过）
    let minAgeToShow = 2
    
    // 标签历史最多保留多少条记录（太多会导致标签切换反应慢）
    private let maxLabelHistory = 10
    
    // 距离历史最多保留多少帧（用于中位数滤波）
    // 3 帧 = 只滞后 1 帧就能跟上真实距离变化，同时过滤单帧噪声
    // 增大可以更抗噪但滞后更多，减小反应更快但过滤效果更弱
    private let maxDistanceHistory = 3
    
    // 把追踪结果转换成 Detection 数组给界面显示
    // 只输出 age >= minAgeToShow 的物体（新出现的前几帧不显示，防止闪烁）
    var stableDetections: [Detection] {
        trackedObjects
            .filter { $0.age >= minAgeToShow }
            .map { tracked in
                Detection(
                    id: tracked.id,
                    label: tracked.stableLabel,
                    confidence: tracked.confidence,
                    boundingBox: tracked.boundingBox,
                    distance: tracked.stableDistance
                )
            }
    }
    
    // 物体追踪：匹配、更新、清理
    //
    // 这个方法每帧调用一次，负责把 YOLO 的检测结果和已有的追踪物体对应起来
    //
    // 核心逻辑：
    //   1. 对每个新检测结果，找到和它重叠最多的已有追踪物体（IoU 最大）
    //   2. 如果 IoU > 阈值 → 匹配成功，更新那个追踪物体的信息
    //   3. 如果找不到匹配 → 这是一个新出现的物体，创建新的追踪记录
    //   4. 没被任何新检测匹配到的旧追踪物体 → 标记为"消失了一帧"
    //   5. 连续消失太多帧的 → 彻底移除
    func update(with detections: [Detection]) {
        
        // 记录哪些已有追踪物体在这一帧被匹配到了
        // 用 Set<UUID> 存储被匹配到的追踪物体的 ID
        var matchedTrackedIDs = Set<UUID>()
        // 记录哪些新检测结果被匹配到了（用索引表示）
        var matchedDetectionIndices = Set<Int>()
        
        // ===================================================================
        // 第一步：为每个新检测结果寻找最佳匹配
        // ===================================================================
        
        // 双重循环：外层遍历新检测，内层遍历已有追踪物体
        // 对每个新检测，找到 IoU 最大的那个追踪物体
        for (detIndex, detection) in detections.enumerated() {
            var bestIoU: CGFloat = 0
            var bestTrackedIndex: Int? = nil
            
            for (trackedIndex, tracked) in trackedObjects.enumerated() {
                // 跳过已经被其他检测匹配走的追踪物体（一对一匹配）
                if matchedTrackedIDs.contains(tracked.id) { continue }
                
                let overlap = iou(detection.boundingBox, tracked.boundingBox)
                if overlap > bestIoU {
                    bestIoU = overlap
                    bestTrackedIndex = trackedIndex
                }
            }
            
            // ===================================================================
            // 第二步：判断是否匹配成功
            // ===================================================================
            
            if bestIoU > iouThreshold, let idx = bestTrackedIndex {
                // 匹配成功，更新这个追踪物体的信息
                
                matchedTrackedIDs.insert(trackedObjects[idx].id)
                matchedDetectionIndices.insert(detIndex)
                
                // 更新边界框为最新位置
                trackedObjects[idx].boundingBox = detection.boundingBox
                // 更新置信度
                trackedObjects[idx].confidence = detection.confidence
                // 重置消失计数（因为这帧又看到它了）
                trackedObjects[idx].missedFrames = 0
                // 年龄 +1
                trackedObjects[idx].age += 1
                
                // 记录这帧的标签到历史中
                trackedObjects[idx].labelHistory.append(detection.label)
                // 如果历史太长，删掉最早的记录，只保留最近的
                if trackedObjects[idx].labelHistory.count > maxLabelHistory {
                    trackedObjects[idx].labelHistory.removeFirst()
                }
                
                // 记录距离到历史数组（用于中位数滤波）
                if let newDist = detection.distance {
                    trackedObjects[idx].distanceHistory.append(newDist)
                    // 如果历史太长，删掉最早的，只保留最近几帧
                    if trackedObjects[idx].distanceHistory.count > maxDistanceHistory {
                        trackedObjects[idx].distanceHistory.removeFirst()
                    }
                }
                // 如果这帧没有距离数据（newDist 为 nil），保留现有历史不变
            }
        }
        
        // ===================================================================
        // 第三步：处理没被匹配到的新检测（新出现的物体）
        // ===================================================================
        
        for (detIndex, detection) in detections.enumerated() {
            if matchedDetectionIndices.contains(detIndex) { continue }
            
            // 创建一个新的追踪记录
            // 如果第一帧就有距离数据，放进历史数组；没有就先空着
            let initialHistory: [Float] = detection.distance.map { [$0] } ?? []
            trackedObjects.append(TrackedObject(
                id: UUID(),
                boundingBox: detection.boundingBox,
                labelHistory: [detection.label],
                confidence: detection.confidence,
                distanceHistory: initialHistory,
                missedFrames: 0,
                // 刚出现，第 1 帧
                age: 1
            ))
        }
        
        // ===================================================================
        // 第四步：处理没被匹配到的旧追踪物体（可能离开了画面）
        // ===================================================================
        
        for i in trackedObjects.indices {
            if !matchedTrackedIDs.contains(trackedObjects[i].id) {
                // 这个物体这帧没有对应的新检测，消失帧数 +1
                trackedObjects[i].missedFrames += 1
            }
        }
        
        // ===================================================================
        // 第五步：移除消失太久的物体
        // ===================================================================
        
        // removeAll(where:) 会删掉所有满足条件的元素
        trackedObjects.removeAll { tracked in
            // 默认容忍度
            var allowedMissed = maxMissedFrames
            
            // 如果物体离得很近（比如小于 3.5 米），给予更长的容忍期（例如 10 帧，约 0.3 秒）
            // 这样即便用户走动导致画面剧烈抖动，ID 也不会轻易断开
            if let lastDist = tracked.stableDistance, lastDist < 3.5 {
                allowedMissed = 10
            }
            
            return tracked.missedFrames > allowedMissed
        }
    }
    
    // 计算两个矩形的 IoU（Intersection over Union，交并比）
    //
    // IoU 是衡量两个框重叠程度的标准指标，范围 0~1：
    //   0 = 完全不重叠
    //   1 = 完全重合
    //   通常 > 0.3 就认为是同一个物体
    //
    // 计算方法：
    //   IoU = 交集面积 / 并集面积
    //   并集面积 = A面积 + B面积 - 交集面积（减掉重复算的部分）
    //
    // 示意图：
    //   ┌──────┐
    //   │  A   │
    //   │   ┌──┼───┐
    //   └───┼──┘   │
    //       │  B   │
    //       └──────┘
    //   中间重叠的部分 = 交集
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        // .intersection() 返回两个矩形的重叠区域
        let intersection = a.intersection(b)
        // .isNull 表示没有重叠（两个框完全分开）
        if intersection.isNull { return 0 }
        // 交集面积
        let intersectionArea = intersection.width * intersection.height
        // 并集面积 = A + B - 交集（因为交集被 A 和 B 各算了一次，要减掉一次）
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        // 避免除以零（理论上不会，但以防万一）
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
