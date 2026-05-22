import SwiftUI

// 统一视觉主题
//
// 设计规范：
//   WCAG 2.1 AA 级别高对比度（文字与背景对比度 ≥ 4.5:1）
//   深色模式为默认模式，减少强光对低视力用户的刺激
//   三色信号系统：红/橙（危险）、绿（安全）、白（信息）
//
// 使用方式：
//   Text("Hello").foregroundColor(Theme.textPrimary)
//   view.background(Theme.backgroundPrimary)

enum Theme {
    
    // =====================================================================
    // 背景层次
    // =====================================================================
    
    // 最底层背景（#121212），用于页面底色
    static let backgroundPrimary = Color(hex: 0x121212)
    
    // 卡片/面板背景（#1E1E1E），比底色略亮，创造层次感
    static let backgroundCard = Color(hex: 0x1E1E1E)
    
    // 输入框/控件背景（#2A2A2A），交互元素的容器
    static let backgroundElevated = Color(hex: 0x2A2A2A)
    
    // =====================================================================
    // 信号色
    // =====================================================================
    
    // 危险/障碍物警示（#FF4500），近距离障碍物的视觉震慑
    static let danger = Color(hex: 0xFF4500)
    
    // 危险色半透明版本，用于背景填充
    static let dangerSubtle = Color(hex: 0xFF4500).opacity(0.15)
    
    // 安全/成功（#00FF00），路径安全或校准完成
    static let safe = Color(hex: 0x00FF00)
    
    // 安全色半透明版本
    static let safeSubtle = Color(hex: 0x00FF00).opacity(0.12)
    
    // 警告/中等距离（#FFB800），介于安全和危险之间
    static let warning = Color(hex: 0xFFB800)
    
    // 品牌强调色（#4A9EFF），用于主要按钮和交互高亮
    static let accent = Color(hex: 0x4A9EFF)
    
    // =====================================================================
    // 文字层次
    // =====================================================================
    
    // 核心信息文字（纯白），步数、方向等关键数据
    static let textPrimary = Color.white
    
    // 次要说明文字（#B0B0B0），辅助描述
    static let textSecondary = Color(hex: 0xB0B0B0)
    
    // 禁用/占位文字（#666666）
    static let textDisabled = Color(hex: 0x666666)
    
    // =====================================================================
    // 边框与分隔
    // =====================================================================
    
    // 卡片边框
    static let border = Color.white.opacity(0.08)
    
    // 分隔线
    static let divider = Color.white.opacity(0.06)
    
    // =====================================================================
    // 检测框颜色（根据距离动态变化）
    // =====================================================================
    
    // 根据距离返回对应的信号色
    // distance: 物体到相机的距离（米）
    // Returns: 危险红 / 警告黄 / 安全绿
    static func distanceColor(for distance: Float?) -> Color {
        guard let d = distance else { return safe }
        if d < 1.5 { return danger }
        if d < 3.5 { return warning }
        return safe
    }
    
    // 根据距离返回对应的信号色（低透明度版本，用于背景）
    static func distanceColorSubtle(for distance: Float?) -> Color {
        guard let d = distance else { return safeSubtle }
        if d < 1.5 { return dangerSubtle }
        if d < 3.5 { return warning.opacity(0.12) }
        return safeSubtle
    }
    
    // =====================================================================
    // 圆角 & 间距规范
    // =====================================================================
    
    // 大圆角（按钮、卡片）
    static let cornerRadiusLarge: CGFloat = 16
    
    // 中圆角（标签、输入框）
    static let cornerRadiusMedium: CGFloat = 12
    
    // 小圆角（徽章、小标签）
    static let cornerRadiusSmall: CGFloat = 8
}

// =====================================================================
// Color 扩展：支持十六进制颜色值
// =====================================================================

extension Color {
    
    // 用十六进制整数创建颜色
    // 示例：Color(hex: 0xFF4500)
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
