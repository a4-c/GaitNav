import SwiftUI

// 标定页面
//
// 视觉改动：
//   - 深色背景（#121212），与主导航页面风格统一
//   - 标定进度用环形动画可视化，替代纯文字
//   - 按钮采用高对比色：Start（品牌蓝）、Stop（危险红）
//   - 结果卡片用荧光绿边框标识成功
struct CalibrationView: View {
    
    @ObservedObject var calibrator: Calibrator
    @Environment(\.dismiss) var dismiss
    
    // 控制步数跳动的动画
    @State private var stepPulse = false
    
    // 用户是否在本次打开页面后尝试过标定
    @State private var hasAttempted = false
    
    // 是否有过标定尝试（本次操作或 Calibrator 中的残留状态）
    // 成功残留：calibratedStepLength 和 calibrationDistance 同时非 nil
    // （仅 calibratedStepLength 非 nil 可能是 init 从 UserDefaults 加载的，不算尝试过）
    // 失败残留：
    //   1. calibrationSteps > 0（走了几步但不够）
    //   2. calibratedStepLength 被 startCalibration 清成了 nil，
    //      但 UserDefaults 里有历史记录（hasEverCalibrated），说明 init 加载的值被清掉了
    private var hasBeenAttempted: Bool {
        hasAttempted
        || (calibrator.calibratedStepLength != nil && calibrator.calibrationDistance != nil)
        || calibrator.calibrationSteps > 0
        || (calibrator.calibratedStepLength == nil && calibrator.hasEverCalibrated)
    }
    
    // 标定失败状态：不在标定中、没有成功结果、但尝试过
    private var isFailureState: Bool {
        !calibrator.isCalibrating && calibrator.calibratedStepLength == nil && hasBeenAttempted
    }
    
    var body: some View {
        ZStack {
            // 全屏深色背景
            Theme.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // 顶部拖拽指示条
                dragIndicator
                    .padding(.top, 12)
                
                ScrollView {
                    VStack(spacing: 28) {
                        
                        // =================================================
                        // 标题区域
                        // =================================================
                        
                        headerSection
                        
                        // =================================================
                        // 步数可视化（标定进行中）
                        // =================================================
                        
                        if calibrator.isCalibrating {
                            stepVisualization
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // =================================================
                        // 状态信息卡片（标定完成后隐藏，因为结果卡片已包含信息）
                        // =================================================
                        
                        if calibrator.calibratedStepLength == nil {
                            statusCard
                        }
                        
                        // =================================================
                        // 标定结果卡片
                        // =================================================
                        
                        if calibrator.calibratedStepLength != nil {
                            resultCard
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    // 给底部按钮留空间
                    .padding(.bottom, 120)
                }
                
                Spacer()
                
                // =================================================
                // 底部操作按钮
                // =================================================
                
                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: calibrator.isCalibrating)
        .animation(.easeInOut(duration: 0.35), value: calibrator.calibratedStepLength != nil)
    }
    
    // =====================================================================
    // 拖拽指示条
    // =====================================================================
    
    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.textDisabled)
            .frame(width: 40, height: 5)
    }
    
    // =====================================================================
    // 标题区域
    // =====================================================================
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            // 图标
            Image(systemName: "figure.walk")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Theme.accent)
            
