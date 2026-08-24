import SwiftUI

// draws bounding boxes + labels on top of camera view
// box color changes with distance: green (far) -> yellow (mid) -> red (close)
struct DetectionOverlay: View {
    
    let detections: [Detection]
    let stepDistanceConverter: StepDistanceConverting
    
    var body: some View {
        GeometryReader { geometry in
            
            let suppressed = Detection.suppressedIDs(in: detections)
            
            ForEach(detections) { detection in
                
                let rect = convertRect(detection.boundingBox, in: geometry.size)
                let color = Theme.distanceColor(for: detection.distance)
                let isClose = (detection.distance ?? 999) < 1.5
                let isSuppressed = suppressed.contains(detection.id)
                let dimming: Double = isSuppressed ? 0.3 : 1.0
                
                Rectangle()
                    .fill(color.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(color, lineWidth: isClose ? 3 : 2)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(dimming)
                
                if isClose && !isSuppressed {
                    cornerMarkers(rect: rect, color: color)
                }
                
                detectionLabel(for: detection, color: color)
                    .position(x: rect.midX, y: rect.minY - 16)
                    .opacity(dimming)
            }
        }
    }
    
    @ViewBuilder
    private func detectionLabel(for detection: Detection, color: Color) -> some View {
        HStack(spacing: 6) {
            
            Text(detection.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            
            if let d = detection.distance {
                Text("·")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                
                Text("\(String(format: "%.1f", d))m")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                
                let steps = stepDistanceConverter.distanceToSteps(d)
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
    
    @ViewBuilder
    private func cornerMarkers(rect: CGRect, color: Color) -> some View {
        let length: CGFloat = min(20, min(rect.width, rect.height) * 0.35)
        let thickness: CGFloat = 5
        let offset: CGFloat = 2
        
        Path { path in
            path.move(to: CGPoint(x: rect.minX - offset, y: rect.minY - offset + length))
            path.addLine(to: CGPoint(x: rect.minX - offset, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.minX - offset + length, y: rect.minY - offset))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        Path { path in
            path.move(to: CGPoint(x: rect.maxX + offset - length, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.minY - offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.minY - offset + length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        Path { path in
            path.move(to: CGPoint(x: rect.minX - offset, y: rect.maxY + offset - length))
            path.addLine(to: CGPoint(x: rect.minX - offset, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.minX - offset + length, y: rect.maxY + offset))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        
        Path { path in
            path.move(to: CGPoint(x: rect.maxX + offset - length, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.maxY + offset))
            path.addLine(to: CGPoint(x: rect.maxX + offset, y: rect.maxY + offset - length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
    }
    
    // Vision normalised coords (origin bottom-left) -> screen coords (origin top-left)
    private func convertRect(_ boundingBox: CGRect, in size: CGSize) -> CGRect {
        let x = boundingBox.minX * size.width
        let y = (1 - boundingBox.maxY) * size.height
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
