import Foundation

// 步伐检测档案：保存可以由 profiling 学习和持久化的两个 EMA 值
struct StepDetectionProfile {
    // 波峰偏差 EMA 用于推导动态高低阈值
    let peakDevEma: Double
    // 步间隔 EMA 用于推导动态防抖间隔
    let intervalEma: TimeInterval
}

// 自适应步伐检测器：使用双阈值迟滞状态机和 EMA 动态阈值确认有效步伐
//
// 步伐检测算法：双阈值迟滞状态机 + EMA 动态阈值
//   核心思想：
//     - 用指数移动平均（EMA）持续追踪近期波峰的强度，从中推导出自适应阈值
//     - 用双阈值迟滞（Schmitt trigger）防止信号在阈值附近抖动造成重复计数
//     - 用 EMA 追踪步间隔，动态调整最小步间隔（防抖）
//   所有检测参数都是信号处理比率，不依赖特定个体的步态特征
//   详见 "信号处理参数" 区域的注释
struct AdaptiveStepDetector {
    
    // 检测算法的固定参数统一来自配置对象
    private let configuration: StepDetectionConfiguration
    
    // =====================================================================
    // 自适应步伐检测：状态机
    // =====================================================================
    //
    // 双阈值迟滞（Schmitt trigger）状态机
    //   比简单的"local max > threshold"更鲁棒
    //   信号必须先升至 TH_HIGH 以上，再回落至 TH_LOW 以下，才算确认一个波峰
    //   这天然防止了信号在阈值附近的小幅抖动造成的重复计数
    //
    //   状态转换：
    //     waitingPeak -> (偏差 > TH_HIGH) -> peakTracking
    //     peakTracking -> (偏差 < TH_LOW) -> waitingPeak（确认一步）
    //     peakTracking 期间持续追踪最大偏差值，用于更新 EMA
    
    // 状态机的两个状态
    private enum PeakDetectionState {
        case waitingPeak   // 等待信号升至上阈值
        case peakTracking  // 正在追踪一个波峰，记录最大偏差
    }
    
    // 当前状态
    private var peakState: PeakDetectionState = .waitingPeak
    
    // peakTracking 状态下追踪到的最大偏差（重力基线以上的部分）
    // 当信号回落至 TH_LOW 以下时，这个值就是本次波峰的确认偏差
    private var trackingMaxDev: Double = 0
    
    // =====================================================================
    // 自适应步伐检测：EMA 动态阈值
    // =====================================================================
    //
    // 指数移动平均（EMA）持续追踪两个量：
    //   1. peakDevEma：近期步伐波峰的平均偏差（合加速度超过重力基线的部分）
    //      → 从中推导出 TH_HIGH 和 TH_LOW
    //   2. intervalEma：近期步伐的平均时间间隔
    //      → 从中推导出最小步间隔（防抖）
    //
    // EMA 更新公式：ema = α × 新值 + (1−α) × 旧值
    // 其中 α = 0.2，代表最近 ~5 次观测贡献约 63% 的权重
    //
    // 初始值来自 GaitProfiler 的保存结果（如果做过 profiling）
    // 否则使用保守的默认值，系统会在用户走的前几步内自动收敛
    
    // 波峰偏差的 EMA（单位：g，相对于重力基线）
    // 代表"用户近期步伐波峰的平均强度"
    private var peakDevEma: Double
    
    // 步伐间隔的 EMA（单位：秒）
    // 代表"用户近期步伐的平均周期"
    private var intervalEma: TimeInterval
    
    // 上一次成功检测到步伐的时间
    // 用于计算步间隔和防抖
    // .distantPast 代表一个极其遥远的过去时间
    //   这样第一步检测时：
    //     now.timeIntervalSince(.distantPast) = 一个巨大的正数
    //     肯定 > 最小步间隔
    //     所以第一步不会被误拦
    private var lastStepTime: Date = .distantPast
    
