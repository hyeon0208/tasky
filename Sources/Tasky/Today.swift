import AppKit

// F26 3단계: 한눈에 보기(칩 내용)와 오늘 카드

/// 칩에 보일 것: 남은 할 일 수, 다음 일정, 작업 상태 점. 순수 계산(자체 검사 대상).
struct Glance: Equatable {
    var tasks = 0
    var tasksOn = false
    /// F26 H1: 머리 위 시계를 칩 줄 끝에 합친다("13:15:51"). 비어 있는지에는 넣지 않는다
    var clock = ""
    /// "2:00 치과" (오늘 남은 시간 있는 일정 중 가장 가까운 것)
    var next = ""
    var dots: [AgentSession.State] = []
    var isEmpty: Bool { !showsTasks && next.isEmpty }   // 작업 상태는 칩이 아니라 곰의 유리 배지로(F26 5차)
    /// F26 H2: 0개면 ✓ 칩을 숨긴다(볼 게 없는 칩이 원형 메뉴 칸을 덮지 않게)
    var showsTasks: Bool { tasks > 0 }
    /// F26 메뉴 막대만: "3 · 2:00 치과" (작업 점은 따로 색으로)
    var menuTitle: String { ((showsTasks ? ["\(tasks)"] : []) + (next.isEmpty ? [] : [next])).joined(separator: " · ") }

    static func make(items: [TaskItem], tasksOn: Bool = false, states: [AgentSession.State], now: Date, calendar: Calendar = .current) -> Glance {
        var g = Glance()
        g.tasksOn = tasksOn
        g.tasks = TaskLogic.pending(items, now: now, calendar: calendar).count
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let from = now.addingTimeInterval(-300)
        var best: TaskItem?
        for i in items where i.isEvent && i.hasTime {
            guard let d = i.date, d >= from, d < end else { continue }
            if best == nil || d < best!.date! { best = i }
        }
        if let e = best, let d = e.date {
            let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "h:mm"
            g.next = "\(f.string(from: d)) \(e.title)"
        }
        // 급한 순: 내 차례 > 실패 > 끝남(하는 중은 점 없음)
        func rank(_ s: AgentSession.State) -> Int { s == .waiting ? 0 : s == .failed ? 1 : 2 }
        let shown = states.filter { $0 != .working }.sorted { rank($0) < rank($1) }
        g.dots = Array(shown.prefix(3))
        return g
    }

    static func color(_ s: AgentSession.State) -> NSColor {
        switch s { case .waiting: .systemOrange; case .failed: .systemRed; case .done: .systemGreen; case .working: .systemBlue }
    }
}

/// 칩 줄 그리기(알약 안·머리 위 공용)
enum GlanceChips {
    static let height: CGFloat = 22
    private static let clockFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private static func font(bold: Bool) -> NSFont { .systemFont(ofSize: 12, weight: bold ? .bold : .semibold) }

    static func width(_ g: Glance) -> CGFloat {
        var w: CGFloat = 0
        if g.showsTasks { w += chipWidth("\(g.tasks)", icon: true) + 4 }
        if !g.next.isEmpty { w += chipWidth(g.next, icon: true) + 4 }
        if !g.clock.isEmpty { w += 10 + (g.clock as NSString).size(withAttributes: [.font: clockFont]).width + 8 }
        return max(0, w - 4)
    }

    private static func chipWidth(_ text: String, icon: Bool) -> CGFloat {
        let t = min((text as NSString).size(withAttributes: [.font: font(bold: true)]).width, 120)
        return t + (icon ? 18 : 0) + 14
    }

