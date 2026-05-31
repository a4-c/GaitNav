import Foundation

// 步伐检测配置：集中保存自适应步伐检测算法使用的固定参数
//
// 职责：
//   1. 保存加速度计采样间隔
//   2. 保存双阈值迟滞状态机使用的信号处理比率
//   3. 保存 EMA 的默认值和静止衰减参数
//
// 这个类型只描述参数，不保存运行时状态，也不执行任何检测逻辑
struct StepDetectionConfiguration {
    
    // 设置采样间隔：每次读取加速度数据的时间间隔
    // 1.0 / 20.0 = 0.05 秒 = 50 毫秒
    // 也就是每秒采样 20 次（20Hz）
    let accelerometerUpdateInterval: TimeInterval = 1.0 / 20.0
    
    // =====================================================================
    // 信号处理参数（比率，非绝对值）
    // =====================================================================
    //
    // 以下参数全部是信号处理领域的标准比率
    // 它们相对于用户自身的信号，不依赖任何特定个体的步态特征
    // 因此不需要通过实验来确定，可以直接引用信号处理文献
    
    // 重力基线：静止时合加速度的值
    // 这是物理常数（1g），不是可调参数
    let gravityBaseline: Double = 1.0
    
    // EMA 平滑因子：每次更新时新值的权重
    // α = 0.2 是指数平滑的标准选择
    // 含义：初始值的残余权重 = (1−α)^n
    //   5 步后：(0.8)^5 = 0.33 → 初始值只剩 33% 影响
    //   10 步后：(0.8)^10 = 0.11 → 基本收敛
    // 平衡了响应速度（快速适应步态变化）和稳定性（不因单步异常而跳变）
    let emaAlpha: Double = 0.2
    
    // 阈值比率：TH_HIGH = gravityBaseline + peakDevEma × peakThresholdRatio
    // 将检测阈值设为近期平均波峰强度的 70%
    // 含义：步伐加速度的步间变异系数约 20-30%
    //   阈值设在均值的 70%，大约位于均值 − 1σ
    //   理论上能捕获 ~84% 的步伐（单侧正态分布）
    //   加上 EMA 持续适应，实际捕获率更高
    // 参考：Pan & Tompkins (1985) 使用同族方法设定自适应阈值
    let peakThresholdRatio: Double = 0.7
    
    // 迟滞比率：TH_LOW = TH_HIGH × hysteresisRatio
    // 标准 Schmitt trigger 设计使用 40-60% 的迟滞带
    // 0.6 意味着信号必须回落到 TH_HIGH 的 60% 以下才确认波峰结束
    // 这保证了一个完整的"升—降"起伏，避免小幅抖动重复触发
    let hysteresisRatio: Double = 0.6
    
    // 步间隔保护比率：minStepInterval = intervalEma × intervalGuardRatio
    // 将最小步间隔设为平均步周期的 70%
    // 含义：正常步频自然波动约 ±15%，最快步伐约为均值的 85%
    //   70% 留出了足够余量，只拦截明显的同步弹跳（bounce）
    let intervalGuardRatio: Double = 0.7
    
    // 最小步间隔绝对下限（单位：秒）
    // 基于人类短跑的运动学数据：
    // Tyson Gay 在 2009 年世锦赛 100m 决赛中达到 4.68 步/秒（0.214 秒/步）
    // 0.2 秒略低于此极限，确保即使是顶级短跑运动员的步伐也不会被误拦
    // 数据来源：Pose Method 对 Berlin 2009 世锦赛的运动学分析
    // 这是任何步频都不可能低于的物理下限
    let minAbsoluteInterval: TimeInterval = 0.2
    
    // 静止衰减超时（单位：秒）
    // 如果超过此时间没有确认任何波峰，开始将 EMA 向默认值衰减
    // 2 秒 ≈ 4 个正常步周期（0.5s × 4），足以确认用户已停止走路
    let decayTimeout: TimeInterval = 2.0
    
    // EMA 默认值：未做 profiling 时的保守初始值
    // peakDevEma = 0.05g → 对应 TH_HIGH = 1.035g（能检测大多数人的步伐）
    // intervalEma = 0.5s → 对应正常步频 2 步/秒
    // defaultPeakDevEma 同时也是阈值的绝对下限：
    //   衰减逻辑确保 peakDevEma 永远不会低于此值
    //   → TH_HIGH 最低 = 1.0 + 0.05 × 0.7 = 1.035g
    //   → 远高于静止状态下的传感器噪声（约 0.01-0.02g RMS）
    //   → 不需要额外的绝对下限参数
    let defaultPeakDevEma: Double = 0.05
    let defaultIntervalEma: TimeInterval = 0.5
}
