import AppKit
import Carbon
import IOKit.hidsystem

// F12 키보드 편의. 근거: intent/F12-키보드-편의/{intent,spec,plan}.md
// 키 입력은 사용자가 켰을 때만, 듣기 전용으로 읽고 전환 키 판단에만 쓴다(저장·전송하지 않음).

enum SwitchKey: String, CaseIterable {
    case capsLock, rightCommand, rightOption

    var title: String {
        switch self {
        case .capsLock: "Caps Lock"
        case .rightCommand: "오른쪽 ⌘"
        case .rightOption: "오른쪽 ⌥"
        }
    }
    /// 이벤트에서 보이는 키 코드. Caps Lock은 내부 키(기본 F18, F31)로 바꿔 둔 뒤 읽는다.
    var keyCode: Int64 {
        switch self {
        case .capsLock: InternalKey.current.keyCode
        case .rightCommand: 54
        case .rightOption: 61
        }
    }
    /// 함께 눌려 있으면 안 되는 수정키: ⌘·⌥·⌃·⇧와 같은 키의 왼쪽(NX_DEVICELCMDKEYMASK 0x8·NX_DEVICELALTKEYMASK 0x20)
    var otherModifiers: UInt64 {
        let cmd: UInt64 = 0x100000, opt: UInt64 = 0x80000, ctrl: UInt64 = 0x40000, shift: UInt64 = 0x20000
        switch self {
        case .capsLock: return 0
        case .rightCommand: return opt | ctrl | shift | 0x8
        case .rightOption: return cmd | ctrl | shift | 0x20
        }
    }
    /// 오른쪽 수정키를 왼쪽과 구분하는 장치 비트(NX_DEVICERCMDKEYMASK·NX_DEVICERALTKEYMASK)
    var deviceMask: UInt64 {
        switch self {
        case .capsLock: 0
        case .rightCommand: 0x10
        case .rightOption: 0x40
        }
    }
}

enum KeyEvent {
    case down(code: Int64, isRepeat: Bool)
    case up(code: Int64)
    case flags(code: Int64, flags: UInt64)
}

/// `capsInstead`: 누를 때 바꾼 입력을 되돌리고 대문자 고정을 켜거나 끈다(Caps를 꾹 눌렀을 때)
enum SwitchAction { case toggleInput, toggleCapsLock, capsInstead }

/// 전환 키를 혼자 눌렀다 뗐는지, Caps Lock을 얼마나 눌렀는지 판단한다(순수).
struct SwitchJudge {
    let key: SwitchKey
    /// 이 판정이 보는 키 코드(Caps면 내부 키)
    let code: Int64
    /// F31 ①: 끄면 길게 눌러도 대문자 고정을 하지 않는다
    let longPressOn: Bool
    static let longPress: TimeInterval = 0.5
    /// 오른쪽 ⌘·⌥를 이보다 오래 누르고 있다 떼면 전환하지 않는다
    static let holdLimit: TimeInterval = 1
    private var pressedAt: Date?
    /// 누르는 동안 다른 키가 끼지 않았는지
    private var alone = false
    private var longFired = false

    init(key: SwitchKey, code: Int64? = nil, longPressOn: Bool = true) {
        self.key = key; self.code = code ?? key.keyCode; self.longPressOn = longPressOn
    }

    /// Caps Lock을 누르고 있는 동안 0.5초가 지나면 바로 대문자 고정(떼기 전, 한 번만)
    mutating func tick(at t: Date) -> SwitchAction? {
        guard key == .capsLock, longPressOn, let p = pressedAt, !longFired, t.timeIntervalSince(p) >= Self.longPress else { return nil }
        longFired = true
        return .capsInstead
    }

