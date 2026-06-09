import ARKit
import Combine

// 感知流水线：ARSession 的管理者和每帧处理的协调者
//
// 职责：
//   1. 创建和配置 ARSession（摄像头 + LiDAR + 世界追踪）
//   2. 接收每帧数据，协调检测 → 测距 → 追踪的流水线
//   3. 把最终结果（稳定的检测列表）发布给 SwiftUI 界面
//
// ObservableObject：告诉 SwiftUI "我是一个可观察的数据源"
// 当里面带 @Published 标记的属性变化时，界面会自动刷新
class PerceptionPipeline: NSObject, ObservableObject {
    
    // 创建 ARSession 实例
    // ARSession 是整个 AR 系统的大脑
    // 它协调摄像头、LiDAR、IMU 等传感器，每一帧产出一个 ARFrame
    // ARFrame 里包含：摄像头画面 + 深度图 + 设备在空间中的位置和朝向
    let session = ARSession()
    
    // 专门处理 ARSession 帧回调的串行队列
    // ARKit 会把 session(_:didUpdate:) 投递到这条后台队列，避免 Vision 推理阻塞主线程
    private let frameProcessingQueue = DispatchQueue(label: "com.gaitnav.perception.frameProcessing", qos: .userInitiated)
    
    // 检测结果数组，现在每个结果里可能带有距离信息
    // @Published 表示这个属性变化时，SwiftUI 界面会自动刷新
    // 每次检测完成，新的结果会写入这里，界面上的框就会更新
    @Published var detections: [Detection] = []
    
    // 检测器（延迟加载，避免阻塞主线程）
    // ML 模型加载耗时较长，放到 start() 中在后台线程初始化
    // 加载完成后的赋值也回到 frameProcessingQueue，确保帧回调读取 detector 时没有跨队列竞争
    private var detector: Detector?
    
    // 距离估算器：利用 LiDAR 深度图计算物体到相机的水平距离
    private let distanceEstimator = DistanceEstimator()
    
    // 物体追踪器：把 YOLO 每帧独立的检测结果串联成连续的追踪轨迹
    private let tracker = ObjectTracker()
    
    // 标记当前是否正在处理一帧，避免堆积
    // 这个标志只在 frameProcessingQueue 上读写，避免主线程和后台队列同时访问
    private var isProcessing = false
    
    // @Published：值变化时自动通知 SwiftUI 刷新界面，这样 ContentView 里的 FPS 显示会实时更新
    @Published var fps: Double = 0
    
    // 计数器：记录从上次统计到现在已经处理了多少帧
    private var frameCount = 0
    // 时间戳：记录上次更新 FPS 的时刻，用来计算时间间隔
    // Date() 表示"现在这一刻"
    private var lastFPSUpdate = Date()
    
    // 启动 AR 会话，由外部在界面准备好后调用
    func start() {
        // 1. 先启动 AR 会话（非阻塞，摄像头很快就能出画面）
        startSession()
        
        // 2. 在后台线程加载 ML 检测模型（耗时操作）
        //    加载完成前，帧回调会跳过检测步骤
        //    加载完成后，把 detector 存回帧处理队列，后续检测自动开始
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 创建 Detector 会同步加载 Core ML / Vision 模型，因此不能放在主线程
            let loadedDetector = Detector()
            // detector 由 AR 帧回调读取，所以赋值也切回同一条串行帧处理队列
            self?.frameProcessingQueue.async {
                // 保存加载好的检测器，下一次帧回调即可进入推理流程
                self?.detector = loadedDetector
            }
        }
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
            // 深度图的每个像素值 = 该点到摄像头的深度（单位：米）
            config.frameSemantics = .sceneDepth
            print("LiDAR available, depth capture enabled.")
        } else {
            print("This device does not support LiDAR.")
        }
        
        // delegate 是"代理"模式
        // 意思是：ARSession 每产出一帧数据，就通知我（self）
        // 具体来说，它会调用我们下面 extension 里写的 session(_:didUpdate:) 方法
        // delegateQueue 指定帧回调进入后台串行队列，而不是默认主队列
        session.delegateQueue = frameProcessingQueue
        session.delegate = self
        
        // 用指定的配置启动 AR 会话
        // 从这一刻起，摄像头开始采集，LiDAR 开始扫描
        session.run(config)
    }
}

// extension：给 PerceptionPipeline 额外添加 ARSessionDelegate 协议的实现
// ARSessionDelegate 定义了一组方法，ARSession 在特定时机会调用它们
// 我们只用到其中的 session(_:didUpdate:)，即每帧更新时的回调
extension PerceptionPipeline: ARSessionDelegate {
    
