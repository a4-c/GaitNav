import Foundation

// Identifiable 协议要求有一个 id 属性，SwiftUI 的 ForEach 需要它来区分每个元素
struct Detection: Identifiable {
    
    // 自动生成一个唯一标识符，每个检测结果都不同
    let id = UUID()
    
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
}
