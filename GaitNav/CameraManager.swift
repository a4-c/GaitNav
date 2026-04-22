import AVFoundation
import UIKit
import ARKit
import Combine

//// Inheriting from NSObject and conforming to ObservableObject
//// ObservableObject: when the data in this class changes, the SwiftUI interface will refresh automatically
//class CameraManager: NSObject, ObservableObject {
//    
//    // 一个管道：摄像头画面从这里进，处理后从这里出
//    let session = AVCaptureSession()
//    
//    // @Published 表示这个属性变化时，SwiftUI 界面会自动刷新
//    // 每次检测完成，新的结果会写入这里，界面上的框就会更新
//    @Published var detections: [Detection] = []
//    
//    // 创建检测器实例
//    private let detector = Detector()
//    // AVCaptureVideoDataOutput：从摄像头管道中截取每一帧画面
//    private let output = AVCaptureVideoDataOutput()
//    // 专门用来处理视频帧的后台队列，不会卡住主线程
//    private let processingQueue = DispatchQueue(label: "videoProcessing")
//    // 标记当前是否正在处理一帧，避免堆积
//    private var isProcessing = false
//    
//    // @Published：值变化时自动通知 SwiftUI 刷新界面，这样 ContentView 里的 FPS 显示会实时更新
//    @Published var fps: Double = 0
//    // 计数器：记录从上次统计到现在已经处理了多少帧
//    private var frameCount = 0
//    // 时间戳：记录上次更新 FPS 的时刻，用来计算时间间隔
//    // Date() 表示"现在这一刻"
//    private var lastFPSUpdate = Date()
//    
//    // 构造函数，对象被创建时自动执行
//    override init() {
//        super.init()
//        //调用自己写的摄像头配置方法
//        setupCamera()
//    }
//    
//    private func setupCamera() {
//        
//        // 设置画质为高质量
//        session.sessionPreset = .high
//        
//        // guard let 是 Swift 的安全解包语法
//        // 意思是：尝试获取后置摄像头，如果失败就执行 else 里的代码然后 return
//        // .builtInWideAngleCamera = 普通广角摄像头
//        // for: .video = 用于拍视频
//        // position: .back = 后置摄像头
//        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
//              // 用这个摄像头创建一个"输入源"，try? 表示如果出错就返回 nil
//              let input = try? AVCaptureDeviceInput(device: camera)
//        else {
//            // 获取失败，打印错误信息
//            print("Cannot access camera")
//            return
//        }
//        
//        // 检查 session 能否添加这个输入源（安全检查）
//        if session.canAddInput(input) {
//            // 把摄像头接入管道
//            session.addInput(input)
//        }
//        
//        // 设置 self 为视频帧的接收者（delegate）
//        // 每当摄像头产出一帧画面，系统就会调用下面写的 captureOutput 方法
//        // queue: processingQueue 表示在后台线程接收，不卡界面
//        output.setSampleBufferDelegate(self, queue: processingQueue)
//        // 如果处理速度跟不上摄像头帧率，丢弃旧帧，只处理最新的
//        output.alwaysDiscardsLateVideoFrames = true
//        
//        // 把视频输出接入摄像头管道
//        if session.canAddOutput(output) {
//            session.addOutput(output)
//        }
//        
//        // 在后台线程启动摄像头
//        // 为什么要后台？因为启动摄像头需要时间，放主线程会卡住界面
//        DispatchQueue.global(qos: .userInitiated).async {
//            // 开始采集画面
//            self.session.startRunning()
//        }
//    }
//}
//
//// extension 是 Swift 的扩展语法，给 CameraManager 额外添加功能
//// 这里让它遵循 AVCaptureVideoDataOutputSampleBufferDelegate 协议
//// 意思是：它能接收摄像头每一帧的回调
//extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
//    
//    // 每当摄像头捕获一帧画面，系统自动调用这个方法
//    // sampleBuffer 里面装着这一帧的图像数据
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        
//        // 如果上一帧还没处理完，跳过这帧（避免堆积）
//        guard !isProcessing else { return }
//        // 从 sampleBuffer 中提取像素数据
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        
//        isProcessing = true  // 标记为正在处理
//        
//        // 把这帧画面交给检测器，检测完成后执行闭包
//        // [weak self] 防止内存泄漏（Swift 的内存管理机制）
//        detector.detect(pixelBuffer: pixelBuffer) { [weak self] detections in
//            // 回到主线程更新 UI（SwiftUI 要求在主线程更新界面）
//            DispatchQueue.main.async {
//                // 把可选的 self 安全解包，避免后面每次都写 self?.
//                guard let self = self else { return }
//                // 更新检测结果
//                self.detections = detections
//                // 标记为处理完毕，可以接收下一帧
//                self.isProcessing = false
//                
//                // FPS 计算
//                self.frameCount += 1
//                let now = Date()
//                let elapsed = now.timeIntervalSince(self.lastFPSUpdate)
//                if elapsed >= 1.0 {
//                    self.fps = Double(self.frameCount) / elapsed
//                    self.frameCount = 0
//                    self.lastFPSUpdate = now
//                }
//            }
//        }
//    }
//}

// Inheriting from NSObject and conforming to ObservableObject
// ObservableObject: when the data in this class changes, the SwiftUI interface will refresh automatically
class CameraManager: NSObject, ObservableObject {

