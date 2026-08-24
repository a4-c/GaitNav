import SwiftUI

struct CalibrationView: View {
    
    @ObservedObject var calibrator: Calibrator
    @Environment(\.dismiss) var dismiss
    
    @State private var speech = SpeechManager()
    private let minStepsToPrompt = 10
    
    @State private var stepPulse = false
    
    @State private var hasAttempted = false
    
    private var hasBeenAttempted: Bool {
        hasAttempted
        || (calibrator.calibratedStepLength != nil && calibrator.calibrationDistance != nil)
        || calibrator.calibrationSteps > 0
        || (calibrator.calibratedStepLength == nil && calibrator.hasEverCalibrated)
    }
    
    private var isFailureState: Bool {
        !calibrator.isCalibrating && calibrator.calibratedStepLength == nil && hasBeenAttempted
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
                        
                        if calibrator.isCalibrating {
                            stepVisualization
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        if calibrator.calibratedStepLength == nil {
                            statusCard
                        }
                        
                        if calibrator.calibratedStepLength != nil {
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
        .animation(.easeInOut(duration: 0.35), value: calibrator.isCalibrating)
        .animation(.easeInOut(duration: 0.35), value: calibrator.calibratedStepLength != nil)
        .onChange(of: calibrator.calibrationSteps) { oldValue, newValue in
            if calibrator.isCalibrating && oldValue < minStepsToPrompt && newValue >= minStepsToPrompt {
                speech.speakInterrupting("You can stop and tap the stop button now.")
            }
        }
        .onChange(of: calibrator.isCalibrating) { wasCalibrating, isCalibrating in
            guard wasCalibrating && !isCalibrating else { return }
            if let stepLength = calibrator.calibratedStepLength {
                speech.speakInterrupting("Calibration complete. Step length: \(String(format: "%.2f", stepLength)) meters.")
            } else {
                speech.speakInterrupting("Calibration failed. \(calibrator.statusMessage)")
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
    
    private var stepVisualization: some View {
        ZStack {
            
            Circle()
                .stroke(Theme.backgroundElevated, lineWidth: 6)
                .frame(width: 180, height: 180)
            
            Circle()
                .trim(from: 0, to: min(CGFloat(calibrator.calibrationSteps) / 20.0, 1.0))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: calibrator.calibrationSteps)
            
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
            stepPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                stepPulse = false
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
            HStack(spacing: 12) {
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
    
    @ViewBuilder
    private var resultCard: some View {
        if let stepLength = calibrator.calibratedStepLength,
           let distance = calibrator.calibrationDistance {
            VStack(spacing: 10) {
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
            if calibrator.isCalibrating {
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
