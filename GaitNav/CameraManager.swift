import ARKit
import Combine

// Inheriting from NSObject and conforming to ObservableObject
// ObservableObject: when the data in this class changes, the SwiftUI interface will refresh automatically
class CameraManager: NSObject, ObservableObject {

    // 创建 ARSession 实例
    // ARSession 是整个 AR 系统的大脑
    // 它协调摄像头、LiDAR、IMU 等传感器，每一帧产出一个 ARFrame
    // ARFrame 里包含：摄像头画面 + 深度图 + 设备在空间中的位置和朝向
    let session = ARSession()
    
    // 检测结果数组，现在每个结果里可能带有距离信息
    // @Published 表示这个属性变化时，SwiftUI 界面会自动刷新
    // 每次检测完成，新的结果会写入这里，界面上的框就会更新
    @Published var detections: [Detection] = []
    // @Published：值变化时自动通知 SwiftUI 刷新界面，这样 ContentView 里的 FPS 显示会实时更新
    @Published var fps: Double = 0
    
    // 创建检测器实例
    private let detector = Detector()
    
    // 标记当前是否正在处理一帧，避免堆积
    private var isProcessing = false
    
    // 计数器：记录从上次统计到现在已经处理了多少帧
    private var frameCount = 0
    // 时间戳：记录上次更新 FPS 的时刻，用来计算时间间隔
    // Date() 表示"现在这一刻"
    private var lastFPSUpdate = Date()

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
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // 如果上一帧还没处理完，跳过这帧（避免堆积）
        guard !isProcessing else { return }
        // 标记为正在处理
        isProcessing = true
        
        // 从 ARFrame 中取出摄像头画面
        // capturedImage 拿到的是 CVPixelBuffer
        let image = frame.capturedImage
        
        // frame.sceneDepth 是 LiDAR 生成的深度数据
        // .depthMap 是一张深度图（CVPixelBuffer 格式），和摄像头画面对齐
        // 如果设备没有 LiDAR 或者这一帧没有深度数据，depthMap 为 nil
        let depthMap = frame.sceneDepth?.depthMap
        