    // ARKit 每产出一帧数据就调用这个方法
    // frame 参数是 ARFrame 类型，包含这一帧的所有信息
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // 如果上一帧还没处理完，跳过这帧（避免堆积）
        guard !isProcessing else { return }
        
        // 检测器还没加载完成，跳过（ML 模型正在后台线程初始化）
        guard let detector = self.detector else { return }
        
        // 标记为正在处理
        isProcessing = true
        
        // 从 ARFrame 中取出摄像头画面
        // capturedImage 拿到的是 CVPixelBuffer
        let image = frame.capturedImage
        
        // frame.sceneDepth 是 LiDAR 生成的深度数据
        // .depthMap 是一张深度图（CVPixelBuffer 格式），和摄像头画面对齐
        // 如果设备没有 LiDAR 或者这一帧没有深度数据，depthMap 为 nil
        let depthMap = frame.sceneDepth?.depthMap
        
        // 置信度图：和深度图大小相同（256×192），每个像素标记了该深度值的可信程度
        // 0 = low（低，不可靠），1 = medium（中等），2 = high（高，最可靠）
        // 后面用它来过滤掉不靠谱的深度值，只用可靠的点来算距离
        let confidenceMap = frame.sceneDepth?.confidenceMap
        
        // 相机内参矩阵（3×3）：描述相机镜头的光学特性
        // 里面包含焦距 fx/fy（决定了"3D空间中1米 → 图像上多少像素"）
        // 和主点 cx/cy（镜头光心在图像中的位置，通常接近图像中心）
        // 后面用来把"2D像素坐标 + 深度值"反算出"3D空间坐标"
        let intrinsics = frame.camera.intrinsics
        
        // 相机变换矩阵（4×4）：描述相机在真实世界中的位置和朝向
        // 用来把"相机坐标系"下的3D点转换到"世界坐标系"
        // 这样我们就能知道物体在真实世界的什么位置
        let cameraTransform = frame.camera.transform
        
        // 摄像头原始画面的分辨率（比如 1920×1440）
        // 内参矩阵是基于这个分辨率定义的
        // 但深度图只有 256×192，分辨率小很多
        // 后面需要用这两个值来计算缩放比例，把内参适配到深度图的分辨率
        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        
        // 把这帧画面交给检测器，检测完成后执行闭包
        // [weak self] 防止内存泄漏（Swift 的内存管理机制）
        detector.detect(pixelBuffer: image) { [weak self] detections in
            
            // 把可选的 self 安全解包，避免后面每次都写 self?.
            guard let self = self else { return }
            
            // detections 是 YOLO 返回的检测结果，目前还没有距离信息
            var results = detections
            
            // 只有在深度图存在的情况下才尝试读取距离
            if let depthMap = depthMap {
                for i in results.indices {
                    // 调用距离估算器：
                    // 采样深度 → 反投影到3D空间 → 转换到世界坐标 → 算水平距离
                    // 给检测结果补上距离
                    results[i].distance = self.distanceEstimator.getDistance(
                        boundingBox: results[i].boundingBox,
                        depthMap: depthMap,
                        confidenceMap: confidenceMap,
                        intrinsics: intrinsics,
                        cameraTransform: cameraTransform,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )
                }
            }
            
            // 回到主线程更新 UI（SwiftUI 要求在主线程更新界面）
            DispatchQueue.main.async {
                // 用追踪器处理这一帧的检测结果：
                //   匹配到已有物体 → 更新位置、平滑距离、记录标签
                //   没匹配到的新物体 → 开始追踪
                //   连续消失的旧物体 → 移除
                self.tracker.update(with: results)
                
                // 从追踪器获取稳定的检测结果
                // 只包含 age >= minAgeToShow 的物体（新出现的前几帧不显示，防止闪烁）
                self.detections = self.tracker.stableDetections
                
                // 更新帧率统计
                self.updateFPS()
                
                // 主线程已经完成追踪、发布和性能记录后，再回到帧处理队列解除忙碌状态
                self.frameProcessingQueue.async {
                    // isProcessing 只在 frameProcessingQueue 上读写，避免跨线程竞争
                    self.isProcessing = false
                }
            }
        }
    }
    
    // FPS 计算逻辑
    // 每处理完一帧调用一次，每秒更新一次 fps 值
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSUpdate = now
        }
    }
}