    mutating func feed(_ e: KeyEvent, at t: Date) -> SwitchAction? {
        switch (key, e) {
        case (.capsLock, .down(let c, let isRepeat)) where c == code:
            // F28: 누르는 순간 바로 전환(gksdud 방식). 빠르게 치면 Caps를 떼기 전에 다음 글자를 누르게 되는데,
            // 떼기 기준이면 그 겹침 때문에 전환이 씹혔다. 꾹 누르면(0.5초) 전환을 되돌리고 대문자 고정
            if !isRepeat {
                pressedAt = t; longFired = false
                return .toggleInput
            }
            return tick(at: t)
        case (.capsLock, .up(let c)) where c == code:
            guard let p = pressedAt else { return nil }
            defer { pressedAt = nil }
            if longFired || !longPressOn { return nil }
            return t.timeIntervalSince(p) >= Self.longPress ? .capsInstead : nil
        case (.capsLock, _):
            return nil   // 다른 키가 겹쳐도 이미 전환했다
        case (_, .flags(let c, let flags)) where c == code:
            if flags & key.deviceMask != 0 {
                // 다른 수정키(왼쪽 같은 키 포함)를 이미 누르고 있으면 전환하지 않는다
                pressedAt = t
                alone = flags & key.otherModifiers == 0
                return nil
            }
            defer { pressedAt = nil }
            guard let p = pressedAt, alone, t.timeIntervalSince(p) < Self.holdLimit else { return nil }
            return .toggleInput
        default:
            if pressedAt != nil { alone = false }
            return nil
        }
    }
}

/// Caps Lock → 내부 키(기본 F18) 바꿈. hidutil 사용자 키 매핑에서 우리 항목만 더하고 뺀다.
enum KeyMapping {
    typealias Entry = [String: UInt64]
    static let caps: UInt64 = 0x7_0000_0039
    static func entry(_ k: InternalKey) -> Entry { ["HIDKeyboardModifierMappingSrc": caps, "HIDKeyboardModifierMappingDst": k.hid] }
    static var ours: Entry { entry(InternalKey.current) }
    /// 내부 키를 바꿔도 예전 항목을 지우도록 Caps → F13–F20은 모두 우리 것으로 본다
    static func isOurs(_ e: Entry) -> Bool { InternalKey.allCases.contains { entry($0) == e } }

    static func adding(_ m: [Entry]) -> [Entry] { removing(m) + [ours] }
    static func removing(_ m: [Entry]) -> [Entry] { m.filter { !isOurs($0) } }

    /// `hidutil property --get UserKeyMapping` 출력(`(null)` 또는 `( { Dst = n; Src = n; } )`)을 읽는다.
    /// 다 읽지 못하면 nil(그때는 아무것도 바꾸지 않아 사용자의 다른 매핑을 지키지 않는다).
    static func parse(_ text: String) -> [Entry]? {
        let entries: [Entry] = text.components(separatedBy: "}").compactMap { block in
            var e: Entry = [:]
            for key in ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"] {
                guard let r = block.range(of: key + #"\s*=\s*(\d+)"#, options: .regularExpression),
                      let n = UInt64(block[r].split(separator: "=").last!.trimmingCharacters(in: .whitespaces)) else { return nil }
                e[key] = n
            }
            return e
        }
        let blocks = text.filter { $0 == "{" }.count
        if blocks == 0 { return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("(") ? [] : nil }
        return entries.count == blocks ? entries : nil
    }