    /// `origin`의 왼쪽 아래부터 가로로. dark: 어두운 바탕 위인지
    static func draw(_ g: Glance, at origin: CGPoint, dark: Bool) {
        var x = origin.x
        let y = origin.y
        let chipBG = dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.06)
        let text = dark ? NSColor.white : NSColor(white: 0.1, alpha: 1)
        let accent = dark ? NSColor(red: 0.45, green: 0.68, blue: 1, alpha: 1) : NSColor(red: 0.12, green: 0.39, blue: 0.92, alpha: 1)
        func chip(_ s: String, symbol: String, color: NSColor, bold: Bool) {
            let w = chipWidth(s, icon: true)
            let r = CGRect(x: x, y: y, width: w, height: height)
            chipBG.setFill()
            NSBezierPath(roundedRect: r, xRadius: height / 2, yRadius: height / 2).fill()
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .bold).applying(.init(paletteColors: [color]))) {
                img.draw(in: CGRect(x: x + 7, y: y + (height - 13) / 2, width: 13, height: 13))
            }
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: s, attributes: [.font: font(bold: bold), .foregroundColor: color == text ? text : color, .paragraphStyle: para])
                .draw(in: CGRect(x: x + 24, y: y + 3, width: w - 30, height: height - 4))
            x += w + 4
        }
        if g.showsTasks { chip("\(g.tasks)", symbol: "checkmark.square", color: accent, bold: true) }
        if !g.next.isEmpty { chip(g.next, symbol: "calendar", color: text, bold: false) }
        if !g.clock.isEmpty {
            x += 2
            text.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: CGRect(x: x, y: y + 5, width: 1, height: height - 10)).fill()
            NSAttributedString(string: g.clock, attributes: [.font: clockFont, .foregroundColor: text])
                .draw(at: CGPoint(x: x + 8, y: y + 3))
        }
    }
}

/// F26 5차: 곰 오른쪽 아래 발치의 AI 작업 배지(6차 P4). 리퀴드 글래스 구 + ✦ 하나(색: 끝남 초록·내 차례 주황·실패 빨강)
final class AgentBadgeView: NSView {
    var state: AgentSession.State? { didSet { if state != oldValue { isHidden = state == nil; face.tint = state.map(Glance.color); if state != nil { pop() } } } }
    /// 뒤 바탕을 흐리게 비추는 진짜 블러(시안의 backdrop-filter). 원 모양으로 잘라 쓴다
    private let blur = NSVisualEffectView()
    private let face = GlassFace()
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; isHidden = true
        blur.blendingMode = .behindWindow; blur.material = .popover; blur.state = .active
        blur.appearance = NSAppearance(named: .aqua)   // 알파를 낮추면 블러가 깨질 수 있어 그대로 둔다
        addSubview(blur); addSubview(face)
        // 바깥 그림자(시안: 0 4px 14px 어두운 초록 30%)
        layer?.shadowColor = NSColor(red: 20/255, green: 60/255, blue: 30/255, alpha: 1).cgColor
        layer?.shadowOpacity = 0.3; layer?.shadowRadius = 7; layer?.shadowOffset = CGSize(width: 0, height: -4)
    }
    required init?(coder: NSCoder) { fatalError() }
    /// 구슬을 누르면 그 작업의 터미널로 간다(F26 6차)
    var onClick: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, let sv = superview else { return nil }
        return face.frame.contains(convert(point, from: sv)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height) - 6
        let ball = CGRect(x: (bounds.width - side) / 2, y: 4, width: side, height: side)
        blur.frame = ball; face.frame = ball
        blur.maskImage = NSImage(size: ball.size, flipped: false) { r in NSBezierPath(ovalIn: r).fill(); return true }
        layer?.shadowPath = CGPath(ellipseIn: ball, transform: nil)
    }

    /// 생길 때 살짝 부풀었다 돌아온다
    private func pop() {
        guard let l = layer else { return }
        // 레이어 기준점이 왼쪽 아래라, 가운데를 기준으로 커지도록 이동·확대·되돌림을 묶는다
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        func t(_ k: CGFloat) -> CATransform3D {
            CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-c.x, -c.y, 0), CATransform3DMakeScale(k, k, 1)), CATransform3DMakeTranslation(c.x, c.y, 0))
        }
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [0.6, 1.15, 1].map { t($0) }; a.keyTimes = [0, 0.6, 1]; a.duration = 0.35
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.add(a, forKey: "pop")
    }
}

