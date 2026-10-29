import AppKit
import SceneKit
import Metal

// F18 3D 메인 캐릭터(곰). 모션은 '상황 → 목표 자세'를 스프링으로 따라가게 해서 자연스럽게 섞인다.
// 근거: intent/F18-3D-캐릭터/. 모델 파일이 오기 전에는 도형 곰(ProceduralBear).

/// 감쇠 스프링 하나(순수, 자체 검사 대상)
struct Spring {
    var value: Double = 0
    var velocity: Double = 0
    var stiffness: Double = 120
    var damping: Double = 14

    mutating func step(to target: Double, dt: Double) {
        // 프레임이 늦어도 터지지 않게 잘게 나눠 적분
        let n = max(1, Int(ceil(dt / (1.0 / 120))))
        let h = dt / Double(n)
        for _ in 0..<n {
            velocity += (stiffness * (target - value) - damping * velocity) * h
            value += velocity * h
        }
    }
}

/// 곰의 관절 목표 값(라디안·배율·높이)
struct BearPose {
    var bodyTilt = 0.0      // 좌우 기울기(z)
    var bodyTurn = 0.0      // 돌아서기(y)
    var bodyRoll = 0.0      // 앞뒤 구르기(x)
    var lift = 0.0          // 뛰어오름(높이, 몸 높이 단위)
    var squash = 1.0        // 세로 배율(가로는 부피 보존)
    var headYaw = 0.0
    var headPitch = 0.0     // +면 고개 숙임
    var armL = 0.0, armR = 0.0   // 0 = 내림, +면 바깥으로 들어 올림
    var ears = 0.0          // +면 처짐
    var eyes = 1.0          // 눈 세로 배율(감기 0.1, 웃음 0.45, 놀람 1.25)
    var tail = 0.0

    static let headYawLimit = 25.0 * .pi / 180
}

/// 상황 → 목표 자세(순수). t = 이 상황이 시작된 뒤 초, look = 커서 방향(-1...1), reduce = 동작 줄이기.
enum BearMotion {
    static func pose(_ s: Situation, t: Double, look: CGPoint, lean: Double, facingRight: Bool, reduce: Bool) -> BearPose {
        var p = BearPose()
        let big = reduce ? 0.0 : 1.0
        let breathe = 1 + 0.02 * sin(2 * .pi * t / 3.5)
        p.squash = breathe
        p.headYaw = Double(look.x) * BearPose.headYawLimit
        p.headPitch = -Double(look.y) * 0.25
        p.bodyTilt = -lean * 0.1
        if lean != 0 { p.headYaw = lean * BearPose.headYawLimit }
        switch s {
        case .idle, .friend:
            // 30초마다 한 번 두리번(왼쪽 → 오른쪽)
            let g = t.truncatingRemainder(dividingBy: 30)
            if g > 26, g < 29, !reduce { p.headYaw = sin((g - 26) / 3 * 2 * .pi) * 0.45 }
            if s == .friend { p.lift = hop(t) * big; p.armR = 1.8 + 0.4 * sin(t * 18) * big }
        case .sleepy, .rest:
            p.squash = 1 + 0.025 * sin(2 * .pi * t / 6)
            p.headPitch = 0.18
            p.headYaw = 0
            p.eyes = 0.08
            p.ears = 0.25
            if s == .rest { p.armL = -0.35; p.armR = -0.35 }
        case .click:
            p.squash = 0.93
            p.eyes = 1.15
        case .pet:
            p.bodyTilt = 0.14 * sin(2 * .pi * t * 2) * big
            p.eyes = 0.45
            p.ears = -0.25 * abs(sin(2 * .pi * t * 2)) * big
            p.headYaw = 0
        case .sulk:
            p.bodyTurn = .pi * 0.85
            p.headPitch = 0.15
            p.ears = 0.3
        case .drag:
            p.bodyTilt = 0.32 * sin(2 * .pi * t * 0.9) * big
            p.armL = 1.0; p.armR = 1.0
            p.eyes = 1.2
            p.squash = 1.06
        case .land:
            p.squash = 0.82
        case .toss:
            p.bodyRoll = -t * 9 * big
            p.eyes = 0.1
        case .fileNear:
            p.armL = 1.4; p.armR = 1.4
            p.eyes = 1.25
            p.headPitch = -0.15
        case .converting:
            p.headPitch = 0.12 + 0.12 * sin(2 * .pi * t * 2.5) * big
        case .converted, .jobDone:
            p.lift = hop(t) * big
            p.eyes = 0.45
            p.armL = t < 1 ? 1.2 : 0; p.armR = p.armL
        case .jobWaiting, .briefing:
            p.armR = 2.2 + 0.45 * sin(2 * .pi * t * 3) * big
            p.eyes = 1.1
        case .jobFailed:
            p.headPitch = 0.18
            p.ears = 0.35
            p.eyes = 0.6
            p.squash = 0.96
        case .walk:
            p.bodyTilt = 0.14 * sin(2 * .pi * t * 2.6) * big
            p.lift = 0.03 * abs(sin(2 * .pi * t * 2.6)) * big
            p.bodyTurn = facingRight ? 0.6 : -0.6
            p.headYaw = 0
        }
        p.tail = 0.35 * sin(2 * .pi * t * 1.3) * big
        p.headYaw = min(max(p.headYaw, -BearPose.headYawLimit * 1.8), BearPose.headYawLimit * 1.8)
        return p
    }

