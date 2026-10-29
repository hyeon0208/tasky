import AppKit

struct Slot {
    let title: String
    let symbol: String
    /// 숫자 배지(기다리는 작업 수 등)
    var badge: Int? = nil
    /// 칸 순서 저장용 이름(F21). 빈 문자열이면 옮길 수 없는 칸
    var id = ""
    let action: () -> Void
}

/// F21 링 칸 순서(순수 계산, 자체 검사 대상)
enum RingOrder {
    static let key = "ringOrder"
    /// 저장한 순서대로 정렬. 저장에 없는 칸은 기본 순서에서 바로 앞 칸 뒤에 끼우고, 없어진 칸은 무시한다.
    static func apply(saved: [String], ids: [String]) -> [String] {
        var out = saved.filter(ids.contains)
        for (i, id) in ids.enumerated() where !out.contains(id) {
            let prev = ids[..<i].last(where: out.contains)
            out.insert(id, at: prev.map { out.firstIndex(of: $0)! + 1 } ?? 0)
        }
        return out
    }
    static func move<T>(_ a: [T], from: Int, to: Int) -> [T] {
        var a = a
        a.insert(a.remove(at: from), at: to)
        return a
    }
}

/// 콩 링. 칸마다 유리 단추를 두고, 클릭·숫자 키·Esc는 이 뷰가 받는다(칸 뷰는 클릭을 넘긴다).
/// macOS 26 이상이면 시스템 유리(NSGlassEffectView), 아니면 뒤 흐림(NSVisualEffectView)에 빛 테두리를 얹는다.
final class RingView: NSView {
    var slots: [Slot] = []
    var centers: [CGPoint] = [] { didSet { build() } }   // 뷰 좌표
    /// 칸이 퍼져 나오는 자리(펫 몸 가운데, 뷰 좌표)
    var origin: CGPoint?
    /// 이름표 하나를 둘 위쪽 끝(펫 몸 아래, 뷰 좌표). 없으면 올린 칸 옆에 둔다.
    var labelTop: CGFloat?
    var onClose: () -> Void = {}
    /// 칸을 옮기면 새 id 순서(F21). nil이면 옮기기 없음(드롭 변환 링)
    var onReorder: (([String]) -> Void)?
    private var hovered: Int? { didSet { if hovered != oldValue { hoverChanged(from: oldValue) } } }
    private let radius: CGFloat = 25
    private var buttons: [GlassButton] = []
    private let label = GlassLabel()

    /// 칸의 투명도(설정, 0 불투명 … 1 가장 투명)
    static var transparency: Double {
        get { UserDefaults.standard.object(forKey: "ringTransparency") as? Double ?? 0.6 }
        set { UserDefaults.standard.set(newValue, forKey: "ringTransparency") }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func build() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = centers.enumerated().map { i, c in
            let b = GlassButton(diameter: radius * 2, symbol: slots[i].symbol, title: slots[i].title, accent: slots[i].id == "status" || (slots[i].id.isEmpty && i == 0), badge: slots[i].badge)
            b.frame = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
            addSubview(b)
            return b
        }
        label.isHidden = true
        addSubview(label)
    }