/// 유리 구슬 겉면: 시안 CSS 값 그대로(왼쪽 위 흰빛 75% → 15% → 가장자리 상태 색 55%, 안쪽 위 흰빛·아래 상태 색 고임, 흰 테두리 80%, 흰 ✦)
private final class GlassFace: NSView {
    var tint: NSColor? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 안쪽 그림자(CSS inset box-shadow): 구 바깥을 채운 모양의 그림자가 구 안으로 번지게 한다
    private func innerShadow(_ oval: NSBezierPath, color: NSColor, dy: CGFloat, blur: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        oval.addClip()
        let sh = NSShadow(); sh.shadowColor = color; sh.shadowBlurRadius = blur; sh.shadowOffset = CGSize(width: 0, height: dy); sh.set()
        let ring = NSBezierPath(rect: bounds.insetBy(dx: -20, dy: -20)); ring.append(oval); ring.windingRule = .evenOdd
        NSColor.black.setFill(); ring.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// 시안 SVG의 별 두 개(viewBox 24)
    private func sparkle(in r: CGRect) -> NSBezierPath {
        let k = r.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * k, y: r.maxY - y * k) }
        let p = NSBezierPath()
        for star in [[(12, 2), (14.2, 8.3), (20.5, 10.5), (14.2, 12.7), (12, 19), (9.8, 12.7), (3.5, 10.5), (9.8, 8.3)],
                     [(19, 15), (19.9, 17.1), (22, 18), (19.9, 18.9), (19, 21), (18.1, 18.9), (16, 18), (18.1, 17.1)]] as [[(CGFloat, CGFloat)]] {
            p.move(to: pt(star[0].0, star[0].1)); star.dropFirst().forEach { p.line(to: pt($0.0, $0.1)) }; p.close()
        }
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tint else { return }
        let oval = NSBezierPath(ovalIn: bounds)
        NSGradient(colorsAndLocations: (NSColor(white: 1, alpha: 0.75), 0), (NSColor(white: 1, alpha: 0.15), 0.38), (tint.withAlphaComponent(0.55), 1))!
            .draw(in: oval, relativeCenterPosition: NSPoint(x: -0.4, y: 0.5))
        innerShadow(oval, color: NSColor(white: 1, alpha: 0.9), dy: -1, blur: 2)      // inset 0 1px 2px 흰빛
        innerShadow(oval, color: tint.withAlphaComponent(0.45), dy: 3, blur: 6)        // inset 0 -3px 6px 상태 색
        let rim = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)); rim.lineWidth = 1
        NSColor(white: 1, alpha: 0.8).setStroke(); rim.stroke()
        let side = bounds.width * 22 / 42
        NSColor.white.setFill()
        sparkle(in: CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)).fill()
    }
}

/// 꺼내 둔 곰 머리 위 칩(마우스 통과). 큰 작업 구슬(F14)을 대신한다.
final class GlanceChipsView: NSView {
    var glance = Glance() { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let w = GlanceChips.width(glance) + 12
        let r = CGRect(x: (bounds.width - w) / 2, y: 1, width: w, height: GlanceChips.height + 8)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(white: 0.12, alpha: 0.92) : NSColor(white: 1, alpha: 0.95)).setFill()
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        NSGraphicsContext.current?.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.18); sh.shadowBlurRadius = 6; sh.shadowOffset = CGSize(width: 0, height: -2); sh.set()
        pill.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        GlanceChips.draw(glance, at: CGPoint(x: r.minX + 6, y: r.minY + 4), dark: dark)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 오늘 카드: 곰을 한 번 누르면 옆에 뜬다. 할 일·입력·다음 일정. (작업 알림은 원형 메뉴 '작업 목록'에서)
final class TodayCard: NSObject, NSTextFieldDelegate {
    static let shared = TodayCard()
    private var panel: FloatingPanel?
    private var monitors: [Any] = []
    private let input = NSTextField()
    private var stack = NSStackView()
    /// 지금 펫 몸 위치(펫을 옮기면 카드도 자식 창으로 따라가고, 다시 그릴 때 이 값으로 자리를 잡는다)
    private var anchor: () -> CGRect = { .zero }
    private var visible: CGRect = .zero
    /// 꺼내 둔 곰: 아래에(메뉴 막대와 겹치지 않게). 붙은 알약: 화면 안쪽 방향
    private var below = false
    private var problem: String?
    var onOpenSettings: () -> Void = {}
    /// 카드 맨 아래 버튼(설정·메뉴). 여는 쪽(펫/메뉴 막대)이 정한다
    var footer: [(String, () -> Void)] = []
    var isOpen: Bool { panel != nil }
    private static let width: CGFloat = 360