        // 把这帧画面交给检测器，检测完成后执行闭包
        // [weak self] 防止内存泄漏（Swift 的内存管理机制）
        detector.detect(pixelBuffer: image) { [weak self] detections in
            
            // 把可选的 self 安全解包，避免后面每次都写 self?.
            guard let self = self else { return }
            
            // detections 是 YOLO 返回的检测结果，目前还没有距离信息
            // 接下来我们要给每个检测结果补上距离
            var results = detections
            
            // 只有在深度图存在的情况下才尝试读取距离
            if let depthMap = depthMap {
                // indices 是数组的索引范围，比如 [0, 1, 2, 3]
                // 用 for i in results.indices 而不是 for result in results
                // 因为我们需要修改数组元素，for-in 循环拿到的是副本，改了不会生效
                for i in results.indices {
                    // 调用 getDepth 方法：根据物体在画面中的位置，从深度图中查找距离
                    results[i].distance = self.getDepth(
                        for: results[i].boundingBox,
                        from: depthMap
                    )
                }
            }
            
            // 回到主线程更新 UI（SwiftUI 要求在主线程更新界面）
            DispatchQueue.main.async {
                // 更新检测结果
                self.detections = results
                // 标记为处理完毕，可以接收下一帧
                self.isProcessing = false
                
                // FPS 计算
                self.frameCount += 1
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastFPSUpdate)
                if elapsed >= 1.0 {
                    self.fps = Double(self.frameCount) / elapsed
                    self.frameCount = 0
                    self.lastFPSUpdate = now
                }
            }
        }
    }
    
    // 核心方法：从深度图中提取某个物体的距离
    // boundingBox：YOLO 检测出的物体在画面中的位置（归一化坐标，0到1）
    // depthMap：LiDAR 生成的深度图（CVPixelBuffer，每个像素是 Float32）
    // 返回值：距离（米），如果无法获取则返回 nil
    private func getDepth(for boundingBox: CGRect, from depthMap: CVPixelBuffer) -> Float? {

        // 获取深度图的分辨率(尺寸)
        // LiDAR 深度图通常是 256x192（横向），比摄像头画面小很多
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // 坐标映射：这是整个方法最关键的部分
        //
        // 问题：Vision 返回的 boundingBox 坐标和深度图的坐标系不一样
        //
        // Vision 的坐标系（因为我们在 Detector 里用了 .right）：
        //   - 是竖屏空间
        //   - x 从左到右（0→1）
        //   - y 从下到上（0→1）
        //
        // 深度图的坐标系：
        //   - 是横屏空间（和摄像头原始数据一致）
        //   - y 从上到下
        //   - 宽 256，高 192
        //
        // 竖屏转横屏的对应关系：
        //   竖屏的 x 方向 → 对应横屏的 y 方向（翻转）
        //   竖屏的 y 方向 → 对应横屏的 x 方向（翻转）
        //
        // 所以：
        //   深度图的 x = (1 - boundingBox.midY) * depthWidth
        //   深度图的 y = (1 - boundingBox.midX) * depthHeight
        //
        // 按照这个映射，取物体中心点
        let centerX = Int((1 - boundingBox.midY) * CGFloat(depthWidth))
        let centerY = Int((1 - boundingBox.midX) * CGFloat(depthHeight))

        // 在中心点周围取一个 5x5 的采样区域（半径为 2）
        // 为什么不只读一个点？
        // 因为单个像素的深度值可能有噪声或无效
        // 取多个点然后用中位数，结果更稳定可靠
        let sampleRadius = 2
        var samples: [Float] = []

        // CVPixelBuffer 是一块被系统管理的内存区域
        // 在读取之前必须锁定它，防止系统在我们读的过程中修改数据
        // .readOnly 表示我们只读不写
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        // defer：无论这个函数后面怎么退出（正常 return 或出错），都会在退出前执行 defer 里的代码
        // 这里用来确保一定会解锁
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // bytesPerRow：深度图每一行占多少字节
        // 这个值可能比 width * 4 大，因为内存对齐的关系，行末可能有填充字节
        // 所以不能直接用 width 来计算偏移量，必须用 bytesPerRow
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        // baseAddress：深度图数据在内存中的起始地址（指针）
        // 从这个地址开始，连续存储了所有像素的深度值
        // ! 是强制解包，因为我们已经锁定了内存，baseAddress 不会为 nil
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!

        // 双重 for 循环：遍历中心点周围 5x5 区域的每个点
        // dy 从 -2 到 +2，dx 从 -2 到 +2
        // 这样会遍历 25 个点（5 * 5）
        for dy in -sampleRadius...sampleRadius {
            for dx in -sampleRadius...sampleRadius {
                // 计算当前采样点的坐标
                let x = centerX + dx
                let y = centerY + dy

                // guard 确保坐标在深度图范围内
                // 如果中心点靠近边缘，有些采样点可能超出范围
                // continue 表示跳过这个点，继续下一个
                guard x >= 0, x < depthWidth, y >= 0, y < depthHeight else { continue }

                // 计算中心点在内存中的偏移量（字节数）
                // 行偏移 = centerY * bytesPerRow（跳过前面所有行）
                // 列偏移 = centerX * MemoryLayout<Float32>.stride（跳过同一行前面的像素）
                // MemoryLayout<Float32>.stride = 4 字节（因为每个深度值是 32 位浮点数）
                let offset = y * bytesPerRow + x * MemoryLayout<Float32>.stride
                // 从计算出的内存位置读取一个 Float32 值
                // 这个值就是那个点到摄像头的距离，单位是米
                let depth = baseAddress.load(fromByteOffset: offset, as: Float32.self)

                // 过滤无效值：
                // depth > 0：排除无效/缺失数据（LiDAR 有时返回 0 表示无法测量）
                // depth < 8：排除超过 8 米的数据（太远了不可靠，也超出了行人导航的实用范围）
                if depth > 0 && depth < 8 {
                    samples.append(depth)
                }
            }
        }

        // 如果所有 25 个采样点都无效，返回 nil（表示无法获取距离）
        guard !samples.isEmpty else { return nil }

        // 排序后取中位数
        // 中位数 = 排好序后最中间那个值
        // 例如 [1.1, 1.2, 1.3, 5.0, 8.0] → 中位数是 1.3
        // 中位数比平均值更好，因为它不受极端值影响
        // 如果 25 个点里有几个异常值，中位数不会被拉偏
        samples.sort()
        return samples[samples.count / 2]
    }
}