    /// 펫 쪽에서 살짝 작고 투명하게 시작해 제자리로(0.22초, 25ms 간격). 동작 줄이기면 나타나기만.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        for (i, b) in buttons.enumerated() {
            guard let layer = b.layer else { continue }
            let start = CACurrentMediaTime() + Double(i) * 0.025
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = reduce ? 0.12 : 0.22
            fade.timingFunction = easeOut
            fade.beginTime = start
            fade.fillMode = .backwards
            layer.add(fade, forKey: "in")
            guard !reduce, let o = origin else { continue }
            let c = centers[i]
            let from = CATransform3DMakeTranslation((o.x - c.x) * 0.4, (o.y - c.y) * 0.4, 0)
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: b.scaled(0.9, base: from))
            move.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            move.duration = 0.22
            move.timingFunction = easeOut
            move.beginTime = start
            move.fillMode = .backwards
            layer.add(move, forKey: "pop")
        }
    }

    private func hoverChanged(from old: Int?) {
        if let old, old < buttons.count { buttons[old].highlighted = false }
        guard let i = hovered, i < buttons.count else { label.isHidden = true; return }
        buttons[i].highlighted = true
        label.text = slots[i].title
        let s = label.fittingSize
        let c = lifted == i ? cursor : centers[i]   // 든 칸은 이름표가 따라간다
        let x: CGFloat, y: CGFloat
        if let top = labelTop, let o = origin, lifted == nil {
            // 이름표는 하나, 펫 몸 아래 가운데
            x = o.x - s.width / 2
            y = top - s.height
        } else {
            // 칸 아래에 두되, 뷰 아래로 벗어나면 칸 위에
            x = c.x - s.width / 2
            y = c.y - radius - s.height - 8 < 2 ? c.y + radius + 8 : c.y - radius - s.height - 8
        }
        label.frame = CGRect(x: min(max(x, 2), bounds.width - s.width - 2), y: max(y, 2), width: s.width, height: s.height)
        if label.isHidden {
            label.isHidden = false
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = 0.12
            label.layer?.add(fade, forKey: "in")
        }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func index(at p: CGPoint) -> Int? {
        centers.firstIndex { hypot($0.x - p.x, $0.y - p.y) <= radius + 4 }
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: 칸 옮기기 (F21, 시안 C 자석 젤리)

    private var press: (index: Int, at: CGPoint)?
    private var pressWork: DispatchWorkItem?
    private var lifted: Int?          // 들고 있는 칸(지금 순서의 자리)
    private var cursor = CGPoint.zero
    private var before: [GlassButton] = []   // Esc로 되돌릴 순서
    private var springs: [(x: Spring, y: Spring, s: Spring)] = []
    private var mover: Timer?

    // 누르면 0.3초 뒤 들기, 그 전에 떼면 실행(spec 3)
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = index(at: p) else { onClose(); return }
        press = (i, p)
        guard onReorder != nil, !slots[i].id.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in self?.lift(i) }
        pressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let l = lifted { cursor = p; swapIfNear(); if lifted == l { hoverChanged(from: nil) }; return }
        if let press, hypot(p.x - press.at.x, p.y - press.at.y) > 3 { pressWork?.cancel(); self.press = nil }   // 실수 방지: 아무것도 안 함
    }

    override func mouseUp(with event: NSEvent) {
        pressWork?.cancel()
        if lifted != nil { drop(cancel: false); return }
        let p = convert(event.locationInWindow, from: nil)
        if let press, index(at: p) == press.index { fire(press.index) }
        press = nil
    }

    private var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func lift(_ i: Int) {
        guard window?.isVisible == true else { return }   // 0.3초 안에 링이 닫혔으면
        press = nil
        lifted = i
        before = buttons
        cursor = centers[i]
        hovered = i
        buttons[i].layer?.removeAnimation(forKey: "hover")
        springs = centers.map { c in
            (Spring(value: c.x, stiffness: 320, damping: 14), Spring(value: c.y, stiffness: 320, damping: 14), Spring(value: 1, stiffness: 300, damping: 20))
        }
        buttons[i].layer?.zPosition = 10
        if reduce { buttons[i].layer?.transform = buttons[i].scaled(1.15); return }
        guard mover == nil else { return }
        var last = CACurrentMediaTime()
        mover = Ticker.every("링 칸 옮기기", 1.0 / 60) { [weak self] t in
            guard let self, self.window?.isVisible == true else { t.invalidate(); return }   // 링이 닫히면(orderOut) 멈춘다
            let now = CACurrentMediaTime()
            self.step(min(now - last, 1.0 / 20))
            last = now
        }
    }

    /// 든 칸이 다른 칸 자리 40pt 안이면 순서를 바꾼다(밀려난 칸은 스프링으로 새 자리로)
    private func swapIfNear() {
        guard let from = lifted else { return }
        if reduce { buttons[from].frame.origin = CGPoint(x: cursor.x - radius, y: cursor.y - radius) }
        guard let to = centers.indices.min(by: { hypot(centers[$0].x - cursor.x, centers[$0].y - cursor.y) < hypot(centers[$1].x - cursor.x, centers[$1].y - cursor.y) }),
              to != from, hypot(centers[to].x - cursor.x, centers[to].y - cursor.y) < 40, !slots[to].id.isEmpty else { return }
        hovered = nil   // 바꾸기 전 자리 기준으로 강조를 끈다
        slots = RingOrder.move(slots, from: from, to: to)
        buttons = RingOrder.move(buttons, from: from, to: to)
        if !springs.isEmpty { springs = RingOrder.move(springs, from: from, to: to) }
        lifted = to
        hovered = to
        if reduce { buttons[to].layer?.removeAnimation(forKey: "hover"); buttons[to].layer?.transform = buttons[to].scaled(1.15) }
        if reduce { for (k, b) in buttons.enumerated() where k != to { b.frame.origin = CGPoint(x: centers[k].x - radius, y: centers[k].y - radius) } }
    }

    private func drop(cancel: Bool) {
        guard let i = lifted else { return }
        let held = buttons[i]
        hovered = nil
        if cancel {   // 들기 전 순서로(버튼 자체를 기준으로 되돌림)
            let perm = before.map { old in buttons.firstIndex { $0 === old }! }
            slots = perm.map { slots[$0] }
            if !springs.isEmpty { springs = perm.map { springs[$0] } }
            buttons = before
        }
        held.layer?.zPosition = 0
        lifted = nil
        if reduce || mover == nil {
            for (k, b) in buttons.enumerated() { b.layer?.transform = CATransform3DIdentity; b.frame.origin = CGPoint(x: centers[k].x - radius, y: centers[k].y - radius) }
        }
        if !cancel { onReorder?(slots.map(\.id).filter { !$0.isEmpty }) }
    }

    /// 한 프레임: 든 칸은 커서를 빠르게, 나머지는 살짝 출렁이며 제자리로. 든 칸은 속도 방향으로 늘어난다.
    private func step(_ dt: Double) {
        var moving = false
        for k in buttons.indices {
            let held = k == lifted
            let target = held ? cursor : centers[k]
            if held { springs[k].x.stiffness = 900; springs[k].x.damping = 45; springs[k].y.stiffness = 900; springs[k].y.damping = 45 }
            else { springs[k].x.stiffness = 320; springs[k].x.damping = 14; springs[k].y.stiffness = 320; springs[k].y.damping = 14 }
            springs[k].x.step(to: target.x, dt: dt)
            springs[k].y.step(to: target.y, dt: dt)
            springs[k].s.step(to: held ? 1.15 : 1, dt: dt)
            let (x, y, sc) = (springs[k].x, springs[k].y, springs[k].s)
            let b = buttons[k]
            b.frame.origin = CGPoint(x: x.value - radius, y: y.value - radius)
            let speed = hypot(x.velocity, y.velocity), stretch = min(0.45, speed / 2200)
            let angle = atan2(y.velocity, x.velocity)
            let c = CGPoint(x: b.bounds.midX, y: b.bounds.midY)
            var t = CATransform3DMakeTranslation(c.x, c.y, 0)
            t = CATransform3DRotate(t, angle, 0, 0, 1)
            t = CATransform3DScale(t, sc.value * (1 + stretch), sc.value * (1 - stretch * 0.6), 1)
            t = CATransform3DRotate(t, -angle, 0, 0, 1)
            t = CATransform3DTranslate(t, -c.x, -c.y, 0)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            b.layer?.removeAnimation(forKey: "hover")   // 호버 스프링이 젤리 변형을 덮지 않게
            b.layer?.transform = t
            CATransaction.commit()
            if held || abs(x.value - target.x) > 0.3 || abs(y.value - target.y) > 0.3 || speed > 5 || abs(sc.value - 1) > 0.005 { moving = true }
        }
        if !moving { mover?.invalidate(); mover = nil }
    }

    override func removeFromSuperview() { mover?.invalidate(); pressWork?.cancel(); super.removeFromSuperview() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { mover?.invalidate(); mover = nil; pressWork?.cancel() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, lifted != nil { drop(cancel: true); return }   // 들고 있으면 Esc는 되돌리기
        if event.keyCode == 53 { onClose(); return }                 // Esc
        if lifted == nil, let n = Int(event.charactersIgnoringModifiers ?? ""), (1...slots.count).contains(n) { fire(n - 1) }
    }

    // MARK: 드롭 변환 링: 파일을 칸 위에 놓으면 그 칸을 실행

    var acceptsFiles = false { didSet { acceptsFiles ? registerForDraggedTypes([.fileURL]) : unregisterDraggedTypes() } }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovered = index(at: convert(sender.draggingLocation, from: nil))
        return hovered == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = index(at: convert(sender.draggingLocation, from: nil)) else { return false }
        fire(i)
        return true
    }

    private func fire(_ i: Int) {
        let action = slots[i].action
        onClose()
        action()
    }

    // 접근성: VoiceOver가 칸을 읽도록 버튼 요소로 노출
    override func accessibilityChildren() -> [Any]? {
        slots.enumerated().map { i, slot in
            let e = NSAccessibilityElement.element(withRole: .button, frame: .zero, label: slot.title, parent: self) as! NSAccessibilityElement
            let c = centers[i]
            e.setAccessibilityFrameInParentSpace(CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            return e
        }
    }
}