    static func hidutil(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// F28: 키보드 장치에만(전체에 걸면 키보드를 다시 연결·깨울 때 새 장치에 빠지고, 수백 개 장치에 중복이 쌓였다)
    static let keyboards = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#

    /// 키보드 장치별 출력에서 첫 장치의 목록만(장치마다 같은 값을 쓴다)
    static func firstBlock(_ text: String) -> String {
        guard let open = text.range(of: "(") else { return text }
        guard let close = text.range(of: "\n)", range: open.upperBound..<text.endIndex) ?? text.range(of: ")", range: open.upperBound..<text.endIndex) else { return text }
        return String(text[open.lowerBound..<close.upperBound])
    }

    /// 출력의 장치별 목록들(같은 조건에 걸린 장치가 여럿일 수 있다). 하나라도 못 읽으면 nil
    static func blocks(_ text: String) -> [[Entry]]? {
        let parts = text.components(separatedBy: "UserKeyMapping").dropFirst()
        if parts.isEmpty { return parse(text).map { [$0] } }
        var out: [[Entry]] = []
        for part in parts {
            guard let e = parse(firstBlock(part)) else { return nil }
            out.append(e)
        }
        return out
    }

    /// 우리가 더한 때만 기록해, 사용자가 직접 만든 같은 매핑은 지우지 않는다
    private static var mappedByUs: Bool {
        get { UserDefaults.standard.bool(forKey: "kbMappedByUs") }
        set { UserDefaults.standard.set(newValue, forKey: "kbMappedByUs") }
    }

    /// 한 조건(키보드 하나 또는 전체 키보드)에 우리 항목을 넣거나 뺀다. 이미 그 상태면 건드리지 않는다
    private static func apply(_ want: Bool, matching: String) {
        guard let now = blocks(hidutil(["property", "--matching", matching, "--get", "UserKeyMapping"])), let first = now.first else { return }
        var next = want ? adding(first) : removing(first)
        next = next.reduce(into: [Entry]()) { if !$0.contains($1) { $0.append($1) } }   // 중복 정리
        if now.allSatisfy({ $0 == next }) { return }
        let json = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": next])
        _ = hidutil(["property", "--matching", matching, "--set", String(data: json ?? Data(), encoding: .utf8) ?? "{}"])
    }

    /// F31: 키보드마다 Caps를 쓰는 곳에만 매핑을 건다(`capsOn`: 그 키보드가 Caps로 전환하는지). `on == false`면 모두 뺀다
    static func sync(_ on: Bool, devices: [KeyboardDevice], capsOn: (KeyboardDevice) -> Bool, fallback: Bool) {
        let wasOurs = mappedByUs
        if !on {
            // 끌 때는 모든 키보드에서 뺀다(vid·pid가 없어 목록에 없는 키보드에 남지 않게)
            if wasOurs { apply(false, matching: keyboards); mappedByUs = false }
            return
        }
        if devices.isEmpty {
            if fallback { apply(true, matching: keyboards) } else if wasOurs { apply(false, matching: keyboards) }
            mappedByUs = fallback
            return
        }
        var any = false
        for d in devices {
            // 우리가 건 적이 없으면 빼지 않는다(사용자가 직접 만든 Caps → F13–F20 매핑을 지키려고)
            if capsOn(d) { apply(true, matching: d.matching); any = true } else if wasOurs { apply(false, matching: d.matching) }
        }
        mappedByUs = any
    }

    /// 키보드가 새로 붙거나(블루투스 재연결) Mac이 깨어나면 다시 건다
    private static var notifyPort: IONotificationPortRef?
    private static var iterator: io_iterator_t = 0
    private static var goneIterator: io_iterator_t = 0
    private static var wakeObserver: Any?
    static func watchKeyboards(_ on: Bool) {
        if !on {
            if iterator != 0 { IOObjectRelease(iterator); iterator = 0 }
            if goneIterator != 0 { IOObjectRelease(goneIterator); goneIterator = 0 }
            if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
            if let w = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(w); wakeObserver = nil }
            return
        }
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let match = IOServiceMatching("IOHIDEventService")
        let cb: IOServiceMatchingCallback = { _, it in
            while case let s = IOIteratorNext(it), s != 0 { IOObjectRelease(s) }   // 비워야 다음 알림이 온다
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { KeySwitcher.shared.devicesChanged() }
        }
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, match, cb, nil, &iterator)
        while case let s = IOIteratorNext(iterator), s != 0 { IOObjectRelease(s) }
        // 떨어진 키보드도(그 키보드만 쓰던 키를 더 감지하지 않게)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOHIDEventService"), cb, nil, &goneIterator)
        while case let s = IOIteratorNext(goneIterator), s != 0 { IOObjectRelease(s) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { KeySwitcher.shared.devicesChanged() }
        }
    }
}

/// 입력 소스: 켜진 것 중 한국어 하나와 영문 하나
struct InputSourceInfo {
    let id: String
    let languages: [String]
    let asciiCapable: Bool
}

enum InputSources {
    /// (한국어, 영문). 하나라도 없으면 nil.
    static func pair(_ list: [InputSourceInfo]) -> (ko: String, en: String)? {
        guard let ko = list.first(where: { $0.languages.first == "ko" }),
              let en = list.first(where: { $0.asciiCapable && $0.languages.first != "ko" }) else { return nil }
        return (ko.id, en.id)
    }

