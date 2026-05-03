import SwiftUI

// 设置页面
//
// 功能：
//   1. 反馈模式切换（Steps / Meters）
//   2. 步长信息展示 + 重新标定入口
//   3. 关于信息
//
// 以 sheet 的形式从底部滑上来，与标定页面保持一致的交互方式
struct SettingsView: View {
    
    @Binding var feedbackDistanceMode: FeedbackDistanceMode
    @ObservedObject var stepConverter: StepConverter
    @Environment(\.dismiss) var dismiss
    
    // 请求打开标定页面的回调
    var onCalibrateRequested: () -> Void
    
    var body: some View {
        ZStack {
            // 全屏深色背景
            Theme.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // 顶部拖拽指示条 + 标题
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.textDisabled)
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                    
                    HStack {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                        
                        Spacer()
                        
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(Theme.backgroundElevated)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // =================================================
                        // 第一组：反馈模式
                        // =================================================
                        
                        settingsSection(title: "Feedback Mode") {
                            VStack(spacing: 14) {
                                // 模式说明
                                Text("Choose how obstacle distances are communicated through voice feedback.")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineSpacing(2)
                                
                                // 模式选择卡片
                                ForEach(FeedbackDistanceMode.allCases) { mode in
                                    modeCard(mode: mode)
                                }
                            }
                        }
                        
                        // =================================================
                        // 第二组：步长
                        // =================================================
                        
                        settingsSection(title: "Step Length") {
                            VStack(spacing: 14) {
                                // 当前步长展示
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current Step Length")
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.textSecondary)
                                        
                                        HStack(spacing: 6) {
                                            Text(String(format: "%.2f", stepConverter.effectiveStepLength))
                                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                                .foregroundColor(Theme.textPrimary)
                                            
                                            Text("m/step")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // 来源标签
                                    stepSourceBadge
                                }
                                .padding(16)
                                .background(Theme.backgroundElevated)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                                
                                // 三级优先级说明
                                VStack(spacing: 8) {
                                    priorityRow(
                                        icon: "bolt.fill",
                                        color: Theme.safe,
                                        title: "Dynamic",
                                        desc: "Real-time measurement while walking",
                                        isActive: stepConverter.stepLengthSource == .dynamic
                                    )
                                    
                                    priorityRow(
                                        icon: "figure.walk",
                                        color: Theme.accent,
                                        title: "Calibrated",
                                        desc: stepConverter.calibrator.effectiveStepLength
                                            .map { "\(String(format: "%.2f", $0)) m/step" }
                                            ?? "Not yet calibrated",
                                        isActive: stepConverter.stepLengthSource == .calibrated
                                    )
                                    
                                    priorityRow(
                                        icon: "ruler",
                                        color: Theme.textDisabled,
                                        title: "Default",
                                        desc: "0.65 m/step (population average)",
                                        isActive: stepConverter.stepLengthSource == .defaultValue
                                    )
                                }
                                
                                // 重新标定按钮
                                Button(action: onCalibrateRequested) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 14, weight: .medium))
                                        Text(stepConverter.hasEverCalibrated
                                             ? "Recalibrate"
                                             : "Calibrate Now")
                                        .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.accent.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                                            .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        
                        // =================================================
                        // 第三组：关于
                        // =================================================
                        
                        settingsSection(title: "About") {
                            VStack(spacing: 12) {
                                aboutRow(title: "Version", value: "1.0.0")
                                Divider().background(Theme.divider)
                                aboutRow(title: "Model", value: "YOLOv8s")
                                Divider().background(Theme.divider)
                                aboutRow(title: "Depth Sensor", value: "LiDAR")
                                Divider().background(Theme.divider)
                                aboutRow(title: "Positioning", value: "ARKit 6DoF")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // =====================================================================
    // 通用分组容器
    // =====================================================================
    
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textDisabled)
                .textCase(.uppercase)
                .tracking(1.5)
            
            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(Theme.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
    
    // =====================================================================
    // 反馈模式选择卡片
    // =====================================================================
    
    private func modeCard(mode: FeedbackDistanceMode) -> some View {
        let isSelected = feedbackDistanceMode == mode
        
        return Button(action: { feedbackDistanceMode = mode }) {
            HStack(spacing: 14) {
                // 模式图标
                Image(systemName: mode == .steps ? "shoeprints.fill" : "ruler")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Theme.accent : Theme.textDisabled)
                    .frame(width: 40, height: 40)
                    .background(
                        isSelected
                        ? Theme.accent.opacity(0.12)
                        : Theme.backgroundElevated
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // 模式描述
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    
                    Text(modeDescription(mode))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textDisabled)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // 选中标记
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Theme.accent : Theme.textDisabled.opacity(0.5))
            }
            .padding(12)
            .background(
                isSelected
                ? Theme.accent.opacity(0.05)
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(
                        isSelected ? Theme.accent.opacity(0.3) : Theme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func modeDescription(_ mode: FeedbackDistanceMode) -> String {
        switch mode {
        case .steps:
            return "Gait-synced countdown: \"5, 4, 3, 2, Arrived\""
        case .meters:
            return "Distance thresholds: \"3m, 2m, 1m, Arrived\""
        }
    }
    
    // =====================================================================
    // 步长来源徽章
    // =====================================================================
    
    private var stepSourceBadge: some View {
        let (text, color): (String, Color) = {
            switch stepConverter.stepLengthSource {
            case .dynamic:      return ("Dynamic", Theme.safe)
            case .calibrated:   return ("Calibrated", Theme.accent)
            case .defaultValue: return ("Default", Theme.textDisabled)
            }
        }()
        
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    // =====================================================================
    // 三级优先级指示行
    // =====================================================================
    
    private func priorityRow(icon: String, color: Color, title: String, desc: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? color : Theme.textDisabled)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 13, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textDisabled)
                .frame(width: 72, alignment: .leading)
            
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(isActive ? Theme.textSecondary : Theme.textDisabled)
            
            Spacer()
            
            if isActive {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isActive ? color.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // =====================================================================
    // 关于信息行
    // =====================================================================
    
    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }
}
