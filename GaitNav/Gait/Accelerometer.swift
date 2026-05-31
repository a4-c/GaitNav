import CoreMotion
import Foundation

// 加速度计：封装 CoreMotion 的采样细节，把原始三轴数据转换成合加速度
//
// 职责：
//   1. 拥有 CMMotionManager，统一管理加速度计生命周期
//   2. 按配置的固定频率采集三轴加速度
//   3. 将方向无关的合加速度和采样时间交给上层步伐检测器
//
// 这个类型不判断是否检测到步伐，也不知道 profiling、calibration 或 live 模式
final class Accelerometer {
    
    // CMMotionManager：运动传感器管理器
    // 它是访问加速度计的入口
    private let motionManager = CMMotionManager()
    
    // 加速度计采样间隔由步伐检测配置统一提供，避免硬编码散落在采集层
    private let updateInterval: TimeInterval
    
    // 当前加速度计是否在运行
    private(set) var isRunning = false
    
    // 当前设备是否提供加速度计硬件
    var isAvailable: Bool {
        // 直接转发 CoreMotion 的硬件能力检查，供编排层在重置检测状态前提前返回
        return motionManager.isAccelerometerAvailable
    }
    
    // 初始化时接收采样间隔，让采集层只关心 CoreMotion 生命周期
    init(updateInterval: TimeInterval) {
        // 保存调用方传入的采样间隔，启动采集时再写入 CMMotionManager
        self.updateInterval = updateInterval
    }
    
    // 启动加速度计并开始输出合加速度
    func start(onMagnitudeReceived: @escaping (_ magnitude: Double, _ timestamp: Date) -> Void) {
        
        // 防止重复启动
        guard !isRunning else { return }
        
        // 检查设备是否有加速度计
        guard motionManager.isAccelerometerAvailable else { return }
        
        // 记录采集器已经启动，确保后续重复调用不会注册多个回调
        isRunning = true
        
        // 设置采样间隔：每次读取加速度数据的时间间隔
        motionManager.accelerometerUpdateInterval = updateInterval
        
        // 开始接收加速度计数据，直到调用 stopAccelerometerUpdates() 为止
        // to: .main：指定回调在主线程执行
        // withHandler: { data, error in ... }：
        //   这个闭包每 0.05 秒被调用一次
        //   这里的 0.05 秒来自 StepDetectionConfiguration 中统一保存的 20Hz 采样间隔
        //   data：CMAccelerometerData 类型，包含本次采样的加速度值
        //     data.acceleration.x / .y / .z 分别是三个方向的加速度（单位是 g）
        //   error：如果出错，这里不是 nil
        motionManager.startAccelerometerUpdates(to: .main) { data, error in
            // 没有拿到本次采样数据时直接忽略，等待下一次 CoreMotion 回调
            guard let data = data else { return }
            
            // 计算合加速度（magnitude）
            // 它表示三个方向加速度的总和
            // 不管手机怎么放，合加速度都只反映"总加速度的大小"
            // 静止时始终 ≈ 1.0（因为重力），走路时 > 1.0
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let magnitude = sqrt(x * x + y * y + z * z)
            
            // 把方向无关的合加速度和采样时间交给上层检测器处理
            onMagnitudeReceived(magnitude, Date())
        }
    }
    
    // 停止加速度计
    func stop() {
        // 没有运行时不需要重复停止 CoreMotion
        guard isRunning else { return }
        // 加速度计停止采集数据，之前注册的回调闭包不再被触发
        motionManager.stopAccelerometerUpdates()
        // 清除运行标记，允许之后在模式切换时重新启动
        isRunning = false
    }
}
