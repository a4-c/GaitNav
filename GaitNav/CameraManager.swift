import AVFoundation
import UIKit
import Combine

// Inheriting from NSObject and conforming to ObservableObject
// ObservableObject: when the data in this class changes, the SwiftUI interface will refresh automatically
class CameraManager: NSObject, ObservableObject {
    
    // 一个管道：摄像头画面从这里进，处理后从这里出
    let session = AVCaptureSession()
    
    // @Published 表示这个属性变化时，SwiftUI 界面会自动刷新
    // 每次检测完成，新的结果会写入这里，界面上的框就会更新
    @Published var detections: [Detection] = []
    
    // 创建检测器实例
    private let detector = Detector()
    // AVCaptureVideoDataOutput：从摄像头管道中截取每一帧画面
    private let output = AVCaptureVideoDataOutput()
    // 专门用来处理视频帧的后台队列，不会卡住主线程
    private let processingQueue = DispatchQueue(label: "videoProcessing")
    // 标记当前是否正在处理一帧，避免堆积
    private var isProcessing = false
    
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
        
        // 设置 self 为视频帧的接收者（delegate）
        // 每当摄像头产出一帧画面，系统就会调用下面写的 captureOutput 方法
        // queue: processingQueue 表示在后台线程接收，不卡界面
        output.setSampleBufferDelegate(self, queue: processingQueue)
        // 如果处理速度跟不上摄像头帧率，丢弃旧帧，只处理最新的
        output.alwaysDiscardsLateVideoFrames = true
        
        // 把视频输出接入摄像头管道
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        // 在后台线程启动摄像头
        // 为什么要后台？因为启动摄像头需要时间，放主线程会卡住界面
        DispatchQueue.global(qos: .userInitiated).async {
            // 开始采集画面
            self.session.startRunning()
        }
    }
}

// extension 是 Swift 的扩展语法，给 CameraManager 额外添加功能
// 这里让它遵循 AVCaptureVideoDataOutputSampleBufferDelegate 协议
// 意思是：它能接收摄像头每一帧的回调
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // 每当摄像头捕获一帧画面，系统自动调用这个方法
    // sampleBuffer 里面装着这一帧的图像数据
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // 如果上一帧还没处理完，跳过这帧（避免堆积）
        guard !isProcessing else { return }
        // 从 sampleBuffer 中提取像素数据
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        isProcessing = true  // 标记为正在处理
        
        // 把这帧画面交给检测器，检测完成后执行闭包
        // [weak self] 防止内存泄漏（Swift 的内存管理机制）
        detector.detect(pixelBuffer: pixelBuffer) { [weak self] detections in
            // 回到主线程更新 UI（SwiftUI 要求在主线程更新界面）
            DispatchQueue.main.async {
                // 更新检测结果
                self?.detections = detections
                // 标记为处理完毕，可以接收下一帧
                self?.isProcessing = false
            }
        }
    }
}
