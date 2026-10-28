import AppKit
import AVFoundation

// F6 싱잉볼 쉼. 근거: intent/F6-싱잉볼/{intent,spec,plan}.md

/// 쉼 한 번: 알림 보류 규칙 (화면과 상관없는 로직)
/// 시간 제한 없음: 그릇을 두드려야 소리가 나므로 사용자가 그만둘 때까지 이어진다.
struct RestSession {
    let start: Date
    /// 보류한 알림(세션 ID, 중복 없음)
    private(set) var held: [String] = []

    enum Route { case hold, small, none }
    /// 쉬는 동안 알림 처리: 끝남·실패는 보류, 승인 대기는 소리 없이 작게, 일하는 중은 알림 없음
    static func route(_ state: AgentSession.State) -> Route {
        switch state {
        case .done, .failed: .hold
        case .waiting: .small
        case .working: .none
        }
    }

    /// 알림을 띄울지 결정한다. 쉬는 중이 아니면 항상 띄우고, 쉬는 중이면 띄우지 않으며 끝남·실패는 보류한다.
    static func shouldAnnounce(_ rest: inout RestSession?, _ s: AgentSession) -> Bool {
        guard rest != nil else { return true }
        if route(s.state) == .hold { rest?.hold(s.id) }
        return false
    }

    mutating func hold(_ sessionID: String) {
        if !held.contains(sessionID) { held.append(sessionID) }
    }
}

/// 싱잉볼 소리 합성. 녹음 음원 없이 비정수배 배음과 맥놀이로 만든다.
final class BowlSynth {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    /// 렌더 스레드와 나누는 값. 각 칸은 한쪽 스레드만 쓴다(치기·사라짐 요청은 카운터로 보내 놓치지 않는다).
    /// [0] 문지르기 목표(메인이 씀), [1] 출력 음량 목표(메인이 씀) · 렌더 스레드 전용: [2] 아직 들어가지 않은 치기, [3] 문지르기 현재, [4] 출력 음량 현재
    private let levels = UnsafeMutablePointer<Float>.allocate(capacity: 5)
    /// [0] 치기 요청 횟수(메인이 씀), [1] 렌더 스레드가 처리한 횟수
    private let strikes = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
    /// 실제 싱잉볼 배음비(약 1 : 2.7 : 5.1 : 8.2), 짝마다 1Hz 안팎 어긋나 맥놀이가 난다
    private static let freqs: [Float] = [176, 176.8, 476, 477.3, 899, 900.6, 1446, 1448.2]
    private static let amps: [Float] = [0.5, 0.5, 0.32, 0.32, 0.16, 0.16, 0.08, 0.08]
    /// 배음마다 사라지는 시간(초): 높은 배음일수록 빨리 사라져 끝소리가 맑게 남는다
    private static let decaySeconds: [Float] = [16, 16, 10, 10, 5, 5, 2.5, 2.5]
    /// 문지르기는 낮은 배음을 주로 울린다
    private static let rubWeights: [Float] = [1, 1, 0.45, 0.45, 0.15, 0.15, 0.05, 0.05]
    /// 배음마다 치기 세기(렌더 스레드 전용)
    private let hits = UnsafeMutablePointer<Float>.allocate(capacity: freqs.count)
    private let phases = UnsafeMutablePointer<Float>.allocate(capacity: freqs.count)
    private let freqPtr = UnsafeMutablePointer<Float>.allocate(capacity: freqs.count)
    private let ampPtr = UnsafeMutablePointer<Float>.allocate(capacity: freqs.count)
    private var configObserver: Any?
    /// 쉬는 중이어야 하는지(장치가 바뀌어 엔진이 멈추면 다시 켠다)
    private var wanted = false

