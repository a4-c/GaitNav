import SwiftUI

struct GaitProfilerView: View {
    
    @ObservedObject var gaitProfiler: GaitProfiler
    @Environment(\.dismiss) var dismiss
    
    @State private var speech = SpeechManager()
    
    private let minSecondsToPrompt = 10
    
    @State private var timerPulse = false
    
    @State private var hasAttempted = false
    
    private var hasBeenAttempted: Bool {
        hasAttempted
        || gaitProfiler.profiledPeakDevEma != nil
        || gaitProfiler.profilingSteps > 0
        || (gaitProfiler.profiledPeakDevEma == nil && gaitProfiler.hasEverProfiled)
    }
    
    private var isFailureState: Bool {
        !gaitProfiler.isProfiling && gaitProfiler.profiledPeakDevEma == nil && hasBeenAttempted
    }
    
    var body: some View {
        ZStack {
            
            Theme.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                dragIndicator
                    .padding(.top, 12)
                
                ScrollView {
                    VStack(spacing: 28) {
                        
                        headerSection
                        
                        if gaitProfiler.isProfiling {
                            timerVisualization
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        if gaitProfiler.profiledPeakDevEma == nil {
                            statusCard
                        }
                        
                        if gaitProfiler.profiledPeakDevEma != nil {
                            resultCard
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                
                Spacer()
                
                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: gaitProfiler.isProfiling)
        .animation(.easeInOut(duration: 0.35), value: gaitProfiler.profiledPeakDevEma != nil)
        .onChange(of: gaitProfiler.profilingSeconds) { oldValue, newValue in
            if gaitProfiler.isProfiling && oldValue < minSecondsToPrompt && newValue >= minSecondsToPrompt {
                speech.speakInterrupting("You can stop and tap the stop button now.")
            }
        }
        .onChange(of: gaitProfiler.isProfiling) { wasProfiling, isProfiling in
            guard wasProfiling && !isProfiling else { return }
            if gaitProfiler.profiledPeakDevEma != nil {
                speech.speakInterrupting("Profiling complete. Your gait pattern has been saved.")
            } else {
                speech.speakInterrupting("Profiling failed. \(gaitProfiler.statusMessage)")
            }
        }
    }
    
    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.textDisabled)
            .frame(width: 40, height: 5)
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
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
    
    private var timerVisualization: some View {
        ZStack {
            
            Circle()
                .stroke(Theme.backgroundElevated, lineWidth: 6)
                .frame(width: 180, height: 180)
            
            Circle()
                .trim(from: 0, to: min(CGFloat(gaitProfiler.profilingSeconds) / 15.0, 1.0))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: gaitProfiler.profilingSeconds)
            
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
                
                Text("\(gaitProfiler.profilingSteps) steps")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textDisabled)
                    .padding(.top, 4)
            }
        }
        .onChange(of: gaitProfiler.profilingSeconds) { _, _ in
            timerPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                timerPulse = false
            }
        }
    }
    
    @ViewBuilder
    private var statusCard: some View {
        if isFailureState {
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
            HStack(spacing: 12) {
                
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
    
    @ViewBuilder
    private var resultCard: some View {
        if let peakDev = gaitProfiler.profiledPeakDevEma {
            VStack(spacing: 10) {
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
                
                VStack(spacing: 18) {
                    resultRow(
                        value: "\(gaitProfiler.profilingSteps)",
                        unit: "",
                        label: "Steps Detected"
                    )
                    
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: 1)
                    
                    resultRow(
                        value: String(format: "%.3f", 1.0 + peakDev * 0.7),
                        unit: "g",
                        label: "Peak Threshold"
                    )
                    
                    if let interval = gaitProfiler.profiledIntervalEma {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
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
    
    private var startButtonLabel: String {
        hasBeenAttempted ? "Restart" : "Start"
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if gaitProfiler.isProfiling {
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
