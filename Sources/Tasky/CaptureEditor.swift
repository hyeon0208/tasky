import AppKit
import CoreImage

// F22 2단계: 캡처 편집 창. 원본 이미지 + 도형 목록, 화면과 결과를 같은 함수로 그린다. 근거: intent/F22-화면-캡처/spec.md 6

enum MarkTool: String, CaseIterable {
    case arrow, rect, text, mosaic, highlight, number, spotlight, magnify, crop

    var title: String {
        switch self {
        case .arrow: "화살표"; case .rect: "네모"; case .text: "글씨"; case .mosaic: "모자이크"; case .highlight: "형광펜"
        case .number: "번호"; case .spotlight: "스포트라이트"; case .magnify: "돋보기"; case .crop: "자르기"
        }
    }
    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"; case .rect: "rectangle"; case .text: "textformat"; case .mosaic: "square.grid.3x3.fill"
        case .highlight: "highlighter"; case .number: "1.circle"; case .spotlight: "light.max"; case .magnify: "plus.magnifyingglass"; case .crop: "crop"
        }
    }
    /// 도구 바꾸기 키
    var key: String {
        switch self {
        case .arrow: "a"; case .rect: "r"; case .text: "t"; case .mosaic: "m"; case .highlight: "h"
        case .number: "n"; case .spotlight: "s"; case .magnify: "z"; case .crop: "c"
        }
    }
}

/// 도형 하나. 좌표는 원본 이미지 픽셀(왼쪽 아래 원점).
struct Mark {
    var tool: MarkTool
    var a: CGPoint
    var b: CGPoint
    var color: NSColor = .systemRed
    var text = ""
    var number = 0
    /// 돋보기의 확대 원 중심
    var dest: CGPoint = .zero

    var rect: CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
    var radius: CGFloat { max(8, hypot(b.x - a.x, b.y - a.y)) }
}

