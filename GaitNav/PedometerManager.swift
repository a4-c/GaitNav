import CoreMotion
import Combine

class PedometerManager: ObservableObject {
    
    // CMPedometer 是 CoreMotion 框架中专门负责计步的类
    // 它不是直接读传感器原始数据，而是用 Apple 的算法
    // 把加速度计的振动模式识别为"一步"
    // 比如你拿着手机走路，手机会随身体上下晃动
    // CMPedometer 能从这个晃动模式中准确数出步数
    private let pedometer = CMPedometer()
    
    // 从开始计步到现在，用户一共走了多少步
    @Published var stepCount: Int = 0
    
    // 检查当前设备是否支持计步功能
    var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }
    
    // 开始实时计步
    // 用户每走一步，stepCount 就会自动更新
    // 直到调用 stopCounting() 为止
    func startCounting() {
        
        // 如果设备不支持计步，就打印提示并直接返回
        guard isAvailable else {
            print("Step counting not available on this device.")
            return
        }
        
        // 参数：
        //   from: Date()
        //     Date() 表示"现在这个时刻"
        //     意思是从现在开始计步，之前走的不算
        //     如果你传入一个更早的时间，它也能回溯查询历史步数
        //     但我们只需要实时数据，所以用 Date()
        //
        //   withHandler: { data, error in ... }
        //     系统每次检测到新的一步，就会调用这个闭包
        //     data：CMPedometerData 类型，包含从 from 到现在的步数、距离等
        //     error：如果出了问题（比如用户拒绝了权限），error 不为 nil
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            
            // guard let data = data：
            //   1. 检查 data 是否为 nil（有时候回调可能没有数据）
            //   2. 如果不为 nil，解包成非可选的 data 变量供后面使用
            // error == nil 确保没有发生错误
            // 两个条件都满足才继续，否则打印错误信息并返回
            guard let data = data, error == nil else {
                // error?.localizedDescription 是系统提供的错误描述文字
                // ?? "unknown" 是兜底：如果连错误对象都是 nil，就显示 "unknown"
                print("Pedometer error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            
            // data.numberOfSteps 是从 from 时间到现在的总步数
            // 类型是 NSNumber，不是 Swift 的 Int
            // .intValue 把它转成 Swift 的 Int
            DispatchQueue.main.async {
                self?.stepCount = data.numberOfSteps.intValue
            }
        }
    }
    
    // 停止计步
    // 调用后，系统不再推送步数更新，回调闭包不会再被触发
    func stopCounting() {
        pedometer.stopUpdates()
    }
}
