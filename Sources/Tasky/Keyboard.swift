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

/// `capsInstead`: 누를 때 바꾼 입력을 되돌리고 대문자 고정을 켜거나 끈다(Caps를 꾹 눌렀을 때)
enum SwitchAction { case toggleInput, toggleCapsLock, capsInstead }

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
        return .capsInstead
    }

    mutating func feed(_ e: KeyEvent, at t: Date) -> SwitchAction? {
        switch (key, e) {
        case (.capsLock, .down(let code, let isRepeat)) where code == key.keyCode:
            // F28: 누르는 순간 바로 전환(gksdud 방식). 빠르게 치면 Caps를 떼기 전에 다음 글자를 누르게 되는데,
            // 떼기 기준이면 그 겹침 때문에 전환이 씹혔다. 꾹 누르면(0.5초) 전환을 되돌리고 대문자 고정
            if !isRepeat {
                pressedAt = t; longFired = false
                return .toggleInput
            }
            return tick(at: t)
        case (.capsLock, .up(let code)) where code == key.keyCode:
            guard let p = pressedAt else { return nil }
            defer { pressedAt = nil }
            if longFired { return nil }
            return t.timeIntervalSince(p) >= Self.longPress ? .capsInstead : nil
        case (.capsLock, _):
            return nil   // 다른 키가 겹쳐도 이미 전환했다
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

    /// F28: 키보드 장치에만(전체에 걸면 키보드를 다시 연결·깨울 때 새 장치에 빠지고, 수백 개 장치에 중복이 쌓였다)
    static let keyboards = #"{"PrimaryUsagePage":1,"PrimaryUsage":6}"#

    /// 키보드 장치별 출력에서 첫 장치의 목록만(장치마다 같은 값을 쓴다)
    static func firstBlock(_ text: String) -> String {
        guard let open = text.range(of: "(") else { return text }
        guard let close = text.range(of: "\n)", range: open.upperBound..<text.endIndex) ?? text.range(of: ")", range: open.upperBound..<text.endIndex) else { return text }
        return String(text[open.lowerBound..<close.upperBound])
    }

    static var current: [Entry]? { parse(firstBlock(hidutil(["property", "--matching", keyboards, "--get", "UserKeyMapping"]))) }

    /// 키보드 중 우리 매핑이 빠진 장치가 있는지(재연결·잠자기 뒤)
    static var missingOnSomeKeyboard: Bool {
        let text = hidutil(["property", "--matching", keyboards, "--get", "UserKeyMapping"])
        let blocks = text.components(separatedBy: "UserKeyMapping").dropFirst()
        return blocks.contains { !$0.contains(String(f18)) }
    }

    /// 우리가 더한 때만 기록해, 사용자가 직접 만든 같은 매핑은 지우지 않는다
    private static var mappedByUs: Bool {
        get { UserDefaults.standard.bool(forKey: "kbMappedByUs") }
        set { UserDefaults.standard.set(newValue, forKey: "kbMappedByUs") }
    }

    static func set(_ on: Bool) {
        if !on && !mappedByUs { return }
        guard let now = current else { return }
        if on && now.contains(ours) && !missingOnSomeKeyboard { return }   // 모든 키보드에 이미 있음
        var next = on ? adding(now) : removing(now)
        next = next.reduce(into: [Entry]()) { if !$0.contains($1) { $0.append($1) } }   // 중복 정리
        if on { mappedByUs = true } else { mappedByUs = false }
        let json = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": next])
        _ = hidutil(["property", "--matching", keyboards, "--set", String(data: json ?? Data(), encoding: .utf8) ?? "{}"])
    }

    /// 키보드가 새로 붙거나(블루투스 재연결) Mac이 깨어나면 다시 건다
    private static var notifyPort: IONotificationPortRef?
    private static var iterator: io_iterator_t = 0
    private static var wakeObserver: Any?
    static func watchKeyboards(_ on: Bool) {
        if !on {
            if iterator != 0 { IOObjectRelease(iterator); iterator = 0 }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if KeySwitcher.shared.running { KeyMapping.set(true) } }
        }
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, match, cb, nil, &iterator)
        while case let s = IOIteratorNext(iterator), s != 0 { IOObjectRelease(s) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if KeySwitcher.shared.running { KeyMapping.set(true) } }
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
    private var judge = SwitchJudge(key: .capsLock)

    /// 설정에 맞춰 켜고 끈다. `ask`면 권한이 없을 때 시스템 권한 창을 띄운다(켤 때만).
    func apply(ask: Bool = false) {
        stop()
        guard Self.enabled else { return }
        if Debug.isOn { diag("시작 — 입력 모니터링 %@, 소스 %@, 손쉬운 사용 %@", hasPermission ? "있음" : "없음", InputSources.available ? "있음" : "없음", AXIsProcessTrusted() ? "있음" : "없음") }
        guard hasPermission else {
            if ask { CGRequestListenEventAccess() }
            return
        }
        guard InputSources.available else { return }   // 바꿀 소스가 없으면 Caps Lock도 건드리지 않는다
        judge = SwitchJudge(key: Self.key)
        InputSources.resetCache()
        // 마우스 누름도 '다른 키'로 본다(⌘-클릭으로 전환되지 않게)
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        // F28: 손쉬운 사용 권한이 있으면 '거르는' 감지(사용자 결정 2026-11-06). 전환을 마친 뒤에 다음 글자가 앱에 가므로
        // 빠르게 칠 때 첫 글자가 이전 언어로 들어가는 일(씹힘)이 없다. 권한이 없으면 예전처럼 듣기만.
        filtering = AXIsProcessTrusted()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: filtering ? .defaultTap : .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeySwitcher>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = me.handle(type, event)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        if Self.key == .capsLock { KeyMapping.set(true); KeyMapping.watchKeyboards(true) }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
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
        KeyMapping.set(false)
    }

    /// 거르는 감지인지(손쉬운 사용 권한이 있을 때)
    private var filtering = false

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
        if Debug.isOn, type == .keyDown, code == judge.key.keyCode, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let lateMs = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- event.timestamp) / 1_000_000
            diag("전환 키 도착 지연 %.1fms, 거르는 감지 %@", lateMs, filtering ? "켬" : "끔")
        }
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
        // F18(Caps)은 앱에 보내지 않는다(다른 앱이 F18을 받아 엉뚱한 동작을 하지 않게)
        if filtering && judge.key == .capsLock && (type == .keyDown || type == .keyUp) && code == judge.key.keyCode { return true }
        // 전환 대기 중에 친 키는 줄에 세웠다가 순서대로 다시 보낸다
        if busy, type == .keyDown || type == .keyUp || type == .flagsChanged, let copy = event.copy() {
            queue.append(.key(copy))
            return true
        }
        return false
    }

    // F28: 다른 앱(터미널·브라우저)은 입력 소스 바뀜을 몇십 ms 늦게 받아, Caps 직후 친 글자가 이전 언어로 들어갔다
    // (진단: 키 도착 지연 최대 5ms, 전환 호출 오류 0). 거르는 감지일 때 키와 전환을 한 줄에 세워
    // [Caps 앞 키 보냄 → 잠깐 → 전환 → 잠깐 → Caps 뒤 키 보냄] 순서를 지킨다. 다시 보낸 키가 감지를 다시 지나기 전엔
    // 새 키도 줄에 세운다(앞질러 '떼기'가 '누르기'보다 먼저 가면 앱이 꾹 누른 걸로 보고 특수 문자 창을 띄웠다).
    static let settleTime: TimeInterval = 0.06
    private static let repostMark: Int64 = 0x54_41_53_4B   // "TASK": 다시 보낸 이벤트 표시
    private enum Queued { case key(CGEvent), toggle(SwitchAction) }
    private var queue: [Queued] = []
    /// 줄을 처리하는 중(전환 대기·다시 보낸 키 기다림)
    private var busy = false
    private var inFlight = 0
    private var postRound = 0

    private func requestToggle(_ a: SwitchAction) {
        guard filtering else { perform(a); return }
        if busy { queue.append(.toggle(a)); return }
        busy = true
        perform(a)
        Ticker.once("한영 전환 대기", Self.settleTime) { [weak self] _ in self?.pump() }
    }

    /// 다음 전환 전까지의 키를 보낸다
    private func pump() {
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
        guard case .toggle(let a) = first else { pump(); return }
        queue.removeFirst()
        Ticker.once("한영 전환 대기", Self.settleTime) { [weak self] _ in
            guard let self else { return }
            self.perform(a)
            Ticker.once("한영 전환 대기", Self.settleTime) { [weak self] _ in self?.pump() }
        }
    }

    /// 감지를 멈출 때 줄에 남은 키를 잃지 않게 보낸다(전환은 버림)
    private func flushQueue() {
        for case .key(let e) in queue { e.setIntegerValueField(.eventSourceUserData, value: Self.repostMark); e.post(tap: .cgSessionEventTap) }
        queue = []; busy = false; inFlight = 0; postRound += 1
    }

    private func act(_ a: SwitchAction?) {
        switch a {
        case .toggleInput, .capsInstead: requestToggle(a!)
        case .toggleCapsLock: Self.toggleCapsLock()
        case nil: break
        }
    }

    private func perform(_ a: SwitchAction) {
        switch a {
        case .toggleInput: InputSources.toggle()
        case .toggleCapsLock: Self.toggleCapsLock()
        case .capsInstead: InputSources.toggle(); Self.toggleCapsLock()
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

/// 한영 전환 진단(--debug에서만 부름). 앱으로 띄우면 NSLog가 로그에 안 남아 stderr에 쓴다(`open --stderr <파일>`로 받음)
func diag(_ format: String, _ args: CVarArg...) {
    let line = "\(Date()) 전환 진단: \(String(format: format, arguments: args))\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}
