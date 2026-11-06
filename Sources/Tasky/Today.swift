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
    /// F28: 오늘 남은 일정 중 `next` 다음 것 개수(받침대 '외 N')
    var moreEvents = 0
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
        var count = 0
        for i in items where i.isEvent && i.hasTime {
            guard let d = i.date, d >= from, d < end else { continue }
            count += 1
            if best == nil || d < best!.date! { best = i }
        }
        g.moreEvents = max(0, count - 1)
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

/// F27 받침대: 곰 발밑 유리 판. 시계(크게) · 할 일 수/다음 일정(작은 두 줄) · 오른쪽 끝 상태 구슬.
/// 구슬만 누를 수 있고, 커서가 받침대에서 나가면 `onExit`로 알린다(갖다대면 모드에서 숨기기).
final class StandView: NSView {
    static let height: CGFloat = 40   // F28 11차 B: 컴팩트 한 줄
    let orb = AgentBadgeView(frame: .zero)
    var onExit: () -> Void = {}
    var onEnter: () -> Void = {}
    var clock = "" { didSet { if clock != oldValue { clockLabel.stringValue = clock; invalidateIntrinsicContentSize() } } }
    var glance = Glance() { didSet { if glance != oldValue { refresh() } } }
    private let glass = makeGlass(cornerRadius: StandView.height / 2, frame: .zero)
    private let clockLabel = NSTextField(labelWithString: "")
    private let taskLabel = NSTextField(labelWithString: "")
    private let nextLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        addSubview(glass)
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .heavy); clockLabel.textColor = .white
        taskLabel.font = .systemFont(ofSize: 11, weight: .semibold); taskLabel.textColor = NSColor(red: 0.54, green: 0.71, blue: 1, alpha: 1)
        nextLabel.font = .systemFont(ofSize: 12, weight: .semibold); nextLabel.textColor = NSColor(red: 1, green: 0.82, blue: 0.54, alpha: 1)
        for l in [taskLabel, nextLabel] { l.lineBreakMode = .byTruncatingTail }
        [clockLabel, taskLabel, nextLabel, orb].forEach(addSubview)
        orb.wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private func width(_ l: NSTextField) -> CGFloat { ceil((l.stringValue as NSString).size(withAttributes: [.font: l.font!]).width) + 6 }
    private func part(_ l: NSTextField) -> CGFloat { l.stringValue.isEmpty ? 0 : min(170, width(l)) + 10 }
    override var fittingSize: NSSize {
        NSSize(width: 14 + width(clockLabel) + part(taskLabel) + part(nextLabel) + (orb.state == nil ? 10 : 36), height: Self.height)
    }

    private func refresh() {
        // 한 줄: 시계 · 할 일 N · 다음 일정(외 N)
        taskLabel.stringValue = glance.showsTasks ? "할 일 \(glance.tasks)" : ""
        nextLabel.stringValue = glance.next.isEmpty ? (glance.tasksOn && !glance.showsTasks ? "오늘 일정 없음" : "") : glance.next + (glance.moreEvents > 0 ? " 외 \(glance.moreEvents)" : "")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        let c = CGSize(width: width(clockLabel), height: clockLabel.intrinsicContentSize.height)
        clockLabel.frame = CGRect(x: 14, y: (bounds.height - c.height) / 2, width: c.width, height: c.height)
        var x = clockLabel.frame.maxX + 10
        for l in [taskLabel, nextLabel] where !l.stringValue.isEmpty {
            l.frame = CGRect(x: x, y: (bounds.height - 16) / 2, width: min(170, width(l)), height: 16)
            x += part(l)
        }
        orb.frame = CGRect(x: bounds.maxX - 34, y: (bounds.height - 28) / 2 - 2, width: 28, height: 28)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { orb.hitTest(point) ?? (bounds.contains(convert(point, from: superview)) ? self : nil) }
    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseExited(with event: NSEvent) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onExit() } }
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

    func toggle(near anchor: @escaping () -> CGRect, in v: CGRect, below: Bool, parent: NSWindow?, growFrom: CGRect? = nil) {
        isOpen ? close() : open(near: anchor, in: v, below: below, parent: parent, growFrom: growFrom)
    }
    /// F27 10차 A+F: 받침대 자리에서 자라나 열린다(받침대 윗변에 붙은 채 아래로). 닫히면 알린다
    private var growFrom: CGRect?
    private var growTop: CGRect?
    var onClose: () -> Void = {}

    func open(near anchor: @escaping () -> CGRect, in v: CGRect, below: Bool, parent: NSWindow?, growFrom: CGRect? = nil) {
        close()
        self.growFrom = growFrom
        growTop = growFrom
        self.anchor = anchor; visible = v; self.below = below; problem = nil
        let p = FloatingPanel(size: CGSize(width: Self.width, height: 200))
        p.appearance = NSAppearance(named: .darkAqua)   // F27: 시안의 어두운 유리
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
        defer { if panel == nil, closing { closing = false; onClose(); onClose = {} } }
        closing = panel != nil
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

    /// F27: AI 작업 덩어리 줄(이름·상태 글·색). 여는 쪽(펫)이 정한다
    var agentRows: () -> [(String, String, NSColor)] = { [] }
    var showsAgents = true
    var onOpenAgents: () -> Void = {}

    /// F28: 줄에 커서를 올리면 오른쪽 끝에 휴지통(바꿀 수 없는 캘린더는 없음). 누르면 4초 되돌리기 뒤 지움
    private func trashRow(_ content: NSView, _ item: TaskItem) -> NSView {
        guard item.ref?.calendar.allowsContentModifications == true else { return content }
        return TrashRow(content, width: Self.width - 28 - 24) { TaskStore.shared.deleteLater(item) }
    }

    /// 색 제목 + 줄들을 담은 덩어리(F27 4번 B)
    private func block(_ title: String, _ color: NSColor, _ rows: [NSView], onClick: (() -> Void)? = nil) -> NSView {
        let head = label(title, size: 12, weight: .bold, color: color)
        let b = box([head] + rows, spacing: 6)
        if let onClick {
            b.addGestureRecognizer(BlockClick(onClick))
        }
        return b
    }

    /// 입력칸은 창이 열려 있는 동안 그대로 두고, 위·아래 줄만 바꾼다(입력 중 contentView를 다시 만들면 포커스·한글 조합이 끊긴다).
    private func rebuild() {
        guard let p = panel else { return }
        let now = Date()
        let store = TaskStore.shared
        let pending = TaskLogic.pending(store.items, now: now)
        var top: [NSView] = [], bottom: [NSView] = []

        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M월 d일 EEEE"
        top.append(label("오늘 · " + f.string(from: now), size: 15, weight: .bold))

        if TaskStore.anyOn {
            // 할 일
            var todos: [NSView] = pending.prefix(4).map { item in
                let b = ClosureButton(item.title) { TaskStore.shared.complete(item) }
                b.setButtonType(.switch)
                b.font = .systemFont(ofSize: 13)
                return trashRow(b, item)
            }
            if pending.count > 4 { todos.append(label("외 \(pending.count - 4)개", size: 11, color: .secondaryLabelColor)) }
            if todos.isEmpty { todos = [label(TaskStore.remindersOn ? "남은 할 일이 없어요" : "설정에서 미리 알림을 켜면 보여요", size: 12, color: .secondaryLabelColor)] }
            // F32: 오늘 끝낸 할 일은 맨 아래에 흐린 취소선(최대 3줄). 체크를 풀면 완료를 푼다
            let done = TaskLogic.doneToday(store.doneItems, now: now)
            todos += done.prefix(3).map { item in
                let b = ClosureButton("") { TaskStore.shared.uncomplete(item) }
                b.setButtonType(.switch)
                b.state = .on
                b.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor,
                                                                                         .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                return b
            }
            if done.count > 3 { todos.append(label("끝낸 것 외 \(done.count - 3)개", size: 11, color: .secondaryLabelColor)) }
            top.append(block(pending.isEmpty ? "할 일" : "할 일 \(pending.count)", NSColor(red: 0.54, green: 0.71, blue: 1, alpha: 1), todos))
            // 일정(설정한 기간까지)
            let events = TaskLogic.upcomingEvents(store.items, now: now, days: TaskStore.eventDays)
            var evRows: [NSView] = events.prefix(4).map { e in
                let d = e.date ?? now
                let mins = Int(d.timeIntervalSince(now) / 60)
                let when = mins >= 0 && mins < 60 ? " · \(mins)분 뒤" : ""
                let l = label(TaskWindow.timeText(d, hasTime: e.hasTime) + "  " + e.title + when, size: 13, weight: .semibold)
                // F28: 일정을 누르면 그 자리에서 고치기(이름·날짜·시간). 바꿀 수 없는 캘린더(공휴일 등)는 안내만
                let row = ClickRow(views: [l])
                row.toolTip = e.ref?.calendar.allowsContentModifications == true ? "눌러서 고치기" : "이 캘린더는 고칠 수 없어요"
                row.onClick = { [weak row] in
                    guard let row, e.ref?.calendar.allowsContentModifications == true else { NSSound.beep(); return }
                    TaskWindow.shared.edit(e, from: row)
                }
                return trashRow(row, e)
            }
            if events.count > 4 { evRows.append(label("외 \(events.count - 4)개", size: 11, color: .secondaryLabelColor)) }
            if evRows.isEmpty { evRows = [label(TaskStore.eventsOn ? "\(TaskStore.eventDays)일 안에 일정이 없어요" : "설정에서 캘린더를 켜면 보여요", size: 12, color: .secondaryLabelColor)] }
            top.append(block(TaskStore.eventDays == 1 ? "일정 · 오늘" : "일정 · \(TaskStore.eventDays)일", NSColor(red: 1, green: 0.82, blue: 0.54, alpha: 1), evRows))
            if let problem { let l = label(problem, size: 12, color: .systemRed); l.lineBreakMode = .byWordWrapping; l.preferredMaxLayoutWidth = Self.width - 28; bottom.append(l) }
        } else {
            top.append(box([label("할 일·일정을 켜면 여기에 보여요", size: 13, color: .secondaryLabelColor),
                            ClosureButton("설정 열기") { [weak self] in self?.close(); self?.onOpenSettings() }]))
        }
        // AI 작업
        let agents = showsAgents ? agentRows() : []
        var agRows: [NSView] = agents.prefix(3).map { a in
            let dot = NSTextField(labelWithString: "●"); dot.font = .systemFont(ofSize: 10); dot.textColor = a.2
            let row = NSStackView(views: [dot, label(a.0, size: 13, weight: .semibold), label(a.1, size: 12, color: .secondaryLabelColor)])
            row.spacing = 6
            return row
        }
        if agRows.isEmpty { agRows = [label("진행 중인 작업이 없어요", size: 12, color: .secondaryLabelColor)] }
        if showsAgents { top.append(block("AI 작업", NSColor(red: 0.53, green: 0.94, blue: 0.67, alpha: 1), agRows) { [weak self] in self?.close(); self?.onOpenAgents() }) }

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
        let target = place(size)
        if let g = growFrom, !p.isVisible || p.frame.size == CGSize(width: Self.width, height: 200) {
            // 처음 열 때만: 받침대 크기에서 시작해 카드로 늘어난다
            growFrom = nil
            p.setFrame(g, display: true)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { p.setFrame(target, display: true) }
            else { NSAnimationContext.runAnimationGroup { $0.duration = 0.25; $0.timingFunction = CAMediaTimingFunction(name: .easeOut); p.animator().setFrame(target, display: true) } }
        } else {
            p.setFrame(target, display: true)
        }
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
            input.placeholderString = "할 일 또는 일정 추가"
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
    private var closing = false

    private func place(_ size: CGSize) -> CGRect {
        if let g = growTop {   // 받침대 윗변에 붙여 아래로(A+F)
            let v = visible
            let x = min(max(g.midX - size.width / 2, v.minX + 8), v.maxX - size.width - 8)
            var y = g.maxY - size.height
            if y < v.minY + 8 { y = v.minY + 8 }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
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

/// 덩어리 누르기: 동작을 인식기가 직접 들고 있어 뷰와 함께 사라진다(공유 표에 남던 누수 없앰)
final class BlockClick: NSClickGestureRecognizer {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(target: nil, action: nil)
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// 받침대 목록의 할 일 동그라미: 누르면 ✓, 1초 뒤 완료. 그 사이 다시 누르면 되돌림
final class CheckCircle: NSView {
    private let color: NSColor, onToggle: (Bool) -> Void, commit: () -> Void
    private var done = false, work: DispatchWorkItem?
    init(color: NSColor, onToggle: @escaping (Bool) -> Void, commit: @escaping () -> Void) {
        self.color = color; self.onToggle = onToggle; self.commit = commit
        super.init(frame: .zero)
        toolTip = "눌러서 완료"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 4)
        let circle = NSBezierPath(ovalIn: r)
        if done {
            color.setFill(); circle.fill()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: r.minX + r.width * 0.26, y: r.midY))
            tick.line(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.3))
            tick.line(to: CGPoint(x: r.minX + r.width * 0.76, y: r.minY + r.height * 0.7))
            tick.lineWidth = 1.8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(0.75).setStroke(); tick.stroke()
        } else {
            circle.lineWidth = 1.6; color.setStroke(); circle.stroke()
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        done.toggle(); needsDisplay = true; onToggle(done)
        work?.cancel(); work = nil
        guard done else { return }
        let w = DispatchWorkItem { [weak self] in self?.commit() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// F28 시안 C: 커서를 올린 줄에만 회색 휴지통(13pt), 휴지통 위에선 빨간색
final class TrashRow: NSStackView {
    private let trash: TrashButton
    init(_ content: NSView, width: CGFloat, onDelete: @escaping () -> Void) {
        trash = TrashButton(onDelete)
        super.init(frame: .zero)
        orientation = .horizontal; spacing = 6
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (content as? NSButton)?.cell?.lineBreakMode = .byTruncatingTail
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        setViews([content, spacer, trash], in: .leading)
        trash.alphaValue = 0
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { trash.alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { trash.alphaValue = 0 }
}

final class TrashButton: NSButton {
    private let onDelete: () -> Void
    init(_ onDelete: @escaping () -> Void) {
        self.onDelete = onDelete
        super.init(frame: .zero)
        isBordered = false; imagePosition = .imageOnly; toolTip = "지우기(4초 안에 되돌릴 수 있어요)"
        image = NSImage(systemSymbolName: "trash", accessibilityDescription: "지우기")?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        contentTintColor = .secondaryLabelColor
        target = self; action = #selector(fire)
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { onDelete() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { contentTintColor = .systemRed }
    override func mouseExited(with event: NSEvent) { contentTintColor = .secondaryLabelColor }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// 누르면 동작하는 줄(손가락 커서)
final class ClickRow: NSStackView {
    var onClick: () -> Void = {}
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// F28 11차 B: 받침대에 커서를 올리면 아래에 붙는 오늘 남은 일정 목록(누르면 고치기)
final class StandEvents {
    private(set) var panel: FloatingPanel?
    /// 시안 A(2026-11-06): 할 일(파랑 제목) 위, 구분선, 일정(노랑 제목) 아래. 각각 4줄까지.
    /// 할 일 ○를 누르면 ✓·취소선으로 바뀌고 1초 뒤 완료(그 사이 다시 누르면 되돌림)
    func show(_ events: [TaskItem], todos: [TaskItem] = [], below stand: CGRect, parent: NSWindow?, onLeave: @escaping () -> Void) {
        hide()
        let todoRows = Array(todos.prefix(4)), eventRows = Array(events.prefix(4))
        guard !todoRows.isEmpty || !eventRows.isEmpty else { return }
        let blue = NSColor(red: 0.54, green: 0.71, blue: 1, alpha: 1), yellow = NSColor(red: 1, green: 0.82, blue: 0.54, alpha: 1)
        let rowH: CGFloat = 28, headH: CGFloat = 22, gap: CGFloat = 13, w = max(200, stand.width)
        func blockH(_ n: Int) -> CGFloat { n == 0 ? 0 : headH + CGFloat(n) * rowH }
        let h = 12 + blockH(todoRows.count) + blockH(eventRows.count) + (todoRows.isEmpty || eventRows.isEmpty ? 0 : gap)
        let p = FloatingPanel(size: CGSize(width: w, height: h))
        p.appearance = NSAppearance(named: .darkAqua)
        p.setFrame(CGRect(x: stand.midX - w / 2, y: stand.minY - h - 4, width: w, height: h), display: false)
        let root = TrackingView(frame: CGRect(origin: .zero, size: p.frame.size))
        root.onExit = onLeave
        root.addSubview(makeGlass(cornerRadius: 14, frame: root.bounds))
        var y = h - 6   // 위에서부터 내려온다
        func head(_ text: String, _ color: NSColor) {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 11, weight: .bold); l.textColor = color
            y -= headH
            l.frame = CGRect(x: 14, y: y + 3, width: w - 28, height: 15)
            root.addSubview(l)
        }
        func titleLabel(_ text: String) -> NSTextField {
            let t = NSTextField(labelWithString: text)
            t.font = .systemFont(ofSize: 12, weight: .semibold); t.textColor = .white; t.lineBreakMode = .byTruncatingTail
            return t
        }
        if !todoRows.isEmpty {
            head("할 일 \(todos.count)", blue)
            for item in todoRows {
                y -= rowH
                let title = titleLabel(item.title)
                let row = ClickRow(views: [title])
                row.frame = CGRect(x: 40, y: y + 5, width: w - 54, height: 18)
                row.toolTip = "눌러서 고치기"
                row.onClick = { [weak row] in if let row { TaskWindow.shared.edit(item, from: row) } }
                let check = CheckCircle(color: blue) { [weak title] done in
                    title?.attributedStringValue = NSAttributedString(string: item.title, attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: done ? NSColor.white.withAlphaComponent(0.45) : NSColor.white,
                        .strikethroughStyle: done ? NSUnderlineStyle.single.rawValue : 0])
                } commit: { TaskStore.shared.complete(item) }
                check.frame = CGRect(x: 12, y: y + 3, width: 22, height: 22)
                root.addSubview(check); root.addSubview(row)
            }
        }
        if !todoRows.isEmpty, !eventRows.isEmpty {
            let line = NSBox(frame: CGRect(x: 14, y: y - gap / 2, width: w - 28, height: 1))
            line.boxType = .custom; line.borderWidth = 0; line.fillColor = NSColor.white.withAlphaComponent(0.12)
            root.addSubview(line)
            y -= gap
        }
        if !eventRows.isEmpty {
            head("일정 \(events.count)", yellow)
            let f = DateFormatter(); f.dateFormat = "H:mm"
            for e in eventRows {
                y -= rowH
                let d = e.date ?? Date()
                let mins = Int(d.timeIntervalSinceNow / 60)
                let time = NSTextField(labelWithString: f.string(from: d))
                time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold); time.textColor = yellow
                let row = ClickRow(views: [time, titleLabel(e.title + (mins >= 0 && mins < 60 ? " · \(mins)분 뒤" : ""))]); row.spacing = 10
                row.frame = CGRect(x: 14, y: y + 5, width: w - 28, height: 18)
                let editable = e.ref?.calendar.allowsContentModifications == true
                row.toolTip = editable ? "눌러서 고치기" : "이 캘린더는 고칠 수 없어요"
                row.onClick = { [weak row] in
                    guard let row, editable else { NSSound.beep(); return }
                    TaskWindow.shared.edit(e, from: row)
                }
                root.addSubview(row)
            }
        }
        p.contentView = root
        p.orderFrontRegardless()
        parent?.addChildWindow(p, ordered: .above)
        panel = p
    }
    func hide() { panel?.parent?.removeChildWindow(panel!); panel?.orderOut(nil); panel = nil }
}

final class TrackingView: NSView {
    var onExit: () -> Void = {}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseExited(with event: NSEvent) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.onExit() } }
}