    private static func prop<T>(_ s: TISInputSource, _ key: CFString) -> T? {
        guard let p = TISGetInputSourceProperty(s, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
    }

    private static var enabled: [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsSelectCapable: true,
                      kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static var currentIsKorean: Bool {
        TISCopyCurrentKeyboardInputSource().map { info($0.takeRetainedValue()).languages.first == "ko" } ?? false
    }

    private static func info(_ s: TISInputSource) -> InputSourceInfo {
        InputSourceInfo(id: prop(s, kTISPropertyInputSourceID) ?? "",
                        languages: prop(s, kTISPropertyInputSourceLanguages) ?? [],
                        asciiCapable: (prop(s, kTISPropertyInputSourceIsASCIICapable) as NSNumber?)?.boolValue ?? false)
    }

    static var available: Bool { pair(enabled.map(info)) != nil }

    /// 한국어·영문 소스(전환 때마다 목록을 다시 읽지 않게 기억, 설정을 다시 적용하면 비움)
    private static var cached: (ko: TISInputSource, en: TISInputSource)?
    static func resetCache() { cached = nil }

    /// 지금이 한국어면 영문으로, 아니면 한국어로
    static func toggle() {
        if cached == nil {
            let sources = enabled
            if let p = pair(sources.map(info)),
               let ko = sources.first(where: { info($0).id == p.ko }), let en = sources.first(where: { info($0).id == p.en }) { cached = (ko, en) }
        }
        guard let c = cached, let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let toKo = nextIsKorean(reportedKorean: info(cur).languages.first == "ko", last: last, now: Date())
        let t0 = Date()
        let err = TISSelectInputSource(toKo ? c.ko : c.en)
        if Debug.isOn { diag("%@로 전환 %.1fms, 결과 %d", toKo ? "한글" : "영문", Date().timeIntervalSince(t0) * 1000, err) }
        if err == noErr { last = (toKo, Date()) } else { cached = nil }
    }

    /// 마지막으로 우리가 고른 소스와 시각
    private static var last: (korean: Bool, at: Date)?

    /// 바꾼 직후에는 시스템이 알려 주는 현재 소스가 아직 이전 값일 수 있어(연타 때 같은 쪽으로만 바뀜),
    /// 1초 안이면 우리가 마지막으로 고른 쪽을 기준으로 뒤집는다.
    static func nextIsKorean(reportedKorean: Bool, last: (korean: Bool, at: Date)?, now: Date) -> Bool {
        if let last, now.timeIntervalSince(last.at) < 1 { return !last.korean }
        return !reportedKorean
    }
}

/// 전역 키 감지(듣기 전용)와 실행. 켜져 있고 입력 모니터링 권한이 있을 때만 돈다.
final class KeySwitcher {
    static let shared = KeySwitcher()

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "kbSwitch") }
        set { UserDefaults.standard.set(newValue, forKey: "kbSwitch") }
    }
    static var key: SwitchKey {
        get { UserDefaults.standard.string(forKey: "kbSwitchKey").flatMap(SwitchKey.init) ?? .capsLock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "kbSwitchKey") }
    }

    var hasPermission: Bool { CGPreflightListenEventAccess() }
    private(set) var running = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// 감지할 키마다 판정 하나(F31: 키보드별로 쓸 키가 다를 수 있다)
    private var judges: [SwitchJudge] = []
    private var devices: [KeyboardDevice] = []
    /// 감지할 키들(키보드별 설정 반영)
    var activeKeys: [SwitchKey] { Keyboards.activeKeys(devices, globalOn: Self.enabled, globalKey: Self.key) }
    /// 켜진 키보드가 하나라도 있는지(전체 끔이어도 '켬' 키보드가 있으면 켜짐)
    var anyActive: Bool { refreshDevices(); return !activeKeys.isEmpty }

    @discardableResult
    private func refreshDevices() -> [KeyboardDevice] {
        devices = Keyboards.connected()
        Keyboards.remember(devices)
        return devices
    }
    private func capsOn(_ d: KeyboardDevice) -> Bool { Keyboards.effectiveKey(d.id, globalOn: Self.enabled, globalKey: Self.key) == .capsLock }
    private var capsCode: Int64 { InternalKey.current.keyCode }
    private var watchesCaps: Bool { judges.contains { $0.key == .capsLock } }

    /// 키보드가 붙거나 깨어났을 때: 새 키보드를 기억하고 매핑을 다시 건다(쓸 키 구성이 바뀌면 다시 시작)
    func devicesChanged() {
        let before = activeKeys
        refreshDevices()
        if activeKeys != before || !running { apply(); return }   // '켬' 키보드가 나중에 붙거나, 쓸 키 구성이 바뀜
        KeyMapping.sync(true, devices: devices, capsOn: capsOn, fallback: Self.key == .capsLock)
    }

    /// 앱을 끝낼 때: 감지를 멈추고 시스템 단축키도 원래대로(⌃Space 등이 계속 되게)
    func shutdown() {
        stop()
        SystemShortcut.restore()
    }

    /// 설정에 맞춰 켜고 끈다. `ask`면 권한이 없을 때 시스템 권한 창을 띄운다(켤 때만).
    func apply(ask: Bool = false) {
        stop()
        refreshDevices()
        let keys = activeKeys
        // F31 ③: 사용자가 내부 키를 고른 뒤로는 켜져 있고 Caps를 쓸 때 시스템 단축키를 맞추고, 아니면 되돌린다
        // 키보드가 붙고 떨어지는 것은 꺼져 있어도 본다('켬' 키보드가 나중에 붙을 수 있다)
        if hasPermission { KeyMapping.watchKeyboards(true) }
        guard !keys.isEmpty else { SystemShortcut.restore(); return }
        if Debug.isOn { diag("시작 — 입력 모니터링 %@, 소스 %@, 손쉬운 사용 %@", hasPermission ? "있음" : "없음", InputSources.available ? "있음" : "없음", AXIsProcessTrusted() ? "있음" : "없음") }
        guard hasPermission else {
            SystemShortcut.restore()
            if ask { CGRequestListenEventAccess() }
            return
        }
        guard InputSources.available else { SystemShortcut.restore(); return }   // 바꿀 소스가 없으면 Caps Lock도 건드리지 않는다
        // F31 ③: 사용자가 내부 키를 고른 뒤로는 실제로 감지할 때만 시스템 단축키를 맞추고, 아니면 되돌린다
        if keys.contains(.capsLock), InternalKey.chosen { SystemShortcut.ensure(InternalKey.current) } else { SystemShortcut.restore() }
        judges = keys.map { SwitchJudge(key: $0, code: $0 == .capsLock ? capsCode : nil, longPressOn: SwitchOptions.longPressCaps) }
        InputSources.resetCache()
        // 마우스 누름도 '다른 키'로 본다(⌘-클릭으로 전환되지 않게)
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        // F28: 손쉬운 사용 권한이 있으면 '거르는' 감지(사용자 결정 2026-11-06). 전환을 마친 뒤에 다음 글자가 앱에 가므로
        // 빠르게 칠 때 첫 글자가 이전 언어로 들어가는 일(씹힘)이 없다. 권한이 없으면 예전처럼 듣기만.
        filtering = AXIsProcessTrusted()
        nativeSwitch = keys.contains(.capsLock) && SystemShortcut.matches(capsCode, in: SystemShortcut.all())
        if Debug.isOn {
            diag("감지할 키 %@, 키보드 %@", keys.map(\.rawValue).joined(separator: ","), devices.map { "\($0.name)(\($0.id))=\(Keyboards.effectiveKey($0.id, globalOn: Self.enabled, globalKey: Self.key)?.rawValue ?? "끔")" }.joined(separator: ", "))
            diag("시스템 단축키가 %@: %@", InternalKey.current.title, nativeSwitch ? "예(시스템에 맡김)" : "아니오")
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: filtering ? .defaultTap : .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeySwitcher>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = me.handle(type, event)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        KeyMapping.sync(true, devices: devices, capsOn: capsOn, fallback: keys.contains(.capsLock))
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
        if srcObserver == nil {   // 실제 입력 소스가 바뀌면 붙잡은 키를 보낸다
            srcObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
                self?.sourceChanged()
            }
        }
    }

    /// 감지를 멈추고 Caps Lock을 원래대로(비정상 종료 뒤 남은 바꿈도 여기서 지운다)
    func stop() {
        flushQueue()   // 줄에 남은 키를 잃지 않게
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        running = false
        KeyMapping.watchKeyboards(false)
        KeyMapping.sync(false, devices: [], capsOn: { _ in false }, fallback: false)
    }

    /// 거르는 감지인지(손쉬운 사용 권한이 있을 때)
    private var filtering = false
    /// F28: 시스템 '이전/다음 입력 소스' 단축키가 F18이면 F18을 그대로 보내 macOS가 바꾸게 한다.
    /// 우리가 TISSelectInputSource로 바꾸면 메뉴 막대는 '한'인데 앞 앱(터미널·브라우저)은 영문으로 남는 일이 있었다.
    private var nativeSwitch = false

    /// 처리하고, 앱에 보내지 않을 이벤트면 true(거르는 감지에서 Caps→F18 키만 삼킨다. 다른 키는 그대로 보낸다)
    @discardableResult
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if Debug.isOn { diag("감지가 꺼졌다 다시 켬(\(type == .tapDisabledByTimeout ? "시간 초과" : "사용자 입력"))") }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.repostMark {   // 우리가 다시 보낸 키
            inFlight = max(0, inFlight - 1)
            if inFlight == 0 { afterPosted() }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if Debug.isOn, type == .keyDown, judges.contains(where: { $0.code == code }), event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let lateMs = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- event.timestamp) / 1_000_000
            diag("전환 키 도착 지연 %.1fms, 거르는 감지 %@", lateMs, filtering ? "켬" : "끔")
        }
        let e: KeyEvent = switch type {
        case .keyDown: .down(code: code, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: .up(code: code)
        case .flagsChanged: .flags(code: code, flags: event.flags.rawValue)
        default: .down(code: -1, isRepeat: false)   // 마우스
        }
        let now = Date()
        for i in judges.indices { act(judges[i].feed(e, at: now), native: judges[i].key == .capsLock && nativeSwitch) }
        // 반복 눌림이 늦게 와도 0.5초에 대문자 고정이 되도록
        if case .down(let c, false) = e, c == capsCode, let i = judges.firstIndex(where: { $0.key == .capsLock }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + SwitchJudge.longPress) { [weak self] in
                guard let self, self.running, i < self.judges.count else { return }
                self.act(self.judges[i].tick(at: Date()), native: self.nativeSwitch)
            }
        }
        // 내부 키(Caps)는 앱에 보내지 않는다(다른 앱이 F18을 받아 엉뚱한 동작을 하지 않게)
        if filtering && !nativeSwitch && watchesCaps && (type == .keyDown || type == .keyUp) && code == capsCode { return true }
        // 전환 대기 중에 친 키는 줄에 세웠다가 순서대로 다시 보낸다.
        // 시스템에 맡길 때(nativeSwitch) F18은 누르기·떼기 모두 바로 보낸다. macOS는 F18을 뗀 뒤에야 바꾸므로
        // 떼기를 붙잡으면 전환이 아예 일어나지 않았다(진단: 바뀜 알림 없이 시간 초과 38번)
        let nativeKey = nativeSwitch && code == capsCode
        if busy, !nativeKey, type == .keyDown || type == .keyUp || type == .flagsChanged, let copy = event.copy() {
            queue.append(.key(copy))
            return true
        }
        return false
    }

    // F28: 다른 앱(터미널·브라우저)은 입력 소스 바뀜을 몇십 ms 늦게 받아, Caps 직후 친 글자가 이전 언어로 들어갔다
    // (진단: 키 도착 지연 최대 5ms, 전환 호출 오류 0). 시스템 단축키가 F18이어도 macOS가 늦게 바꿔 같은 일이 났다(타이ㅍld).
    // 거르는 감지일 때 키와 전환을 한 줄에 세워
    // [Caps 앞 키 보냄 → 잠깐 → 전환 → 잠깐 → Caps 뒤 키 보냄] 순서를 지킨다. 다시 보낸 키가 감지를 다시 지나기 전엔
    // 새 키도 줄에 세운다(앞질러 '떼기'가 '누르기'보다 먼저 가면 앱이 꾹 누른 걸로 보고 특수 문자 창을 띄웠다).
    // 진단: macOS는 F18 뒤 85~160ms에야 입력 소스를 바꿨다(터미널). 고정 60ms로는 모자라 바뀜 알림을 기다린다.
    static let settleTime: TimeInterval = 0.03
    /// 바뀜 알림이 안 와도 키보드가 막히지 않게
    static let switchTimeout: TimeInterval = 0.5
    private static let repostMark: Int64 = 0x54_41_53_4B   // "TASK": 다시 보낸 이벤트 표시
    private enum Queued { case key(CGEvent), toggle(native: Bool) }
    private var queue: [Queued] = []
    /// 줄을 처리하는 중(전환 대기·다시 보낸 키 기다림)
    private var busy = false
    private var inFlight = 0
    private var postRound = 0

    private var srcObserver: NSObjectProtocol?
    private var toggledAt: Date?
    /// 전환했고 실제 입력 소스가 바뀌기를 기다리는 중
    private var waitingSource = false

    /// `native`: 시스템 단축키로 macOS가 바꾸는 중(우리는 바꾸지 않고 기다리기만)
    private func requestToggle(native: Bool) {
        guard filtering else { toggleInput(native: native); return }
        if busy { queue.append(.toggle(native: native)); return }
        busy = true
        switchThenPump(native: native)
    }

    /// 전환하고, 입력 소스가 실제로 바뀐 뒤(알림 + 잠깐) 붙잡은 키를 보낸다
    private func switchThenPump(native: Bool) {
        toggledAt = Date()
        waitingSource = true
        toggleInput(native: native)
        let at = toggledAt
        Ticker.once("한영 전환 대기", Self.switchTimeout) { [weak self] _ in
            guard let self, self.waitingSource, self.toggledAt == at else { return }
            if Debug.isOn { diag("입력 소스 바뀜 알림 없음 — 시간 초과로 보냄") }
            self.waitingSource = false
            self.pump()
        }
    }

    private func sourceChanged() {
        if Debug.isOn, let t = toggledAt { diag("입력 소스 바뀜: 전환 뒤 %.0fms", Date().timeIntervalSince(t) * 1000) }
        guard waitingSource else { return }
        waitingSource = false
        Ticker.once("한영 전환 대기", Self.settleTime) { [weak self] _ in self?.pump() }
    }

    /// 다음 전환 전까지의 키를 보낸다
    private func pump() {
        if Debug.isOn, let t = toggledAt { diag("붙잡은 키 보냄: 전환 뒤 %.0fms, %d개", Date().timeIntervalSince(t) * 1000, queue.count) }
        var n = 0
        while let first = queue.first, case .key(let e) = first {
            queue.removeFirst()
            e.setIntegerValueField(.eventSourceUserData, value: Self.repostMark)
            e.post(tap: .cgSessionEventTap)
            n += 1
        }
        guard n > 0 else { afterPosted(); return }
        inFlight += n
        postRound += 1
        let round = postRound
        // 다시 보낸 키가 돌아오지 않아도 키보드가 막히지 않게
        Ticker.once("한영 전환 대기", 0.3) { [weak self] _ in
            guard let self, self.postRound == round, self.inFlight > 0 else { return }
            self.inFlight = 0
            self.afterPosted()
        }
    }

    /// 보낸 키가 다 지나간 뒤: 줄 앞이 전환이면 잠깐 두고 전환, 비었으면 대기 끝
    private func afterPosted() {
        guard busy, inFlight == 0 else { return }
        guard let first = queue.first else { busy = false; return }
        guard case .toggle(let native) = first else { pump(); return }
        queue.removeFirst()
        Ticker.once("한영 전환 대기", Self.settleTime) { [weak self] _ in
            guard let self else { return }
            self.switchThenPump(native: native)
        }
    }

    /// 감지를 멈출 때 줄에 남은 키를 잃지 않게 보낸다(전환은 버림)
    private func flushQueue() {
        for case .key(let e) in queue { e.setIntegerValueField(.eventSourceUserData, value: Self.repostMark); e.post(tap: .cgSessionEventTap) }
        queue = []; busy = false; waitingSource = false; inFlight = 0; postRound += 1
    }

    private func act(_ a: SwitchAction?, native: Bool) {
        switch a {
        case .toggleInput:
            // ②는 누르는 순간 정한다(전환이 줄에서 기다리는 동안 길게 누르기가 와도 이번 누름 기준으로 보게)
            clearedCapsOnPress = !SwitchOptions.keepCaps && Self.setCapsLock(false)
            requestToggle(native: native)
        case .capsInstead:
            // 누를 때 바꾼 입력을 되돌리고 대문자 고정을 뒤집는다. 누를 때 ②로 대문자 고정을 껐다면 끈 채로 둔다
            // (켜진 대문자 고정을 길게 눌러 끄는 동작이 그대로 되게)
            InputSources.toggle()
            if !clearedCapsOnPress { Self.toggleCapsLock() }
            clearedCapsOnPress = false
        case .toggleCapsLock: Self.toggleCapsLock()
        case nil: break
        }
    }

    /// F31 ②: 이번 누름에서 대문자 고정을 껐는지
    private var clearedCapsOnPress = false

    private func toggleInput(native: Bool) {
        if !native { InputSources.toggle() }   // 시스템에 맡기면 내부 키를 받은 macOS가 바꾼다
    }

    private static var signalSources: [DispatchSourceSignal] = []

    /// 터미널의 Ctrl-C·kill로 끝나도 Caps Lock을 되돌린다(비정상 종료는 다음 실행 때 되돌림)
    static func cleanUpOnSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { shared.shutdown(); exit(0) }
            s.resume()
            signalSources.append(s)
        }
    }

    private static func toggleCapsLock() { _ = setCapsLock(nil) }

    /// 대문자 고정을 켜거나 끈다(nil이면 뒤집기). 상태가 바뀌었으면 true
    @discardableResult
    private static func setCapsLock(_ want: Bool?) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        let next = want ?? !on
        guard next != on else { return false }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), next)
        return true
    }
}

