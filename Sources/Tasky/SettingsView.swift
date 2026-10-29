import AppKit
import Carbon

// F13 설정 창: 위쪽 아이콘 탭 + 탭마다 한 화면. 근거: intent/F13-설정창-원형메뉴-디자인/

struct SettingsTab {
    let id: String
    let title: String
    let symbol: String
    let content: NSView
}

/// 왼쪽 목록 + 오른쪽 내용(macOS 시스템 설정 모양, F19). 창 크기는 고정, 긴 내용은 오른쪽만 스크롤.
final class SettingsTabs: NSView, NSTableViewDataSource, NSTableViewDelegate {
    static let sidebarWidth: CGFloat = 180
    static let width: CGFloat = 500          // 오른쪽 내용 폭
    static let size = CGSize(width: sidebarWidth + width, height: 520)
    private let tabs: [SettingsTab]
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let title = NSTextField(labelWithString: "")
    /// 이 탭 앞에 구분선(개발자·정보)
    private let splitBefore: Set<String> = ["debug"]

    private static var lastTab: String? {
        get { UserDefaults.standard.string(forKey: "settingsTab") }
        set { UserDefaults.standard.set(newValue, forKey: "settingsTab") }
    }

    init(tabs: [SettingsTab]) {
        self.tabs = tabs
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        // 왼쪽 목록
        let side = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: Self.sidebarWidth, height: Self.size.height))
        side.material = .sidebar
        side.blendingMode = .withinWindow
        side.autoresizingMask = [.height]
        addSubview(side)
        let col = NSTableColumn(identifier: .init("tab"))
        col.width = Self.sidebarWidth - 20
        table.addTableColumn(col)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 30
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("설정 목록")
        let sideScroll = NSScrollView(frame: side.bounds.insetBy(dx: 8, dy: 0).offsetBy(dx: 0, dy: -12))
        sideScroll.frame.size.height = Self.size.height - 24
        sideScroll.frame.origin.y = 12
        sideScroll.drawsBackground = false
        sideScroll.documentView = table
        sideScroll.hasVerticalScroller = false
        side.addSubview(sideScroll)
        // 오른쪽 제목 + 내용
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.frame = CGRect(x: Self.sidebarWidth + 24, y: Self.size.height - 44, width: Self.width - 48, height: 24)
        addSubview(title)
        scroll.frame = CGRect(x: Self.sidebarWidth, y: 0, width: Self.width, height: Self.size.height - 56)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        addSubview(scroll)
        table.reloadData()
        select(tabs.firstIndex { $0.id == Self.lastTab } ?? 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ i: Int) {
        Self.lastTab = tabs[i].id
        if table.selectedRow != i { table.selectRowIndexes([i], byExtendingSelection: false) }
        title.stringValue = tabs[i].title
        let content = tabs[i].content
        // 내용은 제 높이로 두고, 문서만 스크롤 칸보다 짧지 않게(남는 공간을 줄이 가져가 늘어나지 않게)
        let fit = content.fittingSize.height
        content.frame = CGRect(x: 0, y: 0, width: Self.width, height: fit)
        let doc = FlippedView(frame: CGRect(x: 0, y: 0, width: Self.width, height: max(fit, scroll.contentSize.height)))
        doc.addSubview(content)
        scroll.documentView = doc
        doc.scroll(.zero)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tabs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = tabs[row]
        let cell = NSTableCellView()
        // 색 있는 둥근 사각 아이콘(시스템 설정 모양)
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 6
        tile.layer?.backgroundColor = Self.tint(t.id).cgColor
        let icon = NSImageView(image: NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = .white
        let name = NSTextField(labelWithString: t.title)
        name.font = .systemFont(ofSize: 13)
        for v in [tile, icon, name] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            tile.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 22), tile.heightAnchor.constraint(equalToConstant: 22),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor), icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 9),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.textField = name
        if splitBefore.contains(t.id) || (t.id == "about" && !tabs.contains { $0.id == "debug" }) {
            let line = NSBox()
            line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                line.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                line.topAnchor.constraint(equalTo: cell.topAnchor, constant: -1),
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 { select(table.selectedRow) }
    }

    private static func tint(_ id: String) -> NSColor {
        switch id {
        case "general": .systemGray
        case "pet": .systemOrange
        case "alerts": .systemRed
        case "keyboard": .systemBlue
        case "clipboard": .systemTeal
        case "snap": .systemIndigo
        case "debug": .systemBrown
        default: .systemGray
        }
    }

    /// 구역들: 구역 제목(작은 회색) + 둥근 카드 안의 줄들.
    /// 줄 = [이름, 컨트롤] 또는 [이름, 컨트롤, 설명]. 이름 자리가 빈 NSView면 그 줄은 카드 폭 전체를 쓴다(안내·미리보기).
    static func grid(_ sections: [(String?, [[NSView]])]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 24, bottom: 24, right: 24)
        let cardWidth = width - 48
        for (i, (title, items)) in sections.enumerated() {
            if let title {
                let t = NSTextField(labelWithString: title)
                t.font = .systemFont(ofSize: 11, weight: .semibold)
                t.textColor = .secondaryLabelColor
                if i > 0 { stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!) }
                stack.addArrangedSubview(t)
            } else if i > 0 {
                stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
            }
            stack.addArrangedSubview(card(items, width: cardWidth))
        }
        return stack
    }

    private static func card(_ items: [[NSView]], width: CGFloat) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        var above: NSLayoutYAxisAnchor = box.topAnchor
        for (n, row) in items.enumerated() {
            let line = NSView()
            line.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(line)
            let wide = type(of: row[0]) == NSView.self   // 이름 없는 줄
            if wide {
                let v = row[1]
                v.translatesAutoresizingMaskIntoConstraints = false
                line.addSubview(v)
                NSLayoutConstraint.activate([
                    v.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: 14),
                    v.trailingAnchor.constraint(lessThanOrEqualTo: line.trailingAnchor, constant: -14),
                    v.topAnchor.constraint(equalTo: line.topAnchor, constant: 8),
                    v.bottomAnchor.constraint(equalTo: line.bottomAnchor, constant: -8),
                ])
            } else {
                let name = row[0], control = row[1]
                if let f = name as? NSTextField { f.font = .systemFont(ofSize: 13) }
                let left = NSStackView(views: [name] + (row.count > 2 ? [row[2]] : []))
                left.orientation = .vertical
                left.alignment = .leading
                left.spacing = 2
                if row.count > 2, let d = row[2] as? NSTextField {
                    d.font = .systemFont(ofSize: 11)
                    d.textColor = .secondaryLabelColor
                    d.lineBreakMode = .byWordWrapping
                    d.maximumNumberOfLines = 2
                    d.preferredMaxLayoutWidth = width * 0.5
                }
                for v in [left, control] { v.translatesAutoresizingMaskIntoConstraints = false; line.addSubview(v) }
                left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                NSLayoutConstraint.activate([
                    left.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: 14),
                    left.centerYAnchor.constraint(equalTo: line.centerYAnchor),
                    left.topAnchor.constraint(greaterThanOrEqualTo: line.topAnchor, constant: 8),
                    control.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 12),
                    control.trailingAnchor.constraint(equalTo: line.trailingAnchor, constant: -14),
                    control.centerYAnchor.constraint(equalTo: line.centerYAnchor),
                    control.topAnchor.constraint(greaterThanOrEqualTo: line.topAnchor, constant: 6),
                    line.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
                    left.bottomAnchor.constraint(lessThanOrEqualTo: line.bottomAnchor, constant: -8),
                    control.bottomAnchor.constraint(lessThanOrEqualTo: line.bottomAnchor, constant: -6),
                ])
                let snug = line.heightAnchor.constraint(equalToConstant: 40)   // 높이를 하나로 정한다(내용이 크면 진다)
                snug.priority = .defaultLow
                snug.isActive = true
            }
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                line.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                line.topAnchor.constraint(equalTo: above),
            ])
            if n > 0 && !wide {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
                    sep.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
                    sep.topAnchor.constraint(equalTo: line.topAnchor),
                ])
            }
            above = line.bottomAnchor
        }
        above.constraint(equalTo: box.bottomAnchor).isActive = true
        return box
    }

    /// 켜기/끄기 스위치
    static func toggle(_ on: Bool, _ change: @escaping (Bool) -> Void) -> NSSwitch {
        let s = ClosureSwitch()
        s.controlSize = .small
        s.state = on ? .on : .off
        s.handler = { [weak s] in change(s?.state == .on) }
        return s
    }
}

final class ClosureSwitch: NSSwitch {
    var handler: () -> Void = {}
    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
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
