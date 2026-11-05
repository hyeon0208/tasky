import AppKit
import Carbon.HIToolbox

// F26 4단계: 빠른 실행(⌘⇧P). 한 줄 입력 → 후보 목록. ↩ 첫 번째(고른 것), ⌘↩ 두 번째.

struct QuickCandidate: Equatable {
    enum Kind: Equatable {
        case add(title: String, date: Date?, hasTime: Bool)
        case command(String)      // QuickRun.commands의 id
        case task(String, isEvent: Bool)   // TaskItem.id
        case clip(Int)            // 클립보드 기록 순서
    }
    var kind: Kind
    var title: String
    var detail: String
    var symbol: String
}

enum QuickRun {
    /// 기능 이름(찾을 말 포함). id는 `QuickRunWindow.run`이 실행한다.
    static let commands: [(id: String, title: String, symbol: String, words: [String])] =
        [("tasks", "할 일 창", "checklist.checked", ["할일", "일정", "todo"]),
         ("clip", "클립보드 기록", "doc.on.clipboard", ["복사", "붙여넣기", "clipboard"]),
         ("settings", "설정", "gearshape", ["환경", "settings"]),
         ("awake", "잠 안 자기", "cup.and.saucer", ["커피", "카페인", "잠"])]
        + CaptureMode.allCases.map { ("capture.\($0.rawValue)", $0.title, "camera.viewfinder", ["캡처", "스크린샷", "찍기"]) }
        + SnapAction.allCases.map { ("snap.\($0.rawValue)", "창 " + $0.title, "rectangle.split.2x1", ["창", "정리"]) }

