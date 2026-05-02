import SwiftUI

struct ContentView: View {
    
    @StateObject private var camera = CameraManager()
    @StateObject private var stepConverter = StepConverter()
    
    @State private var showCalibration = false
    @State private var showSettings = false
    @State private var feedbackDistanceMode = FeedbackDistanceMode.saved
    @State private var isCameraReady = false
    
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
            
            GeometryReader { geo in
                VStack(spacing: 0) {
                    
                    // ---------------------------------------------------------
                    // 顶部工具栏
                    // ---------------------------------------------------------
                    topBar
                    
                    Spacer()
                    
                    // ---------------------------------------------------------
                    // 底部状态面板
                    // ---------------------------------------------------------
                    bottomPanel(bottomInset: geo.safeAreaInsets.bottom)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear {
            // 播报"准备中"
            speech.speak("Preparing")
            
            // camera.start() 现在是非阻塞的：
            //   - AR 会话立刻启动（快）
            //   - ML 检测模型在后台线程加载（慢，但不阻塞主线程）
            //   - 加载完成前，帧数据会被跳过
            //   - 加载完成后，自动开始检测，FPS > 0，加载页面消失
            camera.start()
            
            stepConverter.setARSession(camera.session)
            stepConverter.start()
            
            let fm = FeedbackManager(speech: speech, stepConverter: stepConverter, distanceMode: feedbackDistanceMode)
            feedbackManager = fm
            
            stepConverter.onStepDetected = { [self] in
                guard !showCalibration else { return }
                fm.handleStep(with: camera.detections)
            }
        }
        .onDisappear {
            stepConverter.stop()
            speech.stop()
        }
        .onReceive(camera.$fps) { fps in
            // 当 fps > 0 说明摄像头已经开始出帧，撤掉加载动画
            if fps > 0 && !isCameraReady {
                withAnimation(.easeOut(duration: 0.5)) {
                    isCameraReady = true
                }
            }
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
        // 加载动画覆盖层
        .overlay {
            if !isCameraReady {
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Preparing ...")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .transition(.opacity)
            }
        }
        // 强制深色模式
        .preferredColorScheme(.dark)
    }
    
    // =====================================================================
    // 顶部工具栏
    // =====================================================================
    
    private var topBar: some View {
        HStack(spacing: 12) {
            
            // 步长指示器（仅展示，通过设置页标定）
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
            
            Spacer()
            
            // 设置按钮
            Button(action: { showSettings = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // =====================================================================
    // 底部状态面板
    // =====================================================================
    
    private func bottomPanel(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            
            // 当前反馈模式指示
            HStack(spacing: 6) {
                Image(systemName: feedbackDistanceMode == .steps ? "figure.walk" : "ruler")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text("\(feedbackDistanceMode.label) Mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            
            // 状态信息栏
            HStack(spacing: 16) {
                // 检测数量
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.safe)
                    Text("\(camera.detections.count)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
                
                // 分隔点
                Circle()
                    .fill(Theme.textDisabled)
                    .frame(width: 3, height: 3)
                
                // FPS
                Text("\(String(format: "%.0f", camera.fps)) FPS")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
        .padding(.bottom, max(bottomInset, 16))
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
        return "\(value) m/step"
    }
}

#Preview {
    ContentView()
}
