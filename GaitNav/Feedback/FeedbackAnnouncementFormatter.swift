import Foundation
import CoreGraphics

struct FeedbackAnnouncementFormatter {
    
    // =====================================================================
    // 方位计算
    // =====================================================================

    // 把物体在画面中的水平位置转换成时钟方位
    //
    // 映射关系：
    //   iPhone 竖屏时水平视野（FOV）大约 60°
    //   时钟上每小时 = 30°，所以 60° = 中心两侧各 1 小时
    //   覆盖范围：11 点钟 ~ 1 点钟，正好三个位置
    //
    //   归一化 x 坐标：
    //     0.0 ──── 0.25 ──────── 0.75 ──── 1.0
    //         11点      12点（正前方）    1点
    func clockDirection(from boundingBox: CGRect) -> String {
        let centerX = boundingBox.midX
        let hour: Int
        if centerX < 0.25 {
            hour = 11
        } else if centerX < 0.75 {
            hour = 12
        } else {
            hour = 1
        }
        return "\(hour) o'clock"
    }
    
    // =====================================================================
    // 播报文案生成
    // =====================================================================

    // 完整播报：物体名 + 方位 + 步数
    // 用于首次发现物体时，建立用户的空间映射
    // 示例："chair, 12 o'clock, 7 steps"
    func fullText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "\(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate, mode: mode))"
    }
    
    // 简短播报：物体名 + 步数（省略方位）
    // 用于步数阈值更新，用户已经知道方位了，只需要更新距离
    // 示例："chair, 3 steps"
    func briefText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "\(candidate.detection.label), \(formatDistance(candidate, mode: mode))"
    }
    
    // 紧急播报：warning + 物体名 + 方位 + 步数
    // 用于物体进入 1 步危险范围，或突然出现的近距离威胁
    // 示例："warning, chair, 12 o'clock, 1 step"
    func urgentText(for candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        "warning, \(candidate.detection.label), \(candidate.direction), \(formatDistance(candidate, mode: mode))"
    }
    
    // 修正播报：动态步长发生明显变化时使用
    // 示例："about 8 steps"
    func correctionText(steps: Int) -> String {
        let stepWord = steps == 1 ? "step" : "steps"
        return "about \(steps) \(stepWord)"
    }
    
    // =====================================================================
    // 距离格式化（根据当前模式返回步数或米数文本）
    // =====================================================================
    
    // 统一的距离文本生成器
    // 步数模式 → "7 steps"、"1 step"
    // 米数模式 → "3 meters"、"1.5 meters"、"1 meter"
    private func formatDistance(_ candidate: FeedbackCandidate, mode: FeedbackDistanceMode) -> String {
        switch mode {
        case .steps:
            let stepWord = candidate.steps == 1 ? "step" : "steps"
            return "\(candidate.steps) \(stepWord)"
        case .meters:
            let rounded = (candidate.distance * 10).rounded() / 10
            let meterWord = rounded == 1.0 ? "meter" : "meters"
            return "\(String(format: "%.1f", rounded)) \(meterWord)"
        }
    }
}
