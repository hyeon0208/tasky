import AppKit
import IOKit.pwr_mgt
import IOKit.ps

/// F23 잠 안 자기: 켜진 동안 화면 꺼짐·Mac 잠자기를 막는다. 앱이 끝나면 macOS가 막기를 풀어 준다.
final class Awake {
    static let shared = Awake()
    /// 메뉴 순서 그대로. 0분 = 영원히(끄기 전까지)
    /// 1분은 --debug에서만(테스트용)
    static var choices: [(title: String, minutes: Int)] { (Debug.isOn ? [("1분", 1)] : []) + [("15분", 15), ("1시간", 60), ("2시간", 120), ("5시간", 300), ("12시간", 720), ("영원히", 0)] }
    /// 마지막에 고른 시간(오른쪽 클릭 켜기에 씀). 기본 영원히
    static var minutes: Int {
        get { UserDefaults.standard.integer(forKey: "awakeMinutes") }
        set { UserDefaults.standard.set(newValue, forKey: "awakeMinutes") }
    }

    private var assertion: IOPMAssertionID = 0
    private var autoOff: DispatchWorkItem?
    private(set) var isOn = false
    private(set) var end: Date?
    var onChange: (() -> Void)?

    func start(minutes: Int) {
        autoOff?.cancel()
        if !isOn {
            guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn), "Tasky keep awake" as CFString, &assertion) == kIOReturnSuccess else { return }
            isOn = true
        }
        Awake.minutes = minutes
        syncLid()
        end = Awake.end(minutes: minutes, from: Date())
        if let end {
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            autoOff = work
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + end.timeIntervalSinceNow, execute: work)
        }
        onChange?()
    }

    func stop() {
        autoOff?.cancel(); autoOff = nil
        if isOn { IOPMAssertionRelease(assertion); isOn = false }
        end = nil
        syncLid()
        onChange?()
    }

    // MARK: F30 뚜껑 닫아도 깨어 있기

    static let batteryChoices = [10, 20, 30, 50]
    static let lidTitle = "뚜껑 닫아도 깨어 있기"

    /// 체크를 바꾼다. 처음 켤 때 권한이 없으면 암호를 받아 설치하고, 취소하면 꺼진 채로 둔다.
    static func setLidAwake(_ on: Bool) {
        if on && !LidSleep.installed && !LidSleep.install() { lidAwake = false; shared.onChange?(); return }
        lidAwake = on
        shared.syncLid()
        shared.onChange?()
    }

    /// 먼저 되돌리고 체크를 끈 뒤 sudoers를 지운다
    static func removePermission() {
        lidAwake = false
        shared.syncLid()
        // 되돌리지 못했으면 지우지 않는다(지우면 sudo가 막혀 1이 영영 남음)
        guard !applied else { return }
        _ = LidSleep.uninstall()
        shared.onChange?()
    }
    /// 체크(기본 꺼짐)
    static var lidAwake: Bool {
        get { UserDefaults.standard.bool(forKey: "lidAwake") }
        set { UserDefaults.standard.set(newValue, forKey: "lidAwake") }
    }
    /// 배터리 보호 기준 %(기본 30)
    static var lidBattery: Int {
        get { let v = UserDefaults.standard.integer(forKey: "lidAwakeBattery"); return batteryChoices.contains(v) ? v : 30 }
        set { UserDefaults.standard.set(newValue, forKey: "lidAwakeBattery") }
    }
    /// Tasky가 0→1로 바꿨다는 기록. 이 기록이 있을 때만 0으로 되돌린다(사용자가 직접 켠 1은 건드리지 않음)
    private static var applied: Bool {
        get { UserDefaults.standard.bool(forKey: "lidAwakeApplied") }
        set { UserDefaults.standard.set(newValue, forKey: "lidAwakeApplied") }
    }
    private var powerSource: CFRunLoopSource?
    private var lowWarned = false

    static func lidShouldBlock(on: Bool, checked: Bool, onAC: Bool, percent: Int?, threshold: Int) -> Bool {
        guard on, checked else { return false }
        if onAC { return true }
        return (percent ?? 100) > threshold
    }

    /// 지금 상태대로 SleepDisabled를 맞춘다. quitting이면 무조건 되돌린다.
    func syncLid(quitting: Bool = false) {
        let power = Self.power()
        let block = !quitting && Self.lidShouldBlock(on: isOn, checked: Self.lidAwake, onAC: power.onAC, percent: power.percent, threshold: Self.lidBattery)
        if block {
            if !Self.applied && LidSleep.isDisabled() == false {
                // 먼저 기록해 둔다: 1로 바꾼 직후 죽어도 다음 실행에서 되돌리게
                Self.applied = true
                if !LidSleep.set(true) { Self.applied = false; Self.failed("뚜껑 막기를 켜지 못했어요") }
            }
            lowWarned = false
        } else {
            if Self.applied && LidSleep.set(false) {
                Self.applied = false
                // 이미 닫힌 채로 0이 되면 macOS가 다시 판단하지 않아 깨어 있다. 닫힘 잠자기 조건이면 바로 재운다
                if !quitting { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { LidSleep.sleepIfClosed() } }
            } else if Self.applied && !quitting {
                Self.failed("뚜껑 막기를 풀지 못했어요. 뚜껑을 닫아도 잠들지 않을 수 있어요")
            }
            if !quitting && isOn && Self.lidAwake && !power.onAC && !lowWarned {
                lowWarned = true
                DoneToast.show(text: "배터리가 \(Self.lidBattery)% 아래라 뚜껑을 닫으면 잠들어요", symbol: "battery.25")
            }
        }
        watchPower(isOn && Self.lidAwake && !quitting)
    }

    private static func failed(_ message: String) { DoneToast.show(text: message, symbol: "exclamationmark.triangle") }

    /// 시작할 때: 지난번에 되돌리지 못했으면(강제 종료 등) 0으로
    func restoreOnLaunch() {
        if Self.applied && LidSleep.set(false) { Self.applied = false }
    }

    private func watchPower(_ on: Bool) {
        if on, powerSource == nil {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
                guard let ctx else { return }
                let me = Unmanaged<Awake>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { me.syncLid() }
            }, ctx)?.takeRetainedValue() else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            powerSource = src
        } else if !on, let src = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            powerSource = nil
        }
    }

    static func power() -> (onAC: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (true, nil) }
        let onAC = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) != kIOPSBatteryPowerValue
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (onAC, cur * 100 / max)
        }
        return (onAC, nil)
    }

    static func end(minutes: Int, from now: Date) -> Date? {
        minutes > 0 ? now.addingTimeInterval(TimeInterval(minutes * 60)) : nil
    }

    /// "남은 42분", "남은 1시간 5분" (올림)
    static func left(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded(.up)))
        if m < 60 { return "남은 \(m)분" }
        return m % 60 == 0 ? "남은 \(m / 60)시간" : "남은 \(m / 60)시간 \(m % 60)분"
    }
}