    private static func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "") }

    /// 후보 계산(순수, 자체 검사 대상)
    static func candidates(_ text: String, tasks: [TaskItem], clips: [String], now: Date = Date(), calendar: Calendar = .current) -> [QuickCandidate] {
        let q = norm(text)
        let cmd = { (c: (id: String, title: String, symbol: String, words: [String])) in
            QuickCandidate(kind: .command(c.id), title: c.title, detail: "실행", symbol: c.symbol) }
        guard !q.isEmpty else { return commands.prefix(4).map(cmd) }
        var out: [QuickCandidate] = []
        let parsed = QuickParse.parse(text, now: now, calendar: calendar)
        let addDetail: String
        if let d = parsed.date {
            addDetail = TaskWindow.timeText(d, hasTime: parsed.hasTime) + (parsed.hasTime ? " · 일정에 추가" : " · 할 일에 추가")
            out.append(QuickCandidate(kind: .add(title: parsed.title, date: d, hasTime: parsed.hasTime), title: parsed.title, detail: addDetail, symbol: "calendar.badge.plus"))
        }
        // 이름이 맞으면 앞에, 찾을 말만 맞으면 뒤에
        let named = commands.filter { norm($0.title).contains(q) }
        let worded = commands.filter { c in !named.contains { $0.id == c.id } && c.words.contains { norm($0).contains(q) } }
        out += (named + worded).prefix(6).map(cmd)
        // 지금과 가까운 순(날짜 없는 것은 뒤), 지났는지·앞으로인지 함께
        let found = tasks.filter { norm($0.title).contains(q) }.sorted {
            abs(($0.date ?? .distantFuture).timeIntervalSince(now)) < abs(($1.date ?? .distantFuture).timeIntervalSince(now))
        }
        out += found.prefix(6).map { t in
            let w = when(t, now: now, calendar: calendar)
            return QuickCandidate(kind: .task(t.id, isEvent: t.isEvent), title: t.title, detail: w.text, symbol: w.symbol)
        }
        out += clips.enumerated().filter { norm($0.element).contains(q) }.prefix(4).map {
            QuickCandidate(kind: .clip($0.offset), title: $0.element.replacingOccurrences(of: "\n", with: " "), detail: "클립보드에 다시 복사", symbol: "doc.on.clipboard")
        }
        if parsed.date == nil {   // 날짜가 없어도 할 일로는 넣을 수 있게(맨 뒤)
            out.append(QuickCandidate(kind: .add(title: text.trimmingCharacters(in: .whitespaces), date: nil, hasTime: false), title: text.trimmingCharacters(in: .whitespaces), detail: "할 일에 추가", symbol: "plus.circle"))
        }
        return out
    }

    /// 검색 결과 옆 글: "지난 일정 · 3일 전", "놓친 할 일 · 10/28(화)", "끝낸 할 일", "오늘 오후 3:00 · 2시간 뒤", "5일 뒤 · 11/9(월)"
    static func when(_ t: TaskItem, now: Date, calendar: Calendar = .current) -> (text: String, symbol: String) {
        let kind = t.isEvent ? "일정" : "할 일"
        if t.done { return ("끝낸 할 일" + (t.date.map { " · " + dayText($0, calendar: calendar) } ?? ""), "checkmark.circle") }
        guard let d = t.date else { return ("할 일 · 날짜 없음", "circle") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "a h:mm"
        let time = t.hasTime ? " " + f.string(from: d) : ""
        if days == 0 {
            if t.hasTime && d < now { return (t.isEvent ? "오늘\(time) · 지났어요" : "놓친 할 일 · 오늘\(time)", t.isEvent ? "clock.arrow.circlepath" : "exclamationmark.circle") }
            let mins = Int(d.timeIntervalSince(now) / 60)
            let left = !t.hasTime ? "" : mins < 60 ? " · \(max(mins, 1))분 뒤" : " · \(mins / 60)시간 뒤"
            return ("오늘\(time)\(left)", t.isEvent ? "calendar" : "circle")
        }
        if days < 0 {
            let ago = days == -1 ? "어제" : "\(-days)일 전"
            return (t.isEvent ? "지난 일정 · \(ago)" : "놓친 할 일 · \(ago)", t.isEvent ? "clock.arrow.circlepath" : "exclamationmark.circle")
        }
        let later = days == 1 ? "내일" : "\(days)일 뒤"
        return ("\(later) · \(dayText(d, calendar: calendar))\(time) \(kind)", t.isEvent ? "calendar" : "circle")
    }
    private static func dayText(_ d: Date, calendar: Calendar) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "M/d(E)"
        return f.string(from: d)
    }

    // 단축키(id 300): 기본 ⌘⇧P
    static let hotKeyID: UInt32 = 300
    /// 메뉴에 보일 단축키 글("⌘⇧P"), 꺼져 있으면 ""
    static var keyTitle: String { key.map { HotKey.title(keyCode: $0.code, modifiers: $0.mods) } ?? "" }
    static var key: (code: UInt32, mods: UInt32)? {
        get {
            guard let a = UserDefaults.standard.array(forKey: "quickRunKey") as? [Int] else { return (UInt32(kVK_ANSI_P), UInt32(cmdKey | shiftKey)) }
            return a.count == 2 ? (UInt32(a[0]), UInt32(a[1])) : nil
        }
        set { UserDefaults.standard.set(newValue.map { [Int($0.code), Int($0.mods)] } ?? [], forKey: "quickRunKey") }
    }
    enum KeyStatus { case ok, off, system, taken }
    private(set) static var status: KeyStatus = .off
    static var onPress: () -> Void = {}
    static func register() {
        HotKey.shared.remove(id: hotKeyID)
        guard let k = key else { status = .off; return }
        if SystemHotKeys.conflicts(k, in: SystemHotKeys.load()) { status = .system; return }
        status = HotKey.shared.add(id: hotKeyID, keyCode: k.code, modifiers: k.mods) { onPress() } ? .ok : .taken
    }
}