    // 上一次确认波峰的时间（用于静止衰减判断）
    private var lastPeakConfirmTime: Date = .distantPast
    
    // 初始化检测器，并允许调用方注入 profiling 保存的 EMA
    init(configuration: StepDetectionConfiguration = StepDetectionConfiguration(), profile: StepDetectionProfile? = nil) {
        // 保存固定配置，后续所有阈值都从同一组参数推导
        self.configuration = configuration
        // 有 profiling 档案时使用个性化波峰 EMA，否则使用保守默认值
        self.peakDevEma = profile?.peakDevEma ?? configuration.defaultPeakDevEma
        // 有 profiling 档案时使用个性化步间隔 EMA，否则使用保守默认值
        self.intervalEma = profile?.intervalEma ?? configuration.defaultIntervalEma
    }
    
    // 当前已经收敛的 EMA 档案，profiling 结束时由 GaitCoordinator 读取并保存
    var currentProfile: StepDetectionProfile {
        // 返回值类型只包含可持久化参数，不暴露状态机的瞬时状态
        return StepDetectionProfile(peakDevEma: peakDevEma, intervalEma: intervalEma)
    }
    
    // =====================================================================
    // 动态阈值（从 EMA 实时计算）
    // =====================================================================
    
    // 上阈值：信号偏差超过此值 → 进入 peakTracking 状态
    // 由于衰减逻辑保证 peakDevEma ≥ defaultPeakDevEma (0.05)
    // TH_HIGH 最低 = 1.0 + 0.05 × 0.7 = 1.035，不需要额外下限
    private var thresholdHigh: Double {
        // 根据当前波峰 EMA 实时计算进入波峰追踪状态的高阈值
        configuration.gravityBaseline + peakDevEma * configuration.peakThresholdRatio
    }
    
    // 下阈值：信号偏差低于此值 → 确认波峰，回到 waitingPeak 状态
    private var thresholdLow: Double {
        // 在高阈值基础上应用迟滞比率，避免阈值附近的小幅抖动重复触发
        configuration.gravityBaseline + peakDevEma * configuration.peakThresholdRatio * configuration.hysteresisRatio
    }
    
    // 动态最小步间隔：从步间隔 EMA 实时计算
    private var effectiveMinStepInterval: TimeInterval {
        // 同时应用动态比例和物理下限，防止短时间内把同一步重复计数
        max(intervalEma * configuration.intervalGuardRatio, configuration.minAbsoluteInterval)
    }
    
    // 每个加速度计采样到达时调用
    // 实现双阈值迟滞状态机 + EMA 动态阈值
    mutating func process(magnitude: Double, at now: Date) -> Bool {
        // 默认认为本次采样没有完成一个有效步伐
        var didConfirmStep = false
        
        // 双阈值迟滞状态机
        switch peakState {
            
        case .waitingPeak:
            // 等待信号升至上阈值（TH_HIGH）
            // 合加速度超过 thresholdHigh → 进入 peakTracking 状态
            if magnitude > thresholdHigh {
                peakState = .peakTracking
                trackingMaxDev = magnitude - configuration.gravityBaseline
            }
            
        case .peakTracking:
            // 正在追踪波峰，持续记录最大偏差
            let currentDev = magnitude - configuration.gravityBaseline
            if currentDev > trackingMaxDev {
                trackingMaxDev = currentDev
            }
            
            // 信号回落至下阈值（TH_LOW）以下 → 确认一个完整的波峰
            // trackingMaxDev 就是这次波峰的峰值偏差
            if magnitude < thresholdLow {
                didConfirmStep = confirmPeak(peakDeviation: trackingMaxDev, at: now)
                peakState = .waitingPeak
            }
        }
        
        // 静止衰减：长时间没有确认波峰 → 缓慢降低 EMA
        // 防止高强度走路后突然放慢导致阈值过高，新的轻步伐无法被检测到
        checkDecay(at: now)
        
        // 只有通过波峰确认和步间隔防抖的采样才向上层报告一步
        return didConfirmStep
    }
    
