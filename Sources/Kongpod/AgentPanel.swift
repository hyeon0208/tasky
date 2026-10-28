import AppKit

extension AgentSession.State {
    var color: NSColor {
        switch self {
        case .working: NSColor(red: 0.25, green: 0.61, blue: 0.51, alpha: 1)   // 싹
        case .waiting: NSColor(red: 0.79, green: 0.51, blue: 0.09, alpha: 1)   // 반짝
        case .done: NSColor(red: 0.23, green: 0.45, blue: 0.27, alpha: 1)      // 여묾
        case .failed: NSColor(red: 0.68, green: 0.31, blue: 0.24, alpha: 1)    // 시듦
        }
    }
    var label: String {
        switch self {
        case .working: "일하는 중"
        case .waiting: "기다려요 (터미널에서 답해 주세요)"
        case .done: "끝났어요"
        case .failed: "실패했어요"
        }
    }
}

extension AgentSession {
    /// 도구 구분 이미지. 이 Mac에 설치된 Claude·ChatGPT(Codex) 앱 아이콘을 실행 중에 가져와 쓴다
    /// (앱에 상표 이미지를 넣지 않는다). 앱이 없으면 글자 배지.
    var toolIcon: NSImage {
        let bundleID = tool == "codex" ? "com.openai.codex" : "com.anthropic.claudefordesktop"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let symbol = tool == "codex" ? "o.circle.fill" : "c.circle.fill"
        let color: NSColor = tool == "codex" ? .labelColor : NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: tool)!
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular).applying(.init(paletteColors: [color])))!
    }

    /// 아이콘 + 오른쪽 아래 상태 점
    func badge(size: CGFloat) -> NSView {
        let box = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        let icon = NSImageView(frame: box.bounds)
        icon.image = toolIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        box.addSubview(icon)
        let d: CGFloat = max(8, size * 0.36)
        let dot = NSView(frame: CGRect(x: size - d, y: 0, width: d, height: d))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = state.color.cgColor
        dot.layer?.cornerRadius = d / 2
        dot.layer?.borderWidth = 1.5
        dot.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        box.addSubview(dot)
        box.widthAnchor.constraint(equalToConstant: size).isActive = true
        box.heightAnchor.constraint(equalToConstant: size).isActive = true
        return box
    }
}

/// 작업 알림 목록: 세션마다 상태·요약, 터미널로 가기, 그리고 Claude Code·Codex 연결 버튼.
final class AgentListController: NSObject {
    let view: NSView
    private let store: AgentStore
    private let stack = NSStackView()
    private let size: CGSize
    private let onClose: () -> Void

    init(size: CGSize, store: AgentStore, onClose: @escaping () -> Void) {
        self.size = size
        self.store = store
        self.onClose = onClose
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        view = effect
        super.init()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 44, width: size.width, height: size.height - 44))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let flipped = FlippedView(frame: scroll.bounds)
        flipped.autoresizingMask = [.width]
        flipped.addSubview(stack)
        scroll.documentView = flipped
        view.addSubview(scroll)

        let line = NSBox(frame: CGRect(x: 0, y: 43, width: size.width, height: 1))
        line.boxType = .separator
        view.addSubview(line)
        reload()
    }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let sessions = store.ordered
        if sessions.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: anyConnected
                ? "아직 받은 작업이 없어요. 터미널에서 Claude Code나 Codex에 일을 맡기면 여기에 보여요."
                : "아래에서 Claude Code나 Codex를 연결하면, 작업이 끝나거나 나를 기다릴 때 깍지가 알려줘요.")
            empty.textColor = .secondaryLabelColor
            empty.preferredMaxLayoutWidth = size.width - 28
            stack.addArrangedSubview(empty)
        }
        for s in sessions { stack.addArrangedSubview(row(s)) }
        let height = max(stack.fittingSize.height, size.height - 44)
        stack.frame = CGRect(x: 0, y: 0, width: size.width - 16, height: height)
        stack.superview?.frame.size = CGSize(width: size.width - 16, height: height)
        buildBottomBar()
    }

    private var anyConnected: Bool { HookInstaller.isInstalled(.claude) || HookInstaller.isInstalled(.codex) }

    private func row(_ s: AgentSession) -> NSView {
        let title = NSTextField(labelWithString: s.name)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        let ago = RelativeDateTimeFormatter().localizedString(for: s.updated, relativeTo: Date())
        let status = NSTextField(labelWithString: "\(s.state.label) · \(ago)\(s.whileOff ? " · 펫이 꺼져 있던 동안" : "")")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        let head = NSStackView(views: [s.badge(size: 22), title])
        head.spacing = 8
        var views: [NSView] = [head, status]

        if let summary = s.summary, !summary.isEmpty {
            // 에이전트가 쓴 글은 평문으로만 보여준다(링크·동작 없음)
            let text = NSTextField(wrappingLabelWithString: summary)
            text.font = .systemFont(ofSize: 12)
            text.maximumNumberOfLines = 3
            text.preferredMaxLayoutWidth = size.width - 40
            text.isSelectable = false
            views.append(text)
        }
        var buttons: [NSView] = []
        if let app = s.app, NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) != nil {
            buttons.append(ClosureButton("터미널로 가기") { [weak self] in
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
                self?.onClose()
            })
        }
        if s.state != .working {
            buttons.append(ClosureButton("목록에서 지우기") { [weak self] in self?.store.remove(s.id); self?.reload() })
        }
        if !buttons.isEmpty {
            let b = NSStackView(views: buttons)
            b.spacing = 8
            views.append(b)
        }
        let v = NSStackView(views: views)
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 4
        return v
    }

    private var bottomBar: NSView?

    private func buildBottomBar() {
        bottomBar?.removeFromSuperview()
        let buttons = [HookInstaller.Tool.claude, .codex].map { tool in
            let on = HookInstaller.isInstalled(tool)
            return ClosureButton(on ? "\(tool.title) 연결 끊기" : "\(tool.title) 연결") { [weak self] in self?.toggle(tool, to: !on) }
        }
        let bar = NSStackView(views: buttons)
        bar.spacing = 8
        bar.frame = CGRect(x: 12, y: 8, width: size.width - 24, height: 28)
        view.addSubview(bar)
        bottomBar = bar
    }

    private func toggle(_ tool: HookInstaller.Tool, to install: Bool) {
        _ = HookInstaller.confirmAndSet(tool, install: install)
        reload()
    }
}

