import SwiftUI

// main screen: camera preview + detection overlay + feedback controls
struct ContentView: View {
    
    @StateObject private var perceptionPipeline = PerceptionPipeline()
    @StateObject private var gaitCoordinator = GaitCoordinator()
    
    @State private var showCalibration = false
    @State private var showGaitProfiler = false
    @State private var showSettings = false
    @State private var feedbackDistanceMode = FeedbackDistanceMode.saved
    @State private var isCameraReady = false
    @State private var isNavigationStarted = false
    @State private var isFeedbackActive = false
    @State private var isPaused = false
    
    private let speech = SpeechManager()
    @State private var feedbackEngine: FeedbackEngine? = nil
    
    var body: some View {
        ZStack {
            
            CameraPreview(session: perceptionPipeline.session)
                .ignoresSafeArea()
            
            DetectionOverlay(detections: perceptionPipeline.detections, stepDistanceConverter: gaitCoordinator)
                .ignoresSafeArea()
            
            if isNavigationStarted && !isPaused {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        bottomPanel(bottomInset: geo.safeAreaInsets.bottom)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .transition(.opacity)
                
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
            
            gaitCoordinator.setARSession(perceptionPipeline.session)
            gaitCoordinator.start()
            
            let engine = FeedbackEngine(
                speech: speech,
                stepDistanceConverter: gaitCoordinator,
                distanceMode: feedbackDistanceMode,
                visualCountdownFallbackDelayProvider: { gaitCoordinator.visualCountdownFallbackDelay }
            )
            feedbackEngine = engine
            
            gaitCoordinator.onStepDetected = { [self] in
                guard !showCalibration, !showGaitProfiler, !showSettings, isFeedbackActive else { return }
                engine.handleStep(with: perceptionPipeline.detections)
            }
        }
        .onDisappear {
            gaitCoordinator.stop()
            speech.stop()
        }
        .onReceive(perceptionPipeline.$fps) { fps in
            if fps > 0 && !isCameraReady {
                withAnimation(.easeOut(duration: 0.5)) {
                    isCameraReady = true
                }
                speech.speakInterrupting("Ready. Point your camera and tap Start.")
            }
        }
        .onReceive(perceptionPipeline.$detections) { detections in
            guard isFeedbackActive, !showCalibration, !showGaitProfiler, !showSettings else { return }
            feedbackEngine?.update(with: detections)
        }
        .onChange(of: feedbackDistanceMode) { oldMode, newMode in
            newMode.save()
            feedbackEngine?.distanceMode = newMode
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(calibrator: gaitCoordinator.calibrator)
                .onAppear {
                    speech.stop()
                }
        }
        .sheet(isPresented: $showGaitProfiler) {
            GaitProfilerView(gaitProfiler: gaitCoordinator.gaitProfiler)
                .onAppear {
                    speech.stop()
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                feedbackDistanceMode: $feedbackDistanceMode,
                gaitCoordinator: gaitCoordinator,
                onCalibrateRequested: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showCalibration = true
                    }
                },
                onProfileRequested: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showGaitProfiler = true
                    }
                }
            )
            .onAppear {
                speech.stop()
            }
        }
        .overlay {
            if !isCameraReady {
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
                startOverlay
                    .transition(.opacity)
            } else if isPaused {
                pauseOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
    }
    
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
            
            settingsButton
                .hidden()
                .padding(.top, 16)
        }
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }
    
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
    
    private var topBar: some View {
        HStack(spacing: 12) {
            
            hudCapsule {
                HStack(spacing: 6) {
                    if gaitCoordinator.isDynamicActive {
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
    
    private func bottomPanel(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            
            HStack(spacing: 6) {
                Image(systemName: feedbackDistanceMode == .steps ? "figure.walk" : "ruler")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text("\(feedbackDistanceMode.label) Mode")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            
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
    
    private var stepLengthLabel: String {
        let value = String(format: "%.2f", gaitCoordinator.effectiveStepLength)
        return "\(value) m/step"
    }
}

#Preview {
    ContentView()
}
