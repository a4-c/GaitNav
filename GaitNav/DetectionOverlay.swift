import SwiftUI

// 负责绘制检测框和标签的视图
struct DetectionOverlay: View {
    
    let detections: [Detection]
    
    var body: some View {
        // GeometryReader 能获取父视图的实际尺寸
        // 我们需要它来把模型输出的归一化坐标转成屏幕像素坐标
        GeometryReader { geometry in
            // 遍历每个检测结果
            ForEach(detections) { detection in
                // 把模型的坐标转成屏幕坐标
                let rect = convertRect(detection.boundingBox, in: geometry.size)
                
                // 画一个绿色边框的矩形
                Rectangle()
                    // 绿色描边，线宽2
                    .stroke(Color.green, lineWidth: 2)
                    // 框的大小
                    .frame(width: rect.width, height: rect.height)
                    // 框的位置（中心点）
                    .position(x: rect.midX, y: rect.midY)
                
                // 在框上方显示标签和置信度
                Text("\(detection.label) \(Int(detection.confidence * 100))%")
                    // 小字体
                    .font(.caption)
                    // 黑色文字
                    .foregroundColor(.black)
                    // 内边距
                    .padding(4)
                    // 绿色背景
                    .background(Color.green)
                    // 圆角
                    .cornerRadius(4)
                    // 放在框顶部上方
                    .position(x: rect.midX, y: rect.minY - 12)
            }
        }
    }
    
    // 坐标转换函数
    // Vision 框架返回的坐标是"归一化"的：x 和 y 都在 0 到 1 之间
    // 而且 y 轴是从底部往上的（和屏幕相反）
    // 这个函数把它转成屏幕上的实际像素坐标
    private func convertRect(_ boundingBox: CGRect, in size: CGSize) -> CGRect {
        // x 起点
        let x = boundingBox.minX * size.width
        // y 起点（翻转 y 轴）
        let y = (1 - boundingBox.maxY) * size.height
        // 宽度
        let width = boundingBox.width * size.width
        // 高度
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