extension HookInstaller {
    /// 바뀔 내용을 확인 창으로 보여주고, 동의하면 연결하거나 끊는다.
    static func confirmAndSet(_ tool: Tool, install: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = install ? "\(tool.title)를 연결할까요?" : "\(tool.title) 연결을 끊을까요?"
        alert.informativeText = HookInstaller.preview(tool, install: install)
            + (install && tool == .codex ? "\n\nCodex가 처음 실행될 때 새 훅을 믿을지 물을 수 있어요. 허용해 주세요." : "")
            + (install ? "\n\n이미 실행 중인 세션에는 새로 시작한 뒤부터 적용될 수 있어요." : "")
        alert.addButton(withTitle: install ? "연결" : "끊기")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            try set(tool, installed: install)
            return true
        } catch {
            let fail = NSAlert()
            fail.messageText = "설정 파일을 바꾸지 못했어요"
            fail.informativeText = error.localizedDescription
            fail.runModal()
            return false
        }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ClosureButton: NSButton {
    var handler: () -> Void = {}
    convenience init(_ title: String, _ handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.handler = handler
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(run)
    }
    @objc private func run() { handler() }
}

/// 작업 알림 메시지 창. 알림음과 함께 펫 근처에 뜨고, 커서가 올라가 있지 않으면 8초 뒤 사라진다.
final class AlertCard {
    private(set) var panel: FloatingPanel?
    private var timer: Timer?
    private var shownAt = Date()

    static var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "alertSound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alertSound") }
    }

    struct Action { let title: String; let run: () -> Void }

    func show(session: AgentSession, title: String, body: String?, actions: [Action], near petFrame: CGRect, in v: CGRect) {
        let state = session.state
        dismiss()
        if Self.soundOn {
            let sound = switch state { case .waiting: "Ping"; case .failed: "Basso"; default: "Glass" }
            NSSound(named: sound)?.play()
        }

        let width: CGFloat = 320
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        let head = NSStackView(views: [session.badge(size: 28), titleLabel])
        head.spacing = 8
        var rows: [NSView] = [head]
        if let body, !body.isEmpty {
            let text = NSTextField(wrappingLabelWithString: body)   // 에이전트가 쓴 글은 평문으로만
            text.font = .systemFont(ofSize: 12)
            text.textColor = .secondaryLabelColor
            text.maximumNumberOfLines = 3
            text.preferredMaxLayoutWidth = width - 28
            text.isSelectable = false
            rows.append(text)
        }
        let buttons = actions.map { a in ClosureButton(a.title) { [weak self] in self?.dismiss(); a.run() } }
            + [ClosureButton("닫기") { [weak self] in self?.dismiss() }]
        let bar = NSStackView(views: buttons)
        bar.spacing = 6
        rows.append(bar)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        let height = stack.fittingSize.height
        stack.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let effect = NSVisualEffectView(frame: stack.frame)
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)

        let shown = petFrame.intersection(v).isNull ? petFrame : petFrame.intersection(v)
        let x = min(max(shown.midX - width / 2, v.minX + 8), v.maxX - width - 8)
        let above = shown.maxY + 8 + height <= v.maxY
        let y = above ? shown.maxY + 8 : max(shown.minY - height - 8, v.minY + 8)
        let p = FloatingPanel(size: CGSize(width: width, height: height))
        p.setFrame(CGRect(x: x, y: y, width: width, height: height), display: false)
        p.contentView = effect
        p.orderFrontRegardless()
        panel = p
        shownAt = Date()
        timer = Ticker.every("알림 카드가 펫 따라가기", 0.5) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if panel.frame.contains(NSEvent.mouseLocation) { self.shownAt = Date() }
            else if Date().timeIntervalSince(self.shownAt) > 8 { self.dismiss() }
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
