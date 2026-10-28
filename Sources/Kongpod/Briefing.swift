import AppKit

// F8 귀환 브리핑. 근거: intent/F8-귀환브리핑/{intent,spec,plan}.md

/// 자리를 비운 사이 일을 모은다(펫마다 하나, 화면과 상관없는 로직).
struct Briefing {
    enum Item {
        case agent(AgentSession)
        case conversion(Date, [URL])

        /// 묶음 순서: 승인 대기 → 실패 → 끝남 → 변환
        var group: Int {
            switch self {
            case .agent(let s): s.state == .waiting ? 0 : s.state == .failed ? 1 : 2
            case .conversion: 3
            }
        }
        var date: Date {
            switch self {
            case .agent(let s): s.updated
            case .conversion(let d, _): d
            }
        }
    }

    private(set) var awaySince: Date?
    private(set) var items: [Item] = []

    /// 자리 비움 시작. 이미 비운 중이면(잠금 중 잠자기 등) 처음 시각을 유지한다.
    mutating func leave(at date: Date = Date()) {
        if awaySince == nil { awaySince = date }
    }

    /// 돌아옴. 비운 적이 없으면 아무것도 하지 않는다(잠금 해제와 깨어나기가 연달아 와도 한 번만).
    /// 승인 대기는 떠나기 전부터 기다리던 것도 넣고, 실패·끝남·변환은 비운 뒤 생긴 것만 넣는다. 새로 더한 개수를 돌려준다.
    @discardableResult
    mutating func collect(sessions: [AgentSession], conversions: [(Date, [URL])]) -> Int {
        guard let since = awaySince else { return 0 }
        awaySince = nil
        var added = 0
        for s in sessions {
            let fresh = s.state == .waiting || ((s.state == .failed || s.state == .done) && s.updated >= since)
            guard fresh else { continue }
            if let i = items.firstIndex(where: { if case .agent(let o) = $0 { o.id == s.id } else { false } }) {
                items[i] = .agent(s)            // 같은 세션은 최신 상태 하나
            } else {
                items.append(.agent(s))
                added += 1
            }
        }
        for (date, urls) in conversions where date >= since && !urls.isEmpty {
            items.append(.conversion(date, urls))
            added += 1
        }
        items.sort { $0.group != $1.group ? $0.group < $1.group : $0.date > $1.date }
        return added
    }

    mutating func clear() { items = [] }

    /// 창에 보여 준 항목만 지운다(창이 열린 사이 새로 모인 항목은 남긴다)
    mutating func remove(_ shown: [Item]) {
        let keys = Set(shown.map(\.key))
        items.removeAll { keys.contains($0.key) }
    }
}

extension Briefing.Item {
    var key: String {
        switch self {
        case .agent(let s): "a:\(s.id)"
        case .conversion(let d, let u): "c:\(d.timeIntervalSince1970):\(u.first?.path ?? "")"
        }
    }
}

/// 자리 비움의 출처(화면 잠금·잠자기·싱잉볼 쉼)를 함께 센다. 모든 출처가 끝나야 '돌아옴'이다.
/// 예: 뚜껑을 닫으면 잠금 → 잠자기 → 깨어나기 → 잠금 해제 순서로 오므로, 깨어나기에서 브리핑하지 않고 잠금 해제에서 한다.
struct AwayState {
    private(set) var sources: Set<String> = []
    /// 시작: 처음 자리를 비우는 순간이면 true
    mutating func start(_ source: String) -> Bool { sources.insert(source).inserted && sources.count == 1 }
    /// 끝: 모든 출처가 끝나 돌아온 순간이면 true. 시작한 적 없는 출처의 끝은 무시한다.
    mutating func end(_ source: String) -> Bool { sources.remove(source) != nil && sources.isEmpty }
}

/// 펫 옆 브리핑 창. 닫히면(닫기·Esc·바깥 클릭) `onClose`.
final class BriefingWindow {
    let panel: FloatingPanel
    private var monitor: Any?
    private let onClose: () -> Void

