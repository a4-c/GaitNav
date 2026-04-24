import Foundation

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
}
