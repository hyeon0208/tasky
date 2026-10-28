import AppKit

// F14 작업 구슬: 펫 머리 위에 작업 하나당 구슬 하나. 근거: intent/F14-작업구슬-화면위치/

struct Bead: Equatable {
    enum Kind: Equatable { case working, waiting, failed, done, converting, more(Int) }
    let kind: Kind
    /// C = Claude Code, X = Codex, ⇄ = 변환
    let tag: String
    let big: Bool
    let title: String
    /// 마지막 활동 시각(이름표의 'N분 전'은 올릴 때 계산)
    var at: Date? = nil
}

/// 세션·변환 → 구슬 목록(순수 계산, 자체 검사 대상)
enum BeadModel {
    static let maxShown = 4

    static func beads(sessions: [AgentSession], converting: Int, frontApp: String?, accepts: (String) -> Bool, now: Date = Date()) -> [Bead] {
        let shown = sessions.filter { s in accepts(s.tool) && (s.state != .done || !s.seen) }
        // 앞 = 맨 앞 앱에서 돈 세션, 그중 가장 최근 하나만 큰 구슬
        let front = shown.filter { $0.app != nil && $0.app == frontApp }.max { $0.updated < $1.updated }
        let rank: (AgentSession.State) -> Int = { [.waiting: 0, .failed: 1, .done: 2, .working: 3][$0]! }
        let rest = shown.filter { $0.id != front?.id }.sorted { rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state) : $0.updated > $1.updated }
        func bead(_ s: AgentSession, big: Bool) -> Bead {
            let kind: Bead.Kind = switch s.state { case .working: .working; case .waiting: .waiting; case .failed: .failed; case .done: .done }
            return Bead(kind: kind, tag: s.tool == "codex" ? "X" : "C", big: big, title: s.name, at: s.updated)
        }
        var small = rest.map { bead($0, big: false) }
        small += Array(repeating: Bead(kind: .converting, tag: "⇄", big: false, title: "파일 바꾸는 중"), count: converting)
        let room = maxShown - (front == nil ? 0 : 1)
        if small.count > room {
            let extra = small.count - (room - 1)
            small = Array(small.prefix(room - 1)) + [Bead(kind: .more(extra), tag: "", big: false, title: "작업 \(extra)개 더")]
        }
        guard let front else { return small }
        // 큰 구슬을 가운데에: 작은 것들을 양옆으로 나눈다
        let half = small.count / 2
        return Array(small.prefix(half)) + [bead(front, big: true)] + Array(small.dropFirst(half))
    }
}

/// 구슬 줄 패널(펫의 자식 창). 구슬 위에서만 마우스를 받는다.
final class BeadsView: NSView {
    var beads: [Bead] = [] { didSet { if beads != oldValue { rebuild() } } }
    var onClick: () -> Void = {}
    private var frames: [CGRect] = []
    private let label = NSTextField(labelWithString: "")
    private var hovered: Int?

    static let big: CGFloat = 34, small: CGFloat = 22, gap: CGFloat = 6, labelHeight: CGFloat = 20

    static func width(_ beads: [Bead]) -> CGFloat {
        beads.reduce(0) { $0 + ($1.big ? big : small) + 8 } + gap * CGFloat(max(beads.count - 1, 0))
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        label.layer?.cornerRadius = 6
        label.isHidden = true
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return frames.contains { $0.contains(p) } ? self : nil
    }

    private func rebuild() {
        layer?.sublayers?.filter { $0.name == "bead" }.forEach { $0.removeFromSuperlayer() }
        frames = []
        var x = (bounds.width - Self.width(beads)) / 2
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for b in beads {
            let d = b.big ? Self.big : Self.small
            let box = CGRect(x: x, y: Self.labelHeight + 2, width: d + 8, height: d + 8)
            frames.append(box)
            layer?.addSublayer(Self.beadLayer(b, in: box, spin: !reduce))
            x += d + 8 + Self.gap
        }
        updateTracking()
    }

