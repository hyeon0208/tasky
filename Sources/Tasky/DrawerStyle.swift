import AppKit

/// 폴더 서랍 시안 A(media/design/tasky/drawer-style, index.html `.p-a`)의 색·아이콘·부품.
enum DS {
    // MARK: 색 (시안 `.stage` 토큰, 밝은/어두운 모드)
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    private static func ink(_ a: CGFloat) -> NSColor { rgb(16, 26, 42, a) }
    private static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }

    static let glass = dyn(rgb(250, 250, 252, 0.76), rgb(36, 38, 46, 0.72))
    static let edge = dyn(rgb(20, 28, 45, 0.16), white(0.16))
    static let hi = dyn(white(0.8), white(0.12))
    static let ink = dyn(ink(0.88), white(0.92))
    static let ink2 = dyn(ink(0.66), white(0.58))
    static let ink3 = dyn(ink(0.32), white(0.32))
    static let hair = dyn(ink(0.09), white(0.09))
    static let fill = dyn(ink(0.06), white(0.08))
    static let fill2 = dyn(ink(0.12), white(0.15))
    static let sheet = dyn(white(0.62), NSColor(white: 0, alpha: 0.2))
    static let raise = dyn(.white, white(0.2))
    static let sel = dyn(rgb(0x14, 0x21, 0x3A), white(0.92))
    static let selInk = dyn(.white, rgb(0x14, 0x21, 0x3A))
    static let pin = dyn(rgb(0xF4, 0xB7, 0x40), rgb(0xF5, 0xC2, 0x5A))
    static let pinInk = rgb(0x3B, 0x2A, 0x0B)
    static let pinSoft = dyn(rgb(244, 183, 64, 0.24), rgb(245, 194, 90, 0.2))
    static let drop = dyn(rgb(0x2F, 0x6B, 0xFF), rgb(0x7A, 0xA2, 0xFF))
    static let dropSoft = dyn(rgb(47, 107, 255, 0.14), rgb(122, 162, 255, 0.2))
    static let dropText = dyn(rgb(0x1F, 0x4F, 0xD6), rgb(0xA8, 0xC1, 0xFF))

    // MARK: 아이콘 (원형 메뉴와 같은 둥근 선, 24 격자 SVG → 템플릿 이미지)
    private static func svg(_ inner: String, size: CGFloat, width sw: CGFloat = 2.2, label: String? = nil) -> NSImage {
        let s = ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(size)" height="\##(size)" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="\##(sw)" stroke-linecap="round" stroke-linejoin="round">\##(inner)</svg>"##
        let image = NSImage(data: Data(s.utf8)) ?? NSImage(size: CGSize(width: size, height: size))
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }
    static let folderD = "M3.8 8.2a2.6 2.6 0 0 1 2.6-2.6h2.8c.7 0 1.3.3 1.8.8l1 1.1h5.6a2.6 2.6 0 0 1 2.6 2.6v6.2a2.6 2.6 0 0 1-2.6 2.6H6.4a2.6 2.6 0 0 1-2.6-2.6z"
    static func clock(_ size: CGFloat) -> NSImage { svg(#"<circle cx="12" cy="12" r="8.2"/><path d="M12 7.6V12l2.9 1.9"/>"#, size: size) }
    static func folder(_ size: CGFloat, width: CGFloat = 2.2) -> NSImage { svg(#"<path d="\#(folderD)"/>"#, size: size, width: width) }
    static func plus(_ size: CGFloat) -> NSImage { svg(#"<path d="M12 6.2v11.6M6.2 12h11.6"/>"#, size: size, label: "추가") }
    /// 꺼짐 = 비스듬한(42°) 빈 핀, 켜짐 = 똑바로 선 채운 핀
    static func pinIcon(on: Bool, size: CGFloat) -> NSImage {
        let body = #"<path d="M9 3.6h6"/><path d="M10.2 3.6v5.5l-3.5 3.5v1.9h10.6v-1.9l-3.5-3.5V3.6"\#(on ? ##" fill="#000""## : "")/><path d="M12 14.5v6"/>"#
        return svg(on ? body : #"<g transform="rotate(42 12 12)">\#(body)</g>"#, size: size, width: 2)
    }
    static func cols(_ n: Int, size: CGFloat) -> NSImage {
        let d = (1..<n).map { i in String(format: "M%.2f 5.4v13.2", 3.4 + 17.2 * Double(i) / Double(n)) }.joined()
        return svg(#"<rect x="3.4" y="5.4" width="17.2" height="13.2" rx="3"/><path d="\#(d)"/>"#, size: size, width: 1.8)
    }
    static func win(_ size: CGFloat) -> NSImage {
        svg(#"<rect x="3.6" y="4.6" width="16.8" height="14.8" rx="3"/><path d="M3.6 9h16.8"/>"#, size: size, width: 1.9, label: "Finder에서 열기")
    }
    static func chevron(_ size: CGFloat) -> NSImage { svg(#"<path d="M9.5 6.5 15 12l-5.5 5.5"/>"#, size: size, width: 2) }
    static func into(_ size: CGFloat) -> NSImage {
        svg(#"<path d="M12 3.8v9.4M8.2 9.6 12 13.4l3.8-3.8"/><path d="M4.6 13.8v3.6a2 2 0 0 0 2 2h10.8a2 2 0 0 0 2-2v-3.6"/>"#, size: size, width: 2)
    }

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = DS.ink) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }
    /// 한 줄 글자 폭(말줄임 라벨은 intrinsicContentSize 폭을 주지 않는다)
    static func width(_ l: NSTextField) -> CGFloat { ceil(l.cell?.cellSize.width ?? l.attributedStringValue.size().width) + 2 }
}

/// 누르면 동작하는 레이어 바탕 뷰(칩·단추 공통). 색은 모드가 바뀌면 다시 칠한다.
class DSControl: NSView {
    var action: () -> Void = {}
    var enabled = true
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// 칩: 높이 26, 모서리 13, 왼쪽 9 · 오른쪽 11, 아이콘 15 + 5 + 12.5pt semibold. 아이콘만이면 30×26.
final class DSChip: DSControl {
    enum Style { case normal, on, add, dim }
    private let style: Style
    private let icon = NSImageView()
    private let text: NSTextField?

    init(_ title: String, image: NSImage, style: Style, action: @escaping () -> Void) {
        self.style = style
        text = title.isEmpty ? nil : DS.label(title, size: 12.5, weight: .semibold, color: style == .on ? DS.selInk : DS.ink)
        super.init(frame: .zero)
        self.action = action
        enabled = style != .dim
        alphaValue = style == .dim ? 0.42 : 1
        icon.image = image
        icon.contentTintColor = style == .on ? DS.selInk : DS.ink
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        if let text { addSubview(text) }
        layer?.cornerRadius = 13
        setAccessibilityRole(.button)
        setAccessibilityLabel(title.isEmpty ? image.accessibilityDescription : title)
        translatesAutoresizingMaskIntoConstraints = false
        let w = intrinsicContentSize.width
        widthAnchor.constraint(equalToConstant: w).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        guard let text else { return NSSize(width: 30, height: 26) }
        return NSSize(width: 9 + 15 + 5 + DS.width(text) + 11, height: 26)
    }
    override func layout() {
        super.layout()
        if let text {
            icon.frame = CGRect(x: 9, y: 5.5, width: 15, height: 15)
            let h = text.intrinsicContentSize.height
            text.frame = CGRect(x: 29, y: (26 - h) / 2, width: bounds.width - 29 - 11 + 2, height: h)
        } else {
            icon.frame = CGRect(x: (bounds.width - 15) / 2, y: 5.5, width: 15, height: 15)
        }
    }
    override func updateLayer() {
        switch style {
        case .on: layer?.backgroundColor = DS.sel.cgColor; layer?.borderWidth = 0
        case .add: layer?.backgroundColor = .clear; layer?.borderWidth = 1.2; layer?.borderColor = DS.ink3.cgColor
        case .normal, .dim: layer?.backgroundColor = DS.fill.cgColor; layer?.borderWidth = 0
        }
    }
}

/// 크기 세 칸(작게·보통·크게 = 칼럼 2·3·4). 묶음 바탕 잉크 0.06, 칸 32×24, 눌린 칸 흰 바탕 + 그림자.
final class DSSizeSegment: NSView {
    var onPick: (Int) -> Void = { _ in }
    private var buttons: [DSControl] = []
    var selected: Int? { didSet { needsDisplay = true; buttons.forEach { $0.needsDisplay = true } } }
    static let size = CGSize(width: 104, height: 28)   // 2 + 32×3 + 2×2 + 2
    private static let names = [2: "작게", 3: "보통", 4: "크게"]

    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        setAccessibilityRole(.group); setAccessibilityLabel("서랍 크기")
        for (i, n) in [2, 3, 4].enumerated() {
            let b = SegCell(n: n, owner: self)
            b.frame = CGRect(x: 2 + CGFloat(i) * 34, y: 2, width: 32, height: 24)
            b.action = { [weak self] in self?.onPick(n) }
            b.toolTip = "\(Self.names[n]!) · 칼럼 \(n)개"
            b.setAccessibilityRole(.button); b.setAccessibilityLabel(b.toolTip)
            addSubview(b); buttons.append(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() { layer?.backgroundColor = DS.fill.cgColor }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    private final class SegCell: DSControl {
        let n: Int
        weak var owner: DSSizeSegment?
        private let icon = NSImageView()
        init(n: Int, owner: DSSizeSegment) {
            self.n = n; self.owner = owner
            super.init(frame: .zero)
            icon.image = DS.cols(n, size: 18)
            icon.frame = CGRect(x: 7, y: 3, width: 18, height: 18)
            addSubview(icon)
            layer?.cornerRadius = 7
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            layer?.shadowRadius = 1
            layer?.shadowColor = NSColor.black.cgColor
        }
        required init?(coder: NSCoder) { fatalError() }
        override func updateLayer() {
            let on = owner?.selected == n
            layer?.backgroundColor = on ? DS.raise.cgColor : .clear
            layer?.shadowOpacity = on ? 0.16 : 0
            icon.contentTintColor = on ? DS.ink : DS.ink2
            setAccessibilityValue(on ? "선택됨" : nil)
        }
    }
}

/// 고정 단추: 높이 28, 모서리 14, 왼쪽 8 · 오른쪽 12, 핀 16 + 5 + 12.5pt semibold.
/// 켜짐: 노란 칠 + ‘고정됨’ + 바깥 3pt 옅은 노랑(뷰는 둘레 3pt를 더 크게 잡아 그 안에 그린다).
final class DSPinButton: DSControl {
    static let ring: CGFloat = 3
    var isOn = false { didSet { refresh() } }
    private let pill = CALayer()
    private let icon = NSImageView()
    private let text = DS.label("고정", size: 12.5, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(pill)
        pill.cornerRadius = 14
        addSubview(icon); addSubview(text)
        toolTip = "켜면 서랍 밖을 눌러도 닫히지 않아요"
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("서랍 고정")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 바깥 고리를 뺀 단추 폭
    var pillWidth: CGFloat { 8 + 16 + 5 + DS.width(text) + 12 }

    private func refresh() {
        text.stringValue = isOn ? "고정됨" : "고정"
        icon.image = DS.pinIcon(on: isOn, size: 16)
        setAccessibilityValue(isOn ? 1 : 0)
        needsDisplay = true; needsLayout = true
        effectiveAppearance.performAsCurrentDrawingAppearance { updateLayer() }
    }
    override func layout() {
        super.layout()
        let r = Self.ring
        pill.frame = CGRect(x: r, y: r, width: bounds.width - 2 * r, height: 28)
        icon.frame = CGRect(x: r + 8, y: r + 6, width: 16, height: 16)
        let h = text.intrinsicContentSize.height
        text.frame = CGRect(x: r + 29, y: r + (28 - h) / 2, width: DS.width(text) + 2, height: h)
    }
    override func updateLayer() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pill.backgroundColor = (isOn ? DS.pin : DS.fill).cgColor
        layer?.cornerRadius = 14 + Self.ring
        layer?.backgroundColor = isOn ? DS.pinSoft.cgColor : .clear
        CATransaction.commit()
        let fg = isOn ? DS.pinInk : DS.ink
        icon.contentTintColor = fg
        text.textColor = fg
    }
}

/// 아이콘 단추(`.ib`): 28×26, 모서리 7, 아이콘 16, 흐린 글자색. 올리면 바탕 잉크 0.06.
final class DSIconButton: DSControl {
    private let icon = NSImageView()
    private var hover = false { didSet { needsDisplay = true } }
    init(image: NSImage, tip: String, action: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 28, height: 26))
        self.action = action
        icon.image = image
        icon.frame = CGRect(x: 6, y: 5, width: 16, height: 16)
        addSubview(icon)
        layer?.cornerRadius = 7
        toolTip = tip
        setAccessibilityRole(.button); setAccessibilityLabel(tip)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func updateLayer() {
        layer?.backgroundColor = hover ? DS.fill.cgColor : .clear
        icon.contentTintColor = hover ? DS.ink : DS.ink2
    }
}

/// 아래 줄 경로: ‘… › 고정 폴더 › … › 지금 폴더’(12pt). ‘…’는 고정 폴더 위쪽 폴더로 가는 자리.
final class DSCrumbs: NSView {
    var onGo: (URL) -> Void = { _ in }
    private var items: [NSView] = []

    func show(root: URL?, current: URL?) {
        items.forEach { $0.removeFromSuperview() }
        items = []
        guard let root, let current else { return }
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = current.standardizedFileURL.pathComponents
        let inside = parts.starts(with: rootParts)
        var chain: [URL] = [root]
        if inside { for name in parts.dropFirst(rootParts.count) { chain.append(chain.last!.appendingPathComponent(name)) } }

        let up = DSUpChip()
        up.ancestors = Array(sequence(first: root.deletingLastPathComponent(), next: { $0.path == "/" ? nil : $0.deletingLastPathComponent() }))
        up.onGo = { [weak self] in self?.onGo($0) }
        items.append(up)
        for (i, url) in chain.enumerated() {
            items.append(DS.label("›", size: 12, color: DS.ink3))
            let last = i == chain.count - 1
            let l = CrumbLabel(url: url, last: last)
            l.onGo = { [weak self] in self?.onGo($0) }
            items.append(l)
        }
        items.forEach(addSubview)
        needsLayout = true
    }

    /// 넘치면 앞쪽 폴더부터 감춘다(‘…’와 지금 폴더는 남김)
    override func layout() {
        super.layout()
        let gap: CGFloat = 5
        var widths = items.map { ceil($0.fittingSize.width) }
        var hidden = Set<Int>()
        func total() -> CGFloat { widths.enumerated().filter { !hidden.contains($0.offset) }.reduce(0) { $0 + $1.element } + gap * CGFloat(max(0, items.count - hidden.count - 1)) }
        var k = 1   // 0은 ‘…’. 1,2 = ‘›’ + 첫 폴더 쌍부터 감춘다
        while total() > bounds.width, k + 1 < items.count - 1 { hidden.insert(k); hidden.insert(k + 1); k += 2 }
        if let last = items.indices.last, total() > bounds.width {   // 그래도 넘치면 지금 폴더 이름을 줄인다
            widths[last] = max(40, widths[last] - (total() - bounds.width))
        }
        var x: CGFloat = 0
        for (i, v) in items.enumerated() {
            v.isHidden = hidden.contains(i)
            guard !v.isHidden else { continue }
            let h = v.fittingSize.height
            v.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: widths[i], height: h)
            x += widths[i] + gap
        }
    }

    private final class CrumbLabel: NSTextField {
        let url: URL
        var onGo: (URL) -> Void = { _ in }
        init(url: URL, last: Bool) {
            self.url = url
            super.init(frame: .zero)
            isEditable = false; isBordered = false; drawsBackground = false; isSelectable = false
            stringValue = FileManager.default.displayName(atPath: url.path)
            font = .systemFont(ofSize: 12, weight: last ? .semibold : .regular)
            textColor = last ? DS.ink : DS.ink2
            lineBreakMode = .byTruncatingMiddle
            setAccessibilityRole(.button)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { onGo(url) }
    }
}

/// ‘…’: 바탕 잉크 0.06, 모서리 4. 누르면 고정 폴더 위쪽 폴더 목록.
final class DSUpChip: DSControl {
    var ancestors: [URL] = []
    var onGo: (URL) -> Void = { _ in }
    private let text = DS.label("…", size: 12, color: DS.ink2)
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(text)
        layer?.cornerRadius = 4
        toolTip = "고정 폴더보다 위 폴더"
        setAccessibilityRole(.popUpButton); setAccessibilityLabel(toolTip)
        action = { [weak self] in self?.popUp() }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var fittingSize: NSSize { NSSize(width: DS.width(text) + 8, height: 16) }
    override func layout() { super.layout(); text.frame = CGRect(x: 4, y: (bounds.height - text.intrinsicContentSize.height) / 2, width: bounds.width - 8, height: text.intrinsicContentSize.height) }
    override func updateLayer() { layer?.backgroundColor = DS.fill.cgColor }
    private func popUp() {
        let menu = NSMenu()
        for url in ancestors {
            let item = ClosureMenuItem(FileManager.default.displayName(atPath: url.path)) { [weak self] in self?.onGo(url) }
            let icon = NSWorkspace.shared.icon(forFile: url.path); icon.size = CGSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
    }
}

/// 빈 상태: 안쪽 14, 모서리 14, 1.5 점선 판 + 폴더 그림 46 + 제목 15 + 설명 12.5 + 남색 ‘폴더 넣기’ 단추.
/// 판에 폴더를 놓으면 서랍에 넣는다.
final class DSEmptyBoard: NSView {
    var onAdd: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }
    private let dash = CAShapeLayer()
    private let stack: NSStackView

    override init(frame: NSRect) {
        let icon = NSImageView(image: DS.folder(46, width: 1.7))
        icon.contentTintColor = DS.ink2
        let title = DS.label("자주 가는 폴더를 넣어 두세요", size: 15, weight: NSFont.Weight(0.32))
        let body = NSTextField(wrappingLabelWithString: "")
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineHeightMultiple = 1.2
        body.attributedStringValue = NSAttributedString(string: "폴더를 여기로 끌어 놓거나 ‘폴더 넣기’를 누르세요. 넣은 폴더는 위 칩 줄에 생깁니다.",
            attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: DS.ink2, .paragraphStyle: p])
        body.preferredMaxLayoutWidth = 34 * 12.5 * 0.62
        let cta = DSCTA()
        stack = NSStackView(views: [icon, title, body, cta])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)     // 제목 위 여백 6 + 간격 6
        stack.setCustomSpacing(16, after: body)     // 단추 위 여백 10 + 간격 6
        super.init(frame: frame)
        cta.action = { [weak self] in self?.onAdd() }
        wantsLayer = true
        dash.fillColor = nil
        dash.lineWidth = 1.5
        dash.lineDashPattern = [6, 4]
        layer?.addSublayer(dash)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let r = bounds.insetBy(dx: 14 + 0.75, dy: 14 + 0.75)
        dash.path = CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)
        updateColors()
    }
    override func viewDidChangeEffectiveAppearance() { updateColors() }
    private var dropping = false { didSet { updateColors() } }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dash.strokeColor = (dropping ? DS.drop : DS.ink3).cgColor
            dash.fillColor = dropping ? DS.dropSoft.cgColor : nil
        }
    }
    private func folders(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropping = !folders(sender).isEmpty
        return dropping ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropping = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropping = false
        let urls = folders(sender)
        if !urls.isEmpty { onDrop(urls) }
        return !urls.isEmpty
    }

    /// 높이 30, 모서리 15, 왼쪽 11 · 오른쪽 14, 더하기 15 + 6 + 13pt semibold, 남색
    private final class DSCTA: DSControl {
        private let icon = NSImageView(image: DS.plus(15))
        private let text = DS.label("폴더 넣기", size: 13, weight: .semibold, color: DS.selInk)
        override init(frame: NSRect) {
            super.init(frame: frame)
            icon.contentTintColor = DS.selInk
            addSubview(icon); addSubview(text)
            layer?.cornerRadius = 15
            setAccessibilityRole(.button); setAccessibilityLabel("폴더 넣기")
            translatesAutoresizingMaskIntoConstraints = false
            widthAnchor.constraint(equalToConstant: intrinsicContentSize.width).isActive = true
            heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override var intrinsicContentSize: NSSize { NSSize(width: 11 + 15 + 6 + DS.width(text) + 14, height: 30) }
        override func layout() {
            super.layout()
            icon.frame = CGRect(x: 11, y: 7.5, width: 15, height: 15)
            let h = text.intrinsicContentSize.height
            text.frame = CGRect(x: 32, y: (30 - h) / 2, width: DS.width(text) + 2, height: h)
        }
        override func updateLayer() { layer?.backgroundColor = DS.sel.cgColor }
    }
}

/// 칼럼 위치 막대: 높이 4, 둥근 끝, 바탕 잉크 0.06, 지금 보이는 칸 흐린 글자색. 칼럼이 밀렸을 때만 보인다.
final class DSPositionBar: NSView {
    private let thumb = CALayer()
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 2
        thumb.cornerRadius = 2
        layer?.addSublayer(thumb)
        toolTip = "칼럼이 왼쪽으로 밀려 있어요"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func show(first: Int, visible: Int, total: Int) {
        isHidden = first <= 0 || total <= 0
        guard !isHidden else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        thumb.frame = CGRect(x: bounds.width * CGFloat(first) / CGFloat(total), y: 0,
                             width: bounds.width * CGFloat(min(visible, total - first)) / CGFloat(total), height: bounds.height)
        CATransaction.commit()
    }
    override func updateLayer() {
        layer?.backgroundColor = DS.fill.cgColor
        thumb.backgroundColor = DS.ink2.cgColor
    }
}

/// 칼럼 줄: 높이 24, 좌우 여백 6, 모서리 6, 안쪽 왼쪽 7 · 오른쪽 6, 아이콘 18 + 7 + 13pt, 폴더는 › 12(옅은 글자색).
/// 지나온 폴더 잉크 0.06, 지금 폴더 0.12, 놓을 폴더 파란 테 1.5 + 옅은 파랑. 시스템 파란 선택은 그리지 않는다.
final class DSBrowserCell: NSBrowserCell {
    enum Mark { case none, path, current, drop }
    var mark: Mark = .none
    var node: FileNode?
    private static let chevron = DS.chevron(12)

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let r = cellFrame.insetBy(dx: 6, dy: 0)
        let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        switch mark {
        case .none: break
        case .path: DS.fill.setFill(); p.fill()
        case .current: DS.fill2.setFill(); p.fill()
        case .drop:
            DS.dropSoft.setFill(); p.fill()
            let edge = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: 5.25, yRadius: 5.25)
            edge.lineWidth = 1.5; DS.drop.setStroke(); edge.stroke()
        }
        guard let node else { return }
        node.icon.draw(in: CGRect(x: r.minX + 7, y: r.midY - 9, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        var right = r.maxX - 6
        right -= 0   // 폴더 › 는 NSBrowser가 줄 오른쪽에 그린다
        let p2 = NSMutableParagraphStyle(); p2.lineBreakMode = .byTruncatingMiddle
        let name = NSAttributedString(string: node.name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: DS.ink, .paragraphStyle: p2])
        let h = ceil(name.size().height)
        let x = r.minX + 7 + 18 + 7
        name.draw(with: CGRect(x: x, y: r.midY - h / 2, width: max(0, right - x), height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
    override func highlightColor(withFrame cellFrame: NSRect, in controlView: NSView) -> NSColor? { .clear }
}

extension NSImage {
    /// 템플릿 그림을 한 색으로 칠한 사본
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
