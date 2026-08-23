import Foundation

// steps = step-synchronised countdown (experimental), meters = threshold-based (control)
enum FeedbackDistanceMode: String, CaseIterable, Identifiable {
    
    case steps
    case meters
    
    private static let storageKey = "feedbackDistanceMode"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .steps:
            return "Steps"
        case .meters:
            return "Meters"
        }
    }
    
    // load from UserDefaults, defaults to .steps
    static var saved: FeedbackDistanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let mode = FeedbackDistanceMode(rawValue: rawValue) else {
            return .steps
        }
        return mode
    }
    
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}