    /// 0.9초 안에 두 번 통통
    static func hop(_ t: Double) -> Double {
        guard t < 0.9 else { return 0 }
        return 0.22 * abs(sin(.pi * t / 0.45))
    }
}

/// 노드 이름 표: 모델(usdz)도 같은 이름이면 같은 모션 코드로 움직인다
enum BearRig {
    static let root = "root", body = "body", head = "head", earL = "ear_L", earR = "ear_R"
    static let eyeL = "eye_L", eyeR = "eye_R", armL = "arm_L", armR = "arm_R", tail = "tail"
}

/// 모델 없이 도형으로 만든 곰(base.png 비율·색)
enum ProceduralBear {
    static let cream = NSColor(srgbRed: 0.953, green: 0.918, blue: 0.847, alpha: 1)
    static let pink = NSColor(srgbRed: 0.949, green: 0.722, blue: 0.722, alpha: 1)
    static let ink = NSColor(srgbRed: 0.07, green: 0.06, blue: 0.07, alpha: 1)

    static func make() -> SCNNode {
        func mat(_ c: NSColor, shiny: Bool = false) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = c
            m.roughness.contents = shiny ? 0.15 : 0.95
            m.metalness.contents = 0
            if !shiny {
                // 말랑한 인형 느낌: 테두리를 살짝 밝히고(벨벳), 어두운 쪽을 들어 올려 그림자를 부드럽게
                m.shaderModifiers = [.fragment: """
                float rim = 1.0 - saturate(dot(_surface.normal, normalize(-_surface.position)));
                _output.color.rgb = mix(_output.color.rgb, _surface.diffuse.rgb, 0.35);
                _output.color.rgb += _surface.diffuse.rgb * pow(rim, 2.5) * 0.35;
                """]
            }
            return m
        }
        func ball(_ r: CGFloat, _ m: SCNMaterial, scale: SCNVector3 = SCNVector3(1, 1, 1), at p: SCNVector3, name: String? = nil) -> SCNNode {
            let s = SCNSphere(radius: r)
            s.segmentCount = 48
            s.materials = [m]
            let n = SCNNode(geometry: s)
            n.scale = scale
            n.position = p
            n.name = name
            return n
        }
        let fur = mat(cream), inner = mat(pink), black = mat(ink, shiny: true)
        let root = SCNNode(); root.name = BearRig.root
        let body = SCNNode(); body.name = BearRig.body          // 발바닥이 원점(눌림 축)
        root.addChildNode(body)
        body.addChildNode(ball(0.5, fur, scale: SCNVector3(1.0, 1.1, 0.9), at: SCNVector3(0, 0.55, 0)))
        // 머리 축: 얼굴 부품이 몸 앞면을 따라 돈다
        let head = SCNNode(); head.name = BearRig.head
        head.position = SCNVector3(0, 0.55, 0)   // 몸 중심: 얼굴이 겉면을 따라 돌아 파묻히지 않는다
        body.addChildNode(head)
        for (side, name) in [(-1.0, BearRig.earL), (1.0, BearRig.earR)] {
            let ear = SCNNode(); ear.name = name
            ear.position = SCNVector3(CGFloat(side) * 0.3, 0.47, -0.02)
            ear.addChildNode(ball(0.13, fur, at: SCNVector3(0, 0.03, 0)))
            ear.addChildNode(ball(0.075, inner, scale: SCNVector3(1, 1, 0.3), at: SCNVector3(0, 0.02, 0.112)))
            head.addChildNode(ear)
        }
        for (side, name) in [(-1.0, BearRig.eyeL), (1.0, BearRig.eyeR)] {
            head.addChildNode(ball(0.052, black, scale: SCNVector3(1, 1, 0.7), at: SCNVector3(CGFloat(side) * 0.17, 0.29, 0.355), name: name))
        }
        head.addChildNode(ball(0.13, mat(cream.blended(withFraction: 0.25, of: .white)!), scale: SCNVector3(1.3, 0.85, 0.7), at: SCNVector3(0, 0.14, 0.41)))
        head.addChildNode(ball(0.042, black, scale: SCNVector3(1.35, 0.85, 0.8), at: SCNVector3(0, 0.2, 0.49)))
        for (side, name) in [(-1.0, BearRig.armL), (1.0, BearRig.armR)] {
            // 어깨 축 아래로 늘어진 짧은 팔
            let arm = SCNNode(); arm.name = name
            arm.position = SCNVector3(CGFloat(side) * 0.43, 0.6, 0.06)
            let cap = SCNCapsule(capRadius: 0.1, height: 0.3)
            cap.materials = [fur]
            let a = SCNNode(geometry: cap)
            a.position = SCNVector3(CGFloat(side) * 0.03, -0.12, 0)
            a.eulerAngles.z = CGFloat(side) * 0.25
            arm.addChildNode(a)
            body.addChildNode(arm)
        }
        let tail = ball(0.08, fur, at: SCNVector3(0, 0.3, -0.44), name: BearRig.tail)
        body.addChildNode(tail)
        return root
    }
}

