import AppKit
import QuickLookThumbnailing

// F27 9번: 원형 변환. 파일을 들고 곰에 오면 곰 위에 둥근 부채꼴 칸이 펼쳐지고, 칸에 놓으면 변환한다.
// 칸이 7개 이하면 고리 하나, 넘으면 안쪽(형식)·바깥(동작) 두 고리. 화면 끝에서는 반원.

struct WheelItem {
    let title: String
    var note: String? = nil
    var isFormat = true
    /// 칸에 올렸을 때 가운데 원에 보일 설명
    var detail: String = ""
    let action: () -> Void
}

/// 칸 배치와 맞추기(순수 계산, 자체 검사 대상). 각도는 도(반시계, 0 = 오른쪽), 칸은 `start`에서 시계 방향으로.
enum WheelMath {
    struct Wedge: Equatable { var r0: CGFloat, r1: CGFloat, a0: Double, a1: Double }   // a0 > a1 (시계 방향)
    static let single = (r0: CGFloat(60), r1: CGFloat(170))
    static let inner = (r0: CGFloat(52), r1: CGFloat(116))
    static let outer = (r0: CGFloat(120), r1: CGFloat(182))
    static let maxSingle = 7

    /// 화면 끝에 가까우면 반대쪽으로 반원: (시작 각, 펼침 각)
    static func arc(center c: CGPoint, in v: CGRect, reach: CGFloat) -> (start: Double, span: Double) {
        if c.y - reach < v.minY { return (180, 180) }   // 아래 끝 → 위 반원
        if c.y + reach > v.maxY { return (0, 180) }     // 위 끝 → 아래 반원
        if c.x - reach < v.minX { return (90, 180) }    // 왼쪽 끝 → 오른쪽 반원
        if c.x + reach > v.maxX { return (270, 180) }   // 오른쪽 끝 → 왼쪽 반원
        return (90, 360)                               // 위에서 시작해 한 바퀴
    }

    /// `formats`·`actions` 개수로 칸 자리. 고리 하나면 순서대로 한 고리에
    static func layout(formats: Int, actions: Int, start: Double, span: Double) -> [Wedge] {
        func ring(_ n: Int, _ r: (r0: CGFloat, r1: CGFloat)) -> [Wedge] {
            guard n > 0 else { return [] }
            let step = span / Double(n)
            return (0..<n).map { i in Wedge(r0: r.r0, r1: r.r1, a0: start - Double(i) * step, a1: start - Double(i + 1) * step) }
        }
        let total = formats + actions
        if total <= maxSingle || formats == 0 || actions == 0 { return ring(total, single) }
        return ring(formats, inner) + ring(actions, outer)
    }

    static func outerRadius(_ wedges: [Wedge]) -> CGFloat { wedges.map(\.r1).max() ?? single.r1 }

    /// 가운데에서 `p`만큼 떨어진 점이 몇 번 칸인지(칸 사이 틈은 이웃 칸으로 봐 손떨림에 너그럽게)
    static func slot(_ p: CGPoint, _ wedges: [Wedge]) -> Int? {
        let d = hypot(p.x, p.y)
        var a = atan2(Double(p.y), Double(p.x)) * 180 / .pi
        return wedges.firstIndex { w in
            guard d >= w.r0 - 2, d <= w.r1 + 6 else { return false }
            while a > w.a0 { a -= 360 }
            while a <= w.a0 - 360 { a += 360 }
            return a > w.a1
        }
    }
}

final class ConvertWheelView: NSView {
    var items: [WheelItem] = [] { didSet { needsDisplay = true } }
    var wedges: [WheelMath.Wedge] = []
    var center = CGPoint.zero
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    var caption = ""
    var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    /// 놓은 뒤 변환 중(가운데 진행 링이 돈다)
    var working: String? { didSet { needsDisplay = true; spin() } }
    var onPick: (Int) -> Void = { _ in }
    var onCenterDrop: () -> Void = {}
    private var angle: CGFloat = 0
    private var spinTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { spinTimer?.invalidate() }

