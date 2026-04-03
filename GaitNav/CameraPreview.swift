import SwiftUI
import AVFoundation

// UIViewRepresentable 是一个协议（接口）
// 作用：把传统的 UIKit 视图包装成 SwiftUI 能用的组件
// 因为 SwiftUI 没有直接显示摄像头画面的组件，所以需要这个桥接
struct CameraPreview: UIViewRepresentable {
    
    // 接收外部传入的 session，就是 CameraManager 里那个
    let session: AVCaptureSession
    
    // makeUIView 是 UIViewRepresentable 要求实现的方法
    // 系统会调用它来创建实际的视图，只调用一次
    func makeUIView(context: Context) -> UIView {
        
        // 创建一个空白视图容器
        let view = UIView(frame: .zero)
        
        // AVCaptureVideoPreviewLayer 是专门用来显示摄像头画面的图层
        // 把 session 传给它，它就知道从哪里拿画面了
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        
        // .resizeAspectFill 表示画面填满整个区域，可能会裁剪边缘
        // 类似于图片的 "fill" 模式
        previewLayer.videoGravity = .resizeAspectFill
        
        // 把预览图层添加到视图上
        view.layer.addSublayer(previewLayer)
        
        // 异步设置图层大小，等视图布局完成后再匹配尺寸
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }
        
        // 返回这个视图给 SwiftUI 显示
        return view
    }
    
    // updateUIView 在 SwiftUI 状态更新时被调用
    // 这里我们重新设置图层尺寸，确保旋转屏幕后画面大小正确
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
