import SwiftUI

struct ContentView: View {
    
    // @StateObject 告诉 SwiftUI：我拥有这个对象，帮我管理它的生命周期
    // 当 CameraManager 被创建时，构造函数会自动启动摄像头
    @StateObject private var camera = CameraManager()
    
    // body 是 SwiftUI 要求的属性，定义这个页面长什么样
    var body: some View {
        // ZStack 是层叠布局，里面的元素从下往上叠放
        // 第一个元素在最底层，最后一个在最上层
        ZStack {
            // 底层：全屏摄像头画面
            CameraPreview(session: camera.session)
                // 忽略安全区域，让画面延伸到刘海和底部
                .ignoresSafeArea()
            
            // 上层：文字标签
            // VStack 是垂直排列布局
            VStack {
                // 弹性空间，把下面的内容推到底部
                Spacer()
                Text("GaitNav Camera Preview")
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
    }
}

#Preview {
    ContentView()
}
