import Foundation

// 反馈距离单位模式：决定了避障引导的反馈机制
//   steps: 步数模式（实验组），近距离时与用户步伐同步倒数。
//   meters: 米数模式（对照组），基于固定距离阈值的简短更新。
enum FeedbackDistanceMode: String, CaseIterable, Identifiable {
    
    case steps
    case meters
    
    // 用于持久化存储的键名，确保用户退出 App 后设置依然有效
    private static let storageKey = "feedbackDistanceMode"
    
    var id: String { rawValue }
    
    // 模式的可读标签，用于设置界面的显示
    var label: String {
        switch self {
        case .steps:
            return "Steps"
        case .meters:
            return "Meters"
        }
    }
    
    // 从 UserDefaults 中加载用户保存的反馈模式
    // 如果是首次启动或读取失败，默认返回 .steps 模式
    static var saved: FeedbackDistanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let mode = FeedbackDistanceMode(rawValue: rawValue) else {
            return .steps
        }
        return mode
    }
    
    // 将当前模式保存到本地存储中
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}
