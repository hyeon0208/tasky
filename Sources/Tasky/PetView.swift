import AppKit

/// 포커스를 가져가지 않는 투명 패널. 화면 밖으로 일부 나가 있을 수 있어야 해서 위치 보정을 끈다.
final class FloatingPanel: NSPanel {
    var keyable = false
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
    /// 펫을 따라다니던 창은 닫힐 때 떼어 낸다(붙어 있으면 펫이 앞으로 올 때 다시 나타난다)
    override func orderOut(_ sender: Any?) {
        parent?.removeChildWindow(self)
        super.orderOut(sender)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

protocol PetViewDelegate: AnyObject {
    func petClicked()
    /// delta: 누른 곳부터 지금 커서까지(누적)
    func petDragged(by delta: CGVector)
    func petDragEnded()
    func petHover(_ inside: Bool)
    func petFilesEntered(_ urls: [URL])
    func petFilesDroppedOnBody()
    func petRubbed()
}

/// 2D 깍지. 그리기만 맡고, 상태 판단은 AppController가 한다(나중에 3D로 바꿀 때 이 파일만 교체).
final class PetView: NSView {
    weak var delegate: PetViewDelegate?
    /// F18: 3D 곰을 쓰면 그 위에 그리고, 상황·기울기를 넘긴다(마우스·상황 판단은 그대로 여기서)
    var bear: Pet3DView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let bear { bear.frame = bounds; bear.autoresizingMask = [.width, .height]; addSubview(bear) }
            effectLayer.zPosition = 10   // 효과(음표·Zz)가 3D 곰 위에 보이게
            show()
        }
    }
    /// 정사각 창(캐릭터 그림·3D)인지, 120×84 콩깍지인지
    var isSquare: Bool { bear != nil || character?.resolve(.idle) != nil }
    var mirrored = false { didSet { needsDisplay = true } }

    /// F20 빼꼼 아일랜드: 붙었을 때 펫 창이 되는 알약의 내용. nil이면 보통 펫.
    struct Island: Equatable {
        var vertical: Bool, expanded: Bool
        var dots: [NSColor] = [], extra = 0
        var clock = "", line = "", lineColor: NSColor = .white
        var border: NSColor?
    }
    var island: Island? {
        didSet {
            guard island != oldValue else { return }
            bear?.compact = island != nil
            effectLayer.isHidden = island != nil
            needsLayout = true
            needsDisplay = true
        }
    }
    /// 캐릭터가 그려지는 자리: 보통은 창 전체, 알약이면 작은 얼굴 칸
    private var iconRect: CGRect {
        guard let i = island else { return bounds }
        if i.vertical && !i.expanded { return CGRect(x: (bounds.width - 26) / 2, y: bounds.height - 30, width: 26, height: 26) }
        let s: CGFloat = i.expanded ? (i.vertical ? 52 : 48) : 26
        return CGRect(x: max(4, min(8, (bounds.height - s) / 2)), y: bounds.midY - s / 2, width: s, height: s)
    }


