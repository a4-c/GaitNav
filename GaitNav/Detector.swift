import Vision
import CoreML
import UIKit

class Detector {
    // VNCoreMLModel 是 Vision 框架对 CoreML 模型的包装
    // 有了它，Vision 才知道怎么把图片喂给模型
    private var vnModel: VNCoreMLModel?
    
    init() {
        // 创建时自动加载模型
        setupModel()
    }
    
    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            // .all 表示让系统自动选择最快的计算单元（CPU、GPU 或 Neural Engine）
            config.computeUnits = .all
            
            // yolov8n 是 Xcode 根据导入的 .mlpackage 自动生成的类
            // 名字就是你的模型文件名，首字母小写
            let coreMLModel = try yolov8s(configuration: config).model
            
            // 把 CoreML 模型包装成 Vision 能用的格式
            vnModel = try VNCoreMLModel(for: coreMLModel)
        } catch {
            print("Failed to load model: \(error)")
        }
    }
    
    // 核心方法：接收一帧画面，返回检测结果
    // CVPixelBuffer 就是摄像头捕获的原始图像数据
    // @escaping 表示这个闭包（回调函数）会在方法返回之后才执行
    func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection]) -> Void) {
        // 如果模型没加载成功，直接返回空数组
        guard let vnModel = vnModel else {
            completion([])
            return
        }
        
        // 创建一个 Vision 请求：把这张图喂给模型，处理完后执行大括号里的代码
        let request = VNCoreMLRequest(model: vnModel) { request, error in
            // 尝试把结果转成 VNRecognizedObjectObservation 数组
            // 每个 observation 代表模型检测到的一个物体
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            // compactMap：对数组中每个元素做转换，自动丢弃返回 nil 的元素
            let detections = results.compactMap { observation -> Detection? in
                // 每个物体可能有多个候选标签，取置信度最高的第一个
                guard let topLabel = observation.labels.first else { return nil }
                // 只保留置信度超过 50% 的结果，过滤掉不太确定的
                guard topLabel.confidence > 0.5 else { return nil }
                
                return Detection(
                    label: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            
            // 把结果通过回调返回
            completion(detections)
        }
        
        // 告诉 Vision 怎么处理图片尺寸：缩放填满，不留黑边
        request.imageCropAndScaleOption = .scaleFill
        
        // 创建图片处理器，把摄像头画面和请求绑在一起
        // orientation: .up 表示图片是正向的
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        // 执行请求，try? 表示如果出错就静默忽略
        try? handler.perform([request])
    }
}
