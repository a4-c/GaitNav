import ARKit

// bounding bbox + depth map + intrinsics -> horizontal distance to the object
class DistanceEstimator {
    
    // scale intrinsics -> sample depth pixels -> reproject to 3D camera coords -> world coords -> horizontal distance
    func getDistance(
        boundingBox: CGRect,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageWidth: Int,
        imageHeight: Int
    ) -> Float? {
        
        // 1. scale intrinsics to depth map resolution
        // depth map is much smaller than camera image
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        let scaleX = Float(depthWidth) / Float(imageWidth)
        let scaleY = Float(depthHeight) / Float(imageHeight)
        
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        
        // 2. determine sampling region
        // mid/far range: centre 60% to avoid background pixels at edges
        // close range: tighter + shifted toward bottom
        let bboxArea = boundingBox.width * boundingBox.height
        
        // close-range threshold based on measured bbox areas:
        // chair at 0.5m -> 0.657, 1.0m -> 0.448, 1.5m -> 0.243
        // midpoint of 1.0m and 1.5m = 0.35
        let closeRangeAreaThreshold: CGFloat = 0.35
        let isCloseRange = bboxArea > closeRangeAreaThreshold
        
        // close range: tighter horizontal margin (0.30 vs 0.20)
        let marginX: CGFloat = isCloseRange ? 0.30 : 0.20
        
        // close range: shift sampling toward bottom of bbox
        // bottom has denser LiDAR values (legs/base), top often catches background
        let bottomMarginY: CGFloat = isCloseRange ? 0.10 : marginX
        let topMarginY: CGFloat    = isCloseRange ? 0.40 : marginX
        
        // trimmed sampling region in Vision normalised coords
        let visionXStart = boundingBox.minX + marginX * boundingBox.width
        let visionXEnd   = boundingBox.maxX - marginX * boundingBox.width
        let visionYStart = boundingBox.minY + bottomMarginY * boundingBox.height
        let visionYEnd   = boundingBox.maxY - topMarginY * boundingBox.height
        
        // Vision portrait coords -> depth map landscape pixels (axis swap + flip)
        let depthXStart = max(0, Int((1 - visionYEnd) * CGFloat(depthWidth)))
        let depthXEnd   = min(depthWidth - 1, Int((1 - visionYStart) * CGFloat(depthWidth)))
        let depthYStart = max(0, Int((1 - visionXEnd) * CGFloat(depthHeight)))
        let depthYEnd   = min(depthHeight - 1, Int((1 - visionXStart) * CGFloat(depthHeight)))
        
        guard depthXStart <= depthXEnd, depthYStart <= depthYEnd else { return nil }
        
        // 3. lock pixel buffers
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthBase = CVPixelBufferGetBaseAddress(depthMap)!
        
        var confBase: UnsafeMutableRawPointer? = nil
        var confBytesPerRow = 0
        if let confidenceMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            confBase = CVPixelBufferGetBaseAddress(confidenceMap)
            confBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        }
        defer {
            if let confidenceMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }
        
        // 4. get camera world position
        let camWorldX = cameraTransform.columns.3.x
        let camWorldZ = cameraTransform.columns.3.z
        
        var horizontalDistances: [Float] = []
        
        // 5. for each pixel in sampling region
        for py in depthYStart...depthYEnd {
            for px in depthXStart...depthXEnd {
                
                // 5a. skip low confidence pixels (keep medium = 1 and high = 2 only)
                if let confBase = confBase {
                    let confOffset = py * confBytesPerRow + px * MemoryLayout<UInt8>.stride
                    let confidence = confBase.load(fromByteOffset: confOffset, as: UInt8.self)
                    if confidence < 1 { continue }
                }
                
                // 5b. read depth, filter out noise (<= 0.1m) and out of range (>= 8.0m)
                let depthOffset = py * depthBytesPerRow + px * MemoryLayout<Float32>.stride
                let z = depthBase.load(fromByteOffset: depthOffset, as: Float32.self)
                guard z > 0.1 && z < 8.0 else { continue }
                
                // 5c. reproject pixel to 3D camera coordinates
                let xCam = (Float(px) - cx) * z / fx
                // image y-down vs ARKit y-up
                let yCam = -((Float(py) - cy) * z / fy)
                // ARKit camera looks toward -Z
                let pointInCamera = SIMD4<Float>(xCam, yCam, -z, 1.0)
                
                // 5d. camera coords -> world coords
                let pointInWorld = cameraTransform * pointInCamera
                
                // 5e. horizontal distance
                let dx = pointInWorld.x - camWorldX
                let dz = pointInWorld.z - camWorldZ
                let horizontalDist = sqrtf(dx * dx + dz * dz)
                
                horizontalDistances.append(horizontalDist)
            }
        }
        
        // 6. pick final distance
        guard !horizontalDistances.isEmpty else { return nil }
        horizontalDistances.sort()
        
        // mid/far range: median
        // close range: 25th percentile (skip background leaking through object gaps)
        let percentileIndex = isCloseRange
            ? horizontalDistances.count / 4
            : horizontalDistances.count / 2
        return horizontalDistances[percentileIndex]
    }
}