/// 펫 창 안의 3D 곰. 마우스는 받지 않는다(PetView가 받는다).
final class Pet3DView: SCNView, SCNSceneRendererDelegate {
    // 메인 스레드가 쓰고 그리는 스레드가 읽는 값은 모두 lock 안에서(그리는 쪽은 advance 전체를 잠근다)
    private let lock = NSLock()
    private var _situation: Situation = .idle, _lean = 0.0, _facingRight = false, pendingKick: Situation?
    var situation: Situation {
        get { lock.withLock { _situation } }
        set {
            lock.withLock { if newValue != _situation { _situation = newValue; pendingKick = newValue } }
            if Self.still { settle() }
        }
    }
    var lean: Double { get { lock.withLock { _lean } } set { lock.withLock { _lean = newValue } } }
    var facingRight: Bool { get { lock.withLock { _facingRight } } set { lock.withLock { _facingRight = newValue } } }

    private let bear: SCNNode
    private var nodes: [String: SCNNode] = [:]
    private var rest: [String: SCNVector3] = [:]   // 노드별 처음 자세(scale)
    private var time = 0.0, last: TimeInterval?, started = 0.0
    private var nextBlink = 3.0
    private var springs: [String: Spring] = [:]
    private var fps = 60, lastLook = CGPoint.zero, calmSince = 0.0
    /// 그리는 스레드에서 창을 건드리지 않도록 메인에서 옮길 때마다 적어 둔다
    private var windowFrame = CGRect.zero
    @objc private func moved() { let f = window?.frame ?? .zero; lock.withLock { windowFrame = f } }

    static let center: CGFloat = 0.55
    /// 움직임 끄기(설정, CPU 절약): 그리기를 멈추고 상황이 바뀔 때만 한 장 그린다
    static let stillChanged = Notification.Name("taskyStillChanged")
    static var still: Bool {
        get { UserDefaults.standard.bool(forKey: "petStill") }
        set { UserDefaults.standard.set(newValue, forKey: "petStill"); NotificationCenter.default.post(name: stillChanged, object: nil) }
    }

    /// 모델 파일: Application Support/Tasky/Characters/bear3d/model.usdz (없으면 도형 곰)
    static var modelURL: URL { Character.root().appendingPathComponent("bear3d/model.usdz") }