            Text("Step Calibration")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            
            Text("Walk in a straight line so the app can measure your personal step length.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
        }
    }
    
    // =====================================================================
    // 步数可视化（大圆环 + 步数）
    // =====================================================================
    
    private var stepVisualization: some View {
        ZStack {
            // 外圈轨道
            Circle()
                .stroke(Theme.backgroundElevated, lineWidth: 6)
                .frame(width: 180, height: 180)
            
            // 进度圈（最多 20 步一圈）
            Circle()
                .trim(from: 0, to: min(CGFloat(calibrator.calibrationSteps) / 20.0, 1.0))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: calibrator.calibrationSteps)
            
            // 中间的步数
            VStack(spacing: 4) {
                Text("\(calibrator.calibrationSteps)")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .scaleEffect(stepPulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: calibrator.calibrationSteps)
                
                Text("steps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2)
            }
        }
        .onChange(of: calibrator.calibrationSteps) { _, _ in
            // 每检测到一步，触发一个微小的脉冲动画
            stepPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                stepPulse = false
            }
        }
    }
    
    // =====================================================================
    // 状态信息卡片
    // =====================================================================
    
    @ViewBuilder
    private var statusCard: some View {
        if isFailureState {
            // 失败状态：图标 + 信息居中显示，字号放大
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Theme.warning)
                
                Text(calibrator.statusMessage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Theme.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(Theme.warning.opacity(0.3), lineWidth: 1.5)
            )
        } else {
            // 初始状态 / 标定进行中：图标 + 信息左对齐
            HStack(spacing: 12) {
                // 状态图标
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(statusIconColor)
                    .frame(width: 36, height: 36)
                    .background(statusIconColor.opacity(0.12))
                    .clipShape(Circle())
                
                Text(calibrator.statusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
                
                Spacer()
            }
            .padding(16)
            .background(Theme.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
    
    // 状态图标：根据当前阶段变化
    private var statusIcon: String {
        if calibrator.isCalibrating {
            return "figure.walk"
        } else if calibrator.calibratedStepLength != nil {
            return "checkmark.circle.fill"
        } else {
            return "info.circle"
        }
    }
    
    private var statusIconColor: Color {
        if calibrator.isCalibrating {
            return Theme.accent
        } else if calibrator.calibratedStepLength != nil {
            return Theme.safe
        } else {
            return Theme.textSecondary
        }
    }
    
    // =====================================================================
    // 标定结果卡片
    // =====================================================================
    
    @ViewBuilder
    private var resultCard: some View {
        if let stepLength = calibrator.calibratedStepLength,
           let distance = calibrator.calibrationDistance {
            VStack(spacing: 10) {
                
                // ========== 卡片 1：标定完成提示（荧光绿边框） ==========
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Theme.safe)
                    Text("Calibration Complete")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.safe)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Theme.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                        .stroke(Theme.safe.opacity(0.3), lineWidth: 1.5)
                )
                
                // ========== 卡片 2：数据详情（普通边框） ==========
                VStack(spacing: 18) {
                    resultRow(
                        value: String(format: "%.1f", distance),
                        unit: "m",
                        label: "Distance"
                    )
                    
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                    
                    resultRow(
                        value: "\(calibrator.calibrationSteps)",
                        unit: "",
                        label: "Steps"
                    )
                    
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                    
                    resultRow(
                        value: String(format: "%.2f", stepLength),
                        unit: "m",
                        label: "Step Length"
                    )
                }
                .padding(20)
                .background(Theme.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }
    
    // 结果指标：标签在上（小字），数值在下（大字），居中
    private func resultRow(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textDisabled)
                .textCase(.uppercase)
                .tracking(1.5)
            
            HStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // =====================================================================
    // 底部操作按钮
    // =====================================================================
    
    // 按钮文案逻辑：
    //   首次进入页面、尚未尝试标定 → "Start"
    //   尝试过标定（无论成功或失败）→ "Restart"
    private var startButtonLabel: String {
        hasBeenAttempted ? "Restart" : "Start"
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if calibrator.isCalibrating {
                // 正在标定 → 红色 Stop 按钮
                Button(action: { calibrator.stopCalibration() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                        Text("Stop")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.danger)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge))
                }
            } else {
                // 未在标定 → 蓝色 Start / Restart 按钮
                Button(action: {
                    hasAttempted = true
                    calibrator.startCalibration()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: hasBeenAttempted ? "arrow.counterclockwise" : "play.fill")
                            .font(.system(size: 14))
                        Text(startButtonLabel)
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge))
                }
                
                // 尝试过标定后显示 Done 按钮（无论成功或失败）
                if hasBeenAttempted {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.backgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}
