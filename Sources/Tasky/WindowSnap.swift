import AppKit
import Carbon.HIToolbox

// F15 창 정리: Rectangle(MIT)과 같은 방식·같은 기본 단축키. 코드는 옮기지 않고 새로 씀. 근거: intent/F15-창-정리/

enum SnapAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, restore
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case prevDisplay, nextDisplay

    var title: String {
        switch self {
        case .leftHalf: "왼쪽 반"; case .rightHalf: "오른쪽 반"; case .topHalf: "위쪽 반"; case .bottomHalf: "아래쪽 반"
        case .maximize: "최대화"; case .center: "가운데"; case .restore: "원래대로"
        case .topLeft: "왼쪽 위 4분의 1"; case .topRight: "오른쪽 위 4분의 1"; case .bottomLeft: "왼쪽 아래 4분의 1"; case .bottomRight: "오른쪽 아래 4분의 1"
        case .firstThird: "왼쪽 3분의 1"; case .centerThird: "가운데 3분의 1"; case .lastThird: "오른쪽 3분의 1"
        case .firstTwoThirds: "왼쪽 3분의 2"; case .lastTwoThirds: "오른쪽 3분의 2"
        case .prevDisplay: "이전 모니터로"; case .nextDisplay: "다음 모니터로"
        }
    }

    /// Rectangle 기본값: ⌃⌥ + 키, 모니터 이동은 ⌃⌥⌘
    var defaultKey: (code: UInt32, mods: UInt32) {
        let co = UInt32(controlKey | optionKey)
        let k: Int = switch self {
        case .leftHalf, .prevDisplay: kVK_LeftArrow; case .rightHalf, .nextDisplay: kVK_RightArrow
        case .topHalf: kVK_UpArrow; case .bottomHalf: kVK_DownArrow; case .maximize: kVK_Return
        case .center: kVK_ANSI_C; case .restore: kVK_Delete
        case .topLeft: kVK_ANSI_U; case .topRight: kVK_ANSI_I; case .bottomLeft: kVK_ANSI_J; case .bottomRight: kVK_ANSI_K
        case .firstThird: kVK_ANSI_D; case .centerThird: kVK_ANSI_F; case .lastThird: kVK_ANSI_G
        case .firstTwoThirds: kVK_ANSI_E; case .lastTwoThirds: kVK_ANSI_T
        }
        return (UInt32(k), self == .prevDisplay || self == .nextDisplay ? co | UInt32(cmdKey) : co)
    }

    /// 저장된 키(없으면 기본값). code가 nil이면 사용자가 지움.
    var key: (code: UInt32, mods: UInt32)? {
        get {
            guard let a = UserDefaults.standard.array(forKey: "snapKey.\(rawValue)") as? [Int] else { return defaultKey }
            return a.count == 2 ? (UInt32(a[0]), UInt32(a[1])) : nil
        }
        nonmutating set { UserDefaults.standard.set(newValue.map { [Int($0.code), Int($0.mods)] } ?? [], forKey: "snapKey.\(rawValue)") }
    }
}

