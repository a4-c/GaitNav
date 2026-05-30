import SwiftUI

// 步态分析页面
//
// 与 CalibrationView 风格保持一致：
//   - 深色背景、卡片式布局、底部操作按钮
//   - 进度用环形动画可视化
//   - Start（品牌蓝）/ Stop（危险红）双按钮模式
//
// 与 CalibrationView 的区别：
//   - 环形进度基于时间（秒），而非步数
//   - 结果展示的是学到的步态参数，而非步长
//   - 图标使用波形（waveform），而非步行人物
struct GaitProfilerView: View {
    
    @ObservedObject var gaitProfiler: GaitProfiler
    @Environment(\.dismiss) var dismiss
    
    // 语音播报（走够时间后提示用户可以停下）
    @State private var speech = SpeechManager()
    
    // 达到此秒数时语音提示用户可以停止
    private let minSecondsToPrompt = 10
    
    // 控制秒数跳动的脉冲动画
    @State private var timerPulse = false
    
    // 用户是否在本次打开页面后尝试过分析
    @State private var hasAttempted = false
    
    // 是否有过分析尝试（本次操作或 GaitProfiler 中的残留状态）
    private var hasBeenAttempted: Bool {
        hasAttempted
        || gaitProfiler.profiledPeakDevEma != nil
        || gaitProfiler.profilingSteps > 0
        || (gaitProfiler.profiledPeakDevEma == nil && gaitProfiler.hasEverProfiled)
    }
    