    /// 내 차례 구슬 쪽으로 몸을 살짝 기울인다(-1 왼쪽 … 1 오른쪽, 0 똑바로). 동작 줄이기면 기울이지 않는다.
    func lean(_ toward: CGFloat) {
        bear?.lean = Double(toward)
        let angle = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : -toward * 6 * .pi / 180
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        bodyLayer.setValue(angle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
    }
    /// 싱잉볼 쉼(F6): 호흡 애니메이션과 몸에 겹쳐 그린 작은 그릇
    var breathing = false { didSet { if breathing != oldValue { updateBreathing() } } }
    var holdingBowl = false { didSet { needsDisplay = true } }

    /// 10초 주기: 4초 들숨(1.08배) · 6초 날숨. 동작 줄이기면 크기 대신 밝기만.
    private func updateBreathing() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "breath")
        guard breathing, character == nil else { return }   // 캐릭터는 바탕 상황(.rest)의 숨쉬기를 쓴다
        let a: CAKeyframeAnimation
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [1, 0.8, 1]
        } else {
            // 기준점을 바꾸지 않고 가운데를 중심으로 키운다(펫 위치가 움직이지 않게)
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            func scaled(_ s: CGFloat) -> CATransform3D {
                CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(c.x, c.y, 0), s, s, 1), -c.x, -c.y, 0)
            }
            a = CAKeyframeAnimation(keyPath: "transform")
            a.values = [scaled(1), scaled(1.08), scaled(1)].map { NSValue(caTransform3D: $0) }
        }
        a.keyTimes = [0, 0.4, 1]
        a.duration = 10
        a.repeatCount = .infinity
        layer.add(a, forKey: "breath")
    }

    /// 몸 안의 콩알(작업 상태 색). 최대 5개.
    var beans: [NSColor] = [] { didSet { needsDisplay = true } }
    /// 펫마다 다른 몸 색: 민트·살구·라일락·크림
    var bodyColor = PetView.defaultColors[0] { didSet { needsDisplay = true } }
    static let defaultColors: [NSColor] = [
        NSColor(red: 0.80, green: 0.90, blue: 0.78, alpha: 1),
        NSColor(red: 0.98, green: 0.84, blue: 0.72, alpha: 1),
        NSColor(red: 0.86, green: 0.81, blue: 0.95, alpha: 1),
        NSColor(red: 0.97, green: 0.93, blue: 0.80, alpha: 1),
    ]

    private var downPoint: CGPoint?
    private var dragging = false
    private var lastRubX: CGFloat?
    private var rubDirection: CGFloat = 0
    private var rubTurns: [Date] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        bodyLayer.anchorPoint = CGPoint(x: 0.5, y: 0)   // 창 아래(발바닥)를 축으로 눌리고 뛴다
        faceLayer.contentsGravity = .resizeAspect
        effectLayer.contentsGravity = .resizeAspect
        bodyLayer.addSublayer(faceLayer)
        layer?.addSublayer(bodyLayer)
        layer?.addSublayer(effectLayer)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = iconRect
        bear?.frame = r
        bodyLayer.bounds = CGRect(origin: .zero, size: r.size)
        bodyLayer.position = CGPoint(x: r.midX, y: r.minY)
        faceLayer.bounds = bodyLayer.bounds   // 뒤집힌 상태에서도 맞도록 frame 대신 bounds·position
        // 그림의 바닥선(아래 12%)이 창 아래에 오도록 내린다
        faceLayer.position = CGPoint(x: r.width / 2, y: r.height / 2 - r.height * Self.floor)
        let e = bounds.width * 0.26
        effectLayer.frame = CGRect(x: bounds.width * 0.7, y: bounds.height * 0.72, width: e, height: e)
        CATransaction.commit()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: 파일 받기

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return [] }
        delegate?.petFilesEntered(urls)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        delegate?.petFilesDroppedOnBody()
        return true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let island { drawIsland(island) }
        guard faceLayer.contents == nil, bear == nil else { return }   // 캐릭터 그림·3D면 콩깍지를 그리지 않는다
        let ctx = NSGraphicsContext.current!.cgContext
        // 알약 안에서는 얼굴 칸에 콩깍지 비율(120×84)로
        let r = island == nil ? bounds : iconRect.insetBy(dx: 0, dy: iconRect.height * 0.15)
        ctx.translateBy(x: r.minX, y: r.minY)
        if mirrored { ctx.translateBy(x: r.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
        // 기준 크기(120×84)로 그리고 펫 크기에 맞춰 늘린다
        ctx.scaleBy(x: r.width / 120, y: r.height / 84)
        let body = CGRect(x: 0, y: 0, width: 120, height: 84).insetBy(dx: 8, dy: 12)
        let pod = NSBezierPath(roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)
        bodyColor.setFill()
        pod.fill()
        NSColor(red: 0.23, green: 0.45, blue: 0.27, alpha: 1).setStroke()
        pod.lineWidth = 2.5
        pod.stroke()

        let seam = NSBezierPath()
        seam.move(to: CGPoint(x: body.minX + body.width * 0.3, y: body.midY - 2))
        seam.curve(to: CGPoint(x: body.maxX - 12, y: body.midY - 1),
                   controlPoint1: CGPoint(x: body.midX, y: body.midY - 8),
                   controlPoint2: CGPoint(x: body.maxX - 30, y: body.midY - 6))
        NSColor(red: 0.23, green: 0.45, blue: 0.27, alpha: 0.35).setStroke()
        seam.lineWidth = 1.5
        seam.stroke()

        for (i, color) in beans.prefix(5).enumerated() {
            color.setFill()
            let x = body.minX + body.width * 0.42 + CGFloat(i) * 11
            NSBezierPath(ovalIn: CGRect(x: x, y: body.midY - 12, width: 9, height: 9)).fill()
        }

        if holdingBowl {
            // 몸 아래쪽에 겹쳐 그린 작은 그릇 (실제 자세는 디자인 에셋 때)
            let bowl = NSBezierPath()
            let cx = body.midX + 8, top = body.minY + 14
            bowl.move(to: CGPoint(x: cx - 20, y: top))
            bowl.curve(to: CGPoint(x: cx + 20, y: top), controlPoint1: CGPoint(x: cx - 18, y: top - 20), controlPoint2: CGPoint(x: cx + 18, y: top - 20))
            bowl.close()
            NSColor(red: 0.76, green: 0.58, blue: 0.32, alpha: 1).setFill()
            bowl.fill()
            NSColor(red: 0.55, green: 0.38, blue: 0.18, alpha: 1).setStroke()
            bowl.lineWidth = 1.5
            bowl.stroke()
        }

        NSColor(red: 0.11, green: 0.14, blue: 0.12, alpha: 1).setFill()
        for dx in [CGFloat(18), 32] {
            NSBezierPath(ovalIn: CGRect(x: body.minX + dx, y: body.midY + 6, width: 6, height: 6)).fill()
        }
        let mouth = NSBezierPath()
        mouth.move(to: CGPoint(x: body.minX + 22, y: body.midY))
        mouth.curve(to: CGPoint(x: body.minX + 32, y: body.midY),
                    controlPoint1: CGPoint(x: body.minX + 25, y: body.midY - 4),
                    controlPoint2: CGPoint(x: body.minX + 29, y: body.midY - 4))
        NSColor(red: 0.11, green: 0.14, blue: 0.12, alpha: 1).setStroke()
        mouth.lineWidth = 1.8
        mouth.lineCapStyle = .round
        mouth.stroke()
    }

    /// 검은 알약 + (접힘) 작업 색 점 / (펼침) 시계·작업 한 줄
    private func drawIsland(_ i: Island) {
        let r = bounds.insetBy(dx: 1, dy: 1), radius = min(r.width, r.height, 44) / 2
        let pill = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor(white: 0.08, alpha: 0.94).setFill()
        pill.fill()
        if let b = i.border { b.setStroke(); pill.lineWidth = 2; pill.stroke() }
        let icon = iconRect
        if i.expanded {
            let x = icon.maxX + 10, w = bounds.width - x - 12
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: i.clock, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                                                            .foregroundColor: NSColor.white])
                .draw(in: CGRect(x: x, y: bounds.midY + 1, width: w, height: 20))
            NSAttributedString(string: i.line, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                           .foregroundColor: i.lineColor, .paragraphStyle: para])
                .draw(in: CGRect(x: x, y: bounds.midY - 17, width: w, height: 15))
            return
        }
        let d: CGFloat = 6, step: CGFloat = 10
        func spot(_ k: Int) -> CGPoint {
            i.vertical ? CGPoint(x: bounds.midX, y: icon.minY - 10 - CGFloat(k) * step)
                       : CGPoint(x: icon.maxX + 10 + CGFloat(k) * step, y: bounds.midY)
        }
        for (k, c) in i.dots.enumerated() {
            let p = spot(k)
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)).fill()
        }
        if i.extra > 0 {
            let t = NSAttributedString(string: "+\(i.extra)", attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                                                         .foregroundColor: NSColor(white: 1, alpha: 0.7)])
            let p = spot(i.dots.count), sz = t.size()
            t.draw(at: CGPoint(x: i.vertical ? p.x - sz.width / 2 : p.x - 3, y: p.y - sz.height / 2))
        }
    }

    // MARK: 캐릭터 (F11)

    /// 그림의 바닥선(아래에서 12%)
    static let floor: CGFloat = 0.12
    /// 움직임을 받는 층(발바닥 축)과 그 안의 표정 그림, 머리 위 효과
    private let bodyLayer = CALayer()
    private let faceLayer = CALayer()
    private let effectLayer = CALayer()
    var character: Character? { didSet { show(); updateBreathing() } }
    /// 바탕 상황. 잠깐 반응이 끝나면 이리로 돌아온다.
    var base: Situation = .idle { didSet { if base != oldValue, transient == nil { show() } } }
    /// 걷기 그림은 왼쪽을 보므로 오른쪽으로 걸을 때 뒤집는다
    var walkingRight = false
    private var transient: Situation?
    private var transientWork: DispatchWorkItem?
    private var blinkTimer: Timer?
    private var walkTimer: Timer?

    // MARK: 클릭과 끌기

    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let now = NSEvent.mouseLocation
        if !dragging, hypot(now.x - start.x, now.y - start.y) < 3 { return }
        dragging = true
        // 잡은 곳에서 얼마나 왔는지(누적). 조각조각 더하면 창 좌표 반올림이 쌓여 커서가 캐릭터에서 멀어진다.
        delegate?.petDragged(by: CGVector(dx: now.x - start.x, dy: now.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { delegate?.petDragEnded() } else { delegate?.petClicked() }
        downPoint = nil
        dragging = false
    }

    // MARK: 호버와 쓰다듬기

    override func mouseEntered(with event: NSEvent) { delegate?.petHover(true) }
    override func mouseExited(with event: NSEvent) {
        lastRubX = nil
        delegate?.petHover(false)
    }

    /// 버튼을 누르지 않고 좌우로 문지르면 쓰다듬기. 0.8초 안에 방향이 3번 바뀌면 인정.
    override func mouseMoved(with event: NSEvent) {
        let x = event.locationInWindow.x
        defer { lastRubX = x }
        guard let last = lastRubX, abs(x - last) > 2 else { return }
        let dir: CGFloat = x > last ? 1 : -1
        if rubDirection != 0, dir != rubDirection {
            let now = Date()
            rubTurns = rubTurns.filter { now.timeIntervalSince($0) < 0.8 } + [now]
            if rubTurns.count >= 3 { rubTurns = []; delegate?.petRubbed() }
        }
        rubDirection = dir
    }

    /// 귀환 브리핑(F8): 앞쪽 위에 둥근 손을 보이고 1.5초 동안 세 번 흔든다(손 모양은 에셋 받으면 교체)
    func waveHand() {
        guard let layer else { return }
        let s = bounds.width / 120
        let r = 9 * s
        // 눈이 있는 쪽(앞쪽) 위, 펫 창 안에 들어오게
        let cx = (mirrored ? 120 - 14 : 14) * s, cy = 64 * s
        let hand = CAShapeLayer()
        hand.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        hand.anchorPoint = CGPoint(x: 0.5, y: 0)       // 손목(아래)을 축으로 흔든다
        hand.position = CGPoint(x: cx, y: cy - r)
        hand.path = CGPath(ellipseIn: hand.bounds, transform: nil)
        hand.fillColor = bodyColor.cgColor
        hand.strokeColor = NSColor(red: 0.23, green: 0.45, blue: 0.27, alpha: 1).cgColor
        hand.lineWidth = 2 * s
        layer.addSublayer(hand)
        CATransaction.begin()
        CATransaction.setCompletionBlock { hand.removeFromSuperlayer() }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 1; a.duration = 1.5
            hand.add(a, forKey: "show")
        } else {
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            let t = CGFloat.pi / 7
            a.values = [0, t, -t, t, -t, t, 0]
            a.duration = 1.5
            hand.add(a, forKey: "wave")
        }
        CATransaction.commit()
    }

    func wiggle() {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [1, 0.88, 1.06, 0.97, 1]
        a.duration = 0.45
        layer.add(a, forKey: "wiggle")
    }
}

