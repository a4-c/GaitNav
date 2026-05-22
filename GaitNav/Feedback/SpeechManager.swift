import AVFoundation

// 语音播报管理器：封装 AVSpeechSynthesizer，提供简洁的 TTS 接口
//
// 职责：
//   1. 把文字转成语音念出来
//   2. 管理播报队列：避免重叠、提供打断策略
//   3. 配置语音参数：语速、语言、音调
//
// 使用方式：
//   speechManager.speak("Person, 3 steps ahead")
//   speechManager.speakInterrupting("Warning, obstacle 1 step")
class SpeechManager: NSObject {
    
    // AVSpeechSynthesizer：iOS 系统自带的文字转语音引擎
    private let synthesizer = AVSpeechSynthesizer()
    
    // 语音配置
    // 使用英语（可以之后根据系统语言自动切换）
    private let voiceLanguage = "en-US"
    
    // 语速：0.0（最慢）到 1.0（最快）
    // 视障用户通常习惯偏快的语速（0.5-0.6），因为他们日常大量使用 VoiceOver
    // 但对于障碍物警告，略慢一点（0.5）更容易听清关键信息
    private let speechRate: Float = 0.5
    
    // 音调：0.5（低）到 2.0（高），1.0 是默认
    private let speechPitch: Float = 1.0
    
    // 当前是否正在播报
    // 通过 AVSpeechSynthesizerDelegate 回调来维护这个状态
    private(set) var isSpeaking: Bool = false
    
    override init() {
        
        super.init()
        
        // 设置代理，用于追踪播报状态（开始、结束、取消）
        synthesizer.delegate = self
        
        // 配置音频会话
        // 确保 TTS 能和 ARKit 的音频共存，不会互相打断
        configureAudioSession()
    }
    
    // 配置音频会话
    // AVAudioSession 是 iOS 的音频管理中枢
    // 多个音频源（ARKit、TTS、系统音效）需要通过它来协调
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // .playback：表示"我要播放音频给用户听"
            //   和 .ambient 的区别：
            //     .ambient = 混合播放，静音键有效（适合游戏音效）
            //     .playback = 独占播放，静音键无效（适合语音导航）
            //   视障辅助 app 应该用 .playback，因为用户依赖语音反馈
            //   不能因为静音键就断掉
            //
            // .duckOthers：当 TTS 播报时，压低其他 app 的音量
            //   比如用户在听音乐，播报时音乐会自动变小声
            //   播报结束后音乐恢复原音量
            //   比 .mixWithOthers 好，因为保证了播报的可听性
            try session.setCategory(.playback, options: [.duckOthers])
            
            // 激活音频会话
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    // 普通播报：如果当前正在播报，跳过这次请求
    // 适用于常规信息更新（"person, 3 steps"）
    // 不打断正在播报的内容，避免语音碎片化
    func speak(_ text: String) {
        // 正在说话就不打断，等说完再接受新的
        guard !synthesizer.isSpeaking else { return }
        
        performSpeech(text)
    }
    
    // 打断式播报：停掉当前正在播报的内容，立刻播报新内容
    // 适用于紧急情况（"Warning! Obstacle 1 step ahead"）
    func speakInterrupting(_ text: String) {
        // .immediate：立刻停止当前播报，不等当前词说完
        //   和 .word 的区别：
        //     .word = 把当前这个词说完再停
        //     .immediate = 直接切断
        //   紧急警告场景用 .immediate，因为每一毫秒都重要
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        performSpeech(text)
    }
    
    // 停止所有播报
    // 比如 app 进入后台、用户手动静音等场景
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // 创建语音请求并交给 synthesizer 播报
    private func performSpeech(_ text: String) {
        
        // AVSpeechUtterance：一条待播报的语音内容
        // 它封装了"说什么"+"怎么说"（语速、音调、语言等）
        let utterance = AVSpeechUtterance(string: text)
        
        // 设置语音：指定语言和口音
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        
        // 语速
        utterance.rate = speechRate
        
        // 音调
        utterance.pitchMultiplier = speechPitch
        
        // preUtteranceDelay：开始播报前的等待时间
        // 设为 0，因为导航场景需要即时反馈
        utterance.preUtteranceDelay = 0
        
        // postUtteranceDelay：播报结束后到下一条之间的间隔
        // 设为 0，间隔由上层的冷却机制控制，不在这里管
        utterance.postUtteranceDelay = 0
        
        // 把这条语音交给 synthesizer 播报
        // 如果当前没有在播报，会立刻开始
        // 如果队列里还有其他条目，会排在后面（但我们通常不会排队，上面已经做了过滤）
        synthesizer.speak(utterance)
    }
}

// AVSpeechSynthesizerDelegate：追踪播报生命周期
// 用于维护 isSpeaking 状态
extension SpeechManager: AVSpeechSynthesizerDelegate {
    
    // 开始播报时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }
    
    // 播报正常结束时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    
    // 播报被取消时调用（比如调用了 stopSpeaking）
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
