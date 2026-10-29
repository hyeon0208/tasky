import AppKit
import Carbon

// F13 설정 창: 위쪽 아이콘 탭 + 탭마다 한 화면. 근거: intent/F13-설정창-원형메뉴-디자인/

struct SettingsTab {
    let id: String
    let title: String
    let symbol: String
    let content: NSView
}

/// 아이콘 탭 줄과 내용. 탭을 바꾸면 `onResize`로 새 크기를 알린다(창 높이는 내용에 맞춘다).
final class SettingsTabs: NSView {
    static let width: CGFloat = 520
    private let tabs: [SettingsTab]
    private var buttons: [NSButton] = []
    private let bar = NSStackView()
    private let title = NSTextField(labelWithString: "")
    private var current: NSView?
    var onResize: (CGSize) -> Void = { _ in }

    private static var lastTab: String? {
        get { UserDefaults.standard.string(forKey: "settingsTab") }
        set { UserDefaults.standard.set(newValue, forKey: "settingsTab") }
    }

    init(tabs: [SettingsTab]) {
        self.tabs = tabs
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .center
        addSubview(title)
        bar.orientation = .horizontal
        bar.spacing = 2
        // 탭이 많아도 창 폭 안에 다 들어가게 버튼 폭을 나눈다
        let buttonWidth = min(72, (Self.width - 16 - bar.spacing * CGFloat(tabs.count - 1)) / CGFloat(tabs.count))
        for (i, t) in tabs.enumerated() {
            let b = ClosureButton("") { [weak self] in self?.select(i) }
            b.isBordered = false
            b.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)?
                .withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            b.title = t.title
            b.imagePosition = .imageAbove
            b.font = .systemFont(ofSize: 11)
            b.setAccessibilityRole(.radioButton)
            b.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            b.lineBreakMode = .byClipping
            b.heightAnchor.constraint(equalToConstant: 48).isActive = true
            b.wantsLayer = true
            b.layer?.cornerRadius = 8
            buttons.append(b)
            bar.addArrangedSubview(b)
        }
        addSubview(bar)
        select(tabs.firstIndex { $0.id == Self.lastTab } ?? 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let headerHeight: CGFloat = 96

    func select(_ i: Int) {
        Self.lastTab = tabs[i].id
        for (j, b) in buttons.enumerated() {
            let on = i == j
            b.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
            b.layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor : nil
            b.setAccessibilityValue(on)
        }
        title.stringValue = tabs[i].title
        current?.removeFromSuperview()
        let content = tabs[i].content
        addSubview(content)
        current = content
        let size = CGSize(width: Self.width, height: Self.headerHeight + content.fittingSize.height)
        layoutFor(size)
        onResize(size)
    }

    private func layoutFor(_ size: CGSize) {
        frame.size = size
        title.frame = CGRect(x: 0, y: size.height - 26, width: size.width, height: 18)
        let barSize = bar.fittingSize
        bar.frame = CGRect(x: (size.width - barSize.width) / 2, y: size.height - 30 - barSize.height - 8, width: barSize.width, height: barSize.height)
        if let current {
            current.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height - Self.headerHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 탭 줄 아래 구분선
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - Self.headerHeight + 0.5, width: bounds.width, height: 1).fill()
    }

    /// 구역(제목 + 이름·값 줄)들을 격자로. 제목이 nil이면 제목 줄 없이.
    static func grid(_ sections: [(String?, [[NSView]])]) -> NSView {
        var rows: [[NSView]] = []
        var headerRows: [Int] = []
        for (title, items) in sections {
            if let title {
                let t = NSTextField(labelWithString: title)
                t.font = .systemFont(ofSize: 12, weight: .semibold)
                t.textColor = .secondaryLabelColor
                headerRows.append(rows.count)
                rows.append([t, NSView()])
            }
            rows += items
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 130
        grid.rowAlignment = .firstBaseline
        for i in headerRows {
            let row = grid.row(at: i)
            row.mergeCells(in: NSRange(location: 0, length: 2))
            row.cell(at: 0).xPlacement = .leading
            row.topPadding = i == 0 ? 0 : 10
        }
        let stack = NSStackView(views: [grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 20, right: 22)
        return stack
    }
}

/// 키보드 탭의 '바로 테스트' 칸: 지금 입력 소스(가/A)와 대문자 고정(⇪)을 보여 주고, 설정을 바꾸면 여기서 바로 쳐 본다.
/// 칸의 글자는 저장하지 않는다.
final class KeyTestField: NSStackView {
    private let badge = NSTextField(labelWithString: "")
    private let field = NSTextField()
    private var observer: Any?
    private var flagsMonitor: Any?

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 10
        badge.font = .systemFont(ofSize: 16, weight: .semibold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 10
        badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.setAccessibilityLabel("지금 입력 소스")
        badge.widthAnchor.constraint(equalToConstant: 52).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 32).isActive = true
        field.placeholderString = "한영 전환 키를 누르거나 키를 꾹 눌러 보세요"
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 270).isActive = true
        addArrangedSubview(badge)
        addArrangedSubview(field)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.refresh()
            return e
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 설정 창을 닫을 때 감시를 푼다
    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        observer = nil
        flagsMonitor = nil
    }

    private func refresh() {
        let korean = InputSources.currentIsKorean
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        badge.stringValue = (korean ? "가" : "A") + (caps ? "⇪" : "")
    }
}

/// 시계 말풍선 보이기 방식(모든 펫 공통, 기본: 항상)
enum ClockMode: String, CaseIterable {
    case always, hover, off
    static let changed = Notification.Name("taskyClockModeChanged")
    var title: String {
        switch self {
        case .always: "항상"
        case .hover: "커서를 올렸을 때"
        case .off: "끄기"
        }
    }
    static var current: ClockMode {
        get { ClockMode(rawValue: UserDefaults.standard.string(forKey: "clockMode") ?? "") ?? .always }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "clockMode")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    /// 24시간제(기본 꺼짐), 초 보이기(기본 켜짐)
    static var hour24: Bool {
        get { UserDefaults.standard.bool(forKey: "clock24") }
        set { UserDefaults.standard.set(newValue, forKey: "clock24"); NotificationCenter.default.post(name: changed, object: nil) }
    }
    static var showSeconds: Bool {
        get { UserDefaults.standard.object(forKey: "clockSeconds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "clockSeconds"); NotificationCenter.default.post(name: changed, object: nil) }
    }
    /// "오후 3:07:09" · 24시간제면 "15:07:09" · 초를 끄면 초 없이
    static func text(_ d: Date, hour24: Bool = ClockMode.hour24, seconds: Bool = ClockMode.showSeconds, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0, s = c.second ?? 0
        let sec = seconds ? String(format: ":%02d", s) : ""
        if hour24 { return String(format: "%02d:%02d", h, m) + sec }
        return String(format: "%@ %d:%02d", h < 12 ? "오전" : "오후", h % 12 == 0 ? 12 : h % 12, m) + sec
    }
}

/// 어두운 알약 + 아래 꼬리(시안의 말풍선)
final class ClockBubble: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let body = CGRect(x: 0, y: 6, width: bounds.width, height: bounds.height - 6)
        let path = NSBezierPath(roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)
        path.move(to: CGPoint(x: bounds.midX - 6, y: 6))
        path.line(to: CGPoint(x: bounds.midX, y: 0))
        path.line(to: CGPoint(x: bounds.midX + 6, y: 6))
        path.close()
        NSColor(white: 0.11, alpha: 0.85).setFill()
        path.fill()
    }
}
