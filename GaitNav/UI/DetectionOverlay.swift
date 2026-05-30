import SwiftUI

// 检测框叠加层
//
// 视觉变化：
//   - 检测框颜色随距离动态变化：绿色（远）→ 黄色（中）→ 红色（近）
//   - 标签改为深色底 + 高对比文字
//   - 距离信息用更大的字号突出显示
//   - 近距离物体的框线加粗 + 闪烁，增强视觉警示
struct DetectionOverlay: View {
    
    let detections: [Detection]
    let gaitPipeline: GaitPipeline
    
    var body: some View {
        GeometryReader { geometry in
            
            // 被大框包含且距离相似的小框，视觉上降低透明度
            let suppressed = Detection.suppressedIDs(in: detections)
            
            ForEach(detections) { detection in
                
                let rect = convertRect(detection.boundingBox, in: geometry.size)
                let color = Theme.distanceColor(for: detection.distance)
                let isClose = (detection.distance ?? 999) < 1.5
                let isSuppressed = suppressed.contains(detection.id)
                
                // 被包含的小框整体降低透明度，视觉上"退到背后"
                let dimming: Double = isSuppressed ? 0.3 : 1.0
                
                // ==========================================================
                // 检测框
                // ==========================================================
                
                // 半透明填充 + 描边
                Rectangle()
                    .fill(color.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(color, lineWidth: isClose ? 3 : 2)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(dimming)
                
                // 近距离时，框的四个角加重标记
                // 被抑制的小框不显示角标（它们已经退到背后，角标反而干扰）
                if isClose && !isSuppressed {
                    cornerMarkers(rect: rect, color: color)
                }
                
                // ==========================================================
                // 标签（固定在框的上边缘外侧）
                // ==========================================================
                
                detectionLabel(for: detection, color: color)
                    .position(x: rect.midX, y: rect.minY - 16)
                    .opacity(dimming)
            }
        }
    }
    
    // =====================================================================
    // 标签视图
    // =====================================================================
    
    @ViewBuilder
    private func detectionLabel(for detection: Detection, color: Color) -> some View {
        HStack(spacing: 6) {
            // 物体名称
            Text(detection.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            
            // 距离信息（如果有）
            if let d = detection.distance {
                // 分隔符
                Text("·")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                
                // 距离（米）
                Text("\(String(format: "%.1f", d))m")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                
                // 步数
                let steps = gaitPipeline.distanceToSteps(d)
                Text("(\(steps) steps)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.backgroundPrimary.opacity(0.85))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
    
    // =====================================================================
    // 近距离角标（四个角的加重 L 形标记）
    // =====================================================================
    
    @ViewBuilder
    private func cornerMarkers(rect: CGRect, color: Color) -> some View {
        let length: CGFloat = min(20, min(rect.width, rect.height) * 0.35)
        let thickness: CGFloat = 5
        // 向外偏移，避免与边框重叠
        let offset: CGFloat = 2
        
        // 左上角
        Path { path in
            path.move(to: CGPoint(x: rect.minX - offset, y: rect.minY - offset + length))
            path.addLine(to: CGPoint(x: rect.minX - offset, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.minX - offset + length, y: rect.minY - offset))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        // 右上角
        Path { path in
            path.move(to: CGPoint(x: rect.maxX + offset - length, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.minY - offset + length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        // 左下角
        Path { path in
            path.move(to: CGPoint(x: rect.minX - offset, y: rect.maxY + offset - length))
            path.addLine(to: CGPoint(x: rect.minX - offset, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.minX - offset + length, y: rect.maxY + offset))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        // 右下角
        Path { path in
            path.move(to: CGPoint(x: rect.maxX + offset - length, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.maxY + offset - length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
    }
    
    // =====================================================================
    // 坐标转换
    // =====================================================================
    
    private func convertRect(_ boundingBox: CGRect, in size: CGSize) -> CGRect {
        let x = boundingBox.minX * size.width
        let y = (1 - boundingBox.maxY) * size.height
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