    init() {
        Self.live = self
        levels.initialize(repeating: 0, count: 5)
        strikes.initialize(repeating: 0, count: 2)
        phases.initialize(repeating: 0, count: Self.freqs.count)
        hits.initialize(repeating: 0, count: Self.freqs.count)
        freqPtr.initialize(from: Self.freqs, count: Self.freqs.count)
        ampPtr.initialize(from: Self.amps, count: Self.amps.count)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.wanted, !self.engine.isRunning else { return }
            try? self.engine.start()
        }
    }
    deinit {
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        levels.deallocate(); strikes.deallocate(); phases.deallocate(); hits.deallocate(); freqPtr.deallocate(); ampPtr.deallocate()
    }

    /// 설정의 싱잉볼 소리 크기(0~1, 기본 0.8)
    /// 지금 쓰는 합성기(앱에 하나)
    private static weak var live: BowlSynth?
    static var userVolume: Float {
        get { UserDefaults.standard.object(forKey: "bowlVolume") as? Float ?? 0.8 }
        set {
            UserDefaults.standard.set(newValue, forKey: "bowlVolume")
            if let live, live.isRunning { live.volume = newValue }   // 쉬는 중에도 바로 바뀐다
        }
    }

    var isRunning: Bool { engine.isRunning }
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// 치기 세기가 `seconds` 동안 1/100로 줄도록 하는 표본당 곱셈 값
    static func decayFactor(sampleRate sr: Float, seconds: Float) -> Float { expf(-logf(100) / (seconds * sr)) }

    func start() throws {
        wanted = true
        levels[1] = 1
        if engine.isRunning { return }
        if node == nil {
            let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
            let sr = Float(rate > 0 ? rate : 44_100)
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 1)!
            let levels = levels, strikes = strikes, phases = phases, freqs = freqPtr, amps = ampPtr, hits = hits
            let n = Self.freqs.count
            let decays = UnsafeMutablePointer<Float>.allocate(capacity: n)
            decays.initialize(from: Self.decaySeconds.map { Self.decayFactor(sampleRate: sr, seconds: $0) }, count: n)
            let rubW = UnsafeMutablePointer<Float>.allocate(capacity: n)
            rubW.initialize(from: Self.rubWeights, count: n)
            // 노드와 함께 끝까지 쓰는 값이라 해제하지 않는다(엔진당 한 번만 만든다)
            let attack = 1 - expf(-1 / (0.004 * sr))   // 채로 칠 때 4ms에 걸쳐 올라가 '딱' 소리를 없앤다
            let rubFollow = 1 - expf(-1 / (0.3 * sr))
            let gainFollow = 1 - expf(-1 / (0.05 * sr))
            // 렌더 블록: 미리 잡은 포인터만 쓰고 메모리 할당·잠금이 없다
            let src = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                if strikes[0] != strikes[1] { strikes[1] = strikes[0]; levels[2] = 1 }
                let rubTarget = levels[0], gainTarget = levels[1]
                for i in 0..<Int(frameCount) {
                    let add = levels[2] * attack
                    levels[2] -= add
                    levels[3] += (rubTarget - levels[3]) * rubFollow
                    levels[4] += (gainTarget - levels[4]) * gainFollow
                    let rub = levels[3], gain = levels[4]
                    var sample: Float = 0
                    if (hits[0] > 0.0005 || rub > 0.0005 || add > 0) && gain > 0.0005 {
                        for k in 0..<n {
                            hits[k] = min(hits[k] * decays[k] + add, 1.2)
                            sample += amps[k] * (hits[k] + rub * rubW[k]) * sinf(phases[k])
                            phases[k] += 2 * .pi * freqs[k] / sr
                            if phases[k] > 2 * .pi { phases[k] -= 2 * .pi }
                        }
                    }
                    out[i] = sample * gain * 0.35
                }
                return noErr
            }
            engine.attach(src)
            engine.connect(src, to: engine.mainMixerNode, format: format)
            node = src
        }
        try engine.start()
    }

    /// 소리를 0.15초에 걸쳐 줄인 뒤 엔진을 끈다(뚝 끊기는 소리 방지). 그 사이 다시 `start()`하면 끄지 않는다.
    func fadeOutAndStop() {
        wanted = false
        levels[0] = 0
        levels[1] = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.wanted else { return }
            self.engine.stop()
        }
    }

    /// 바로 끈다(앱 종료·검사용)
    func stop() {
        wanted = false
        engine.stop()
        levels[0] = 0
    }

    func strike() { strikes[0] &+= 1 }

    /// 그릇 중심을 도는 커서 각속도(rad/s)로 문지르기 세기를 정한다
    func rub(angularSpeed: Double) { levels[0] = Float(Self.targetLevel(angularSpeed: angularSpeed)) }

    /// 너무 느리면 울리지 않고, 적당한 속도(약 3 rad/s, 2초에 한 바퀴)에서 가장 크며, 너무 빠르면 줄어든다
    static func targetLevel(angularSpeed w: Double) -> Double {
        let w = abs(w)
        if w < 0.5 { return 0 }
        if w <= 3 { return (w - 0.5) / 2.5 }
        if w <= 9 { return 1 - 0.7 * (w - 3) / 6 }
        return 0.3
    }
}