/// macOS 26 이상에만 있는 시스템 유리. 지금 SDK(15)에는 없어 이름으로 찾는다.
private let systemGlass = NSClassFromString("NSGlassEffectView") as? NSView.Type

/// 유리 바탕: 시스템 유리가 있으면 그것, 없으면 뒤 흐림
private func makeGlass(cornerRadius: CGFloat, frame: CGRect) -> NSView {
    if let cls = systemGlass {
        let g = cls.init(frame: frame)
        g.setValue(cornerRadius, forKey: "cornerRadius")
        return g
    }
    let v = NSVisualEffectView(frame: frame)
    v.material = .popover
    v.blendingMode = .behindWindow
    v.state = .active
    v.wantsLayer = true
    v.layer?.cornerRadius = cornerRadius
    v.layer?.masksToBounds = true
    return v
}

/// 둥근 유리 단추 한 칸. 클릭은 링 뷰로 넘긴다.
final class GlassButton: NSView {
    private let tint = CALayer()
    private var glass: NSView?
    private let accent: Bool
    var highlighted = false { didSet { update(animated: true) } }

    init(diameter d: CGFloat, symbol: String, title: String, accent: Bool, badge: Int?) {
        self.accent = accent
        super.init(frame: CGRect(x: 0, y: 0, width: d, height: d))
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 11
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        let g = makeGlass(cornerRadius: d / 2, frame: bounds)
        addSubview(g)
        glass = g

        // 옅은 색(투명도 설정)과 위쪽이 밝은 빛 테두리. 시스템 유리는 스스로 빛을 그리므로 색만 얹는다.
        let overlay = NSView(frame: bounds)
        overlay.wantsLayer = true
        tint.frame = bounds
        tint.cornerRadius = d / 2
        overlay.layer?.addSublayer(tint)
        if systemGlass == nil {
            let rim = CAGradientLayer()
            rim.frame = bounds
            rim.colors = [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0.12).cgColor, NSColor(white: 1, alpha: 0.35).cgColor]
            rim.locations = [0, 0.55, 1]
            rim.startPoint = CGPoint(x: 0.2, y: 1)
            rim.endPoint = CGPoint(x: 0.8, y: 0)
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor.black.cgColor
            ring.lineWidth = 1.5
            rim.mask = ring
            overlay.layer?.addSublayer(rim)
        }
        // 볼록한 유리알: 위 왼쪽 반사광, 위는 밝고 아래는 어두운 안쪽 테두리(시스템 유리 위에도 얹는다)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let shine = CAGradientLayer()
            shine.frame = CGRect(x: d * 0.18, y: d * 0.6, width: d * 0.44, height: d * 0.22)
            shine.cornerRadius = d * 0.11
            shine.colors = [NSColor(white: 1, alpha: 0.85).cgColor, NSColor(white: 1, alpha: 0).cgColor]
            shine.startPoint = CGPoint(x: 0.5, y: 1)
            shine.endPoint = CGPoint(x: 0.5, y: 0)
            shine.setAffineTransform(CGAffineTransform(rotationAngle: 18 * .pi / 180))
            overlay.layer?.addSublayer(shine)
            let depth = CAGradientLayer()
            depth.frame = bounds
            depth.colors = [NSColor(white: 1, alpha: 0.55).cgColor, NSColor(white: 1, alpha: 0).cgColor,
                            NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.14).cgColor]
            depth.locations = [0, 0.12, 0.7, 1]
            depth.startPoint = CGPoint(x: 0.5, y: 1)
            depth.endPoint = CGPoint(x: 0.5, y: 0)
            let edge = CAShapeLayer()
            edge.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            edge.fillColor = nil
            edge.strokeColor = NSColor.black.cgColor
            edge.lineWidth = 3
            depth.mask = edge
            overlay.layer?.addSublayer(depth)
        }
        addSubview(overlay)

        let icon = NSImageView(frame: bounds)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold).applying(.preferringHierarchical()))
        icon.contentTintColor = .white   // 시안: 흰 아이콘 + 아래 그림자
        icon.imageScaling = .scaleNone
        icon.shadow = {
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.35)
            sh.shadowOffset = CGSize(width: 0, height: -1)
            sh.shadowBlurRadius = 1.5
            return sh
        }()
        addSubview(icon)
        if let badge, badge > 0 {
            let size: CGFloat = 18
            let dot = NSView(frame: CGRect(x: d - size + 2, y: d - size + 2, width: size, height: size))
            dot.wantsLayer = true
            let ball = CAGradientLayer()
            ball.type = .radial
            ball.frame = dot.bounds
            ball.cornerRadius = size / 2
            ball.colors = [NSColor(red: 1, green: 0.82, blue: 0.48, alpha: 1).cgColor, NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1).cgColor,
                           NSColor(red: 0.85, green: 0.47, blue: 0, alpha: 1).cgColor]
            ball.startPoint = CGPoint(x: 0.35, y: 0.7)
            ball.endPoint = CGPoint(x: 1.1, y: -0.1)
            dot.layer?.addSublayer(ball)
            dot.layer?.shadowOpacity = 0.3
            dot.layer?.shadowRadius = 2
            dot.layer?.shadowOffset = CGSize(width: 0, height: -2)
            let n = NSTextField(labelWithString: badge > 9 ? "9+" : "\(badge)")
            n.font = .systemFont(ofSize: 10, weight: .heavy)
            n.textColor = NSColor(red: 0.23, green: 0.13, blue: 0, alpha: 1)
            n.alignment = .center
            n.frame = CGRect(x: 0, y: 2, width: size, height: 13)
            dot.addSubview(n)
            addSubview(dot)
        }
        update(animated: false)
    }

    /// 가운데를 축으로 키운 변환(뷰 층은 기준점이 왼쪽 아래라 이동을 더한다)
    func scaled(_ s: CGFloat, base: CATransform3D = CATransform3DIdentity, lift: CGFloat = 0) -> CATransform3D {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let t = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(c.x, c.y + lift, 0), s, s, 1), -c.x, -c.y, 0)
        return CATransform3DConcat(t, base)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func update(animated: Bool) {
        let reduceGlass = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        // 흐림 바탕 자체가 꽤 불투명해서, 색만이 아니라 바탕의 보임 정도도 함께 바꿔야 차이가 난다
        let clear = reduceGlass ? 0 : RingView.transparency
        glass?.alphaValue = 1 - clear   // 가장 투명하면 흐림도 없어 뒤 글자가 그대로 보인다
        let base = reduceGlass ? 0.95 : 0.05 + 0.85 * (1 - clear)
        let alpha = min(1, base + (highlighted ? 0.18 : 0))
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.15 : 0)
        // 흰 아이콘이 읽히도록 어두운 유리로 칠한다(불투명할수록 진하게). 첫 칸은 따뜻한 빛만 살짝.
        tint.backgroundColor = (accent ? NSColor(red: 0.30, green: 0.20, blue: 0.08, alpha: alpha * 0.9)
                                       : NSColor(white: 0.1, alpha: alpha * 0.9)).cgColor
        CATransaction.commit()
        guard let layer else { return }
        // 올리면 1.08배로 커지고 2pt 떠오른다
        let up = highlighted && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let t = scaled(up ? 1.08 : 1, lift: up ? 2 : 0)
        if animated {
            let a = CASpringAnimation(keyPath: "transform")
            a.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            a.toValue = NSValue(caTransform3D: t)
            a.damping = 14
            a.stiffness = 300
            a.duration = a.settlingDuration
            layer.add(a, forKey: "hover")
        }
        layer.transform = t
        // 그림자는 단추 아래에도 깔리므로 투명할수록 옅게(가장 투명하면 거의 없음)
        layer.shadowOpacity = Float((highlighted ? 0.55 : 0.45) * (1 - 0.85 * clear))
    }
}

