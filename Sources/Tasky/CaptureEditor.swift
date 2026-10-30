import AppKit
import Vision
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
    /// 도구 바꾸기 키(키 위치. 한글 입력 중에도 같은 자리)
    var keyCode: UInt16 {
        switch self {
        case .arrow: 0; case .rect: 15; case .text: 17; case .mosaic: 46; case .highlight: 4
        case .number: 45; case .spotlight: 1; case .magnify: 6; case .crop: 8
        }
    }
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
    /// 글씨·번호 크기 배율
    var size: CGFloat = 1

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
                let r = 13 * scale * m.size
                ctx.fillEllipse(in: CGRect(x: m.a.x - r, y: m.a.y - r, width: 2 * r, height: 2 * r))
                let s = NSAttributedString(string: "\(m.number)", attributes: [.font: NSFont.systemFont(ofSize: 15 * scale * m.size, weight: .bold),
                                                                             .foregroundColor: m.color == .systemYellow ? NSColor.black : NSColor.white])
                let size = s.size()
                s.draw(at: CGPoint(x: m.a.x - size.width / 2, y: m.a.y - size.height / 2))
            case .text:
                NSAttributedString(string: m.text, attributes: [.font: NSFont.systemFont(ofSize: 20 * scale * m.size, weight: .semibold),
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
    private var keyMonitor: Any?

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
            tools.setLabel(t.key.uppercased(), forSegment: i)
            tools.setImageScaling(.scaleProportionallyDown, forSegment: i)
            tools.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: i)
            tools.setWidth(42, forSegment: i)
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
        let ocr = Self.button("text.viewfinder", "글자 복사") { [weak self] in self?.copyText() }
        let pin = Self.button("pin", "화면에 고정") { [weak self] in self?.pin() }
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [tools, colors, undo, note, NSView(), ocr, pin, copy, save])
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
        // 버튼을 누른 뒤에도 키가 먹게 창 단위로 받는다(글씨 입력 중에는 빼고)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window, !self.canvas.isEditingText else { return e }
            return self.key(e) ? nil : e
        }
        canvas.onSelect = { [weak self] color in
            guard let self, let color, let i = MarkRender.colors.firstIndex(of: color) else { return }
            self.colors.selectedSegment = i
        }
        canvas.onChange = { [weak self] in self?.note.stringValue = "" }

        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    func windowWillClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        Self.open.removeAll { $0 === self }
    }

    @objc private func toolChanged() { canvas.tool = MarkTool.allCases[tools.selectedSegment] }
    @objc private func colorChanged() { canvas.setColor(MarkRender.colors[colors.selectedSegment]) }

    /// ⌘Z ⇧⌘Z ⌘C ⌘S ⌘W, 글자 키로 도구 바꾸기
    private func key(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        // 키 위치: Z 6, C 8, S 1, W 13
        switch (mods, e.keyCode) {
        case ([.command], 6): canvas.undo()
        case ([.command, .shift], 6): canvas.redo()
        case ([.command], 8): copyResult()
        case ([.command], 1): save()
        case ([.command], 13): window.performClose(nil)
        case ([], _) where e.keyCode == 51 || e.keyCode == 117: canvas.deleteSelected()   // ⌫ ⌦
        case ([], _) where e.keyCode == 53: canvas.select(nil)   // Esc
        case ([], _):
            guard let i = MarkTool.allCases.firstIndex(where: { $0.keyCode == e.keyCode }) else { return false }
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

    private func copyText() {
        canvas.finishText()
        guard let img = MarkRender.image(base: canvas.base, marks: canvas.marks, scale: canvas.scale, pixelated: canvas.pixelated) else { return }
        note.stringValue = "글자 읽는 중…"
        DispatchQueue.global(qos: .userInitiated).async {
            let lines = Self.recognize(img)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !lines.isEmpty else { self.note.stringValue = "글자를 찾지 못했어요"; return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                self.note.stringValue = "\(lines.count)줄 복사됨"
            }
        }
    }

    /// 한국어·영어 글자 인식. 줄 순서(위→아래)대로 돌려준다.
    static func recognize(_ image: CGImage) -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["ko-KR", "en-US"]
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func pin() {
        canvas.finishText()
        guard let img = MarkRender.image(base: canvas.base, marks: canvas.marks, scale: canvas.scale, pixelated: canvas.pixelated) else { return }
        PinView.show(img, scale: canvas.scale)
        window.performClose(nil)
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
    private var undoStack: [[Mark]] = []
    private var redoStack: [[Mark]] = []
    private var drafting: Mark?
    private var selected: Int? { didSet { needsDisplay = true; onSelect(selected.map { marks[$0].color }) } }
    /// 끄는 중인 것: 통째로 옮기기, 끝점(a/b) 옮기기, 확대 원 옮기기
    private enum Drag { case move(start: CGPoint, original: Mark), pointA, pointB, dest, corner(fixed: CGPoint), scale(original: Mark) }
    private var drag: Drag?
    private var editor: NSTextField?
    private var editorPoint: CGPoint = .zero
    var tool: MarkTool = .arrow { didSet { finishText(); select(nil) } }
    var color: NSColor = .systemRed
    var onChange: () -> Void = {}
    var onSelect: (NSColor?) -> Void = { _ in }
    var isEditingText: Bool { editor != nil }
    private(set) lazy var pixelated: CGImage? = MarkRender.pixelate(base)

    init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
        super.init(frame: .zero)
        setAccessibilityLabel("캡처 이미지. 끌어서 표시를 더하고, 표시를 눌러 옮겨요")
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

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

    /// 화면에서 8pt를 이미지 픽셀로
    private var tolerance: CGFloat { 8 / layout.k }

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
        // 자르기를 끄는 중이면 그 영역만 테두리로 보여 준다(아직 자르지 않음)
        let shown = drafting.map { $0.tool == .crop ? marks : marks + [$0] } ?? marks
        MarkRender.draw(base: base, marks: shown, scale: scale, pixelated: pixelated, in: ctx)
        ctx.setLineWidth(1.5 / l.k)
        if let d = drafting, d.tool == .crop {
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineDash(phase: 0, lengths: [6 / l.k, 4 / l.k])
            ctx.stroke(d.rect)
        }
        if let i = selected {
            let m = marks[i]
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineDash(phase: 0, lengths: [4 / l.k, 3 / l.k])
            ctx.stroke(bounds(of: m).insetBy(dx: -4 / l.k, dy: -4 / l.k))
            ctx.setLineDash(phase: 0, lengths: [])
            for (h, _) in handles(of: m) {
                let r = 4.5 / l.k
                let box = CGRect(x: h.x - r, y: h.y - r, width: 2 * r, height: 2 * r)
                ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: box); ctx.strokeEllipse(in: box)
            }
        }
        ctx.restoreGState()
    }

    // MARK: 고르기

    /// 도형이 차지하는 영역(고르기·테두리용)
    private func bounds(of m: Mark) -> CGRect {
        switch m.tool {
        case .arrow: return m.rect
        case .highlight: return CGRect(x: min(m.a.x, m.b.x), y: m.a.y - 12 * scale, width: abs(m.b.x - m.a.x), height: 24 * scale)
        case .number: let r = 13 * scale * m.size; return CGRect(x: m.a.x - r, y: m.a.y - r, width: 2 * r, height: 2 * r)
        case .text: return CGRect(origin: m.a, size: textSize(m))
        case .magnify:
            let r = m.radius, big = 2 * r
            return CGRect(x: m.a.x - r, y: m.a.y - r, width: 2 * r, height: 2 * r).union(CGRect(x: m.dest.x - big, y: m.dest.y - big, width: 2 * big, height: 2 * big))
        default: return m.rect
        }
    }

    private func textSize(_ m: Mark) -> CGSize {
        NSAttributedString(string: m.text, attributes: [.font: NSFont.systemFont(ofSize: 20 * scale * m.size, weight: .semibold)]).size()
    }

    /// 끌어서 모양·크기를 바꾸는 점
    private func handles(of m: Mark) -> [(point: CGPoint, drag: Drag)] {
        switch m.tool {
        case .arrow: return [(m.a, .pointA), (m.b, .pointB)]
        case .highlight: return [(m.a, .pointA), (CGPoint(x: m.b.x, y: m.a.y), .pointB)]
        case .rect, .mosaic, .spotlight: // 네 모서리, 맞은편 모서리는 그대로
            let r = m.rect
            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            return corners.indices.map { (corners[$0], .corner(fixed: corners[($0 + 2) % 4])) }
        case .magnify: return [(m.b, .pointB)]
        case .text, .number: let b = bounds(of: m); return [(CGPoint(x: b.maxX, y: b.maxY), .scale(original: m))]
        case .crop: return []
        }
    }

    /// 누른 자리의 맨 위 도형(자르기는 고르지 않음)
    private func hit(_ p: CGPoint) -> Int? {
        let t = tolerance
        return marks.indices.reversed().first { i in
            let m = marks[i]
            switch m.tool {
            case .crop: return false
            case .arrow: return Self.distance(p, m.a, m.b) < t + 2 * scale
            case .highlight: return Self.distance(p, m.a, CGPoint(x: m.b.x, y: m.a.y)) < t + 12 * scale
            case .rect: // 테두리 근처만(안쪽을 눌러 새로 그릴 수 있게)
                return m.rect.insetBy(dx: -t, dy: -t).contains(p) && !m.rect.insetBy(dx: t, dy: t).contains(p)
            case .magnify:
                return hypot(p.x - m.a.x, p.y - m.a.y) < m.radius + t || hypot(p.x - m.dest.x, p.y - m.dest.y) < 2 * m.radius + t
            default: return bounds(of: m).insetBy(dx: -t, dy: -t).contains(p)
            }
        }
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy
        let t = len == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    func select(_ i: Int?) { if selected != i { selected = i } }

    func deleteSelected() {
        guard let i = selected else { return }
        commit()
        marks.remove(at: i)
        selected = nil
        onChange()
    }

    /// 색을 고르면 고른 도형에도 칠한다
    func setColor(_ c: NSColor) {
        color = c
        guard let i = selected, marks[i].color != c else { return }
        commit()
        marks[i].color = c
        needsDisplay = true
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        finishText()
        let p = toImage(convert(event.locationInWindow, from: nil))
        // 고른 도형의 끝점·확대 원
        if let i = selected {
            let m = marks[i], t = tolerance
            if let h = handles(of: m).first(where: { hypot(p.x - $0.point.x, p.y - $0.point.y) < t }) { commit(); drag = h.drag; return }
        }
        if let i = hit(p) {
            let m = marks[i]
            if event.clickCount == 2, m.tool == .text { editText(i); return }
            selected = i
            commit()
            drag = m.tool == .magnify && hypot(p.x - m.dest.x, p.y - m.dest.y) < 2 * m.radius && hypot(p.x - m.a.x, p.y - m.a.y) > m.radius
                ? .dest : .move(start: p, original: m)
            return
        }
        select(nil)
        switch tool {
        case .text:
            startText(image: p, text: "", color: color)
        case .number:
            add(Mark(tool: .number, a: p, b: p, color: color, number: (marks.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1))
        default:
            drafting = Mark(tool: tool, a: p, b: p, color: color)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        if let d = drag, let i = selected {
            switch d {
            case let .move(start, o):
                let dx = p.x - start.x, dy = p.y - start.y
                marks[i].a = CGPoint(x: o.a.x + dx, y: o.a.y + dy)
                marks[i].b = CGPoint(x: o.b.x + dx, y: o.b.y + dy)
                marks[i].dest = CGPoint(x: o.dest.x + dx, y: o.dest.y + dy)
            case .pointA: marks[i].a = p
            case .pointB: marks[i].b = p
            case .dest: marks[i].dest = p
            case let .corner(fixed): marks[i].a = fixed; marks[i].b = p
            case let .scale(o):
                // 기준점(글씨는 왼쪽 아래, 번호는 가운데)에서 손잡이까지 거리 비율로 키우고 줄인다
                let b = bounds(of: o)
                let was = hypot(b.maxX - o.a.x, b.maxY - o.a.y)
                marks[i].size = max(0.4, min(6, o.size * hypot(p.x - o.a.x, p.y - o.a.y) / max(was, 1)))
            }
            needsDisplay = true
            return
        }
        guard var d = drafting else { return }
        d.b = p
        if d.tool == .magnify { d.dest = Self.magnifyDest(d, in: CGSize(width: base.width, height: base.height)) }
        drafting = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if drag != nil {
            drag = nil
            // 눌렀다 떼기만 했으면 되돌리기 기록을 남기지 않는다
            if undoStack.last.map({ $0.count == marks.count && zip($0, marks).allSatisfy { $0.a == $1.a && $0.b == $1.b && $0.dest == $1.dest } }) == true {
                undoStack.removeLast()
            }
            onChange()
            return
        }
        guard let d = drafting else { return }
        drafting = nil
        let tiny = d.tool == .magnify ? hypot(d.b.x - d.a.x, d.b.y - d.a.y) < 4 : (abs(d.b.x - d.a.x) < 4 && abs(d.b.y - d.a.y) < 4)
        if !tiny {
            add(d)
            if d.tool != .crop { selected = marks.count - 1 }
        } else { needsDisplay = true }
    }

    /// 확대 원 자리: 오른쪽 위, 이미지 밖으로 나가면 반대쪽
    static func magnifyDest(_ m: Mark, in size: CGSize) -> CGPoint {
        let r = m.radius, off = r * 3.2
        var x = m.a.x + off, y = m.a.y + off * 0.4
        if x + 2 * r > size.width { x = m.a.x - off }
        if y + 2 * r > size.height { y = m.a.y - off * 0.4 }
        return CGPoint(x: x, y: y)
    }

    // MARK: 되돌리기

    /// 바꾸기 직전 상태를 남긴다
    private func commit() {
        undoStack.append(marks)
        redoStack.removeAll()
    }

    private func add(_ m: Mark) {
        commit()
        marks.append(m)
        needsDisplay = true
        onChange()
    }

    func undo() {
        finishText()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(marks)
        marks = prev
        selected = nil
        onChange()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(marks)
        marks = next
        selected = nil
        onChange()
    }

    // MARK: 글씨

    private func viewPoint(_ p: CGPoint) -> NSPoint {
        let l = layout
        return NSPoint(x: l.frame.minX + (p.x - l.visible.minX) * l.k, y: l.frame.minY + (p.y - l.visible.minY) * l.k)
    }

    /// 더블클릭한 글씨를 다시 입력칸으로
    private func editText(_ i: Int) {
        let m = marks[i]
        commit()
        marks.remove(at: i)
        selected = nil
        startText(image: m.a, text: m.text, color: m.color, recorded: true)
    }

    private var textRecorded = false

    private func startText(image p: CGPoint, text: String, color c: NSColor, recorded: Bool = false) {
        let v = viewPoint(p)
        let f = NSTextField(frame: NSRect(x: v.x - 3, y: v.y - 4, width: 240, height: 20 * scale * layout.k + 10))
        f.font = .systemFont(ofSize: 20 * scale * layout.k, weight: .semibold)
        f.stringValue = text
        f.textColor = c
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
        textRecorded = recorded
        needsDisplay = true
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
        guard !text.isEmpty else { needsDisplay = true; onChange(); return }
        if !textRecorded { commit() }   // 다시 고친 글씨는 이미 기록함
        marks.append(Mark(tool: .text, a: editorPoint, b: editorPoint, color: c, text: text))
        needsDisplay = true
        onChange()
    }
}

/// 화면에 고정한 이미지. 끌어서 옮기고, 스크롤로 크기, ⌥스크롤로 투명도. 더블클릭은 편집, Esc는 닫기.
final class PinView: NSView {
    private static var open: [PinView] = []
    private let panel: NSPanel
    private let image: CGImage
    private let scale: CGFloat
    private var zoom: CGFloat = 1

    static func show(_ image: CGImage, scale: CGFloat) { open.append(PinView(image: image, scale: scale)) }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let v = NSScreen.withMouse.visibleFrame
        panel = NSPanel(contentRect: NSRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(frame: NSRect(origin: .zero, size: size))
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        setAccessibilityLabel("고정한 캡처. 더블클릭하면 편집, Esc로 닫기")
        panel.contentView = self
        panel.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    private func close() {
        panel.orderOut(nil)
        Self.open.removeAll { $0 === self }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            close()
            CaptureEditor.show(image, scale: scale)
        } else {
            panel.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
        if event.modifierFlags.contains(.option) {
            panel.alphaValue = min(1, max(0.2, panel.alphaValue + d))
            return
        }
        zoom = min(4, max(0.2, zoom + d))
        let f = panel.frame
        let size = NSSize(width: CGFloat(image.width) / scale * zoom, height: CGFloat(image.height) / scale * zoom)
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }
}
