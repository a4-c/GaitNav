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
    
    // 创建检测器实例
    private let detector = Detector()
    
    // 标记当前是否正在处理一帧，避免堆积
    private var isProcessing = false
    
    // @Published：值变化时自动通知 SwiftUI 刷新界面，这样 ContentView 里的 FPS 显示会实时更新
    @Published var fps: Double = 0
    
    // 计数器：记录从上次统计到现在已经处理了多少帧
    private var frameCount = 0
    // 时间戳：记录上次更新 FPS 的时刻，用来计算时间间隔
    // Date() 表示"现在这一刻"
    private var lastFPSUpdate = Date()
    
    // 当前正在追踪的所有物体
    private var trackedObjects: [TrackedObject] = []
    
    // IoU 阈值：两个框的重叠度超过这个值，才认为是同一个物体
    // IoU = 交集面积 / 并集面积，范围 0~1
    // 0.3 比较宽松，适合物体在帧间有较大移动的情况
    private let iouThreshold: CGFloat = 0.3
    // 物体连续消失超过这么多帧就移除
    private let maxMissedFrames = 3
    // 物体至少要存在这么多帧才会显示（防止误检一闪而过）
    private let minAgeToShow = 2
    // 标签历史最多保留多少条记录（太多会导致标签切换反应慢）
    private let maxLabelHistory = 10
    // 距离历史最多保留多少帧（用于中位数滤波）
    // 3 帧 = 只滞后 1 帧就能跟上真实距离变化，同时过滤单帧噪声
    // 增大可以更抗噪但滞后更多，减小反应更快但过滤效果更弱
    private let maxDistanceHistory = 3
    
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
            // 深度图的每个像素值 = 该点到摄像头的深度（单位：米）
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
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        
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
                    // 调用 getDepth 方法：
                    // 采样深度 → 反投影到3D空间 → 转换到世界坐标 → 算水平距离
                    // 给检测结果补上距离
                    results[i].distance = self.getDistance(
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
                // 用追踪系统处理这一帧的检测结果：
                //   匹配到已有物体 → 更新位置、平滑距离、记录标签
                //   没匹配到的新物体 → 开始追踪
                //   连续消失的旧物体 → 移除
                self.updateTracking(with: results)
                
                // 把追踪结果转换成 Detection 数组给界面显示
                // 只输出 age >= minAgeToShow 的物体（新出现的前几帧不显示，防止闪烁）
                self.detections = self.trackedObjects
                    .filter { $0.age >= self.minAgeToShow }
                    .map { tracked in
                        Detection(
                            id: tracked.id,
                            label: tracked.stableLabel,
                            confidence: tracked.confidence,
                            boundingBox: tracked.boundingBox,
                            distance: tracked.stableDistance
                        )
                    }
                
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
    
    // 计算某个物体到相机的水平距离
    //
    // 整体流程：
    //   1. 缩放相机内参，适配深度图分辨率
    //   2. 确定采样区域（检测框中间60%）
    //   3. 遍历区域内每个像素，过滤低置信度和无效深度
    //   4. 反投影到3D空间，转换到世界坐标系
    //   5. 计算水平距离，取中位数
    //
    // 参数：
    //   boundingBox：YOLO 检测出的物体位置（归一化坐标，0到1）
    //   depthMap：LiDAR 深度图（每个像素是 Float32，单位：米）
    //   confidenceMap：置信度图（每个像素是 UInt8，0/1/2）
    //   intrinsics：相机内参矩阵（3×3，包含焦距和主点）
    //   cameraTransform：相机在世界中的位姿（4×4变换矩阵）
    //   imageWidth/Height：摄像头原始画面的分辨率
    //
    // 返回值：
    //   水平距离（米），如果无法获取则返回 nil
    private func getDistance(
        boundingBox: CGRect,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> Float? {
        
        // ===================================================================
        // 第一步：获取深度图尺寸 & 缩放相机内参
        // ===================================================================
        
        // 获取深度图的分辨率(尺寸)
        // LiDAR 深度图通常是 256x192（横向），比摄像头画面小很多
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        // 相机内参（intrinsics）里的焦距和主点是基于摄像头全分辨率的
        // 比如 fx=1400 是在 1920 像素宽的图上定义的
        // 但深度图只有 256 像素宽，所以必须等比例缩小
        //
        // 缩放公式：
        //   缩放后的 fx = 原始 fx × (深度图宽 / 摄像头画面宽)
        //   比如：1400 × (256 / 1920) ≈ 186.7
        //
        // 如果不缩放，反投影出来的 3D 坐标会完全错误
        let scaleX = Float(depthWidth) / Float(imageWidth)
        let scaleY = Float(depthHeight) / Float(imageHeight)
        
        // 从内参矩阵中提取四个关键参数，并缩放到深度图的分辨率
        //
        // intrinsics 是 3×3 矩阵，在 Swift 中是列优先存储：
        //   intrinsics[列][行]
        //
        // 矩阵长这样：
        //   ┌ fx   0   cx ┐
        //   │  0  fy   cy │
        //   └  0   0    1 ┘
        //
        // 在列优先存储中：
        //   第0列 = [fx, 0, 0]  → intrinsics[0][0] = fx
        //   第1列 = [0, fy, 0]  → intrinsics[1][1] = fy
        //   第2列 = [cx, cy, 1] → intrinsics[2][0] = cx, intrinsics[2][1] = cy
        //
        // fx, fy：焦距（像素单位），值越大 = 镜头越"长焦"（视野越窄）
        // cx, cy：主点，镜头光心在图像上的投影位置，通常接近图像中心
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        
        // ===================================================================
        // 第二步：确定采样区域（检测框中间 60%）
        // ===================================================================
        
        // 不采整个检测框，而是只采中间 60% 的区域
        // 因为 YOLO 的检测框不是精确贴合物体的——边缘部分经常包含背景
        // 如果采到了背景的深度值，距离就会算错
        //
        // 示意图（检测框）：
        //   ┌──────────────────┐
        //   │  20% 边距（跳过）  │
        //   │  ┌────────────┐  │
        //   │  │ 中间 60%    │  │
        //   │  │（实际采样）  │  │
        //   │  └────────────┘  │
        //   │  20% 边距（跳过）  │
        //   └──────────────────┘
        let margin: CGFloat = 0.2
        
        // 在 Vision 坐标系中，计算缩小后的采样区域的四个边界
        let visionXStart = boundingBox.minX + margin * boundingBox.width
        let visionXEnd   = boundingBox.maxX - margin * boundingBox.width
        let visionYStart = boundingBox.minY + margin * boundingBox.height
        let visionYEnd   = boundingBox.maxY - margin * boundingBox.height
        
        // 坐标映射：Vision 竖屏归一化坐标 → 深度图横屏像素坐标
        //
        // 映射关系：
        //   深度图 x = (1 - Vision y) × 深度图宽度
        //   深度图 y = (1 - Vision x) × 深度图高度
        //
        // 注意翻转：Vision 的 yEnd（值更大，在画面上方）
        //          → 深度图的 xStart（值更小，在横屏左侧）
        // 同理：    Vision 的 xEnd（值更大，在画面右侧）
        //          → 深度图的 yStart（值更小，在横屏上方）
        //
        // max(0, ...) 和 min(width-1, ...)：确保不越界
        let depthXStart = max(0, Int((1 - visionYEnd) * CGFloat(depthWidth)))
        let depthXEnd   = min(depthWidth - 1, Int((1 - visionYStart) * CGFloat(depthWidth)))
        let depthYStart = max(0, Int((1 - visionXEnd) * CGFloat(depthHeight)))
        let depthYEnd   = min(depthHeight - 1, Int((1 - visionXStart) * CGFloat(depthHeight)))
        
        // 如果计算出的采样区域无效（起点在终点后面），说明检测框太小了
        guard depthXStart <= depthXEnd, depthYStart <= depthYEnd else { return nil }
        
        // ===================================================================
        // 第三步：锁定内存，准备读取深度图和置信度图
        // ===================================================================
        
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
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        // baseAddress：深度图数据在内存中的起始地址（指针）
        // 从这个地址开始，连续存储了所有像素的深度值
        // ! 是强制解包，因为我们已经锁定了内存，baseAddress 不会为 nil
        let depthBase = CVPixelBufferGetBaseAddress(depthMap)!
        
        // 如果置信度图存在，也锁定它并读取其基地址
        // 置信度图和深度图大小完全相同（256×192），但每个像素是 UInt8 类型
        //   0 = low（低置信度，LiDAR 对这个点的测量没信心）
        //   1 = medium（中等置信度）
        //   2 = high（高置信度，最可靠）
        var confBase: UnsafeMutableRawPointer? = nil
        var confBytesPerRow = 0
        if let confidenceMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            confBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        // 函数退出时也要解锁置信度图
        defer {
            if let confidenceMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }
        
        // ===================================================================
        // 第四步：获取相机的世界坐标（用于最终计算距离）
        // ===================================================================
        
        // cameraTransform 是一个 4×4 矩阵，它的第 4 列（columns.3）
        // 存储的就是相机在世界坐标系中的位置 (x, y, z, 1)
        //
        // ARKit 的世界坐标系：
        //   X 轴：水平方向
        //   Y 轴：垂直方向（朝上）
        //   Z 轴：水平方向（和 X 垂直）
        //
        // 我们只取 X 和 Z（水平面上的位置），不需要 Y（高度）
        let camWorldX = cameraTransform.columns.3.x
        let camWorldZ = cameraTransform.columns.3.z
        
        // 用来收集所有有效采样点的水平距离
        var horizontalDistances: [Float] = []
        
        // ===================================================================
        // 第五步：遍历采样区域，对每个像素执行完整的 pipeline
        // ===================================================================
        
        // 对采样区域里的每一个像素，我们要做：
        //   检查置信度 → 读取深度 → 过滤无效值 → 反投影到相机 3D 坐标 → 转换到世界坐标 → 算水平距离
        //
        // py 遍历深度图的行（y 方向），px 遍历列（x 方向）
        for py in depthYStart...depthYEnd {
            for px in depthXStart...depthXEnd {
                
                // ----- 5a：检查置信度（如果有置信度图的话） -----
                
                // 跳过低置信度（0）的像素，只保留 medium（1）和 high（2）
                // 低置信度的点通常出现在：反射面、透明物体、超出 LiDAR 量程等情况
                //
                // 如果你想更严格，可以把 < 1 改成 < 2（只保留 high）
                // 但那样可能会导致有效采样点太少
                if let confBase = confBase {
                    // 计算这个像素在置信度图内存中的位置
                    // UInt8 每个占 1 字节，所以 stride = 1
                    let confOffset = py * confBytesPerRow + px * MemoryLayout<UInt8>.stride
                    // 读取置信度值（0、1 或 2）
                    let confidence = confBase.load(fromByteOffset: confOffset, as: UInt8.self)
                    // 如果是低置信度（0），跳过这个像素
                    if confidence < 1 { continue }
                }
                
                // ----- 5b：读取深度值 -----
                
                // 从内存中读取 Float32 类型的深度值
                let depthOffset = py * depthBytesPerRow + px * MemoryLayout<Float32>.stride
                let z = depthBase.load(fromByteOffset: depthOffset, as: Float32.self)
                
                // 过滤无效深度值：
                // ≤ 0.1m：太近了，通常是噪声或测量错误
                // ≥ 8.0m：太远了，LiDAR 不可靠，也超出行人导航范围
                guard z > 0.1 && z < 8.0 else { continue }
                
                // ----- 5c：反投影到相机 3D 坐标系 -----
                
                // 原理：拍照是 3D→2D 的过程（投影），现在我们要反过来（反投影）
                //
                // 拍照时（投影）：
                //   已知：3D点 (X, Y, Z)
                //   计算：像素坐标 (u, v)
                //     u = fx × (X / Z) + cx
                //     v = fy × (Y / Z) + cy
                //
                // 反过来（反投影）：
                //   已知：像素坐标 (px, py) + 深度值 z
                //   计算：3D点 (X, Y, Z)
                //     X = (px - cx) × z / fx
                //     Y = (py - cy) × z / fy
                //     Z = z
                //
                // 这样就从一个 2D 像素恢复出了它在 3D 空间中的位置
                let xCam = (Float(px) - cx) * z / fx
                // Y 要取反
                // 因为图像坐标系的 Y 是从上往下增长的（像素行号）
                // 但 ARKit 相机坐标系的 Y 是朝上的
                let yCam = -((Float(py) - cy) * z / fy)
                // Z 取负号，因为 ARKit 相机坐标系中，相机前方是 -Z 方向
                // （Z 轴朝后，指向观察者自己，所以物体在前方 = Z 为负）
                let pointInCamera = SIMD4<Float>(xCam, yCam, -z, 1.0)
                
                // ----- 5d：从相机坐标系转换到世界坐标系 -----
                
                // pointInCamera 是以相机为原点的坐标："物体在我左边0.3米、下方0.5米、前方2米"
                // 但相机在真实世界中可能是歪的、倾斜的、朝着任意方向的
                // 我们需要知道物体在真实世界中的绝对位置
                //
                // cameraTransform 就像一张地图：
                //   它告诉我们"相机在世界中的位置"和"相机面朝哪个方向"
                //   用矩阵乘法，就能把相机坐标转换成世界坐标
                //
                // 数学公式：世界坐标 = cameraTransform × 相机坐标
                //
                // 结果 pointInWorld 包含 (x, y, z, w)：
                //   x, z = 物体在世界水平面上的位置
                //   y = 物体的高度（我们不需要）
                let pointInWorld = cameraTransform * pointInCamera
                
                // ----- 5e：计算水平距离 -----
                
                // "水平距离"的意思是：忽略高度差，只看地面上的距离
                //
                // 想象你在 3 楼窗户看对面楼 1 楼的人：
                //   直线距离 = 斜着量，比较远
                //   水平距离 = 只看平面上的间隔，更短
                //   水平距离才是你走过去需要走的路
                //
                // 计算方法（勾股定理）：
                //   dx = 物体和相机在 X 方向的差
                //   dz = 物体和相机在 Z 方向的差
                //   水平距离 = √(dx² + dz²)
                //
                // 我们不用 Y 方向的差，因为 Y 是垂直方向（高度）
                let dx = pointInWorld.x - camWorldX
                let dz = pointInWorld.z - camWorldZ
                let horizontalDist = sqrtf(dx * dx + dz * dz)
                
                horizontalDistances.append(horizontalDist)
            }
        }
        
        // ===================================================================
        // 第六步：从所有水平距离中取中位数作为最终结果
        // ===================================================================
        
        // 如果没有任何有效的采样点，返回 nil
        guard !horizontalDistances.isEmpty else { return nil }
        
        // 排序后取中位数
        // 中位数比平均值更好，因为它不受极端值影响
        // 即使有几个像素采到了背景（距离突然变大），中位数也不会被拉偏
        horizontalDistances.sort()
        return horizontalDistances[horizontalDistances.count / 2]
    }
    
    // 物体追踪：匹配、更新、清理
    //
    // 这个方法每帧调用一次，负责把 YOLO 的检测结果和已有的追踪物体对应起来
    //
    // 核心逻辑：
    //   1. 对每个新检测结果，找到和它重叠最多的已有追踪物体（IoU 最大）
    //   2. 如果 IoU > 阈值 → 匹配成功，更新那个追踪物体的信息
    //   3. 如果找不到匹配 → 这是一个新出现的物体，创建新的追踪记录
    //   4. 没被任何新检测匹配到的旧追踪物体 → 标记为"消失了一帧"
    //   5. 连续消失太多帧的 → 彻底移除
    private func updateTracking(with detections: [Detection]) {
        
        // 记录哪些已有追踪物体在这一帧被匹配到了
        // 用 Set<UUID> 存储被匹配到的追踪物体的 ID
        var matchedTrackedIDs = Set<UUID>()
        // 记录哪些新检测结果被匹配到了（用索引表示）
        var matchedDetectionIndices = Set<Int>()
        
        // ===================================================================
        // 第一步：为每个新检测结果寻找最佳匹配
        // ===================================================================
        
        // 双重循环：外层遍历新检测，内层遍历已有追踪物体
        // 对每个新检测，找到 IoU 最大的那个追踪物体
        for (detIndex, detection) in detections.enumerated() {
            var bestIoU: CGFloat = 0
            var bestTrackedIndex: Int? = nil
            
            for (trackedIndex, tracked) in trackedObjects.enumerated() {
                // 跳过已经被其他检测匹配走的追踪物体（一对一匹配）
                if matchedTrackedIDs.contains(tracked.id) { continue }
                
                let overlap = iou(detection.boundingBox, tracked.boundingBox)
                if overlap > bestIoU {
                    bestIoU = overlap
                    bestTrackedIndex = trackedIndex
                }
            }
            
            // ===================================================================
            // 第二步：判断是否匹配成功
            // ===================================================================
            
            if bestIoU > iouThreshold, let idx = bestTrackedIndex {
                // 匹配成功，更新这个追踪物体的信息
                
                matchedTrackedIDs.insert(trackedObjects[idx].id)
                matchedDetectionIndices.insert(detIndex)
                
                // 更新边界框为最新位置
                trackedObjects[idx].boundingBox = detection.boundingBox
                // 更新置信度
                trackedObjects[idx].confidence = detection.confidence
                // 重置消失计数（因为这帧又看到它了）
                trackedObjects[idx].missedFrames = 0
                // 年龄 +1
                trackedObjects[idx].age += 1
                
                // 记录这帧的标签到历史中
                trackedObjects[idx].labelHistory.append(detection.label)
                // 如果历史太长，删掉最早的记录，只保留最近的
                if trackedObjects[idx].labelHistory.count > maxLabelHistory {
                    trackedObjects[idx].labelHistory.removeFirst()
                }
                
                // 记录距离到历史数组（用于中位数滤波）
                if let newDist = detection.distance {
                    trackedObjects[idx].distanceHistory.append(newDist)
                    // 如果历史太长，删掉最早的，只保留最近几帧
                    if trackedObjects[idx].distanceHistory.count > maxDistanceHistory {
                        trackedObjects[idx].distanceHistory.removeFirst()
                    }
                }
                // 如果这帧没有距离数据（newDist 为 nil），保留现有历史不变
            }
        }
        
        // ===================================================================
        // 第三步：处理没被匹配到的新检测（新出现的物体）
        // ===================================================================
        
        for (detIndex, detection) in detections.enumerated() {
            if matchedDetectionIndices.contains(detIndex) { continue }
            
            // 创建一个新的追踪记录
            // 如果第一帧就有距离数据，放进历史数组；没有就先空着
            let initialHistory: [Float] = detection.distance.map { [$0] } ?? []
            trackedObjects.append(TrackedObject(
                id: UUID(),
                boundingBox: detection.boundingBox,
                labelHistory: [detection.label],
                confidence: detection.confidence,
                distanceHistory: initialHistory,
                missedFrames: 0,
                // 刚出现，第 1 帧
                age: 1
            ))
        }
        
        // ===================================================================
        // 第四步：处理没被匹配到的旧追踪物体（可能离开了画面）
        // ===================================================================
        
        for i in trackedObjects.indices {
            if !matchedTrackedIDs.contains(trackedObjects[i].id) {
                // 这个物体这帧没有对应的新检测，消失帧数 +1
                trackedObjects[i].missedFrames += 1
            }
        }
        
        // ===================================================================
        // 第五步：移除消失太久的物体
        // ===================================================================
        
        // removeAll(where:) 会删掉所有满足条件的元素
        trackedObjects.removeAll { $0.missedFrames > maxMissedFrames }
    }
    
    // 计算两个矩形的 IoU（Intersection over Union，交并比）
    //
    // IoU 是衡量两个框重叠程度的标准指标，范围 0~1：
    //   0 = 完全不重叠
    //   1 = 完全重合
    //   通常 > 0.3 就认为是同一个物体
    //
    // 计算方法：
    //   IoU = 交集面积 / 并集面积
    //   并集面积 = A面积 + B面积 - 交集面积（减掉重复算的部分）
    //
    // 示意图：
    //   ┌──────┐
    //   │  A   │
    //   │   ┌──┼───┐
    //   └───┼──┘   │
    //       │  B   │
    //       └──────┘
    //   中间重叠的部分 = 交集
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        // .intersection() 返回两个矩形的重叠区域
        let intersection = a.intersection(b)
        // .isNull 表示没有重叠（两个框完全分开）
        if intersection.isNull { return 0 }
        // 交集面积
        let intersectionArea = intersection.width * intersection.height
        // 并集面积 = A + B - 交集（因为交集被 A 和 B 各算了一次，要减掉一次）
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        // 避免除以零（理论上不会，但以防万一）
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