/// F30: `pmset -a disablesleep`을 `/etc/sudoers.d/tasky`(이 두 명령만 암호 없이)로 바꾼다.
enum LidSleep {
    static let sudoersPath = "/etc/sudoers.d/tasky"

    static func sudoersLine(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    /// `pmset -g`의 " SleepDisabled\t\t1" 줄. 없으면 nil
    static func parseDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (ok: Bool, out: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return (false, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    /// 뚜껑이 닫혀 있고 닫힘이 잠자기를 부르는 상태(외부 모니터+전원이 아님)면 지금 재운다
    static func sleepIfClosed() {
        let out = run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d1"]).out
        if out.contains("\"AppleClamshellState\" = Yes") && out.contains("\"AppleClamshellCausesSleep\" = Yes") {
            run("/usr/bin/pmset", ["sleepnow"])
        }
    }

    static func isDisabled() -> Bool? { parseDisabled(run("/usr/bin/pmset", ["-g"]).out) }

    static func set(_ disabled: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]).ok
    }

    static var installed: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
            && run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]).ok
    }

    /// 관리자 암호를 한 번 받아 설치. 취소·실패면 false
    static func install() -> Bool {
        // 임시 파일은 관리자 셸 안에서 root 소유로 만든다(사용자 파일을 검사 뒤 바꿔치기 못 하게)
        let line = sudoersLine(user: NSUserName()).trimmingCharacters(in: .newlines)
        guard !line.contains("'") else { return false }
        let sh = "t=$(/usr/bin/mktemp /tmp/tasky-sudoers.XXXXXX) && echo '\(line)' > $t && /usr/sbin/visudo -cf $t && /usr/bin/install -m 0440 -o root -g wheel $t \(sudoersPath); r=$?; /bin/rm -f $t; exit $r"
        return admin(sh) && installed
    }

    /// 관리자 암호를 한 번 받아 삭제
    static func uninstall() -> Bool { admin("/bin/rm -f \(sudoersPath)") }

    private static func admin(_ sh: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let script = "do shell script \"\(sh)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script]).ok
    }
}

/// 메뉴 막대 C2: 곰 옆에 든 컵과 김. 템플릿이라 메뉴 막대 색을 따른다.
enum AwakeIcon {
    /// steam 0: 김 없음, 1: 낮게, 2: 높게
    static func image(bear: NSImage?, steam: Int) -> NSImage {
        let img = NSImage(size: NSSize(width: 23, height: 18), flipped: false) { _ in
            bear?.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            NSColor.black.set()
            // 컵 몸통과 손잡이, 컵을 받친 손
            NSBezierPath(roundedRect: NSRect(x: 16, y: 2, width: 6, height: 7), xRadius: 1.2, yRadius: 1.2).fill()
            let handle = NSBezierPath(); handle.lineWidth = 1
            handle.appendArc(withCenter: NSPoint(x: 22, y: 5.5), radius: 1.6, startAngle: -90, endAngle: 90)
            handle.stroke()
            NSBezierPath(ovalIn: NSRect(x: 14.5, y: 3, width: 3, height: 3)).fill()
            guard steam > 0 else { return true }
            for x in [17.5, 20.5] {
                let p = NSBezierPath(); p.lineWidth = 1; p.lineCapStyle = .round
                let base = steam == 1 ? 10.5 : 11.5, top = steam == 1 ? 13.5 : 16.5
                p.move(to: NSPoint(x: x, y: base))
                p.curve(to: NSPoint(x: x, y: top), controlPoint1: NSPoint(x: x + 1.2, y: base + 1), controlPoint2: NSPoint(x: x - 1.2, y: top - 1))
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Tasky 잠 안 자기 켜짐"
        return img
    }
}