    func toggle(near anchor: @escaping () -> CGRect, in v: CGRect, below: Bool, parent: NSWindow?) {
        isOpen ? close() : open(near: anchor, in: v, below: below, parent: parent)
    }

    func open(near anchor: @escaping () -> CGRect, in v: CGRect, below: Bool, parent: NSWindow?) {
        close()
        self.anchor = anchor; visible = v; self.below = below; problem = nil
        let p = FloatingPanel(size: CGSize(width: Self.width, height: 200))
        p.keyable = true   // 입력칸을 누르면 바로 칠 수 있게(앱을 앞으로 가져오지는 않음)
        panel = p
        rebuild()
        p.orderFrontRegardless()
        parent?.addChildWindow(p, ordered: .above)   // 펫을 들고 옮기면 같이 움직인다
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53 { self?.close(); return nil }   // Esc
                return e
            },
        ].compactMap { $0 }
        TaskStore.shared.reload()
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: TaskStore.changedNote, object: nil)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        NotificationCenter.default.removeObserver(self, name: TaskStore.changedNote, object: nil)
        panel?.orderOut(nil); panel = nil
    }

    @objc private func changed() { if panel != nil { rebuild() } }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: s)
        f.font = .systemFont(ofSize: size, weight: weight); f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    private func box(_ views: [NSView], spacing: CGFloat = 2) -> NSView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing
        s.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        s.wantsLayer = true
        s.layer?.cornerRadius = 14
        s.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: Self.width - 28).isActive = true
        return s
    }

    /// 입력칸은 창이 열려 있는 동안 그대로 두고, 위·아래 줄만 바꾼다(입력 중 contentView를 다시 만들면 포커스·한글 조합이 끊긴다).
    private func rebuild() {
        guard let p = panel else { return }
        let now = Date()
        let store = TaskStore.shared
        let pending = TaskLogic.pending(store.items, now: now)
        var top: [NSView] = [], bottom: [NSView] = []

        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M월 d일 EEEE"
        top.append(label(f.string(from: now), size: 12, color: .secondaryLabelColor))
        let title = !TaskStore.anyOn ? "오늘도 반가워요" : pending.isEmpty ? "오늘 할 일을 다 했어요" : "할 일 \(pending.count)개 남았어요"
        top.append(label(title, size: 19, weight: .bold))

        if TaskStore.anyOn {
            if !pending.isEmpty {
                let checks: [NSView] = pending.prefix(5).map { item in
                    let b = ClosureButton(item.title) { TaskStore.shared.complete(item) }
                    b.setButtonType(.switch)
                    b.font = .systemFont(ofSize: 14)
                    return b
                }
                var list = checks
                if pending.count > 5 { list.append(label("외 \(pending.count - 5)개", size: 12, color: .secondaryLabelColor)) }
                top.append(box(list, spacing: 4))
            }
            if let problem { let l = label(problem, size: 12, color: .systemRed); l.lineBreakMode = .byWordWrapping; l.preferredMaxLayoutWidth = Self.width - 28; bottom.append(l) }
            if let e = store.items.filter({ $0.isEvent && $0.hasTime && ($0.date ?? .distantPast) >= now }).min(by: { $0.date! < $1.date! }),
               let d = e.date, Calendar.current.isDateInToday(d) {
                let mins = Int(d.timeIntervalSince(now) / 60)
                let when = mins < 60 ? "\(mins)분 뒤" : TaskWindow.timeText(d, hasTime: true)
                bottom.append(box([label("다음 일정", size: 11, weight: .semibold, color: .systemBlue), label(e.title, size: 14, weight: .semibold),
                                   label(TaskWindow.timeText(d, hasTime: true) + " · " + when, size: 12, color: .secondaryLabelColor)]))
            }
        } else {
            top.append(box([label("할 일·일정을 켜면 여기에 보여요", size: 13, color: .secondaryLabelColor),
                            ClosureButton("설정 열기") { [weak self] in self?.close(); self?.onOpenSettings() }]))
        }
        input.isHidden = !TaskStore.anyOn
        if !footer.isEmpty {
            let buttons: [NSView] = footer.map { f in
                let b = ClosureButton(f.0) { [weak self] in self?.close(); f.1() }
                b.bezelStyle = .inline; b.font = .systemFont(ofSize: 12)
                return b
            }
            let row = NSStackView(views: buttons); row.spacing = 8
            bottom.append(row)
        }

        if p.contentView !== root { buildRoot(in: p) }
        topStack.setViews(top, in: .leading)
        bottomStack.setViews(bottom, in: .leading)
        bottomStack.isHidden = bottom.isEmpty
        let size = CGSize(width: Self.width, height: stack.fittingSize.height)
        p.setFrame(place(size), display: true)
    }

    private let root = NSView()
    private let topStack = NSStackView(), bottomStack = NSStackView()

    /// 창마다 한 번: 유리 배경 + [위 줄, 입력칸, 아래 줄]
    private func buildRoot(in p: FloatingPanel) {
        root.subviews.forEach { $0.removeFromSuperview() }
        root.frame = CGRect(origin: .zero, size: p.frame.size)
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true
        for s in [topStack, bottomStack] { s.orientation = .vertical; s.alignment = .leading; s.spacing = 10 }
        if input.target == nil {
            input.placeholderString = "내일 3시 치과처럼 적고 ↩"
            input.font = .systemFont(ofSize: 14)
            input.bezelStyle = .roundedBezel
            input.delegate = self
            input.target = self; input.action = #selector(submit)
            input.cell?.sendsActionOnEndEditing = false   // 칸을 떠날 때는 추가하지 않는다
            input.translatesAutoresizingMaskIntoConstraints = false
            input.widthAnchor.constraint(equalToConstant: Self.width - 28).isActive = true
        }
        stack = NSStackView(views: [topStack, input, bottomStack])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 14, bottom: 14, right: 14)
        let glass = makeGlass(cornerRadius: 22, frame: root.bounds)
        glass.autoresizingMask = [.width, .height]
        stack.autoresizingMask = [.width, .height]
        stack.frame = root.bounds
        root.addSubview(glass)
        root.addSubview(stack)
        p.contentView = root
    }

    /// 펫 옆(화면 안쪽 방향), 화면 밖으로 나가지 않게
    private func place(_ size: CGSize) -> CGRect {
        let near = anchor()
        let v = visible, shown = near.intersection(v).isNull ? near : near.intersection(v)
        if below {   // 몸 아래 가운데, 아래 자리가 모자라면 위로
            let x = min(max(shown.midX - size.width / 2, v.minX + 8), v.maxX - size.width - 8)
            var y = shown.minY - size.height - 12
            if y < v.minY + 8 { y = min(shown.maxY + 12, v.maxY - size.height - 8) }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        var x = shown.midX > v.midX ? shown.minX - size.width - 10 : shown.maxX + 10
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        var y = shown.midY - size.height / 2
        if shown.maxY > v.maxY - 60 { y = shown.minY - size.height - 8; x = min(max(shown.midX - size.width / 2, v.minX + 8), v.maxX - size.width - 8) }
        y = min(max(y, v.minY + 8), v.maxY - size.height - 8)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// ↩(텍스트 칸 동작). 한글 조합 중 ↩도 조합이 끝난 뒤 여기로 온다.
    @objc private func submit() {
        let text = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard panel != nil, !text.isEmpty else { return }
        let r = QuickParse.parse(text)
        let store = TaskStore.shared
        problem = store.add(title: r.title, date: r.date, hasTime: r.hasTime, asEvent: r.hasTime && store.canAddEvent)
        if problem == nil { input.stringValue = "" } else { NSSound.beep() }
        rebuild()
        panel?.makeFirstResponder(input)
    }
}
