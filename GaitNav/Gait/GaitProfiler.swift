import Foundation
import Combine

// 步态分析器：让用户走一段路，让自适应步伐检测算法收敛到个性化参数
//
// 解决的问题：
//   不同人的步态差异很大 —— 体重轻的人波峰偏差可能只有 0.05g，体重重的人可能到 0.30g
//   固定阈值无法适应所有人
//   GaitProfiler 通过让用户走一段路，让 EMA（指数移动平均）自然收敛
//   到适合这个人的步态特征参数
//
// 与 GaitCoordinator 的关系：
//   GaitCoordinator 持有自适应状态机（双阈值迟滞 + EMA 动态阈值）
//   GaitProfiler 只是一个控制器：
//     1. 告诉 GaitCoordinator 切换到 profiling 模式（EMA 重置为保守初始值）
//     2. 记录 profiling 期间确认的步数（由 GaitCoordinator 的状态机分发）
//     3. profiling 结束时，接收 GaitCoordinator 当前已收敛的 EMA 值并存入 UserDefaults
//   GaitProfiler 自身不做任何信号处理或波峰检测
//
// 为什么必须在 Calibrator 之前运行：
//   Calibrator 的步长计算依赖准确的计步（步长 = 距离 / 步数）
//   如果检测参数不对，计步就不准，步长也不准
//   profiling 让 EMA 收敛后，Calibrator 才能用准确的步伐检测来计步
class GaitProfiler: ObservableObject {
    
    // =====================================================================
    // UI 状态（@Published 驱动 GaitProfilerView）
    // =====================================================================
    
    // 是否正在进行步态分析
    @Published var isProfiling = false
    
    // profiling 期间确认的步数（由 GaitCoordinator 状态机分发）
    @Published var profilingSteps = 0
    
    // 分析已持续的秒数（驱动 UI 上的计时器和进度环）
    @Published var profilingSeconds = 0
    
    // 状态提示信息，不同阶段显示不同内容
    @Published var statusMessage = ""
    
    // 本次分析得出的波峰偏差 EMA（nil = 还没分析完或分析失败）
    @Published var profiledPeakDevEma: Double? = nil
    
    // 本次分析得出的步间隔 EMA（nil = 还没分析完或分析失败）
    @Published var profiledIntervalEma: TimeInterval? = nil
    
    // =====================================================================
    // 内部数据
    // =====================================================================
    
    // 计时器：每秒更新 profilingSeconds
    private var timer: Timer?
    
    // =====================================================================
    // 持久化
    // =====================================================================
    
    // UserDefaults 的 key
    private let peakDevEmaKey = "profiledPeakDevEma"
    private let intervalEmaKey = "profiledIntervalEma"
    
    // 当前可用的波峰偏差 EMA
    // 没有返回 nil，由 GaitCoordinator 决定用默认值
    var effectivePeakDevEma: Double? {
        let saved = UserDefaults.standard.double(forKey: peakDevEmaKey)
        return saved > 0 ? saved : nil
    }
    
    // 当前可用的步间隔 EMA
    // 没有返回 nil，由 GaitCoordinator 决定用默认值
    var effectiveIntervalEma: TimeInterval? {
        let saved = UserDefaults.standard.double(forKey: intervalEmaKey)
        return saved > 0 ? saved : nil
    }
    
    // 用户是否曾经成功做过步态分析
    // 判断依据是 UserDefaults 中有没有保存过 EMA 值
    var hasEverProfiled: Bool {
        UserDefaults.standard.double(forKey: peakDevEmaKey) > 0
    }
    
    // =====================================================================
    // 回调
    // =====================================================================
    
    // 分析开始 / 结束时通知 GaitCoordinator
    //   onProfilingStarted：GaitCoordinator 切换到 .profiling 模式（重置 EMA 为初始值）
    //   onProfilingStopped：GaitCoordinator 将当前已收敛的 EMA 传给 saveProfile()
    var onProfilingStarted: (() -> Void)?
    var onProfilingStopped: (() -> Void)?
    