    // 波峰确认后的处理：更新 EMA、检查步间隔、分发步伐事件
    private mutating func confirmPeak(peakDeviation: Double, at now: Date) -> Bool {
        
        // 更新波峰偏差 EMA：追踪近期步伐的平均强度
        // EMA 公式：ema = α × 新值 + (1−α) × 旧值
        peakDevEma = configuration.emaAlpha * peakDeviation + (1 - configuration.emaAlpha) * peakDevEma
        
        // 记录波峰确认时间（用于静止衰减判断）
        lastPeakConfirmTime = now
        
        // 最小步间隔检查（防抖）
        // 如果距上一步时间太短，这个波峰是同一步的弹跳而非新步伐
        let interval = now.timeIntervalSince(lastStepTime)
        guard interval > effectiveMinStepInterval else { return false }
        
        // 更新步间隔 EMA（仅在合理范围内更新，防止停顿期间的超长间隔污染 EMA）
        if interval > configuration.minAbsoluteInterval && interval < 2.0 {
            intervalEma = configuration.emaAlpha * interval + (1 - configuration.emaAlpha) * intervalEma
        }
        
        // 记录这一步的时间
        lastStepTime = now
        
        // 返回 true，通知 GaitCoordinator 分发本次确认步伐
        return true
    }
    
    // 静止衰减：防止高阈值锁死
    // 场景：用户快走（EMA 升高 → 阈值升高）→ 突然慢走或停下
    //   如果 EMA 不衰减，阈值会卡在高位，轻步伐永远达不到阈值
    //   → EMA 永远不更新 → 系统锁死
    // 衰减机制打破这个死锁：超时后将 EMA 缓慢向默认值靠拢
    private mutating func checkDecay(at now: Date) {
        // 使用传入的采样时间计算静止时长，保证算法可以被确定性测试
        let timeSinceLastPeak = now.timeIntervalSince(lastPeakConfirmTime)
        // 超过静止超时且 EMA 仍高于默认值 → 逐步衰减
        // 每个采样周期衰减 0.2%（与 EMA α = 0.2 对应的每采样微调）
        // 在 20Hz 采样率下：
        //   1 秒后（20 采样）：0.998^20 = 0.961 → 衰减 4%
        //   5 秒后（100 采样）：0.998^100 = 0.819 → 衰减 18%
        //   足够缓慢，不会在短暂停顿时破坏已收敛的 EMA
        if timeSinceLastPeak > configuration.decayTimeout && peakDevEma > configuration.defaultPeakDevEma {
            peakDevEma = max(peakDevEma * 0.998, configuration.defaultPeakDevEma)
        }
    }
    
    // 重置状态机
    // 在模式切换时调用，避免上一个模式的残留状态影响新模式
    mutating func resetDetectionState() {
        peakState = .waitingPeak
        trackingMaxDev = 0
        lastStepTime = .distantPast
        lastPeakConfirmTime = .distantPast
    }
    
    // 应用 profiling 保存的个性化 EMA，并清理上一个模式留下的瞬时状态
    mutating func applyProfile(_ profile: StepDetectionProfile) {
        // 使用保存的波峰 EMA 恢复个性化检测阈值
        peakDevEma = profile.peakDevEma
        // 使用保存的步间隔 EMA 恢复个性化防抖间隔
        intervalEma = profile.intervalEma
        // 清理状态机瞬时状态，避免模式切换时继承未完成波峰
        resetDetectionState()
    }
    
    // 恢复保守默认 EMA，供 profiling 从统一起点重新学习
    mutating func resetToDefaultProfile() {
        // 将波峰 EMA 恢复为适用于首次使用的保守默认值
        peakDevEma = configuration.defaultPeakDevEma
        // 将步间隔 EMA 恢复为每秒两步的默认值
        intervalEma = configuration.defaultIntervalEma
        // 清理状态机瞬时状态，让 profiling 从干净状态开始
        resetDetectionState()
    }
}