/// 위치 계산(순수, 자체 검사 대상). 사각형은 AppKit 좌표(왼쪽 아래 원점).
enum SnapMath {
    static func rect(_ a: SnapAction, area r: CGRect, current: CGRect) -> CGRect? {
        let w = r.width, h = r.height
        func cols(_ from: CGFloat, _ span: CGFloat) -> CGRect { CGRect(x: r.minX + w * from, y: r.minY, width: w * span, height: h) }
        switch a {
        case .leftHalf, .rightHalf:
            // 같은 쪽을 다시 누르면 1/2 → 2/3 → 1/3 → 1/2 (Rectangle 기본 동작)
            let left = a == .leftHalf
            func side(_ f: CGFloat) -> CGRect { left ? cols(0, f) : cols(1 - f, f) }
            let next: CGFloat = near(current, side(1 / 2)) ? 2 / 3 : near(current, side(2 / 3)) ? 1 / 3 : 1 / 2
            return side(next)
        case .topHalf: return CGRect(x: r.minX, y: r.minY + h / 2, width: w, height: h / 2)
        case .bottomHalf: return CGRect(x: r.minX, y: r.minY, width: w, height: h / 2)
        case .maximize: return r
        case .center:
            let s = CGSize(width: min(current.width, w), height: min(current.height, h))
            return CGRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height)
        case .topLeft: return CGRect(x: r.minX, y: r.minY + h / 2, width: w / 2, height: h / 2)
        case .topRight: return CGRect(x: r.minX + w / 2, y: r.minY + h / 2, width: w / 2, height: h / 2)
        case .bottomLeft: return CGRect(x: r.minX, y: r.minY, width: w / 2, height: h / 2)
        case .bottomRight: return CGRect(x: r.minX + w / 2, y: r.minY, width: w / 2, height: h / 2)
        case .firstThird: return cols(0, 1 / 3)
        case .centerThird: return cols(1 / 3, 1 / 3)
        case .lastThird: return cols(2 / 3, 1 / 3)
        case .firstTwoThirds: return cols(0, 2 / 3)
        case .lastTwoThirds: return cols(1 / 3, 2 / 3)
        case .restore, .prevDisplay, .nextDisplay: return nil
        }
    }

    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// 끌어 맞추기: 커서가 화면(frame) 가장자리 5pt 안이면 맞출 동작. 모서리(20pt)가 먼저.
    static func edge(_ p: CGPoint, screen s: CGRect) -> SnapAction? {
        let m: CGFloat = 5, c: CGFloat = 20
        let left = p.x <= s.minX + m, right = p.x >= s.maxX - m, top = p.y >= s.maxY - m, bottom = p.y <= s.minY + m
        let nearTop = p.y >= s.maxY - c, nearBottom = p.y <= s.minY + c
        let nearLeft = p.x <= s.minX + c, nearRight = p.x >= s.maxX - c
        if (left && nearTop) || (top && nearLeft) { return .topLeft }
        if (right && nearTop) || (top && nearRight) { return .topRight }
        if (left && nearBottom) || (bottom && nearLeft) { return .bottomLeft }
        if (right && nearBottom) || (bottom && nearRight) { return .bottomRight }
        if left { return .leftHalf }
        if right { return .rightHalf }
        if top { return .maximize }
        return nil
    }

    /// AX(왼쪽 위 원점) ↔ AppKit(왼쪽 아래 원점). 주 화면 높이로 뒤집으며, 두 번 하면 제자리.
    static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}

/// macOS 시스템 단축키(켜진 것)의 (키코드, Carbon 수정키)
enum SystemHotKeys {
    static func load() -> [(code: UInt32, mods: UInt32)] {
        guard let d = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") else { return [] }
        return d.values.compactMap { v in
            guard let e = v as? [String: Any], e["enabled"] as? Bool == true,
                  let p = (e["value"] as? [String: Any])?["parameters"] as? [Int], p.count == 3, p[1] != 65535 else { return nil }
            return (UInt32(p[1]), HotKey.carbonModifiers(NSEvent.ModifierFlags(rawValue: UInt(p[2]))))
        }
    }
    static func conflicts(_ k: (code: UInt32, mods: UInt32), in list: [(code: UInt32, mods: UInt32)]) -> Bool {
        list.contains { $0.code == k.code && $0.mods == k.mods }
    }
}

