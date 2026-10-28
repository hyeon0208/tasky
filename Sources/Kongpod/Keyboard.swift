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
    /// 이벤트에서 보이는 키 코드. Caps Lock은 F18(79)로 바꿔 둔 뒤 읽는다.
    var keyCode: Int64 {
        switch self {
        case .capsLock: 79
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

enum SwitchAction { case toggleInput, toggleCapsLock }

/// 전환 키를 혼자 눌렀다 뗐는지, Caps Lock을 얼마나 눌렀는지 판단한다(순수).
struct SwitchJudge {
    let key: SwitchKey
    static let longPress: TimeInterval = 0.5
    /// 오른쪽 ⌘·⌥를 이보다 오래 누르고 있다 떼면 전환하지 않는다
    static let holdLimit: TimeInterval = 1
    private var pressedAt: Date?
    /// 누르는 동안 다른 키가 끼지 않았는지
    private var alone = false
    private var longFired = false

    init(key: SwitchKey) { self.key = key }

    /// Caps Lock을 누르고 있는 동안 0.5초가 지나면 바로 대문자 고정(떼기 전, 한 번만)
    mutating func tick(at t: Date) -> SwitchAction? {
        guard key == .capsLock, let p = pressedAt, !longFired, t.timeIntervalSince(p) >= Self.longPress else { return nil }
        longFired = true
        return .toggleCapsLock
    }

    mutating func feed(_ e: KeyEvent, at t: Date) -> SwitchAction? {
        switch (key, e) {
        case (.capsLock, .down(let code, let isRepeat)) where code == key.keyCode:
            // 새로 누름은 늘 처음부터(떼기를 놓쳤어도 다음 누름이 꼬이지 않게)
            if !isRepeat {
                pressedAt = t; alone = true; longFired = false
                return nil
            }
            return tick(at: t)
        case (.capsLock, .up(let code)) where code == key.keyCode:
            guard let p = pressedAt else { return nil }
            defer { pressedAt = nil }
            if longFired { return nil }
            if t.timeIntervalSince(p) >= Self.longPress { return .toggleCapsLock }
            return alone ? .toggleInput : nil
        case (.capsLock, _):
            if pressedAt != nil { alone = false }
            return nil
        case (_, .flags(let code, let flags)) where code == key.keyCode:
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

/// Caps Lock → F18 바꿈. hidutil 사용자 키 매핑에서 우리 항목만 더하고 뺀다.
enum KeyMapping {
    typealias Entry = [String: UInt64]
    static let caps: UInt64 = 0x7_0000_0039
    static let f18: UInt64 = 0x7_0000_006D
    static let ours: Entry = ["HIDKeyboardModifierMappingSrc": caps, "HIDKeyboardModifierMappingDst": f18]

    static func adding(_ m: [Entry]) -> [Entry] { removing(m) + [ours] }
    static func removing(_ m: [Entry]) -> [Entry] { m.filter { $0 != ours } }

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

    static var current: [Entry]? { parse(hidutil(["property", "--get", "UserKeyMapping"])) }

    /// 우리가 더한 때만 기록해, 사용자가 직접 만든 같은 매핑은 지우지 않는다
    private static var mappedByUs: Bool {
        get { UserDefaults.standard.bool(forKey: "kbMappedByUs") }
        set { UserDefaults.standard.set(newValue, forKey: "kbMappedByUs") }
    }

    static func set(_ on: Bool) {
        if !on && !mappedByUs { return }
        guard let now = current else { return }
        if on && now.contains(ours) { return }   // 이미 있음(사용자가 만든 것일 수 있음)
        let next = on ? adding(now) : removing(now)
        mappedByUs = on
        let json = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": next])
        _ = hidutil(["property", "--set", String(data: json ?? Data(), encoding: .utf8) ?? "{}"])
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

    /// 지금이 한국어면 영문으로, 아니면 한국어로
    static func toggle() {
        let sources = enabled
        guard let p = pair(sources.map(info)),
              let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let toKo = nextIsKorean(reportedKorean: info(cur).languages.first == "ko", last: last, now: Date())
        let target = toKo ? p.ko : p.en
        if let s = sources.first(where: { info($0).id == target }) {
            TISSelectInputSource(s)
            last = (toKo, Date())
        }
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
    private var judge = SwitchJudge(key: .capsLock)

    /// 설정에 맞춰 켜고 끈다. `ask`면 권한이 없을 때 시스템 권한 창을 띄운다(켤 때만).
    func apply(ask: Bool = false) {
        stop()
        guard Self.enabled else { return }
        guard hasPermission else {
            if ask { CGRequestListenEventAccess() }
            return
        }
        guard InputSources.available else { return }   // 바꿀 소스가 없으면 Caps Lock도 건드리지 않는다
        judge = SwitchJudge(key: Self.key)
        // 마우스 누름도 '다른 키'로 본다(⌘-클릭으로 전환되지 않게)
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            if let refcon { Unmanaged<KeySwitcher>.fromOpaque(refcon).takeUnretainedValue().handle(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        if Self.key == .capsLock { KeyMapping.set(true) }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
    }

    /// 감지를 멈추고 Caps Lock을 원래대로(비정상 종료 뒤 남은 바꿈도 여기서 지운다)
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        running = false
        KeyMapping.set(false)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let e: KeyEvent = switch type {
        case .keyDown: .down(code: code, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: .up(code: code)
        case .flagsChanged: .flags(code: code, flags: event.flags.rawValue)
        default: .down(code: -1, isRepeat: false)   // 마우스
        }
        act(judge.feed(e, at: Date()))
        // 반복 눌림이 늦게 와도 0.5초에 대문자 고정이 되도록
        if case .down(let c, false) = e, c == judge.key.keyCode, judge.key == .capsLock {
            DispatchQueue.main.asyncAfter(deadline: .now() + SwitchJudge.longPress) { [weak self] in
                guard let self, self.running else { return }
                self.act(self.judge.tick(at: Date()))
            }
        }
    }

    private func act(_ a: SwitchAction?) {
        switch a {
        case .toggleInput: InputSources.toggle()
        case .toggleCapsLock: Self.toggleCapsLock()
        case nil: break
        }
    }

    private static var signalSources: [DispatchSourceSignal] = []

    /// 터미널의 Ctrl-C·kill로 끝나도 Caps Lock을 되돌린다(비정상 종료는 다음 실행 때 되돌림)
    static func cleanUpOnSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { shared.stop(); exit(0) }
            s.resume()
            signalSources.append(s)
        }
    }

    private static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !on)
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
