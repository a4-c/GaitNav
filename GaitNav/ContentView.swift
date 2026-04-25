import SwiftUI

struct ContentView: View {
    
    // @StateObject 告诉 SwiftUI：我拥有这个对象，帮我管理它的生命周期
    // 当 CameraManager 被创建时，构造函数会自动启动摄像头
    @StateObject private var camera = CameraManager()
    
    // 标定器：管理步长标定流程和步数换算
    @StateObject private var calibrator = Calibrator()
    
    // 控制是否显示标定页面
    // true = 弹出标定页面（以 sheet 的形式从底部滑上来）
    // false = 隐藏标定页面
    @State private var showCalibration = false
    
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
            DetectionOverlay(detections: camera.detections, calibrator: calibrator)
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
                        // 按钮上显示当前有效步长
                        // effectiveStepLength 会自动返回标定值或默认值
                        // 用户一眼就能看到当前用的是什么步长
                        // 如果觉得不准，点击就能重新标定
                        Text("Step: \(String(format: "%.2f", calibrator.effectiveStepLength))m")
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
        // 把 CameraManager 的 ARSession 传给 Calibrator
        // 标定流程需要用 ARSession 来读取手机的 3D 空间位置
        // Calibrator 不自己创建 ARSession，因为一个 app 只能有一个
        .onAppear {
            calibrator.arSession = camera.session
        }
        // .sheet：模态页面
        // isPresented 绑定到 showCalibration：
        //   showCalibration 变为 true → CalibrationView 从底部滑上来
        //   用户下滑关闭或点 Done → showCalibration 自动变回 false
        // $showCalibration 前面的 $ 是"绑定"语法：
        //   普通变量是只读的（单向：数据 → 界面）
        //   $变量 是双向绑定（数据 ↔ 界面），sheet 关闭时能把值改回 false
        .sheet(isPresented: $showCalibration) {
            CalibrationView(calibrator: calibrator)
        }
    }
}

#Preview {
    ContentView()
}