    private static func colors(_ k: Bead.Kind) -> [NSColor] {
        func c(_ hex: UInt32) -> NSColor { NSColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
        switch k {
        case .working, .converting: return [c(0x8CC8FF), c(0x0A84FF), c(0x0057B8)]
        case .waiting: return [c(0xFFD38A), c(0xFF9F0A), c(0xC06A00)]
        case .done: return [c(0x9BF0B0), c(0x30C25A), c(0x1A7A36)]
        case .failed: return [c(0xFF9A92), c(0xFF453A), c(0xB0241B)]
        case .more: return [c(0xD8D8DC), c(0x8E8E93), c(0x5A5A5E)]
        }
    }

    private static func beadLayer(_ b: Bead, in box: CGRect, spin: Bool) -> CALayer {
        let d = b.big ? big : small
        let root = CALayer()
        root.name = "bead"
        root.frame = box
        let ball = CAGradientLayer()
        ball.type = .radial
        ball.frame = CGRect(x: 4, y: 4, width: d, height: d)
        ball.cornerRadius = d / 2
        ball.colors = colors(b.kind).map(\.cgColor)
        ball.locations = [0, 0.48, 1]
        ball.startPoint = CGPoint(x: 0.34, y: 0.72)
        ball.endPoint = CGPoint(x: 1.1, y: -0.1)
        ball.shadowOpacity = 0.3
        ball.shadowRadius = b.big ? 5 : 3
        ball.shadowOffset = CGSize(width: 0, height: -3)
        root.addSublayer(ball)
        let shine = CAGradientLayer()
        shine.frame = CGRect(x: 4 + d * 0.2, y: 4 + d * 0.62, width: d * 0.42, height: d * 0.24)
        shine.cornerRadius = d * 0.12
        shine.colors = [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        shine.startPoint = CGPoint(x: 0.5, y: 1)
        shine.endPoint = CGPoint(x: 0.5, y: 0)
        shine.setAffineTransform(CGAffineTransform(rotationAngle: 0.35))
        root.addSublayer(shine)
        let mark: String = switch b.kind { case .waiting: "!"; case .done: "✓"; case .failed: "×"; case .more(let n): "+\(n)"; default: "" }
        if !mark.isEmpty {
            let t = CATextLayer()
            t.string = mark
            t.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
            t.fontSize = b.big ? 16 : (mark.count > 2 ? 9 : 11)
            t.foregroundColor = NSColor.white.cgColor
            t.alignmentMode = .center
            t.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            t.frame = CGRect(x: 4, y: 4 + d / 2 - t.fontSize * 0.62, width: d, height: t.fontSize * 1.3)
            root.addSublayer(t)
        }
        if b.kind == .working || b.kind == .converting {
            // 일하는 중: 둘레를 도는 고리
            let ring = CAShapeLayer()
            ring.frame = root.bounds
            ring.path = CGPath(ellipseIn: root.bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor(red: 0.04, green: 0.52, blue: 1, alpha: 1).cgColor
            ring.lineWidth = 2.5
            ring.lineCap = .round
            ring.strokeEnd = 0.28
            if spin {
                let a = CABasicAnimation(keyPath: "transform.rotation.z")
                a.fromValue = 0
                a.toValue = -2 * Double.pi
                a.duration = 1.2
                a.repeatCount = .infinity
                ring.add(a, forKey: "spin")
            }
            root.addSublayer(ring)
        }
        if !b.tag.isEmpty {
            let tag = CATextLayer()
            tag.string = b.tag
            tag.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            tag.fontSize = 9
            tag.foregroundColor = NSColor.white.cgColor
            tag.backgroundColor = NSColor(white: 0.11, alpha: 1).cgColor
            tag.cornerRadius = 5
            tag.alignmentMode = .center
            tag.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            tag.frame = CGRect(x: box.width / 2 - 8, y: -2, width: 16, height: 12)
            root.addSublayer(tag)
        }
        return root
    }

    // MARK: 이름표·클릭

    private func updateTracking() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = frames.firstIndex { $0.contains(p) }
        guard i != hovered else { return }
        hovered = i
        guard let i else { label.isHidden = true; return }
        let at = beads[i].at.map { Int(Date().timeIntervalSince($0) / 60) }.map { $0 < 1 ? " · 방금 활동" : " · \($0)분 전 활동" } ?? ""
        label.stringValue = " \(beads[i].title)\(at) "
        let w = min(label.intrinsicContentSize.width + 8, bounds.width)
        label.frame = CGRect(x: min(max(frames[i].midX - w / 2, 0), bounds.width - w), y: 0, width: w, height: Self.labelHeight - 2)
        label.isHidden = false
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; label.isHidden = true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() { super.updateTrackingAreas(); updateTracking() }

    /// 기다리는 구슬의 가운데 x(뷰 좌표), 없으면 nil
    var waitingX: CGFloat? {
        beads.firstIndex { $0.kind == .waiting }.map { frames[$0].midX }
    }
}

/// 설정: 작업 구슬 보이기(모든 펫 공통, 기본 켜짐)
enum BeadsSetting {
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "beadsOn") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "beadsOn")
            NotificationCenter.default.post(name: ClockMode.changed, object: nil)
        }
    }
}