/// 그릇 그림. 클릭하면 치기, 창 안에서 그릇 둘레를 따라 원을 그리면 문지르기.
final class BowlView: NSView {
    var onStrike: () -> Void = {}
    var onRub: (Double) -> Void = { _ in }
    var onEscape: () -> Void = {}
    var active = false { didSet { needsDisplay = true } }
    private var lastAngle: Double?
    private var lastTime: TimeInterval = 0
    private var speed: Double = 0
    private var idleTimer: Timer?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape() }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override func draw(_ dirtyRect: NSRect) {
        let r = min(bounds.width, bounds.height) / 2 - 10
        let rim = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        NSColor(red: 0.76, green: 0.58, blue: 0.32, alpha: 1).setFill()
        rim.fill()
        let inner = NSBezierPath(ovalIn: CGRect(x: center.x - r * 0.78, y: center.y - r * 0.78, width: r * 1.56, height: r * 1.56))
        NSColor(red: 0.55, green: 0.38, blue: 0.18, alpha: 1).setFill()
        inner.fill()
        if active {
            NSColor(white: 1, alpha: 0.35).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r * 0.9, y: center.y - r * 0.9, width: r * 1.8, height: r * 1.8))
            ring.setLineDash([4, 6], count: 2, phase: 0)
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if active { onStrike() }
    }

    /// 버튼을 누른 채 테두리를 따라 끌어도 문지르기
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    /// 커서 위치는 이 뷰 안에서만 읽는다(전역 감지 없음). 테두리 근처(반지름 55~110%)에서만 문지르기로 본다.
    override func mouseMoved(with event: NSEvent) {
        guard active else { return }
        let p = convert(event.locationInWindow, from: nil)
        let r = Double(min(bounds.width, bounds.height) / 2 - 10)
        let dist = hypot(Double(p.x - center.x), Double(p.y - center.y))
        guard dist > r * 0.55, dist < r * 1.1 else { lastAngle = nil; return }
        let angle = atan2(Double(p.y - center.y), Double(p.x - center.x))
        let now = event.timestamp
        if let last = lastAngle, now > lastTime {
            var d = angle - last
            if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
            let w = d / (now - lastTime)
            speed = speed * 0.7 + abs(w) * 0.3      // 흔들림 줄이기
            onRub(speed)
        }
        lastAngle = angle
        lastTime = now
        // 커서가 멈추면 문지르기를 멈춘다
        idleTimer?.invalidate()
        idleTimer = Ticker.once("싱잉볼 문지르기 멈춤 확인", 0.2) { [weak self] _ in
            self?.speed = 0
            self?.onRub(0)
        }
    }

    override func mouseExited(with event: NSEvent) {
        lastAngle = nil
        speed = 0
        onRub(0)
    }
}

/// 펫 옆 싱잉볼 창: 시간 고르기 → 쉬는 중(남은 시간·그만두기·승인 대기 한 줄) → 끝
final class BowlWindow {
    let panel: FloatingPanel
    let bowl = BowlView(frame: CGRect(x: 30, y: 74, width: 180, height: 180))
    private let stopButton: ClosureButton
    private let waitingButton = ClosureButton("") {}
    private let title = NSTextField(labelWithString: "클릭하거나 테두리를 따라 돌려요")

    /// 창을 열면 바로 쉼이 시작된다(시간 제한 없음). 그만두기·Esc로 끝낸다.
    init(nextTo petFrame: CGRect, in v: CGRect, onStop: @escaping () -> Void, onOpenList: @escaping () -> Void) {
        let size = CGSize(width: 240, height: 290)
        let shown = petFrame.intersection(v).isNull ? petFrame : petFrame.intersection(v)
        var x = shown.midX > v.midX ? shown.minX - size.width - 8 : shown.maxX + 8
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(shown.midY - size.height / 2, v.minY + 8), v.maxY - size.height - 8)
        panel = FloatingPanel(size: size)
        panel.keyable = true            // Esc를 받는다. 바깥 클릭으로는 닫지 않는다(쉼 중 실수 방지)
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)

        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.frame = CGRect(x: 12, y: size.height - 30, width: size.width - 24, height: 16)
        effect.addSubview(title)
        bowl.active = true
        effect.addSubview(bowl)

        stopButton = ClosureButton("그만두기", onStop)
        stopButton.frame = CGRect(x: size.width / 2 - 50, y: 30, width: 100, height: 26)
        effect.addSubview(stopButton)

        waitingButton.isBordered = false
        waitingButton.font = .systemFont(ofSize: 11)
        waitingButton.contentTintColor = .secondaryLabelColor
        waitingButton.handler = onOpenList
        waitingButton.frame = CGRect(x: 8, y: 6, width: size.width - 16, height: 18)
        waitingButton.isHidden = true
        effect.addSubview(waitingButton)

        bowl.onEscape = onStop
        panel.contentView = effect
        panel.makeKeyAndOrderFront(nil)   // Esc를 바로 받도록(앱을 활성화하지 않는 패널)
        panel.makeFirstResponder(bowl)
    }

    func showSoundError() { title.stringValue = "소리를 낼 수 없어요 (출력 장치 확인)" }

    func update(waiting: Int) {
        waitingButton.title = "승인을 기다리는 작업 \(waiting)"
        waitingButton.isHidden = waiting == 0
    }

    func close() { panel.orderOut(nil) }
}
