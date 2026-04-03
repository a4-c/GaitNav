import AVFoundation
import UIKit
import Combine

// Inheriting from NSObject and conforming to ObservableObject
// ObservableObject: when the data in this class changes, the SwiftUI interface will refresh automatically
class CameraManager: NSObject, ObservableObject {
    
    // 一个管道：摄像头画面从这里进，处理后从这里出
    let session = AVCaptureSession()
    
    // 构造函数，对象被创建时自动执行
    override init() {
        super.init()
        //调用自己写的摄像头配置方法
        setupCamera()
    }
    
    private func setupCamera() {
        
        // 设置画质为高质量
        session.sessionPreset = .high
        
        // guard let 是 Swift 的安全解包语法
        // 意思是：尝试获取后置摄像头，如果失败就执行 else 里的代码然后 return
        // .builtInWideAngleCamera = 普通广角摄像头
        // for: .video = 用于拍视频
        // position: .back = 后置摄像头
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              // 用这个摄像头创建一个"输入源"，try? 表示如果出错就返回 nil
              let input = try? AVCaptureDeviceInput(device: camera)
        else {
            // 获取失败，打印错误信息
            print("Cannot access camera")
            return
        }
        
        // 检查 session 能否添加这个输入源（安全检查）
        if session.canAddInput(input) {
            // 把摄像头接入管道
            session.addInput(input)
        }
        
        // 在后台线程启动摄像头
        // 为什么要后台？因为启动摄像头需要时间，放主线程会卡住界面
        DispatchQueue.global(qos: .userInitiated).async {
            // 开始采集画面
            self.session.startRunning()
        }
    }
}
