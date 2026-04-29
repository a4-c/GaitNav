import SwiftUI

struct ContentView: View {
    
    // @StateObject 告诉 SwiftUI：我拥有这个对象，帮我管理它的生命周期
    // 当 CameraManager 被创建时，构造函数会自动启动摄像头
    @StateObject private var camera = CameraManager()
    
    // 步长转换器：协调标定、动态步长检测和距离 → 步数转换
    // StepConverter 内部持有 Calibrator 和 DynamicStepEstimator
    @StateObject private var stepConverter = StepConverter()
    
    // 控制是否显示标定页面
    // true = 弹出标定页面（以 sheet 的形式从底部滑上来）
    // false = 隐藏标定页面
    @State private var showCalibration = false
    
    // 语音播报引擎
    private let speech = SpeechManager()
    
    // 语音反馈管理器
    // 延迟初始化（在 .onAppear 里设置），因为它依赖 stepConverter
    @State private var feedbackManager: FeedbackManager? = nil
    
    // body 是 SwiftUI 要求的属性，定义这个页面长什么样
    var body: some View {
        // ZStack 是层叠布局，里面的元素从下往上叠放
        // 第一个元素在最底层，最后一个在最上层
        ZStack {
            // 底层：ARKit全屏摄像头画面
            CameraPreview(session: camera.session)
                // 忽略安全区域，让画面延伸到刘海和底部
                .ignoresSafeArea()
            
            // 中层：检测框叠加层
            // camera.detections 变化时，这个视图会自动重绘
            DetectionOverlay(detections: camera.detections, stepConverter: stepConverter)
                .ignoresSafeArea()
            
            // 上层：UI控件
            // VStack 是垂直排列布局
            VStack {
                
                // 右上角：标定入口按钮
                // HStack 是水平排列，Spacer 把按钮推到最右边
                HStack {
                    Spacer()
                    Button(action: {
                        // 点击后把 showCalibration 设为 true
                        // .sheet 修饰符会捕捉到这个变化，弹出标定页面
                        showCalibration = true
                    }) {
                        // 按钮上显示当前有效步长 + 来源标记
                        // effectiveStepLength 会自动返回动态值、标定值或默认值
                        // 用户一眼就能看到当前用的是什么步长
                        // 如果觉得不准，点击就能重新标定
                        Text("\(stepLengthLabel)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6))
                            // 做成胶囊形状（圆角足够大就变成椭圆）
                            .cornerRadius(20)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                
                // 弹性空间，把下面的内容推到底部
                Spacer()
                
                Text("\(camera.detections.count) objects detected. \(String(format: "%.1f", camera.fps)) FPS")
                    // 标题字体
                    .font(.headline)
                    // 白色文字
                    .foregroundColor(.white)
                    // 四周加内边距
                    .padding()
                    // 半透明黑色背景
                    .background(.black.opacity(0.6))
                    // 圆角
                    .cornerRadius(10)
                    // 距离底部 40 点
                    .padding(.bottom, 40)
            }
        }
        // .onAppear：页面第一次出现时执行
        .onAppear {
            // 把 ARSession 传给 StepConverter
            // StepConverter 会自动转发给 Calibrator 和 DynamicStepEstimator
            stepConverter.setARSession(camera.session)
            // 启动动态步长检测
            // 加速度计从这里开始持续采集
            // 用户走路时会自动实时计算步长
            stepConverter.start()
            
            // 初始化语音反馈管理器
            let fm = FeedbackManager(speech: speech, stepConverter: stepConverter)
            feedbackManager = fm
            
            // 把步伐事件连接到语音反馈
            // 用户每走一步，StepConverter 检测到后通知 FeedbackManager
            // FeedbackManager 据此决定是否播报倒数数字
            // 这是语音倒数的"主路"：confirmed step 优先于画面帧刷新。
            stepConverter.onStepDetected = {
                fm.handleStep(with: camera.detections)
            }
        }
        // .onDisappear：页面消失时执行
        // 停止加速度计和语音播报，避免 app 在后台时白费电
        .onDisappear {
            stepConverter.stop()
            speech.stop()
        }
        // .onReceive：每次 camera.detections 发布新结果时触发
        // 这是语音反馈的驱动点：感知管线每处理完一帧，就把最新检测结果传给 FeedbackManager
        // FeedbackManager 内部判断是否需要播报（新物体、步数变化、危险距离等）
        // 这条路主要负责刷新实时步数；只有步伐漏检时，才会兜底推进倒数。
        .onReceive(camera.$detections) { detections in
            feedbackManager?.update(with: detections)
        }
        // .sheet：模态页面
        // isPresented 绑定到 showCalibration：
        //   showCalibration 变为 true → CalibrationView 从底部滑上来
        //   用户下滑关闭或点 Done → showCalibration 自动变回 false
        // $showCalibration 前面的 $ 是"绑定"语法：
        //   普通变量是只读的（单向：数据 → 界面）
        //   $变量 是双向绑定（数据 ↔ 界面），sheet 关闭时能把值改回 false
        .sheet(isPresented: $showCalibration) {
            // CalibrationView 直接观察 StepConverter 内部的 Calibrator
            CalibrationView(calibrator: stepConverter.calibrator)
        }
    }
    
    // 步长来源标签
    // 帮助用户理解当前步长数据是怎么来的：
    //   ⚡ 0.65m/step → 动态步长（实时检测中，用户正在走路）
    //   Step: 0.65m → 静态步长（标定值或默认值，用户静止）
    private var stepLengthLabel: String {
        let value = String(format: "%.2f", stepConverter.effectiveStepLength)
        
        // 动态步长有效时显示 ⚡ 标记（表示实时检测中）
        if stepConverter.isDynamicActive {
            return "⚡ \(value)m/step"
        }
        // 否则显示静态步长
        return "Step: \(value)m"
    }
}

#Preview {
    ContentView()
}
