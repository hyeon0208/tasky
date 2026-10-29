import AppKit
import IOKit.pwr_mgt

/// F23 잠 안 자기: 켜진 동안 화면 꺼짐·Mac 잠자기를 막는다. 앱이 끝나면 macOS가 막기를 풀어 준다.
final class Awake {
    static let shared = Awake()
    /// 메뉴 순서 그대로. 0분 = 영원히(끄기 전까지)
    static let choices: [(title: String, minutes: Int)] = [("15분", 15), ("1시간", 60), ("2시간", 120), ("5시간", 300), ("12시간", 720), ("영원히", 0)]
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
        onChange?()
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