    // 分析失败状态：不在分析中、没有成功结果、但尝试过
    private var isFailureState: Bool {
        !gaitProfiler.isProfiling && gaitProfiler.profiledPeakDevEma == nil && hasBeenAttempted
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
                        // 计时可视化（分析进行中）
                        // =================================================
                        
                        if gaitProfiler.isProfiling {
                            timerVisualization
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // =================================================
                        // 状态信息卡片（分析完成后隐藏，因为结果卡片已包含信息）
                        // =================================================
                        
                        if gaitProfiler.profiledPeakDevEma == nil {
                            statusCard
                        }
                        
                        // =================================================
                        // 分析结果卡片
                        // =================================================
                        
                        if gaitProfiler.profiledPeakDevEma != nil {
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
        .animation(.easeInOut(duration: 0.35), value: gaitProfiler.isProfiling)
        .animation(.easeInOut(duration: 0.35), value: gaitProfiler.profiledPeakDevEma != nil)
        .onChange(of: gaitProfiler.profilingSeconds) { oldValue, newValue in
            // 走够 10 秒后语音提示用户可以停止
            if gaitProfiler.isProfiling && oldValue < minSecondsToPrompt && newValue >= minSecondsToPrompt {
                speech.speakInterrupting("You can stop and tap the stop button now.")
            }
        }
        .onChange(of: gaitProfiler.isProfiling) { wasProfiling, isProfiling in
            // 分析刚结束（true → false）时播报结果
            guard wasProfiling && !isProfiling else { return }
            if gaitProfiler.profiledPeakDevEma != nil {
                speech.speakInterrupting("Profiling complete. Your gait pattern has been saved.")
            } else {
                speech.speakInterrupting("Profiling failed. \(gaitProfiler.statusMessage)")
            }
        }
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
            // 图标：波形代表加速度信号分析
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Theme.accent)
            
            Text("Gait Profiling")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            
            Text("Walk naturally for about 10 seconds so the app can learn your step pattern.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)
        }
    }
    
    // =====================================================================
    // 计时可视化（大圆环 + 秒数）
    // =====================================================================
    
    private var timerVisualization: some View {
        ZStack {
            // 外圈轨道
            Circle()
                .stroke(Theme.backgroundElevated, lineWidth: 6)
                .frame(width: 180, height: 180)
            
            // 进度圈（15 秒一圈）
            Circle()
                .trim(from: 0, to: min(CGFloat(gaitProfiler.profilingSeconds) / 15.0, 1.0))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: gaitProfiler.profilingSeconds)
            
            // 中间的秒数和步数
            VStack(spacing: 4) {
                Text("\(gaitProfiler.profilingSeconds)")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .scaleEffect(timerPulse ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: gaitProfiler.profilingSeconds)
                
                Text("seconds")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(2)
                
                // 已确认步数（次要信息）
                Text("\(gaitProfiler.profilingSteps) steps")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textDisabled)
                    .padding(.top, 4)
            }
        }
        .onChange(of: gaitProfiler.profilingSeconds) { _, _ in
            // 每秒触发一个微小的脉冲动画
            timerPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                timerPulse = false
            }
        }
    }
    
    // =====================================================================
    // 状态信息卡片
    // =====================================================================
    
    @ViewBuilder
    private var statusCard: some View {
        if isFailureState {
            // 失败状态：图标 + 信息居中显示
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Theme.warning)
                
                Text(gaitProfiler.statusMessage)
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
            // 初始状态 / 分析进行中：图标 + 信息左对齐
            HStack(spacing: 12) {
                // 状态图标
                Image(systemName: statusIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(statusIconColor)
                    .frame(width: 36, height: 36)
                    .background(statusIconColor.opacity(0.12))
                    .clipShape(Circle())
                
                Text(gaitProfiler.statusMessage)
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
        if gaitProfiler.isProfiling {
            return "waveform.path.ecg"
        } else if gaitProfiler.profiledPeakDevEma != nil {
            return "checkmark.circle.fill"
        } else {
            return "info.circle"
        }
    }
    
    private var statusIconColor: Color {
        if gaitProfiler.isProfiling {
            return Theme.accent
        } else if gaitProfiler.profiledPeakDevEma != nil {
            return Theme.safe
        } else {
            return Theme.textSecondary
        }
    }
    
    // =====================================================================
    // 分析结果卡片
    // =====================================================================
    
    @ViewBuilder
    private var resultCard: some View {
        if let peakDev = gaitProfiler.profiledPeakDevEma {
            VStack(spacing: 10) {
                
                // ========== 卡片 1：分析完成提示（荧光绿边框） ==========
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Theme.safe)
                    Text("Profiling Complete")
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
                
                // ========== 卡片 2：数据详情 ==========
                VStack(spacing: 18) {
                    resultRow(
                        value: "\(gaitProfiler.profilingSteps)",
                        unit: "",
                        label: "Steps Detected"
                    )
                    
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                    
                    // 将 EMA 转换为用户可理解的阈值显示
                    // TH_HIGH = 1.0 + peakDevEma × 0.7
                    resultRow(
                        value: String(format: "%.3f", 1.0 + peakDev * 0.7),
                        unit: "g",
                        label: "Peak Threshold"
                    )
                    
                    // 如果有步间隔数据
                    if let interval = gaitProfiler.profiledIntervalEma {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                        
                        // 将 EMA 转换为用户可理解的最小步间隔显示
                        // minInterval = intervalEma × 0.7
                        resultRow(
                            value: String(format: "%.2f", interval * 0.7),
                            unit: "s",
                            label: "Min Step Interval"
                        )
                    }
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
    
    // 结果指标行：标签在上（小字），数值在下（大字），居中
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
    //   首次进入页面、尚未尝试 → "Start"
    //   尝试过（无论成功或失败）→ "Restart"
    private var startButtonLabel: String {
        hasBeenAttempted ? "Restart" : "Start"
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if gaitProfiler.isProfiling {
                // 正在分析 → 红色 Stop 按钮
                Button(action: { gaitProfiler.stopProfiling() }) {
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
                // 未在分析 → 蓝色 Start / Restart 按钮
                Button(action: {
                    hasAttempted = true
                    gaitProfiler.startProfiling()
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
                
                // 尝试过后显示 Done 按钮（无论成功或失败）
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