/// 설정의 투명도 미리보기: 색 배경 위 유리 단추 세 개. 슬라이더를 움직이면 `refresh()`로 다시 칠한다.
final class RingPreview: NSView {
    private var buttons: [GlassButton] = []

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 220, height: 76))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        let bg = CAGradientLayer()
        bg.frame = bounds
        bg.colors = [NSColor(red: 1, green: 0.54, blue: 0.36, alpha: 1).cgColor, NSColor(red: 0.37, green: 0.78, blue: 1, alpha: 1).cgColor,
                     NSColor(red: 0.65, green: 0.48, blue: 1, alpha: 1).cgColor]
        bg.startPoint = CGPoint(x: 0, y: 0)
        bg.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(bg)
        widthAnchor.constraint(equalToConstant: bounds.width).isActive = true
        heightAnchor.constraint(equalToConstant: bounds.height).isActive = true
        setAccessibilityLabel("원형 메뉴 미리보기")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = [("folder", "폴더 서랍"), ("bell", "싱잉볼"), ("gearshape", "설정")].enumerated().map { i, item in
            let b = GlassButton(diameter: 50, symbol: item.0, title: item.1, accent: false, badge: i == 0 ? 2 : nil)
            b.frame.origin = CGPoint(x: 25 + CGFloat(i) * 60, y: 13)
            addSubview(b)
            return b
        }
    }
}

/// 칸 이름표: 유리 알약
private final class GlassLabel: NSView {
    private let field = NSTextField(labelWithString: "")
    private var glass: NSView?
    var text = "" { didSet { field.stringValue = text; needsLayout = true } }

    init() {
        super.init(frame: .zero)
        field.font = .systemFont(ofSize: 12, weight: .semibold)
        field.textColor = .labelColor
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var fittingSize: NSSize {
        let s = field.intrinsicContentSize
        return NSSize(width: s.width + 20, height: s.height + 8)
    }

    override func layout() {
        super.layout()
        glass?.removeFromSuperview()
        let g = makeGlass(cornerRadius: bounds.height / 2, frame: bounds)
        addSubview(g, positioned: .below, relativeTo: field)
        glass = g
        let s = field.intrinsicContentSize
        field.frame = CGRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
    }
}
