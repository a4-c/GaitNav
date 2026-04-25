import SwiftUI

// 引导用户走一段路来测量个人步长
//
// 以 sheet 的形式从主界面底部滑上来
// 用户完成标定后可以点"Done"关闭，或者直接下滑关闭
//
// 流程：
//   1. 用户看到说明文字和"Start"按钮
//   2. 点击 Start → 记录起点，开始计步
//   3. 用户直线走路，界面实时显示步数
//   4. 用户点击 Stop → 记录终点，计算步长
//   5. 显示结果，用户点"Done"返回主界面
struct CalibrationView: View {
    
    // @ObservedObject：观察但不拥有这个对象
    // 和 @StateObject 的区别：
    //   @StateObject：我创建并拥有它，我消失了它也跟着销毁
    //                 用在 ContentView 里，因为 ContentView 是 Calibrator 的主人
    //   @ObservedObject：别人创建的，我只是用一下
    //                    用在 CalibrationView 里，因为 Calibrator 是 ContentView 传过来的
    // 效果是一样的：Calibrator 里的 @Published 属性变了，界面会自动刷新
    @ObservedObject var calibrator: Calibrator
    
    // Environment 是 SwiftUI 的"环境变量"系统
    // \.dismiss 是系统提供的一个环境值，类型是 DismissAction
    // 调用 dismiss() 可以关闭当前的 sheet 页面
    // 系统会自动把 ContentView 里的 showCalibration 设回 false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        
        // VStack：垂直排列，spacing 是子元素之间的间距
        VStack(spacing: 24) {
            
            // ===================================================================
            // 标题区域
            // ===================================================================
            
            Text("Step Length Calibration")
                .font(.title)
                .fontWeight(.bold)
            
            // 说明文字
            // multilineTextAlignment(.center) 让多行文字居中对齐
            // .foregroundColor(.gray) 用灰色，表示这是辅助说明，不是主要内容
            Text("Tap Start, walk in a straight line, then tap Stop. The app will measure your step length.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            // ===================================================================
            // 状态信息区域
            // ===================================================================
            
            // 显示 calibrator.statusMessage 的内容
            // 这个文字在标定的不同阶段会自动变化（因为是 @Published）
            Text(calibrator.statusMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()
                // frame(maxWidth: .infinity) 让这个区域占满整行宽度
                // 这样背景色不会只包住文字那么窄
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            
            // ===================================================================
            // 标定过程中：大字显示步数
            // ===================================================================
            
            // 只在 isCalibrating == true 时显示
            // 大字号是为了让用户走路时余光能看到数字在涨
            // 确认系统在正常工作
            if calibrator.isCalibrating {
                Text("\(calibrator.calibrationSteps)")
                    // .system(size:weight:) 自定义字号和粗细
                    // 72 号字，加粗
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.blue)
                Text("steps")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            // ===================================================================
            // 标定结果展示
            // ===================================================================
            
            // 只在标定完成后显示（两个值都不为 nil）
            // if let 是 Swift 的"可选绑定"：
            //   如果 calibratedStepLength 不是 nil，解包赋给 stepLength
            //   如果 calibrationDistance 不是 nil，解包赋给 distance
            //   两个都成功才进入 if 块
            if let stepLength = calibrator.calibratedStepLength,
               let distance = calibrator.calibrationDistance {
                VStack(spacing: 8) {
                    Text("Distance: \(String(format: "%.1f", distance))m")
                    Text("Steps: \(calibrator.calibrationSteps)")
                    // 步长是最重要的结果，加粗突出
                    Text("Step length: \(String(format: "%.2f", stepLength))m/step")
                        .fontWeight(.bold)
                }
                .font(.body)
                .padding()
                // 绿色背景表示"成功"
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Spacer 把按钮推到底部
            // 这样不管上面的内容多少，按钮始终在屏幕下方
            // 方便用户走路时单手操作
            Spacer()
            
            // ===================================================================
            // 操作按钮
            // ===================================================================
            
            // 根据 isCalibrating 显示不同的按钮
            // 这是一个简单的状态机：
            //   isCalibrating == false → 显示 Start（蓝色）
            //   isCalibrating == true → 显示 Stop（红色）
            if calibrator.isCalibrating {
                // 正在标定 → 显示红色的 Stop 按钮
                Button(action: {
                    calibrator.stopCalibration()
                }) {
                    Text("Stop")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        // frame(maxWidth: .infinity) 让按钮占满整行宽度
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
            } else {
                // 未在标定 → 显示蓝色的 Start 按钮
                Button(action: {
                    calibrator.startCalibration()
                }) {
                    Text("Start")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                
                // 如果已经有标定结果，显示"Done"按钮让用户返回主界面
                // 没有标定结果时不显示，避免用户还没标定就离开
                if calibrator.calibratedStepLength != nil {
                    Button("Done") {
                        // 调用 dismiss() 关闭这个 sheet
                        // ContentView 里的 showCalibration 会自动变回 false
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 32)
    }
}
