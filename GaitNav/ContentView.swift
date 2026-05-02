import SwiftUI

struct ContentView: View {
    
    @StateObject private var camera = CameraManager()
    @StateObject private var stepConverter = StepConverter()
    
    @State private var showCalibration = false
    @State private var showSettings = false
    @State private var feedbackDistanceMode = FeedbackDistanceMode.saved
    
    private let speech = SpeechManager()
    @State private var feedbackManager: FeedbackManager? = nil
    
    var body: some View {
        ZStack {
            
            // =============================================================
            // 底层：AR 摄像头画面
            // =============================================================
            
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            
            // =============================================================
            // 中层：检测框叠加层（使用新的主题色系）
            // =============================================================
            
            DetectionOverlay(detections: camera.detections, stepConverter: stepConverter)
                .ignoresSafeArea()
            
            // =============================================================
            // 上层：导航 HUD
            // =============================================================
            
            VStack(spacing: 0) {
                
                // ---------------------------------------------------------
                // 顶部工具栏
                // ---------------------------------------------------------
                topBar
                
                Spacer()
                
                // ---------------------------------------------------------
                // 底部状态面板
                // ---------------------------------------------------------
                bottomPanel
            }
        }
        .onAppear {
            stepConverter.setARSession(camera.session)
            stepConverter.start()
            
            let fm = FeedbackManager(speech: speech, stepConverter: stepConverter, distanceMode: feedbackDistanceMode)
            feedbackManager = fm
            
            stepConverter.onStepDetected = { [self] in
                // 标定页面打开期间不做语音反馈
                guard !showCalibration else { return }
                fm.handleStep(with: camera.detections)
            }
        }
        .onDisappear {
            stepConverter.stop()
            speech.stop()
        }
        .onReceive(camera.$detections) { detections in
            guard !showCalibration else { return }
            feedbackManager?.update(with: detections)
        }
        .onChange(of: feedbackDistanceMode) { oldMode, newMode in
            newMode.save()
            feedbackManager?.distanceMode = newMode
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(calibrator: stepConverter.calibrator)
                .onAppear {
                    // 标定页弹出的瞬间，打断正在播的避障语音
                    speech.stop()
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                feedbackDistanceMode: $feedbackDistanceMode,
                stepConverter: stepConverter,
                onCalibrateRequested: {
                    // 关闭设置页后打开标定页
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showCalibration = true
                    }
                }
            )
        }
        // 强制深色模式
        .preferredColorScheme(.dark)
    }
    
    // =====================================================================
    // 顶部工具栏
    // =====================================================================
    
    private var topBar: some View {
        HStack(spacing: 12) {
            
            // 步长指示器（点击进入标定）
            Button(action: { showCalibration = true }) {
                HStack(spacing: 6) {
                    // 动态步长激活时显示脉动圆点
                    if stepConverter.isDynamicActive {
                        Circle()
                            .fill(Theme.safe)
                            .frame(width: 8, height: 8)
                    }
                    
                    Text(stepLengthLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.backgroundCard.opacity(0.9))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            
            Spacer()
            
            // 设置按钮
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.backgroundCard.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // =====================================================================
    // 底部状态面板
    // =====================================================================
    
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            
            // 反馈模式切换（Steps / Meters）
            Picker("Feedback distance", selection: $feedbackDistanceMode) {
                ForEach(FeedbackDistanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            // 状态信息栏
            HStack(spacing: 16) {
                // 检测数量
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 12))
                        .foregroundColor(
                            camera.detections.isEmpty
                            ? Theme.textSecondary
                            : Theme.safe
                        )
                    Text("\(camera.detections.count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
                
                // 分隔点
                Circle()
                    .fill(Theme.textDisabled)
                    .frame(width: 3, height: 3)
                
                // FPS
                Text("\(String(format: "%.0f", camera.fps)) FPS")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            Theme.backgroundPrimary.opacity(0.85)
                .background(.ultraThinMaterial)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.cornerRadiusLarge,
                topTrailingRadius: Theme.cornerRadiusLarge
            )
        )
    }
    
    // =====================================================================
    // 步长来源标签
    // =====================================================================
    
    private var stepLengthLabel: String {
        let value = String(format: "%.2f", stepConverter.effectiveStepLength)
        if stepConverter.isDynamicActive {
            return "\(value) m/s"
        }
        return "\(value) m/s"
    }
}

#Preview {
    ContentView()
}