    private func spin() {
        spinTimer?.invalidate(); spinTimer = nil
        guard working != nil else { return }
        spinTimer = Ticker.every("변환 진행 링", 1 / 30) { [weak self] _ in self?.angle -= 8; self?.needsDisplay = true }
    }

    private func point(_ sender: NSDraggingInfo) -> CGPoint {
        let p = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: p.x - center.x, y: p.y - center.y)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard working == nil else { return [] }
        hovered = WheelMath.slot(point(sender), wedges)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard working == nil else { return false }
        if let i = WheelMath.slot(point(sender), wedges) { onPick(i) } else { onCenterDrop() }
        return true
    }

    /// 모서리 둥근 부채꼴: 반지름 `rad`만큼 안으로 줄인 모양을 같은 색의 굵은 둥근 선으로 감싼다
    private func wedgePath(_ w: WheelMath.Wedge, rad: CGFloat = 9, gap: CGFloat = 5, push: CGFloat = 0) -> NSBezierPath {
        let a = w.r0 + rad, b = w.r1 - rad
        let mid = (w.a0 + w.a1) / 2 * .pi / 180
        let c = CGPoint(x: center.x + push * cos(mid), y: center.y + push * sin(mid))
        let io = Double((gap / 2 + rad) / b) * 180 / .pi, ii = Double((gap / 2 + rad) / a) * 180 / .pi
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: b, startAngle: w.a0 - io, endAngle: w.a1 + io, clockwise: true)
        p.appendArc(withCenter: c, radius: a, startAngle: w.a1 + ii, endAngle: w.a0 - ii, clockwise: false)
        p.close()
        p.lineJoinStyle = .round
        p.lineWidth = rad * 2
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        let shadow = NSShadow(); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        for (i, w) in wedges.enumerated() {
            let on = i == hovered
            let path = wedgePath(w, push: on ? 6 : 0)
            let rim = path.copy() as! NSBezierPath
            rim.lineWidth = path.lineWidth + 2
            NSColor.white.withAlphaComponent(0.95).set(); rim.fill(); rim.stroke()
            (on ? NSColor.systemBlue.withAlphaComponent(0.95) : NSColor.white.withAlphaComponent(0.82)).set()
            path.fill(); path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        // 칸 이름·설명
        for (i, w) in wedges.enumerated() where i < items.count {
            let on = i == hovered
            let mid = (w.a0 + w.a1) / 2 * .pi / 180, r = (w.r0 + w.r1) / 2 + (on ? 6 : 0)
            let tc = on ? NSColor.white : NSColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1)
            let small = (w.a0 - w.a1) < 40 && w.r1 - w.r0 < 70
            let t = NSAttributedString(string: items[i].title, attributes: [.font: NSFont.systemFont(ofSize: small ? 11 : 12, weight: .bold), .foregroundColor: tc])
            let p = CGPoint(x: center.x + r * cos(mid), y: center.y + r * sin(mid))
            let ts = t.size()
            if let note = items[i].note {
                let n = NSAttributedString(string: note, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: tc.withAlphaComponent(0.7)])
                t.draw(at: CGPoint(x: p.x - ts.width / 2, y: p.y))
                n.draw(at: CGPoint(x: p.x - n.size().width / 2, y: p.y - n.size().height))
            } else {
                t.draw(at: CGPoint(x: p.x - ts.width / 2, y: p.y - ts.height / 2))
            }
        }
        // 가운데 원
        let r: CGFloat = min(46, (wedges.map(\.r0).min() ?? 52) - 6)
        let circle = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        NSColor.white.withAlphaComponent(0.88).setFill(); circle.fill()
        NSColor.white.setStroke(); circle.lineWidth = 1; circle.stroke()
        let ink = NSColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
        func lines(_ texts: [String]) {
            let h: CGFloat = 15, top = center.y + CGFloat(texts.count) * h / 2
            for (k, s) in texts.enumerated() {
                NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: k == 0 ? 12 : 10, weight: k == 0 ? .bold : .medium),
                                                          .foregroundColor: k == 0 ? ink : ink.withAlphaComponent(0.7), .paragraphStyle: para])
                    .draw(in: CGRect(x: center.x - r + 6, y: top - CGFloat(k + 1) * h, width: r * 2 - 12, height: h))
            }
        }
        if let working {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: r - 5, startAngle: angle, endAngle: angle + 250)
            NSColor.systemGreen.setStroke(); arc.lineWidth = 5; arc.lineCapStyle = .round; arc.stroke()
            lines([working, "바꾸는 중"])
        } else if let i = hovered, i < items.count {
            lines([items[i].title] + items[i].detail.split(separator: "\n").map(String.init))
        } else {
            if let thumbnail {
                let s: CGFloat = r * 1.1
                thumbnail.draw(in: CGRect(x: center.x - s / 2, y: center.y - s / 2 + 8, width: s, height: s * 0.75), from: .zero, operation: .sourceOver, fraction: 1)
            }
            NSAttributedString(string: caption, attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: ink, .paragraphStyle: para])
                .draw(in: CGRect(x: center.x - r + 6, y: center.y - r + 12, width: r * 2 - 12, height: 14))
        }
    }
}

