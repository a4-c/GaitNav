import SwiftUI
// [实验] UIPasteboard 用于复制 CSV 到剪贴板，实验结束后删除
import UIKit

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
    
    // [实验] 当前检测列表，距离日志实验用，实验结束后删除
    var detections: [Detection]
    
    // [实验] CSV 复制成功的提示状态，实验结束后删除
    @State private var showCopiedConfirmation = false
    
    // [实验] 距离日志的提示状态，实验结束后删除
    @State private var showDistanceCopiedConfirmation = false
    @State private var showNoDetectionWarning = false
    
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
                        
                        // =================================================
                        // [实验] 波峰日志调试区（实验结束后删除整个 section）
                        // =================================================
                        
                        settingsSection(title: "Peak Logging (Debug)") {
                            VStack(spacing: 14) {
                                // 状态指示：录制中 / 空闲 + 已记录波峰数
                                HStack {
                                    Circle()
                                        .fill(stepConverter.isLoggingPeaks ? Theme.danger : Theme.textDisabled)
                                        .frame(width: 8, height: 8)
                                    Text(stepConverter.isLoggingPeaks ? "Recording..." : "Idle")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(stepConverter.isLoggingPeaks ? Theme.danger : Theme.textSecondary)
                                    Spacer()
                                    Text("\(stepConverter.peakLogCount) peaks")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                
                                // 复制成功提示
                                if showCopiedConfirmation {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                        Text("CSV copied to clipboard")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Theme.safe)
                                    .transition(.opacity)
                                }
                                
                                // 三个操作按钮：Start / Stop & Copy / Clear
                                HStack(spacing: 10) {
                                    // Start 按钮
                                    Button(action: {
                                        stepConverter.startPeakLogging()
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "record.circle")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Start")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(stepConverter.isLoggingPeaks ? Theme.textDisabled : Theme.safe)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(stepConverter.isLoggingPeaks ? Theme.backgroundElevated : Theme.safe.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(stepConverter.isLoggingPeaks ? Theme.border : Theme.safe.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    .disabled(stepConverter.isLoggingPeaks)
                                    
                                    // Stop & Copy 按钮
                                    Button(action: {
                                        let csv = stepConverter.stopPeakLoggingAndExportCSV()
                                        UIPasteboard.general.string = csv
                                        // 显示复制成功提示，2 秒后自动消失
                                        withAnimation { showCopiedConfirmation = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { showCopiedConfirmation = false }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "stop.circle")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Stop & Copy")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(!stepConverter.isLoggingPeaks ? Theme.textDisabled : Theme.warning)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(!stepConverter.isLoggingPeaks ? Theme.backgroundElevated : Theme.warning.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(!stepConverter.isLoggingPeaks ? Theme.border : Theme.warning.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    .disabled(!stepConverter.isLoggingPeaks)
                                    
                                    // Clear 按钮
                                    Button(action: {
                                        stepConverter.clearPeakLog()
                                        showCopiedConfirmation = false
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Clear")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(stepConverter.peakLogCount == 0 ? Theme.textDisabled : Theme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Theme.backgroundElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(Theme.border, lineWidth: 1)
                                        )
                                    }
                                    .disabled(stepConverter.peakLogCount == 0)
                                }
                            }
                        }
                        
                        // =================================================
                        // [实验] 距离日志调试区（实验结束后删除整个 section）
                        // =================================================
                        
                        settingsSection(title: "Distance Logging (Debug)") {
                            VStack(spacing: 14) {
                                // 已记录条数
                                HStack {
                                    Image(systemName: "list.bullet.clipboard")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textSecondary)
                                    Text("\(stepConverter.distanceLogCount) entries logged")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    // 实时显示当前最近物体的距离，方便确认读数稳定
                                    if let nearest = detections
                                        .filter({ $0.distance != nil })
                                        .min(by: { $0.distance! < $1.distance! }),
                                       let dist = nearest.distance {
                                        Text("\(nearest.label) \(String(format: "%.2f", dist))m")
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(Theme.accent)
                                    } else {
                                        Text("No detection")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.textDisabled)
                                    }
                                }
                                
                                // 提示信息（复制成功 / 无检测物体）
                                if showDistanceCopiedConfirmation {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                        Text("CSV copied to clipboard")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Theme.safe)
                                    .transition(.opacity)
                                }
                                if showNoDetectionWarning {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 12))
                                        Text("No object detected — point camera at target")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Theme.warning)
                                    .transition(.opacity)
                                }
                                
                                // 三个操作按钮：Log Distance / Copy CSV / Clear
                                HStack(spacing: 10) {
                                    // Log Distance 按钮
                                    Button(action: {
                                        showNoDetectionWarning = false
                                        let success = stepConverter.logDistance(from: detections)
                                        if !success {
                                            // 没有检测到任何有距离信息的物体
                                            withAnimation { showNoDetectionWarning = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                withAnimation { showNoDetectionWarning = false }
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Log")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(Theme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Theme.accent.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    
                                    // Copy CSV 按钮
                                    Button(action: {
                                        let csv = stepConverter.exportDistanceLogCSV()
                                        UIPasteboard.general.string = csv
                                        withAnimation { showDistanceCopiedConfirmation = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation { showDistanceCopiedConfirmation = false }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Copy CSV")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(stepConverter.distanceLogCount == 0 ? Theme.textDisabled : Theme.warning)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(stepConverter.distanceLogCount == 0 ? Theme.backgroundElevated : Theme.warning.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(stepConverter.distanceLogCount == 0 ? Theme.border : Theme.warning.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    .disabled(stepConverter.distanceLogCount == 0)
                                    
                                    // Clear 按钮
                                    Button(action: {
                                        stepConverter.clearDistanceLog()
                                        showDistanceCopiedConfirmation = false
                                        showNoDetectionWarning = false
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Clear")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundColor(stepConverter.distanceLogCount == 0 ? Theme.textDisabled : Theme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Theme.backgroundElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                .stroke(Theme.border, lineWidth: 1)
                                        )
                                    }
                                    .disabled(stepConverter.distanceLogCount == 0)
                                }
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
            return "Gait-synced countdown: \"5, 4, 3, 2, Stop\""
        case .meters:
            return "Distance thresholds: \"3m, 2m, 1m, Stop\""
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