/// 키 반복(전역 설정, `defaults -g`와 같은 곳). 단위 15ms. 처음 바꾸기 전 값을 기억해 되돌린다.
enum KeyRepeat {
    static let initial = "InitialKeyRepeat"
    static let rate = "KeyRepeat"
    /// 고를 수 있는 범위: 반복 시작 10~120, 반복 속도 1~120
    static func range(_ key: String) -> ClosedRange<Int> { key == initial ? 10...120 : 1...120 }
    /// 값이 없을 때 시스템이 쓰는 값(추정: macOS 기본)
    static func fallback(_ key: String) -> Int { key == initial ? 25 : 6 }
    /// 단위는 1/60초(지금 HIDKeyRepeat 33333333ns = 값 2로 확인)
    static func ms(_ value: Int) -> Int { Int((Double(value) * 1000 / 60).rounded()) }
    static func nanoseconds(_ value: Int) -> Int { value * 1_000_000_000 / 60 }

    /// 기억할 원래 값: 이미 기억했으면 그대로, 아니면 지금 값(없으면 -1 = 원래 없음)
    static func original(stored: Int?, current: Int?) -> Int { stored ?? current ?? -1 }
    /// 되돌릴 값: -1이면 nil(키 삭제)
    static func restoreValue(_ original: Int) -> Int? { original < 0 ? nil : original }