extension PetView {
    /// 상황에 맞는 표정·움직임·효과. 캐릭터 그림이 없으면 지금의 콩깍지 반응을 한다.
    func react(_ s: Situation) {
        let r = Reaction.of(s)
        guard bear != nil || character?.resolve(r.pose) != nil else {
            switch s {
            case .briefing: waveHand()
            case .pet, .converted, .jobDone, .jobWaiting, .jobFailed: wiggle()
            default: break
            }
            if r.seconds == 0 { base = s }
            return
        }
        guard r.seconds > 0 else {
            // 바탕 상황은 하던 잠깐 반응을 끊는다(삐친 채로 끌려가지 않게)
            transientWork?.cancel()
            transient = nil
            if base == s { show() } else { base = s }
            return
        }
        transientWork?.cancel()
        transient = s
        show()
        let work = DispatchWorkItem { [weak self] in self?.transient = nil; self?.show() }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + r.seconds, execute: work)
    }

    /// 창 안에서 몸이 차지하는 부분(0...1). 캐릭터는 그림을 바닥선만큼 내려 그린 만큼 옮긴다.
    var bodyUnit: CGRect {
        if island != nil { return CGRect(x: 0, y: 0, width: 1, height: 1) }   // 알약 전체가 몸
        if bear != nil { return Pet3DView.bodyUnit }
        guard let character, character.resolve(.idle) != nil else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let b = character.bodyRect.offsetBy(dx: 0, dy: -Self.floor)
        return b.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// 지금 캐릭터 그림을 보여 주고 있는지(아니면 콩깍지)
    var showsCharacter: Bool { bear != nil || faceLayer.contents != nil }

    /// 표정은 그대로 두고 효과만 잠깐(싱잉볼을 칠 때 음표)
    func flash(_ effect: Effect) {
        guard showsCharacter else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectLayer.contents = effect.image
        CATransaction.commit()
        let shown = effectLayer.contents as AnyObject?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, (self.effectLayer.contents as AnyObject?) === shown else { return }
            self.effectLayer.contents = self.showsCharacter ? Reaction.of(self.transient ?? self.base).effect?.image : nil
        }
    }

    private func setFace(_ pose: Pose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        faceLayer.contents = character?.image(pose)
        CATransaction.commit()
    }

    private func show() {
        let s = transient ?? base
        if let bear {
            bear.situation = s
            bear.facingRight = walkingRight
            faceLayer.contents = nil
            effectLayer.contents = Reaction.of(s).effect?.image
            needsDisplay = true
            return
        }
        let r = Reaction.of(s)
        setFace(r.pose)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let flip = (s == .walk && walkingRight) || r.motion == .turn
        faceLayer.setAffineTransform(flip ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        effectLayer.contents = faceLayer.contents == nil ? nil : r.effect?.image
        CATransaction.commit()
        if effectLayer.contents != nil {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = 1; a.duration = 0.15
            effectLayer.add(a, forKey: "in")
        }
        needsDisplay = true
        animate(faceLayer.contents == nil ? .none : r.motion)
        walkTimer?.invalidate()
        walkTimer = nil
        if s == .walk, faceLayer.contents != nil {
            var second = false
            walkTimer = Ticker.every("걷는 그림 바꾸기", 0.3) { [weak self] _ in
                second.toggle()
                self?.setFace(second ? .walk2 : .walk1)
            }
        }
        scheduleBlink()
    }

    /// 대기 중 3~8초마다 0.15초 눈 감기
    private func scheduleBlink() {
        blinkTimer?.invalidate()
        guard transient == nil, base == .idle, character?.files[.blink] != nil else { return }
        blinkTimer = Ticker.once("눈 깜빡이기", .random(in: 3...8)) { [weak self] _ in
            guard let self, self.transient == nil, self.base == .idle else { return }
            self.setFace(.blink)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.transient == nil, self.base == .idle else { return }
                self.setFace(.idle)
                self.scheduleBlink()
            }
        }
    }

    /// 동작 줄이기면 표정만 바뀌고 움직이지 않는다
    private func animate(_ m: Motion) {
        bodyLayer.removeAllAnimations()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let h = bounds.height
        func kf(_ path: String, _ values: [CGFloat], _ duration: Double, times: [NSNumber]? = nil,
                forever: Bool = false, reverse: Bool = false) {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = times
            a.duration = duration
            a.autoreverses = reverse
            if forever { a.repeatCount = .infinity }
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bodyLayer.add(a, forKey: path)
        }
        switch m {
        case .none, .turn: break
        case .breathe: kf("transform.scale.y", [1, 1.025, 1], 4, forever: true)
        case .breatheSlow: kf("transform.scale.y", [1, 1.035, 1], 6, forever: true)
        case .breatheRest: kf("transform.scale.y", [1, 1.06, 1], 10, times: [0, 0.4, 1], forever: true)   // 4초 들숨·6초 날숨
        case .hop: kf("transform.translation.y", [0, h * 0.1, 0], 0.35)
        case .jumpTwice: kf("transform.translation.y", [0, h * 0.14, 0, h * 0.08, 0], 0.8)
        case .sway: kf("transform.rotation.z", [0, 0.12, -0.12, 0.12, -0.12, 0], 1.1)
        case .squish:
            kf("transform.scale.y", [1, 0.78, 1.06, 1], 0.4)
            kf("transform.scale.x", [1, 1.15, 0.97, 1], 0.4)
        case .pendulum: kf("transform.rotation.z", [-0.12, 0.12], 0.6, forever: true, reverse: true)
        case .shake: kf("transform.translation.x", [0, -4, 4, -4, 4, -3, 3, 0], 0.5)
        case .chew: kf("transform.scale.y", [1, 0.93, 1], 0.28, forever: true)
        case .stretch: kf("transform.scale.y", [1, 1.1], 0.5, forever: true, reverse: true)
        case .wave: kf("transform.rotation.z", [0, 0.1, -0.1, 0.1, -0.1, 0], 1.5)
        case .walk: kf("transform.translation.y", [0, 3, 0], 0.3, forever: true)
        }
    }
}
