import ARKit

// 距离估算器：利用 LiDAR 深度图计算检测物体到相机的水平距离
//
// 整体流程：
//   1. 缩放相机内参，适配深度图分辨率
//   2. 确定采样区域（检测框中间60%）
//   3. 遍历区域内每个像素，过滤低置信度和无效深度
//   4. 反投影到3D空间，转换到世界坐标系
//   5. 计算水平距离，取中位数
class DistanceEstimator {
    
    // 计算某个物体到相机的水平距离
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
    func getDistance(
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
}
