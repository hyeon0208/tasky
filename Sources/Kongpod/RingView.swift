import AppKit

struct Slot {
    let title: String
    let symbol: String
    /// 숫자 배지(기다리는 작업 수 등)
    var badge: Int? = nil
    let action: () -> Void
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
            let b = GlassButton(diameter: radius * 2, symbol: slots[i].symbol, title: slots[i].title, accent: i == 0, badge: slots[i].badge)
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
        let c = centers[i]
        let x: CGFloat, y: CGFloat
        if let top = labelTop, let o = origin {
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

    override func mouseDown(with event: NSEvent) {
        if let i = index(at: convert(event.locationInWindow, from: nil)) { fire(i) } else { onClose() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose(); return }                 // Esc
        if let n = Int(event.charactersIgnoringModifiers ?? ""), (1...slots.count).contains(n) { fire(n - 1) }
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