/// 빠른 실행 창: 화면 위쪽 3분의 1, 입력 + 후보 목록
final class QuickRunWindow: NSObject, NSTextFieldDelegate {
    static let shared = QuickRunWindow()
    private var panel: FloatingPanel?
    private let input = NSTextField()
    private let list = NSStackView()
    private let root = NSView()
    private let icon = NSImageView(image: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage())
    private var glass: NSView?
    /// 찾을 할 일·일정(열 때 앞뒤 1년을 읽어 둔다)
    private var index: [TaskItem] = []
    /// 지난번에 읽은 검색 목록(캘린더 2년치는 느려서, 새로 읽는 동안 먼저 쓴다)
    private var cached: [TaskItem]?
    private var items: [QuickCandidate] = []
    private var selected = 0
    private var previousApp: NSRunningApplication?
    private var monitors: [Any] = []
    /// 앱 쪽 동작(설정 열기·잠 안 자기 등)
    var runCommand: (String) -> Void = { _ in }
    private static let width: CGFloat = 520, rowH: CGFloat = 40

    func toggle() { panel == nil ? open() : close(restore: true) }

    func open() {
        guard panel == nil else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let p = FloatingPanel(size: CGSize(width: Self.width, height: 60))
        p.keyable = true
        p.level = .popUpMenu
        panel = p
        input.placeholderString = "할 일 적기, 기능 이름, 찾기 · ↩ 실행 · Esc 닫기"
        input.font = .systemFont(ofSize: 18)
        input.isBordered = false; input.drawsBackground = false; input.focusRingType = .none
        input.stringValue = ""
        input.delegate = self
        list.orientation = .vertical; list.spacing = 2; list.alignment = .leading
        index = TaskStore.anyOn ? cached ?? TaskLogic.pending(TaskStore.shared.items, now: Date()) : []
        if TaskStore.anyOn {
            TaskStore.shared.searchIndex { [weak self] all in
                guard let self else { return }
                self.cached = all
                guard self.panel != nil else { return }
                self.index = all
                if !self.input.stringValue.isEmpty { self.refresh() }
            }
        }
        refresh()
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close(restore: false) },
            // ⌘↩는 입력칸의 insertNewline:으로 오지 않으므로 여기서 받는다
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.window === self.panel, e.keyCode == 36 || e.keyCode == 76,
                      e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return e }
                self.run(1); return nil
            },
        ].compactMap { $0 }
        NSApp.activate(ignoringOtherApps: true)   // 사용자가 직접 연 창이라 바로 입력
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(input)
    }

    func close(restore: Bool) {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        panel?.orderOut(nil); panel = nil
        root.subviews.forEach { $0.removeFromSuperview() }
        if restore { previousApp?.activate() }
    }

    private func refresh() {
        guard let p = panel else { return }
        let clips = ClipStore.shared.history.items.compactMap(\.text)
        items = QuickRun.candidates(input.stringValue, tasks: index, clips: clips)
        selected = min(selected, max(items.count - 1, 0))
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, c) in items.prefix(8).enumerated() { list.addArrangedSubview(row(c, on: i == selected, index: i)) }

        // 입력칸은 그대로 두고 크기·목록만 바꾼다(창을 다시 만들면 입력 포커스·한글 조합이 끊긴다)
        let w = Self.width, listH = CGFloat(min(items.count, 8)) * (Self.rowH + 2)
        let h = 56 + (listH > 0 ? listH + 10 : 0)
        if p.contentView !== root {
            root.wantsLayer = true; root.layer?.cornerRadius = 20; root.layer?.masksToBounds = true
            glass = makeGlass(cornerRadius: 20, frame: CGRect(x: 0, y: 0, width: w, height: h))
            glass?.autoresizingMask = [.width, .height]
            root.subviews.forEach { $0.removeFromSuperview() }
            [glass!, icon, input, list].forEach(root.addSubview)
            icon.contentTintColor = .secondaryLabelColor
            icon.autoresizingMask = [.minYMargin]; input.autoresizingMask = [.minYMargin]
            p.contentView = root
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        let top = p.isVisible ? p.frame.maxY : v.maxY - v.height / 4
        let x = p.isVisible ? p.frame.minX : v.midX - w / 2
        p.setFrame(CGRect(x: x, y: top - h, width: w, height: h), display: true)
        icon.frame = CGRect(x: 16, y: h - 40, width: 22, height: 22)
        input.frame = CGRect(x: 46, y: h - 44, width: w - 62, height: 28)
        list.frame = CGRect(x: 8, y: 8, width: w - 16, height: listH)
    }

    private func row(_ c: QuickCandidate, on: Bool, index: Int) -> NSView {
        let v = QuickRow(frame: CGRect(x: 0, y: 0, width: Self.width - 16, height: Self.rowH))
        v.wantsLayer = true; v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: Self.width - 16).isActive = true
        v.heightAnchor.constraint(equalToConstant: Self.rowH).isActive = true
        let img = NSImageView(image: NSImage(systemSymbolName: c.symbol, accessibilityDescription: nil) ?? NSImage())
        img.contentTintColor = .labelColor
        img.frame = CGRect(x: 12, y: 11, width: 18, height: 18)
        let t = NSTextField(labelWithString: c.title); t.font = .systemFont(ofSize: 14, weight: .medium); t.lineBreakMode = .byTruncatingTail
        t.frame = CGRect(x: 40, y: 11, width: Self.width - 220, height: 18)
        let d = NSTextField(labelWithString: c.detail + (index == 0 ? "  ↩" : index == 1 ? "  ⌘↩" : "")); d.font = .systemFont(ofSize: 12); d.textColor = .secondaryLabelColor
        d.alignment = .right; d.lineBreakMode = .byTruncatingTail
        d.frame = CGRect(x: Self.width - 186, y: 12, width: 160, height: 16)
        [img, t, d].forEach(v.addSubview)
        v.onClick = { [weak self] in self?.run(index) }
        return v
    }

    func controlTextDidChange(_ obj: Notification) { selected = 0; refresh() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            run(selected); return true
        case #selector(NSResponder.cancelOperation(_:)): close(restore: true); return true
        case #selector(NSResponder.moveDown(_:)): selected = min(selected + 1, min(items.count, 8) - 1); refresh(); return true
        case #selector(NSResponder.moveUp(_:)): selected = max(selected - 1, 0); refresh(); return true
        default: return false
        }
    }

    private func run(_ index: Int) {
        guard items.indices.contains(index) else { NSSound.beep(); return }
        let c = items[index]
        switch c.kind {
        case let .add(title, date, hasTime):
            let store = TaskStore.shared
            if let problem = store.add(title: title, date: date, hasTime: hasTime, asEvent: hasTime && store.canAddEvent) {
                NSSound.beep(); input.placeholderString = problem; return
            }
            close(restore: true)
        case let .task(_, isEvent):
            // 지난 일·끝낸 일도 볼 수 있게 캘린더·미리 알림 앱을 연다
            close(restore: false)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: isEvent ? "com.apple.iCal" : "com.apple.reminders") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        case let .clip(i):
            let all = ClipStore.shared.history.items.filter { $0.text != nil }
            if all.indices.contains(i) { ClipWatcher.shared.put(all[i]) }
            close(restore: true)
        case let .command(id):
            close(restore: !id.hasPrefix("tasks") && !id.hasPrefix("clip") && id != "settings")
            // 앞 앱으로 돌아간 뒤 창 정리·캡처가 그 창을 대상으로 하도록 조금 뒤에
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.perform(id) }
        }
    }

    private func perform(_ id: String) {
        if id.hasPrefix("capture."), let m = CaptureMode(rawValue: String(id.dropFirst(8))) { Capture.shared.take(m); return }
        if id.hasPrefix("snap."), let a = SnapAction(rawValue: String(id.dropFirst(5))) { SnapController.shared.perform(a); return }
        switch id {
        case "tasks": TaskWindow.shared.open()
        case "clip": ClipWindow.shared.open()
        default: runCommand(id)
        }
    }
}

private final class QuickRow: NSView {
    var onClick: () -> Void = {}
    override func mouseUp(with event: NSEvent) { onClick() }
}
