import SwiftUI
import AVFoundation
import ARKit
import RealityKit

// UIViewRepresentable 是一个协议（接口）
// 作用：把传统的 UIKit 视图包装成 SwiftUI 能用的组件
// 因为 SwiftUI 没有直接显示摄像头画面的组件，所以需要这个桥接
//struct CameraPreview: UIViewRepresentable {
//    
//    // 接收外部传入的 session，就是 CameraManager 里那个
//    let session: AVCaptureSession
//    
//    // makeUIView 是 UIViewRepresentable 要求实现的方法
//    // 系统会调用它来创建实际的视图，只调用一次
//    func makeUIView(context: Context) -> UIView {
//        
//        // 创建一个空白视图容器
//        let view = UIView(frame: .zero)
//        
//        // AVCaptureVideoPreviewLayer 是专门用来显示摄像头画面的图层
//        // 把 session 传给它，它就知道从哪里拿画面了
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        
//        // .resizeAspectFill 表示画面填满整个区域，可能会裁剪边缘
//        // 类似于图片的 "fill" 模式
//        previewLayer.videoGravity = .resizeAspectFill
//        
//        // 把预览图层添加到视图上
//        view.layer.addSublayer(previewLayer)
//        
//        // 异步设置图层大小，等视图布局完成后再匹配尺寸
//        DispatchQueue.main.async {
//            previewLayer.frame = view.bounds
//        }
//        
//        // 返回这个视图给 SwiftUI 显示
//        return view
//    }
//    
//    // updateUIView 在 SwiftUI 状态更新时被调用
//    // 这里我们重新设置图层尺寸，确保旋转屏幕后画面大小正确
//    func updateUIView(_ uiView: UIView, context: Context) {
//        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
//            layer.frame = uiView.bounds
//        }
//    }
//}

// UIViewRepresentable 是一个协议（接口）
// 作用：把传统的 UIKit 视图包装成 SwiftUI 能用的组件
// 因为 SwiftUI 没有直接显示摄像头画面的组件，所以需要这个桥接
// 从 AVCaptureSession 切换到 ARSession
// ARSCNView 是 ARKit 自带的视图，自动处理摄像头画面显示和方向
struct CameraPreview: UIViewRepresentable {
    
    // 之前这里是 AVCaptureSession，现在换成 ARSession
    // ARSession 是 ARKit 的核心控制器
    // 它同时管理：摄像头画面 + LiDAR 深度数据 + 设备位姿追踪
    // 相当于一个升级版的 AVCaptureSession，功能更多
    let session: ARSession

    // makeUIView 是 UIViewRepresentable 要求实现的方法
    // 系统会调用它来创建实际的视图，只调用一次
    func makeUIView(context: Context) -> ARView {
        
        // ARView 是 RealityKit 提供的专用视图
        // 它自动把摄像头画面显示出来，不需要手动处理预览层
        // 之前用 AVCaptureVideoPreviewLayer 手动搞了很多旋转方向的问题
        // ARView 全部自动处理，省掉了那些麻烦
        let view = ARView(frame: .zero)
        
        // 把我们的 ARSession 绑定到这个视图上
        // 视图就知道从哪里拿画面数据了
        view.session = session
        
        return view
    }

    // 视图更新时调用，我们这里不需要做任何事
    // ARSCNView 自己会自动跟着 ARSession 更新画面
    func updateUIView(_ uiView: ARView, context: Context) {}
}