    // =====================================================================
    // 初始化
    // =====================================================================
    
    init() {
        // 尝试从 UserDefaults 读取之前保存的分析结果
        let savedPeakDev = UserDefaults.standard.double(forKey: peakDevEmaKey)
        let savedInterval = UserDefaults.standard.double(forKey: intervalEmaKey)
        if savedPeakDev > 0 {
            profiledPeakDevEma = savedPeakDev
            profiledIntervalEma = savedInterval > 0 ? savedInterval : nil
            let intervalStr = savedInterval > 0
                ? ", interval: \(String(format: "%.2f", savedInterval))s"
                : ""
            statusMessage = "Saved peak EMA: \(String(format: "%.3f", savedPeakDev))g\(intervalStr)"
        } else {
            statusMessage = "Not profiled. Using defaults."
        }
    }
    
    // =====================================================================
    // 步伐事件
    // =====================================================================
    
    // GaitCoordinator 在 .profiling 模式下确认一步时调用
    // GaitProfiler 只需要计数，不做任何信号处理
    // （信号处理由 GaitCoordinator 的自适应状态机完成）
    func handleStep() {
        guard isProfiling else { return }
        profilingSteps += 1
    }
    
    // =====================================================================
    // 开始分析
    // =====================================================================
    
    func startProfiling() {
        
        // 重置所有状态
        profilingSteps = 0
        profilingSeconds = 0
        profiledPeakDevEma = nil
        profiledIntervalEma = nil
        isProfiling = true
        statusMessage = "Walk now..."
        
        // 启动计时器：每秒更新一次，驱动 UI 进度环
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.profilingSeconds += 1
        }
        
        // 通知 GaitCoordinator 切换到 profiling 模式
        // GaitCoordinator 会重置 EMA 为初始值，让自适应算法从零开始收敛
        onProfilingStarted?()
    }
    
    // =====================================================================
    // 停止分析
    // =====================================================================
    
    func stopProfiling() {
        
        isProfiling = false
        timer?.invalidate()
        timer = nil
        
        // 通知 GaitCoordinator profiling 结束
        // GaitCoordinator 会调用 saveProfile() 传入当前已收敛的 EMA 值
        onProfilingStopped?()
    }
    
    // =====================================================================
    // 保存分析结果
    // =====================================================================
    
    // 由 GaitCoordinator 在 profiling 结束时调用
    // 接收 GaitCoordinator 自适应状态机当前已收敛的 EMA 值
    func saveProfile(peakDevEma: Double, intervalEma: TimeInterval) {
        
        // 最少需要确认 8 步，确保 EMA 已充分收敛
        // EMA α = 0.2 意味着初始值的残余权重 = (1-0.2)^8 = 0.17
        // 8 步后初始值只剩 17% 的影响，已经基本收敛
        guard profilingSteps >= 8 else {
            statusMessage = "Too few steps (\(profilingSteps)). Walk more actively."
            return
        }
        
        // 合理性检查：波峰偏差应在 (0.02, 1.0) 范围内
        //   < 0.02g：接近传感器噪声，几乎不可能是真步伐
        //   > 1.0g：异常高（合加速度 > 2.0g），可能是传感器故障
        guard peakDevEma > 0.02 && peakDevEma < 1.0 else {
            statusMessage = "Result unreasonable. Please retry."
            return
        }
        
        // 保存到 UserDefaults
        profiledPeakDevEma = peakDevEma
        UserDefaults.standard.set(peakDevEma, forKey: peakDevEmaKey)
        
        if intervalEma > 0.2 && intervalEma < 2.0 {
            profiledIntervalEma = intervalEma
            UserDefaults.standard.set(intervalEma, forKey: intervalEmaKey)
        }
        
        // 构造状态信息
        let intervalStr = profiledIntervalEma != nil
            ? ", interval: \(String(format: "%.2f", profiledIntervalEma!))s"
            : ""
        statusMessage = "Done! \(profilingSteps) steps → peak EMA: \(String(format: "%.3f", peakDevEma))g\(intervalStr)"
    }
}