    init(items: [Briefing.Item], nextTo petFrame: CGRect, in v: CGRect, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let size = CGSize(width: 420, height: 380)
        let shown = petFrame.intersection(v).isNull ? petFrame : petFrame.intersection(v)
        var x = shown.midX > v.midX ? shown.minX - size.width - 8 : shown.maxX + 8
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(shown.midY - size.height / 2, v.minY + 8), v.maxY - size.height - 8)
        panel = FloatingPanel(size: size)
        panel.keyable = true
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)

        let effect = EscapableEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let titles = ["승인을 기다리는 작업", "실패한 작업", "끝난 작업", "변환 결과"]
        var lastGroup = -1
        for item in items {
            if item.group != lastGroup {
                lastGroup = item.group
                let h = NSTextField(labelWithString: titles[item.group])
                h.font = .systemFont(ofSize: 12, weight: .semibold)
                h.textColor = .secondaryLabelColor
                stack.addArrangedSubview(h)
            }
            stack.addArrangedSubview(Self.row(item, width: size.width - 40))
        }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 44, width: size.width, height: size.height - 44))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let height = max(stack.fittingSize.height, size.height - 44)
        let doc = FlippedView(frame: CGRect(x: 0, y: 0, width: size.width - 16, height: height))
        stack.frame = doc.bounds
        doc.addSubview(stack)
        scroll.documentView = doc
        effect.addSubview(scroll)
        let line = NSBox(frame: CGRect(x: 0, y: 43, width: size.width, height: 1))
        line.boxType = .separator
        effect.addSubview(line)
        let title = NSTextField(labelWithString: "그 사이 \(items.count)건")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = CGRect(x: 14, y: 13, width: 200, height: 18)
        effect.addSubview(title)

        panel.contentView = effect
        let close = ClosureButton("닫기") {}
        close.frame = CGRect(x: size.width - 90, y: 9, width: 76, height: 26)
        effect.addSubview(close)
        close.handler = { [weak self] in self?.close() }
        effect.onEscape = { [weak self] in self?.close() }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(effect)
        // 바깥(다른 앱)을 클릭하면 닫는다
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.close() }
    }

    private static func row(_ item: Briefing.Item, width: CGFloat) -> NSView {
        var views: [NSView] = []
        switch item {
        case .agent(let s):
            let title = NSTextField(labelWithString: s.name)
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.lineBreakMode = .byTruncatingMiddle
            let ago = RelativeDateTimeFormatter().localizedString(for: s.updated, relativeTo: Date())
            let status = NSTextField(labelWithString: "\(s.state.label) · \(ago)")
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            let head = NSStackView(views: [s.badge(size: 20), title])
            head.spacing = 8
            views += [head, status]
            if s.state == .done, let summary = s.summary, !summary.isEmpty {
                let text = NSTextField(wrappingLabelWithString: summary)   // 에이전트 글은 평문으로만
                text.font = .systemFont(ofSize: 12)
                text.maximumNumberOfLines = 3
                text.preferredMaxLayoutWidth = width
                text.isSelectable = false
                views.append(text)
            }
            if let app = s.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                views.append(ClosureButton("터미널로 가기") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) })
            }
        case .conversion(let date, let urls):
            let names = urls.map(\.lastPathComponent)
            let title = NSTextField(labelWithString: names.count == 1 ? names[0] : "\(names[0]) 외 \(names.count - 1)개")
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.lineBreakMode = .byTruncatingMiddle
            let ago = NSTextField(labelWithString: RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
            ago.font = .systemFont(ofSize: 11)
            ago.textColor = .secondaryLabelColor
            views += [title, ago, ClosureButton("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting(urls) }]
        }
        let v = NSStackView(views: views)
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 3
        return v
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onClose()
    }
}

/// Esc를 받는 배경 뷰
final class EscapableEffectView: NSVisualEffectView {
    var onEscape: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}