    // 创建 ARSession 实例
    // ARSession 是整个 AR 系统的大脑
    // 它协调摄像头、LiDAR、IMU 等传感器，每一帧产出一个 ARFrame
    // ARFrame 里包含：摄像头画面 + 深度图 + 设备在空间中的位置和朝向
    let session = ARSession()

    // @Published：当这个值变化时，自动通知 SwiftUI 刷新界面
    // 用来在屏幕底部显示深度信息
    @Published var depthInfo: String = "Waiting for depth data ..."

    // 构造函数，对象创建时自动执行
    override init() {
        // 调用父类构造函数
        super.init()
        // 配置+启动 AR 会话
        startSession()
    }

    private func startSession() {

        // ARWorldTrackingConfiguration 是 ARKit 最强大的配置模式
        // "World Tracking" 意思是追踪设备在真实世界中的位置和方向
        // 它用到了摄像头 + IMU（加速度计和陀螺仪）来实现 6DoF 追踪
        // 6DoF = 6 Degrees of Freedom = 前后、左右、上下 + 俯仰、偏航、翻滚
        let config = ARWorldTrackingConfiguration()

        // 检查当前设备是否支持 .sceneDepth
        // .sceneDepth 需要 LiDAR 传感器，只有 iPhone Pro 系列才有
        // 普通 iPhone 这里会返回 false
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {

            // 启用场景深度语义
            // 启用后，ARKit 每一帧都会生成一张深度图（depthMap）
            // 深度图的每个像素值 = 该点到摄像头的距离（单位：米）
            config.frameSemantics = .sceneDepth
            print("LiDAR available, depth capture enabled.")
        } else {
            print("This device does not support LiDAR.")
        }

        // delegate 是"代理"模式
        // 意思是：ARSession 每产出一帧数据，就通知我（self）
        // 具体来说，它会调用我们下面 extension 里写的 session(_:didUpdate:) 方法
        session.delegate = self

        // 用指定的配置启动 AR 会话
        // 从这一刻起，摄像头开始采集，LiDAR 开始扫描
        session.run(config)
    }
}

// extension：给 CameraManager 额外添加 ARSessionDelegate 协议的实现
// ARSessionDelegate 定义了一组方法，ARSession 在特定时机会调用它们
// 我们只用到其中的 session(_:didUpdate:)，即每帧更新时的回调
extension CameraManager: ARSessionDelegate {

    // ARKit 每产出一帧数据就调用这个方法
    // frame 参数是 ARFrame 类型，包含这一帧的所有信息
    // ARKit 大约每秒产出 60 帧
    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        // frame.sceneDepth 是 LiDAR 生成的深度数据
        // .depthMap 是一张深度图（CVPixelBuffer 格式）
        // 它和摄像头画面对齐，但分辨率小得多（通常 256x192）
        // guard let 确保深度数据存在，否则直接返回
        guard let depthMap = frame.sceneDepth?.depthMap else { return }

        // CVPixelBufferGetWidth / Height 获取深度图的像素尺寸
        // LiDAR 深度图通常是 256x192（横向）
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // 计算深度图正中心的坐标
        // 我们先只读中心点的深度值，验证 LiDAR 是否在工作
        
        // 水平中心
        let centerX = width / 2
        // 垂直中心
        let centerY = height / 2

        // CVPixelBuffer 是一块被系统管理的内存区域
        // 在读取之前必须"锁定"它，防止系统在我们读的过程中修改数据
        // .readOnly 表示我们只读不写
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)

        // defer 是 Swift 的语法糖
        // 意思是：无论这个函数后面怎么退出（正常 return 或出错）
        // 都会在退出前执行 defer 里的代码
        // 这里用来确保一定会解锁，避免内存泄漏
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // bytesPerRow：深度图每一行占多少字节
        // 这个值可能比 width * 4 大，因为内存对齐的关系，行末可能有填充字节
        // 所以不能直接用 width 来计算偏移量，必须用 bytesPerRow
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // baseAddress：深度图数据在内存中的起始地址（指针）
        // 从这个地址开始，连续存储了所有像素的深度值
        // ! 是强制解包，因为我们已经锁定了内存，baseAddress 不会为 nil
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!

        // 计算中心点在内存中的偏移量（字节数）
        // 行偏移 = centerY * bytesPerRow（跳过前面所有行）
        // 列偏移 = centerX * MemoryLayout<Float32>.stride（跳过同一行前面的像素）
        // MemoryLayout<Float32>.stride = 4 字节（因为每个深度值是 32 位浮点数）
        let offset = centerY * bytesPerRow + centerX * MemoryLayout<Float32>.stride

        // 从计算出的内存位置读取一个 Float32 值
        // 这个值就是画面正中心那个点到摄像头的距离，单位是米
        let centerDepth = baseAddress.load(fromByteOffset: offset, as: Float32.self)

        // 回到主线程更新 UI
        // SwiftUI 的 @Published 属性必须在主线程修改
        DispatchQueue.main.async {
            // String(format:) 是格式化字符串
            // %d = 整数，%dx%d 显示成 "256x192" 这样
            // %.2f = 保留两位小数的浮点数，比如 1.35
            self.depthInfo = String(format: "深度图: %dx%d · 中心距离: %.2fm", width, height, centerDepth)
        }
    }
}