enum MarkRender {
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .black]

    /// 원본 + 도형을 결과 이미지로. 자르기는 마지막 자르기 도형을 쓴다.
    static func image(base: CGImage, marks: [Mark], scale: CGFloat, pixelated: CGImage? = nil) -> CGImage? {
        let crop = visibleRect(base: base, marks: marks)
        guard let ctx = CGContext(data: nil, width: Int(crop.width), height: Int(crop.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        draw(base: base, marks: marks, scale: scale, pixelated: pixelated, in: ctx)
        return ctx.makeImage()
    }

    static func visibleRect(base: CGImage, marks: [Mark]) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        guard let c = marks.last(where: { $0.tool == .crop })?.rect.integral.intersection(full), c.width >= 4, c.height >= 4 else { return full }
        return c
    }

    /// scale: 이미지 픽셀 / 포인트(레티나면 2). 선 굵기·글자 크기에 곱한다.
    static func draw(base: CGImage, marks: [Mark], scale: CGFloat, pixelated: CGImage?, in ctx: CGContext) {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        ctx.draw(base, in: full)
        let mosaic = marks.contains { $0.tool == .mosaic } ? (pixelated ?? pixelate(base)) : nil
        // 가리기·스포트라이트는 원본 바로 위, 나머지는 그 위에 그린 순서대로
        for m in marks where m.tool == .mosaic {
            guard let mosaic else { break }
            ctx.saveGState(); ctx.clip(to: m.rect); ctx.draw(mosaic, in: full); ctx.restoreGState()
        }
        let spots = marks.filter { $0.tool == .spotlight }
        if !spots.isEmpty {
            ctx.saveGState()
            ctx.addRect(full)
            spots.forEach { ctx.addPath(CGPath(roundedRect: $0.rect, cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil)) }
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let line = 4 * scale
        for m in marks {
            let c = m.color.cgColor
            ctx.saveGState()
            ctx.setStrokeColor(c); ctx.setFillColor(c); ctx.setLineWidth(line); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            switch m.tool {
            case .arrow:
                let angle = atan2(m.b.y - m.a.y, m.b.x - m.a.x), head = 5 * line
                let back = CGPoint(x: m.b.x - cos(angle) * head * 0.8, y: m.b.y - sin(angle) * head * 0.8)
                ctx.move(to: m.a); ctx.addLine(to: back); ctx.strokePath()
                ctx.move(to: m.b)
                ctx.addLine(to: CGPoint(x: m.b.x - cos(angle - 0.45) * head, y: m.b.y - sin(angle - 0.45) * head))
                ctx.addLine(to: CGPoint(x: m.b.x - cos(angle + 0.45) * head, y: m.b.y - sin(angle + 0.45) * head))
                ctx.closePath(); ctx.fillPath()
            case .rect:
                ctx.addPath(CGPath(roundedRect: m.rect, cornerWidth: 3 * scale, cornerHeight: 3 * scale, transform: nil)); ctx.strokePath()
            case .highlight:
                ctx.setStrokeColor(m.color.withAlphaComponent(0.35).cgColor); ctx.setLineWidth(6 * line); ctx.setLineCap(.butt)
                ctx.move(to: m.a); ctx.addLine(to: CGPoint(x: m.b.x, y: m.a.y)); ctx.strokePath()   // 가로줄로 곧게
            case .number:
                let r = 13 * scale
                ctx.fillEllipse(in: CGRect(x: m.a.x - r, y: m.a.y - r, width: 2 * r, height: 2 * r))
                let s = NSAttributedString(string: "\(m.number)", attributes: [.font: NSFont.systemFont(ofSize: 15 * scale, weight: .bold),
                                                                             .foregroundColor: m.color == .systemYellow ? NSColor.black : NSColor.white])
                let size = s.size()
                s.draw(at: CGPoint(x: m.a.x - size.width / 2, y: m.a.y - size.height / 2))
            case .text:
                NSAttributedString(string: m.text, attributes: [.font: NSFont.systemFont(ofSize: 20 * scale, weight: .semibold),
                                                                .foregroundColor: m.color]).draw(at: m.a)
            case .magnify:
                let r = m.radius, big = r * 2
                let src = CGRect(x: m.a.x - r, y: m.a.y - r, width: 2 * r, height: 2 * r)
                let dst = CGRect(x: m.dest.x - big, y: m.dest.y - big, width: 2 * big, height: 2 * big)
                // 원 테두리 사이를 잇는 선
                let angle = atan2(m.dest.y - m.a.y, m.dest.x - m.a.x)
                ctx.setLineWidth(line / 2)
                ctx.move(to: CGPoint(x: m.a.x + cos(angle) * r, y: m.a.y + sin(angle) * r))
                ctx.addLine(to: CGPoint(x: m.dest.x - cos(angle) * big, y: m.dest.y - sin(angle) * big)); ctx.strokePath()
                ctx.strokeEllipse(in: src)
                ctx.saveGState()
                ctx.addEllipse(in: dst); ctx.clip()
                ctx.interpolationQuality = .none
                // 확대: src 영역을 dst에 맞춰 원본을 2배로
                ctx.translateBy(x: dst.minX - src.minX * 2, y: dst.minY - src.minY * 2)
                ctx.scaleBy(x: 2, y: 2)
                ctx.draw(base, in: full)
                ctx.restoreGState()
                ctx.setLineWidth(line / 2); ctx.strokeEllipse(in: dst)
            case .mosaic, .spotlight, .crop: break
            }
            ctx.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 모자이크용 전체 픽셀화(가리기 영역만 잘라 쓴다)
    static func pixelate(_ base: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: base)
        let f = CIFilter(name: "CIPixellate")!
        f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(max(10, CGFloat(base.width) / 90), forKey: kCIInputScaleKey)
        guard let out = f.outputImage?.cropped(to: ci.extent) else { return nil }
        return CIContext().createCGImage(out, from: ci.extent)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// 편집 창
final class CaptureEditor: NSObject, NSWindowDelegate {
    private static var open: [CaptureEditor] = []
    private let window: NSWindow
    private let canvas: MarkCanvas
    private let note = NSTextField(labelWithString: "")
    private let tools = NSSegmentedControl()
    private let colors = NSSegmentedControl()

    static func show(_ image: CGImage, scale: CGFloat) {
        let e = CaptureEditor(image: image, scale: scale)
        open.append(e)
    }

    private init(image: CGImage, scale: CGFloat) {
        canvas = MarkCanvas(base: image, scale: scale)
        let v = NSScreen.withMouse.visibleFrame
        let fit = min(1, (v.width * 0.8) / (CGFloat(image.width) / scale), (v.height * 0.8 - 50) / (CGFloat(image.height) / scale))
        let size = NSSize(width: max(560, CGFloat(image.width) / scale * fit), height: max(320, CGFloat(image.height) / scale * fit + 50))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "캡처 편집"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]

        tools.segmentCount = MarkTool.allCases.count
        for (i, t) in MarkTool.allCases.enumerated() {
            tools.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: i)
            tools.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: i)
            tools.setWidth(30, forSegment: i)
        }
        tools.trackingMode = .selectOne
        tools.selectedSegment = 0
        tools.target = self
        tools.action = #selector(toolChanged)
        colors.segmentCount = MarkRender.colors.count
        for (i, c) in MarkRender.colors.enumerated() {
            colors.setImage(Self.swatch(c), forSegment: i)
            colors.setWidth(26, forSegment: i)
        }
        colors.selectedSegment = 0
        colors.target = self
        colors.action = #selector(colorChanged)
        colors.setAccessibilityLabel("색")
        let undo = Self.button("arrow.uturn.backward", "되돌리기 (⌘Z)") { [weak self] in self?.canvas.undo() }
        let copy = Self.button("doc.on.doc", "복사 (⌘C)") { [weak self] in self?.copyResult() }
        let save = Self.button("square.and.arrow.down", "저장 (⌘S)") { [weak self] in self?.save() }
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [tools, colors, undo, note, NSView(), copy, save])
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let stack = NSStackView(views: [bar, canvas])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        canvas.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        canvas.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = stack
        canvas.onKey = { [weak self] in self?.key($0) ?? false }
        canvas.onChange = { [weak self] in self?.note.stringValue = "" }

        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }

    @objc private func toolChanged() { canvas.tool = MarkTool.allCases[tools.selectedSegment] }
    @objc private func colorChanged() { canvas.color = MarkRender.colors[colors.selectedSegment] }

    /// ⌘Z ⇧⌘Z ⌘C ⌘S ⌘W, 글자 키로 도구 바꾸기
    private func key(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (mods, ch) {
        case ([.command], "z"): canvas.undo()
        case ([.command, .shift], "z"): canvas.redo()
        case ([.command], "c"): copyResult()
        case ([.command], "s"): save()
        case ([.command], "w"): window.performClose(nil)
        case ([], _):
            guard let i = MarkTool.allCases.firstIndex(where: { $0.key == ch }) else { return false }
            tools.selectedSegment = i
            toolChanged()
        default: return false
        }
        return true
    }

    private func result() -> Data? {
        canvas.finishText()
        return MarkRender.image(base: canvas.base, marks: canvas.marks, scale: canvas.scale, pixelated: canvas.pixelated).flatMap(MarkRender.png)
    }

    private func copyResult() {
        guard let png = result() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        note.stringValue = "복사됨"
    }

    private func save() {
        guard let png = result() else { return }
        note.stringValue = (try? Capture.save(png)) != nil ? "저장됨" : "저장하지 못했어요"
    }

    private static func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            NSColor.separatorColor.setStroke(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
    }

    private static func button(_ symbol: String, _ tip: String, _ action: @escaping () -> Void) -> NSButton {
        let b = ClosureButton("", action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        b.bezelStyle = .texturedRounded
        return b
    }
}

/// 이미지를 창에 맞춰 보여 주고, 끌어서 도형을 더한다.
final class MarkCanvas: NSView {
    let base: CGImage
    let scale: CGFloat
    private(set) var marks: [Mark] = []
    private var redoStack: [Mark] = []
    private var drafting: Mark?
    private var movingDest: Int?
    private var editor: NSTextField?
    private var editorPoint: CGPoint = .zero
    var tool: MarkTool = .arrow { didSet { finishText() } }
    var color: NSColor = .systemRed
    var onKey: (NSEvent) -> Bool = { _ in false }
    var onChange: () -> Void = {}
    private(set) lazy var pixelated: CGImage? = MarkRender.pixelate(base)

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        super.init(frame: .zero)
        setAccessibilityLabel("캡처 이미지. 끌어서 표시를 더해요")
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { if !onKey(event) { super.keyDown(with: event) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { editor == nil && event.modifierFlags.contains(.command) ? onKey(event) : false }

    /// 보이는 영역(자르기 반영)을 뷰에 맞춘 사각형과 배율
    private var layout: (visible: CGRect, frame: CGRect, k: CGFloat) {
        let vis = MarkRender.visibleRect(base: base, marks: marks)
        let area = bounds.insetBy(dx: 12, dy: 12)
        let k = min(area.width / vis.width, area.height / vis.height, 1 / scale)
        let size = CGSize(width: vis.width * k, height: vis.height * k)
        return (vis, CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), k)
    }

    private func toImage(_ p: NSPoint) -> CGPoint {
        let l = layout
        return CGPoint(x: l.visible.minX + (p.x - l.frame.minX) / l.k, y: l.visible.minY + (p.y - l.frame.minY) / l.k)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.blended(withFraction: 0.3, of: .gray)?.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let l = layout
        ctx.saveGState()
        ctx.clip(to: l.frame)
        ctx.translateBy(x: l.frame.minX, y: l.frame.minY)
        ctx.scaleBy(x: l.k, y: l.k)
        ctx.translateBy(x: -l.visible.minX, y: -l.visible.minY)
        var all = marks
        if let d = drafting { all.append(d) }
        // 자르기를 끄는 중이면 그 영역만 테두리로 보여 준다(아직 자르지 않음)
        let shown = drafting?.tool == .crop ? marks : all
        MarkRender.draw(base: base, marks: shown, scale: scale, pixelated: pixelated, in: ctx)
        if let d = drafting, d.tool == .crop {
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2 / l.k); ctx.setLineDash(phase: 0, lengths: [6 / l.k, 4 / l.k])
            ctx.stroke(d.rect)
        }
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        finishText()
        let p = toImage(convert(event.locationInWindow, from: nil))
        // 돋보기 확대 원을 누르면 옮긴다
        if let i = marks.lastIndex(where: { $0.tool == .magnify && hypot($0.dest.x - p.x, $0.dest.y - p.y) < $0.radius * 2 }) {
            movingDest = i
            return
        }
        switch tool {
        case .text:
            startText(at: convert(event.locationInWindow, from: nil), image: p)
        case .number:
            add(Mark(tool: .number, a: p, b: p, color: color, number: marks.filter { $0.tool == .number }.count + 1))
        default:
            drafting = Mark(tool: tool, a: p, b: p, color: color)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        if let i = movingDest { marks[i].dest = p; needsDisplay = true; return }
        guard var d = drafting else { return }
        d.b = p
        if d.tool == .magnify { d.dest = Self.magnifyDest(d, in: CGSize(width: base.width, height: base.height)) }
        drafting = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingDest != nil { movingDest = nil; return }
        guard let d = drafting else { return }
        drafting = nil
        let tiny = d.tool == .magnify ? hypot(d.b.x - d.a.x, d.b.y - d.a.y) < 4 : (abs(d.b.x - d.a.x) < 4 && abs(d.b.y - d.a.y) < 4)
        if !tiny { add(d) } else { needsDisplay = true }
    }

    /// 확대 원 자리: 오른쪽 위, 이미지 밖으로 나가면 반대쪽
    static func magnifyDest(_ m: Mark, in size: CGSize) -> CGPoint {
        let r = m.radius, off = r * 3.2
        var x = m.a.x + off, y = m.a.y + off * 0.4
        if x + 2 * r > size.width { x = m.a.x - off }
        if y + 2 * r > size.height { y = m.a.y - off * 0.4 }
        return CGPoint(x: x, y: y)
    }

    private func add(_ m: Mark) {
        marks.append(m)
        redoStack.removeAll()
        needsDisplay = true
        onChange()
    }

    func undo() {
        finishText()
        guard let m = marks.popLast() else { return }
        redoStack.append(m)
        needsDisplay = true
        onChange()
    }

    func redo() {
        guard let m = redoStack.popLast() else { return }
        marks.append(m)
        needsDisplay = true
        onChange()
    }

    private func startText(at viewPoint: NSPoint, image p: CGPoint) {
        let f = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - 4, width: 220, height: 28))
        f.font = .systemFont(ofSize: 20 * scale * layout.k, weight: .semibold)
        f.textColor = color
        f.isBordered = true
        f.drawsBackground = false
        f.focusRingType = .none
        f.placeholderString = "글씨 입력 후 Enter"
        f.target = self
        f.action = #selector(textDone)
        addSubview(f)
        window?.makeFirstResponder(f)
        editor = f
        editorPoint = p
    }

    @objc private func textDone() {
        finishText()
        window?.makeFirstResponder(self)
    }

    /// 쓰던 글씨가 있으면 도형으로 바꾼다
    func finishText() {
        guard let f = editor else { return }
        editor = nil
        let text = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = f.textColor ?? color
        f.removeFromSuperview()
        if !text.isEmpty { add(Mark(tool: .text, a: editorPoint, b: editorPoint, color: c, text: text)) }
    }
}