    static func read(_ key: String) -> Int? {
        CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? Int
    }

    static func write(_ key: String, _ value: Int?) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFNumber }, kCFPreferencesAnyApplication)
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        // 전역 값은 로그아웃 뒤에만 읽히므로, 지금 키보드에도 바로 건다
        let hid = key == initial ? "HIDInitialKeyRepeat" : "HIDKeyRepeat"
        _ = KeyMapping.hidutil(["property", "--set", "{\"\(hid)\":\(nanoseconds(value ?? fallback(key)))}"])
    }

    private static func originalKey(_ key: String) -> String { "kbOriginal.\(key)" }

    static func set(_ key: String, _ value: Int) {
        let d = UserDefaults.standard
        d.set(original(stored: d.object(forKey: originalKey(key)) as? Int, current: read(key)), forKey: originalKey(key))
        write(key, value)
    }

    static func restore() {
        for key in [initial, rate] {
            guard let o = UserDefaults.standard.object(forKey: originalKey(key)) as? Int else { continue }
            write(key, restoreValue(o))
            UserDefaults.standard.removeObject(forKey: originalKey(key))
        }
    }
}

/// 한영 전환 진단(--debug에서만 부름). 앱으로 띄우면 NSLog가 로그에 안 남아 stderr에 쓴다(`open --stderr <파일>`로 받음)
func diag(_ format: String, _ args: CVarArg...) {
    let line = "\(Date()) 전환 진단: \(String(format: format, arguments: args))\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}