/// 다른 앱 창 읽기·쓰기(손쉬운 사용 권한 필요). 좌표는 AX 그대로.
enum AXWindow {
    static func focused() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let a = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(a, 0.5)
        return attr(a, kAXFocusedWindowAttribute)
    }
    /// 커서 아래 창(AX 좌표의 점)
    static func at(_ p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.2)   // 멈춘 앱 때문에 펫이 멈추지 않게
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &el) == .success, let el else { return nil }
        if role(el) == kAXWindowRole { return el }
        return attr(el, kAXWindowAttribute)
    }
    static func frame(_ w: AXUIElement) -> CGRect? {
        guard let pv: AXValue = attr(w, kAXPositionAttribute), let sv: AXValue = attr(w, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv, .cgPoint, &p)
        AXValueGetValue(sv, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
    static func set(_ w: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        // 크기 → 위치 → 크기: 다른 모니터로 갈 때 크기가 먼저 막히는 경우를 피한다
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
    }
    private static func role(_ e: AXUIElement) -> String? { attr(e, kAXRoleAttribute) }
    private static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
}

final class SnapController {
    static let shared = SnapController()
    enum Status { case ok, off, system, taken, ours }
    private(set) var status: [SnapAction: Status] = [:]
    var onChange: () -> Void = {}

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "snapOn") }   // 기본 꺼짐
        set { UserDefaults.standard.set(newValue, forKey: "snapOn") }
    }
    static var dragOn: Bool {
        get { UserDefaults.standard.object(forKey: "snapDrag") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "snapDrag"); shared.start() }
    }
    /// 같은 단축키를 쓰는 창 정리 앱 중 실행 중인 것(이름만 보여 준다)
    static func runningSnapApps() -> [String] {
        let ids = ["com.knollsoft.Rectangle", "com.knollsoft.Hookshot", "com.crowdcafe.windowmagnet", "com.divisiblebyzero.Spectacle", "com.manytricks.Moom", "com.MrKai77.Loop"]
        return NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") }.compactMap(\.localizedName)
    }

    private var permissionTimer: Timer?
    private var monitors: [Any] = []
    private var preview: FloatingPanel?
    private var saved: [CFHashCode: (original: CGRect, last: CGRect)] = [:]   // 창 → 맞추기 전·마지막으로 맞춘 자리(AX 좌표, 메모리만)

    /// 사용자가 켜거나 끈다. 켤 때만 권한을 요청한다.
    func setEnabled(_ on: Bool) {
        Self.enabled = on
        if on && !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        start()
    }

    /// 지금 설정대로 다시 건다(켜져 있고 권한이 있을 때만 단축키·마우스 감시)
    func start() {
        stop()
        guard Self.enabled else { onChange(); return }
        guard AXIsProcessTrusted() else {
            permissionTimer = Ticker.every("창 정리 권한 생겼는지 보기", 2) { [weak self] _ in
                if AXIsProcessTrusted() { self?.start() }
            }
            onChange()
            return
        }
        let system = SystemHotKeys.load()
        var used: [(code: UInt32, mods: UInt32)] = ClipWatcher.enabled ? [(HotKey.keyCode, HotKey.modifiers)] : []
        for (i, a) in SnapAction.allCases.enumerated() {
            guard let k = a.key else { status[a] = .off; continue }
            if SystemHotKeys.conflicts(k, in: system) { status[a] = .system; continue }
            if SystemHotKeys.conflicts(k, in: used) { status[a] = .ours; continue }   // 클립보드나 앞 동작과 같은 키
            used.append(k)
            status[a] = HotKey.shared.add(id: 100 + UInt32(i), keyCode: k.code, modifiers: k.mods) { [weak self] in self?.perform(a) } ? .ok : .taken
        }
        if Self.dragOn { watchDrags() }
        onChange()
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        for i in SnapAction.allCases.indices { HotKey.shared.remove(id: 100 + UInt32(i)) }
        status = [:]
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hidePreview()
    }

    // MARK: 맞추기

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func screen(for r: CGRect) -> NSScreen? {
        NSScreen.screens.max { $0.frame.intersection(r).area < $1.frame.intersection(r).area }
    }

    func perform(_ a: SnapAction) {
        guard let w = AXWindow.focused() else { return }
        snap(w, a)
    }

    private func snap(_ w: AXUIElement, _ a: SnapAction) {
        guard let ax = AXWindow.frame(w) else { return }
        let key = CFHash(w)
        if a == .restore {
            guard let s = saved.removeValue(forKey: key) else { return }
            AXWindow.set(w, s.original)
            return
        }
        let cur = SnapMath.flip(ax, primaryHeight: primaryHeight)
        guard let scr = screen(for: cur) else { return }
        var target: CGRect?
        if a == .prevDisplay || a == .nextDisplay {
            let all = NSScreen.screens
            guard all.count > 1, let i = all.firstIndex(of: scr) else { return }
            let to = all[(i + (a == .nextDisplay ? 1 : all.count - 1)) % all.count].visibleFrame
            target = Self.displayRect(cur: cur, from: scr.visibleFrame, to: to)
        } else {
            target = SnapMath.rect(a, area: scr.visibleFrame, current: cur)
        }
        guard let target else { return }
        // 맞춘 뒤 사용자가 옮겼으면 그 자리를 새 '원래 자리'로
        if saved[key].map({ !SnapMath.near($0.last, ax) }) ?? true { saved[key] = (ax, ax) }
        let t = SnapMath.flip(target, primaryHeight: primaryHeight)
        AXWindow.set(w, t)
        saved[key]?.last = AXWindow.frame(w) ?? t
    }

    /// 다른 모니터로: 같은 비율 자리로, 크기는 새 화면에 맞게 줄인다
    static func displayRect(cur: CGRect, from: CGRect, to: CGRect) -> CGRect {
        let s = CGSize(width: min(cur.width, to.width), height: min(cur.height, to.height))
        let fx = from.width > cur.width ? (cur.minX - from.minX) / (from.width - cur.width) : 0
        let fy = from.height > cur.height ? (cur.minY - from.minY) / (from.height - cur.height) : 0
        return CGRect(x: to.minX + (to.width - s.width) * min(max(fx, 0), 1), y: to.minY + (to.height - s.height) * min(max(fy, 0), 1), width: s.width, height: s.height)
    }

    // MARK: 끌어서 맞추기 (마우스만 듣는다)

    private var dragWindow: AXUIElement?
    private var dragStart: CGRect?
    private var dragging = false
    private var checks = 0
    private var pending: (SnapAction, NSScreen)?

    private func watchDrags() {
        let m1 = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            dragWindow = AXWindow.at(CGPoint(x: p.x, y: primaryHeight - p.y))
            dragStart = dragWindow.flatMap(AXWindow.frame)
            dragging = false
            checks = 0
        }
        let m2 = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.dragged() }
        let m3 = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.released() }
        monitors = [m1, m2, m3].compactMap { $0 }
    }

    private func dragged() {
        guard let w = dragWindow, let start = dragStart else { return }
        if !dragging {
            // 창이 실제로 움직였을 때만 창 끌기(글자 선택·크기 조절 드래그는 무시)
            // 몇 번 봐도 그대로면 이번 끌기는 창 끌기가 아니다(AX 호출을 계속하지 않는다)
            checks += 1
            if checks > 8 { dragWindow = nil; return }
            guard let now = AXWindow.frame(w), now.size == start.size,
                  abs(now.minX - start.minX) + abs(now.minY - start.minY) >= 4 else { return }
            dragging = true
        }
        let p = NSEvent.mouseLocation
        guard let scr = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
              let a = SnapMath.edge(p, screen: scr.frame),
              let r = SnapMath.rect(a, area: scr.visibleFrame, current: .zero) else { pending = nil; hidePreview(); return }
        pending = (a, scr)
        showPreview(r)
    }

    private func released() {
        defer { dragWindow = nil; dragStart = nil; dragging = false; pending = nil; hidePreview() }
        guard dragging, let w = dragWindow, let (a, scr) = pending, let start = dragStart else { return }
        // 끌기 전 자리를 원래 자리로 기억
        let key = CFHash(w)
        if saved[key].map({ !SnapMath.near($0.last, start) }) ?? true { saved[key] = (start, start) }
        guard let r = SnapMath.rect(a, area: scr.visibleFrame, current: .zero) else { return }
        let t = SnapMath.flip(r, primaryHeight: primaryHeight)
        AXWindow.set(w, t)
        saved[key]?.last = AXWindow.frame(w) ?? t
    }

    private func showPreview(_ r: CGRect) {
        if preview == nil {
            let p = FloatingPanel(size: r.size)
            p.ignoresMouseEvents = true
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
            v.layer?.borderWidth = 2
            v.layer?.cornerRadius = 10
            p.contentView = v
            preview = p
        }
        guard let p = preview else { return }
        let f = r.insetBy(dx: 4, dy: 4)
        if p.frame != f { p.setFrame(f, display: true) }
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func hidePreview() { preview?.orderOut(nil) }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
