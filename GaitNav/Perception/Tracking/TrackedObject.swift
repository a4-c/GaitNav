import Foundation

// 物体追踪系统
//
// 为什么需要追踪？
// YOLO 每一帧独立检测，不知道"这帧的人"和"上一帧的人"是同一个
// 所以每帧的检测结果 ID 都不同，标签可能在 "person" 和 "man" 之间跳来跳去
// 距离也可能因为个别帧的噪声突然跳一下
//
// 作用：
//   1. 把连续帧的检测结果匹配起来（用 IoU 判断是不是同一个物体）
//   2. 稳定标签（用最近几帧的投票结果，而不是单帧的标签）
//   3. 平滑距离（用指数移动平均，消除突然的跳变）
//   4. 防闪烁（物体消失 1-2 帧不立刻移除，新物体出现 2 帧以上才显示）

// TrackedObject：一个被持续追踪的物体
// 它跨越多帧存在，记录了这个物体的历史信息
struct TrackedObject {
    
    // 稳定的唯一标识符，在这个物体被追踪期间不会改变
    // 和 Detection 的 id 不同（Detection 每帧生成新的 UUID）
    let id: UUID
    
    // 物体在画面中的位置（每帧更新为最新位置）
    var boundingBox: CGRect
    
    // 最近几帧的标签记录，用于投票决定最终显示哪个标签
    // 比如最近 10 帧里 7 次是 "person"、3 次是 "man" → 显示 "person"
    var labelHistory: [String]
    
    // 最新的置信度
    var confidence: Float
    
    // 最近几帧的距离记录（原始值，不做任何平滑）
    // 每帧把新的距离值追加进来，超过上限就删掉最早的
    // 最终输出时取这个数组的中位数
    //
    // 为什么用中位数而不是指数移动平均（EMA）？
    // 因为用户在走路，距离在持续变化。EMA 会让距离滞后于真实值
    // 比如你已经走到 1.4m 了，EMA 还显示 1.63m，警告就来晚了。
    // 中位数只滞后 1 帧（最多），但单帧噪声会被直接过滤掉。
    var distanceHistory: [Float]
    
    // 连续多少帧没有被匹配到新的检测结果
    // 每次匹配成功就重置为 0，每次没匹配到就 +1
    // 超过一定帧数（比如 3 帧）就认为物体已经离开画面，移除它
    var missedFrames: Int
    
    // 这个物体总共存在了多少帧
    // 新出现的物体 age=1，之后每帧 +1
    // 只有 age >= 2 的物体才会显示在界面上，防止误检闪一下就消失
    var age: Int
    
    // 计算属性：从标签历史中选出出现次数最多的标签
    var stableLabel: String {
        // Dictionary(grouping:by:) 把数组按元素分组
        // 比如 ["person","man","person","person"] → ["person": ["person","person","person"], "man": ["man"]]
        // mapValues { $0.count } 把每组的数组变成它的长度 → ["person": 3, "man": 1]
        let counts = Dictionary(grouping: labelHistory, by: { $0 }).mapValues { $0.count }
        // max(by:) 找出计数最大的那个键值对，取它的 key（标签名）
        // ?? 是兜底：如果历史为空（理论上不会），就返回 "?"
        return counts.max(by: { $0.value < $1.value })?.key ?? "?"
    }
    
    // 计算属性：从距离历史中取中位数
    // 比如最近 3 帧距离是 [1.6, 2.1, 1.6]
    // 排序后 [1.6, 1.6, 2.1]，中位数 = 1.6
    // 那个 2.1 的噪声就被过滤掉了
    var stableDistance: Float? {
        // 如果没有任何距离记录，返回 nil
        guard !distanceHistory.isEmpty else { return nil }
        let sorted = distanceHistory.sorted()
        return sorted[sorted.count / 2]
    }
}
