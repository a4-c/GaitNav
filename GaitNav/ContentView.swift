import SwiftUI

struct ContentView: View {
    
    // @StateObject 告诉 SwiftUI：我拥有这个对象，帮我管理它的生命周期
    // 当 CameraManager 被创建时，构造函数会自动启动摄像头
    @StateObject private var camera = CameraManager()
    
    @StateObject private var pedometer = PedometerManager()
    
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
            DetectionOverlay(detections: camera.detections)
                .ignoresSafeArea()
            
            // 上层：底部状态栏
            // VStack 是垂直排列布局
            VStack {
                // 弹性空间，把下面的内容推到底部
                Spacer()
                
                // 步数显示条（临时用，验证计步器是否工作）
                // 走路时这个数字应该会实时增加
                // 验证完成后，后面的 Day 会把它整合到更合适的位置
                Text("Steps: \(pedometer.stepCount)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(.blue.opacity(0.6))
                    .cornerRadius(10)
                    // 距离下面的检测信息条留一点间距
                    .padding(.bottom, 8)
                
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
        // .onAppear 是 SwiftUI 的生命周期修饰符
        // 当这个页面第一次出现在屏幕上时，里面的代码会执行一次
        //
        // 为什么不在 PedometerManager 的 init() 里自动启动？
        // 因为计步器需要用户授权，而授权弹窗应该在界面已经显示之后才弹出
        // 如果在 init() 里启动，可能界面还没加载完就弹窗，体验不好
        //
        // 和 CameraManager 不同：ARSession 在 init 里启动是因为
        // 相机权限通常在 app 首次安装时就已经授权了
        .onAppear {
            pedometer.startCounting()
        }
    }
}

#Preview {
    ContentView()
}