    override init(frame: NSRect) {
        if FileManager.default.fileExists(atPath: Self.modelURL.path), let s = try? SCNScene(url: Self.modelURL) {
            let n = SCNNode()
            n.name = BearRig.root
            s.rootNode.childNodes.forEach { n.addChildNode($0) }
            bear = n
        } else {
            bear = ProceduralBear.make()
        }
        super.init(frame: frame, options: nil)
        let scene = SCNScene()
        // 회전 축을 발바닥이 아니라 몸 가운데로: 굴러도·기울어도 몸이 카메라 밖으로 휘둘리지 않는다
        bear.pivot = SCNMatrix4MakeTranslation(0, Self.center, 0)
        bear.position.y = Self.center
        scene.rootNode.addChildNode(bear)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 22
        cam.position = SCNVector3(0, 0.95, 4)
        cam.look(at: SCNVector3(0, 0.66, 0))
        scene.rootNode.addChildNode(cam)
        let key = SCNNode(); key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 650
        key.eulerAngles = SCNVector3(-0.7, 0.5, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 700
        fill.light?.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.94, alpha: 1)
        scene.rootNode.addChildNode(fill)
        self.scene = scene
        pointOfView = cam
        backgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        antialiasingMode = .multisampling2X   // 레티나라 2배면 충분, CPU·GPU 절약
        preferredFramesPerSecond = 60
        rendersContinuously = true
        delegate = self
        for name in [BearRig.body, BearRig.head, BearRig.earL, BearRig.earR, BearRig.eyeL, BearRig.eyeR, BearRig.armL, BearRig.armR, BearRig.tail] {
            if let n = bear.childNode(withName: name, recursively: true) { nodes[name] = n; rest[name] = n.scale }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 창이 안 보이면 그리지 않는다(빼꼼 숨김·다른 Space)
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: window)
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { isPlaying = false; return }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusion), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusion), name: Self.stillChanged, object: nil)
        occlusion()
        moved()
    }
    @objc private func occlusion() {
        let play = (window?.occlusionState.contains(.visible) ?? false) && !Self.still
        isPlaying = play
        rendersContinuously = play
        if Self.still { settle() }
    }

    /// 멈춰 있을 때: 지금 상황의 자세로 바로 옮겨 한 장 그린다(그리기 루프가 멈춰 있어 경쟁 없음)
    private func settle() {
        guard !isPlaying else { return }
        for _ in 0..<90 { advance(1.0 / 60, look: .zero) }
        needsDisplay = true
    }

    /// 상황이 바뀌는 순간의 툭 치기(찌그러짐이 스프링으로 되튄다)
    private func kick(_ s: Situation) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        switch s {
        case .click: springs["squash", default: Self.spring("squash")].velocity -= 2.5
        case .land: springs["squash", default: Self.spring("squash")].velocity -= 4
        case .pet, .jobDone, .converted: springs["squash", default: Self.spring("squash")].velocity += 1.5
        default: break
        }
    }

    private static func spring(_ key: String) -> Spring {
        switch key {
        case "squash": Spring(value: 1, stiffness: 260, damping: 9)        // 탱글하게 되튐
        case "ears", "tail": Spring(stiffness: 70, damping: 6)              // 한 박자 늦게 흔들림
        case "eyes": Spring(value: 1, stiffness: 900, damping: 60)          // 깜빡임은 빠르게
        case "headYaw", "headPitch": Spring(stiffness: 60, damping: 13)     // 부드럽게 따라봄
        case "bodyRoll": Spring(stiffness: 400, damping: 40)
        default: Spring(stiffness: 140, damping: 15)
        }
    }

    private func follow(_ key: String, _ target: Double, _ dt: Double) -> Double {
        var s = springs[key] ?? Self.spring(key)
        s.step(to: target, dt: dt)
        springs[key] = s
        return s.value
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime now: TimeInterval) {
        let dt = min(last.map { now - $0 } ?? 0, 0.1)
        last = now
        // 커서 방향: 펫 창 가운데 기준, 400pt에서 끝까지
        let f = lock.withLock { windowFrame }, m = NSEvent.mouseLocation
        advance(dt, look: CGPoint(x: min(max((m.x - f.midX) / 400, -1), 1), y: min(max((m.y - f.midY) / 400, -1), 1)))
    }

    /// 시간을 dt만큼 진행하고 노드에 자세를 입힌다(그리기 루프·그림 확인용 공용)
    func advance(_ dt: Double, look: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        time += dt
        if let k = pendingKick {
            pendingKick = nil; started = time; kick(k)
        }
        let situation = _situation, lean = _lean, facingRight = _facingRight
        defer { pace(situation, look: look) }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var p = BearMotion.pose(situation, t: time - started, look: look, lean: lean, facingRight: facingRight, reduce: reduce)
        // 평소 눈 깜빡임(3~6초마다 0.12초)
        if time >= nextBlink { if time > nextBlink + 0.12 { nextBlink = time + .random(in: 3...6) } else if p.eyes > 0.5 { p.eyes = 0.1 } }

        let squash = follow("squash", p.squash, dt)
        let wide = 1 / sqrt(max(squash, 0.5))   // 부피 보존
        nodes[BearRig.body]?.scale = SCNVector3(wide, squash, wide)
        let tilt = follow("bodyTilt", p.bodyTilt, dt), turn = follow("bodyTurn", p.bodyTurn, dt)
        let roll = reduce ? 0 : p.bodyRoll   // 구르기는 바로(스프링이면 늦게 돈다)
        bear.eulerAngles = SCNVector3(roll, turn, tilt)
        bear.position.y = Self.center + follow("lift", p.lift, dt)
        nodes[BearRig.head]?.eulerAngles = SCNVector3(follow("headPitch", p.headPitch, dt), follow("headYaw", p.headYaw, dt), 0)
        let al = follow("armL", p.armL, dt), ar = follow("armR", p.armR, dt)
        nodes[BearRig.armL]?.eulerAngles.z = -al
        nodes[BearRig.armR]?.eulerAngles.z = ar
        // 귀는 몸 기울기를 늦게 따라가며 흔들린다
        let ears = follow("ears", p.ears + tilt * 0.8, dt)
        nodes[BearRig.earL]?.eulerAngles.z = ears
        nodes[BearRig.earR]?.eulerAngles.z = -ears
        nodes[BearRig.tail]?.eulerAngles.y = follow("tail", p.tail, dt)
        let eyes = follow("eyes", p.eyes, dt)
        for n in [BearRig.eyeL, BearRig.eyeR] {
            if let node = nodes[n], let r = rest[n] { node.scale = SCNVector3(r.x, r.y * max(eyes, 0.06), r.z) }
        }
    }

    /// 움직임이 있을 때만 60fps, 숨쉬기·깜빡임만 남으면 0.5초 뒤 30fps(가만히 있을 때 CPU 절약).
    /// 30fps에서도 숨쉬기는 느려서 끊겨 보이지 않는다. 커서가 움직이거나 스프링이 빠르게 움직이면 바로 60.
    private func pace(_ s: Situation, look: CGPoint) {
        let moving = hypot(look.x - lastLook.x, look.y - lastLook.y) > 0.002
            || springs.contains { $0.key != "squash" && $0.key != "eyes" && abs($0.value.velocity) > 0.05 }
            || ![.idle, .sleepy, .rest].contains(s)
        lastLook = look
        if moving { calmSince = time }
        let want = time - calmSince > 0.5 ? 30 : 60
        guard want != fps else { return }
        fps = want
        DispatchQueue.main.async { [weak self] in self?.preferredFramesPerSecond = want }
    }

    /// 확인용: 상황마다 1초 진행한 모습을 PNG로(`Tasky --render-bear <폴더>`)
    static func renderSamples(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        for (s, t) in [(Situation.idle, 1.0), (.pet, 0.3), (.drag, 0.6), (.land, 0.08), (.sleepy, 1.5), (.jobWaiting, 0.4), (.jobFailed, 1.0), (.sulk, 1.5), (.walk, 0.2), (.fileNear, 1.0), (.toss, 0.17), (.toss, 0.35)] {
            let v = Pet3DView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
            v.nextBlink = 99
            if s == .land { v.situation = .drag; for _ in 0..<30 { v.advance(1.0 / 60, look: .zero) } }
            v.situation = s
            for _ in 0..<Int(t * 60) { v.advance(1.0 / 60, look: CGPoint(x: 0.5, y: 0.2)) }
            r.scene = v.scene
            r.pointOfView = v.pointOfView
            let img = r.snapshot(atTime: 0, with: CGSize(width: 240, height: 240), antialiasingMode: .multisampling4X)
            if let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(s == .toss ? "toss\(Int(t * 100)).png" : "\(s).png"))
            }
        }
    }

    /// 창 안에서 몸이 차지하는 부분(0...1, 카메라 기준 대략)
    static let bodyUnit = CGRect(x: 0.18, y: 0.03, width: 0.64, height: 0.74)
}