/// 원형 변환 패널(포커스를 뺏지 않음). 칸에 놓으면 변환하고 끝나면 접힌다. 끌기를 그만두면 닫힌다.
final class ConvertWheel {
    private(set) var panel: FloatingPanel?
    private var view: ConvertWheelView?
    private var dragTimer: Timer?

    func open(items: [WheelItem], files: [URL], center c: CGPoint, in v: CGRect, onCenterDrop: @escaping () -> Void) {
        close()
        let formats = items.filter(\.isFormat), actions = items.filter { !$0.isFormat }
        let ordered = formats + actions
        let reach = WheelMath.outer.r1 + 12
        let arc = WheelMath.arc(center: c, in: v, reach: reach)
        let wedges = WheelMath.layout(formats: formats.count, actions: actions.count, start: arc.start, span: arc.span)
        let side = (WheelMath.outerRadius(wedges) + 20) * 2
        let p = FloatingPanel(size: CGSize(width: side, height: side))
        p.setFrame(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side), display: false)
        let wv = ConvertWheelView(frame: CGRect(origin: .zero, size: p.frame.size))
        wv.center = CGPoint(x: side / 2, y: side / 2)
        wv.wedges = wedges
        wv.items = ordered
        wv.caption = files.count > 1 ? "\(files.count)개" : Self.sizeText(files.first)
        wv.onCenterDrop = { [weak self] in self?.close(); onCenterDrop() }
        wv.onPick = { [weak wv] i in guard let wv, i < ordered.count else { return }; wv.hovered = nil; ordered[i].action() }
        p.contentView = wv
        p.orderFrontRegardless()
        panel = p; view = wv
        Self.thumbnail(files.first) { [weak wv] img in wv?.thumbnail = img }
        // 칸이 아닌 곳에 놓거나 끌기를 그만두면 닫는다(변환 중이면 끝날 때 닫는다)
        dragTimer = Ticker.every("변환 원 끌기 끝났는지 보기", 0.2) { [weak self] _ in
            guard let self, self.view?.working == nil, NSEvent.pressedMouseButtons == 0 else { return }
            self.close()
        }
    }

    var isWorking: Bool { view?.working != nil }

    /// 놓은 뒤: 가운데 진행 링
    func showWorking(_ title: String) { view?.working = title; dragTimer?.invalidate(); dragTimer = nil }

    func close() {
        dragTimer?.invalidate(); dragTimer = nil
        view?.working = nil
        panel?.orderOut(nil); panel = nil; view = nil
    }

    static func sizeText(_ url: URL?) -> String {
        guard let url, let n = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return url?.lastPathComponent ?? "" }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private static func thumbnail(_ url: URL?, _ done: @escaping (NSImage?) -> Void) {
        guard let url else { done(nil); return }
        done(NSWorkspace.shared.icon(forFile: url.path))
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 72), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { done(img) }
        }
    }
}
