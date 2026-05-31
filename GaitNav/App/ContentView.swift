import SwiftUI

struct ContentView: View {
    
    @StateObject private var perceptionPipeline = PerceptionPipeline()
    @StateObject private var gaitPipeline = GaitPipeline()
    
    @State private var showCalibration = false
    @State private var showGaitProfiler = false
    @State private var showSettings = false
    @State private var feedbackDistanceMode = FeedbackDistanceMode.saved
    @State private var isCameraReady = false
    @State private var isNavigationStarted = false
    @State private var isFeedbackActive = false
    @State private var isPaused = false
    
    private let speech = SpeechManager()
    @State private var feedbackPipeline: FeedbackPipeline? = nil
    
    var body: some View {
        ZStack {
            
            // =============================================================
            // 底层：AR 摄像头画面
            // =============================================================
            
            CameraPreview(session: perceptionPipeline.session)
                .ignoresSafeArea()
            
            // =============================================================
            // 中层：检测框叠加层
            // =============================================================
            
            DetectionOverlay(detections: perceptionPipeline.detections, gaitPipeline: gaitPipeline)
                .ignoresSafeArea()
            
            // =============================================================
            // 上层：导航 HUD（导航开始后才显示）
            // =============================================================
            
            if isNavigationStarted && !isPaused {
                // HUD 顶栏 + 底栏
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        bottomPanel(bottomInset: geo.safeAreaInsets.bottom)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
                
                // 暂停按钮 + 设置按钮
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPaused = true
                        }
                        isFeedbackActive = false
                        speech.speakInterrupting("Paused.")
                    } label: {
                        navigationActionButton(icon: "pause.fill", text: "Pause", color: Theme.danger, textColor: .white)
                    }
                    
                    settingsButton
                        .padding(.top, 16)
                }
                .padding(.bottom, 100)
                .transition(.opacity)
            }
        }
        .onAppear {
            perceptionPipeline.start()
            
            gaitPipeline.setARSession(perceptionPipeline.session)
            gaitPipeline.start()
            
            let pipeline = FeedbackPipeline(speech: speech, gaitPipeline: gaitPipeline, distanceMode: feedbackDistanceMode)
            feedbackPipeline = pipeline
            
            gaitPipeline.onStepDetected = { [self] in
                guard !showCalibration, !showGaitProfiler, !showSettings, isFeedbackActive else { return }
                pipeline.handleStep(with: perceptionPipeline.detections)
            }
        }
        .onDisappear {
            gaitPipeline.stop()
            speech.stop()
        }
        .onReceive(perceptionPipeline.$fps) { fps in
            if fps > 0 && !isCameraReady {
                withAnimation(.easeOut(duration: 0.5)) {
                    isCameraReady = true
                }
                // 摄像头就绪后播报提示
                speech.speakInterrupting("Ready. Point your camera and tap Start.")
            }
        }
        .onReceive(perceptionPipeline.$detections) { detections in
            guard isFeedbackActive, !showCalibration, !showGaitProfiler, !showSettings else { return }
            feedbackPipeline?.update(with: detections)
        }
        .onChange(of: feedbackDistanceMode) { oldMode, newMode in
            newMode.save()
            feedbackPipeline?.distanceMode = newMode
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(calibrator: gaitPipeline.calibrator)
                .onAppear {
                    speech.stop()
                }
        }
        // 步态分析页面（学习个性化波峰阈值）
        .sheet(isPresented: $showGaitProfiler) {
            GaitProfilerView(gaitProfiler: gaitPipeline.gaitProfiler)
                .onAppear {
                    speech.stop()
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                feedbackDistanceMode: $feedbackDistanceMode,
                gaitPipeline: gaitPipeline,
                onCalibrateRequested: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showCalibration = true
                    }
                },
                // 步态分析：关闭设置页后打开 GaitProfilerView
                onProfileRequested: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showGaitProfiler = true
                    }
                },
                perceptionPipeline: perceptionPipeline      // [实验] 性能日志实验用，实验结束后删除
            )
            .onAppear {
                speech.stop()
            }
        }
        // =================================================================
        // 覆盖层：加载中 → 开始按钮 → 导航界面
        // =================================================================
        .overlay {
            if !isCameraReady {
                // ── 阶段 1：加载动画 ──
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Preparing ...")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .transition(.opacity)
            } else if !isNavigationStarted {
                // ── 阶段 2：摄像头就绪，等待用户点击开始 ──
                startOverlay
                    .transition(.opacity)
            } else if isPaused {
                // ── 阶段 3：导航暂停中 ──
                pauseOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // =====================================================================
    // 开始按钮覆盖层
    // =====================================================================
    
    private var startOverlay: some View {
        VStack {
            Spacer()
            
            Text("Point your camera ahead")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 20)
            
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    isNavigationStarted = true
                }
                speech.speakInterrupting("Navigation started.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isFeedbackActive = true
                }
            } label: {
                navigationActionButton(icon: "location.fill", text: "Start")
            }
            
            // 占位：与 Pause / Resume 页的 Settings 按钮等高，保持主按钮位置一致
            settingsButton
                .hidden()
                .padding(.top, 16)
        }
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }
    
    // =====================================================================
    // 暂停覆盖层
    // =====================================================================
    
    private var pauseOverlay: some View {
        VStack {
            Spacer()
            
            Text("Navigation paused")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 20)
            
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    isPaused = false
                }
                speech.speakInterrupting("Resumed.")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isFeedbackActive = true
                }
            } label: {
                navigationActionButton(icon: "play.fill", text: "Resume")
            }
            
            settingsButton
                .padding(.top, 16)
        }
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }
    
    // =====================================================================
    // 通用导航操作按钮（Start / Pause / Resume 复用）
    // =====================================================================
    
    private func navigationActionButton(icon: String, text: String, color: Color = Theme.safe, textColor: Color = .black) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.system(size: 18, weight: .semibold))
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 40)
        .padding(.vertical, 14)
        .background(color)
        .clipShape(Capsule())
    }
    
    // =====================================================================
    // 通用设置按钮（Pause / Resume 页复用）
    // =====================================================================
    
    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .medium))
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Theme.backgroundCard.opacity(0.8))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }
    
    // =====================================================================
    // 顶部工具栏
    // =====================================================================
    
    private var topBar: some View {
        HStack(spacing: 12) {
            
            // 步长指示器（仅展示，通过设置页标定）
            hudCapsule {
                HStack(spacing: 6) {
                    if gaitPipeline.isDynamicActive {
                        Circle()
                            .fill(Theme.safe)
                            .frame(width: 8, height: 8)
                    }
                    Text(stepLengthLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
            }
            
            Spacer()
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
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.safe)
                    Text("\(perceptionPipeline.detections.count)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                }
                
                Circle()
                    .fill(Theme.textDisabled)
                    .frame(width: 3, height: 3)
                
                Text("\(String(format: "%.0f", perceptionPipeline.fps)) FPS")
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
    // 通用 HUD 胶囊样式（顶部工具栏复用）
    // =====================================================================
    
    private func hudCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.backgroundCard.opacity(0.9))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
    
    // =====================================================================
    // 步长标签
    // =====================================================================
    
    private var stepLengthLabel: String {
        let value = String(format: "%.2f", gaitPipeline.effectiveStepLength)
        return "\(value) m/step"
    }
}

#Preview {
    ContentView()
}
