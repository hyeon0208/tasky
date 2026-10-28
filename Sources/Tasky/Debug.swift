import AppKit
import Darwin

// F17 개발자 옵션(--debug). 근거: intent/F17-개발자-옵션/

enum Debug {
    static let isOn = CommandLine.arguments.contains("--debug")
}

/// 이름 붙은 타이머. 살아 있는 것만 세어 개발자 탭에 보여 준다(우리 코드가 만든 것만).
enum Ticker {
    private final class Entry { let name: String; weak var timer: Timer?; init(_ n: String, _ t: Timer) { name = n; timer = t } }
    /// 사람이 읽는 간격: "30초마다", "0.1초마다", 한 번이면 "한 번"
    static func every(_ t: Timer) -> String {
        t.timeInterval <= 0 ? "한 번" : (t.timeInterval >= 1 ? String(format: "%.0f초마다", t.timeInterval) : String(format: "%g초마다", t.timeInterval))
    }
    private static var entries: [Entry] = []

    @discardableResult
    /// `mode`: 기본 `.common`(메뉴가 열려 있어도 돈다). 메뉴 중에 멈춰야 하는 것은 `.default`.
    static func every(_ name: String, _ interval: TimeInterval, from start: Date? = nil, mode: RunLoop.Mode = .common,
                      _ block: @escaping (Timer) -> Void) -> Timer {
        let t = Timer(fire: start ?? Date().addingTimeInterval(interval), interval: interval, repeats: true, block: block)
        t.tolerance = min(interval * 0.1, 0.05)
        return add(name, t, mode)
    }

    @discardableResult
    static func once(_ name: String, _ delay: TimeInterval, _ block: @escaping (Timer) -> Void) -> Timer {
        add(name, Timer(timeInterval: delay, repeats: false, block: block), .common)
    }

    private static func add(_ name: String, _ t: Timer, _ mode: RunLoop.Mode) -> Timer {
        RunLoop.main.add(t, forMode: mode)
        entries.removeAll { $0.timer?.isValid != true }
        entries.append(Entry(name, t))
        return t
    }

    /// 지금 도는 타이머: 이름(간격)별 개수
    static var live: [(name: String, count: Int)] {
        entries.removeAll { $0.timer?.isValid != true }
        var counts: [String: Int] = [:]
        for e in entries { if let t = e.timer { counts["\(e.name) (\(every(t)))", default: 0] += 1 } }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// 이 앱의 CPU·메모리·화면 갱신·애니메이션 수를 1초마다 잰다. 보는 곳이 있거나 기록 중일 때만 돈다.
final class PerfSampler: NSObject {
    static let shared = PerfSampler()

    struct Sample { let cpu: Double; let memoryMB: Double; let frames: Int; let animations: Int; let timers: Int }

    /// 애니메이션 수·화면 갱신을 잴 펫 창들
    var windows: () -> [NSWindow] = { [] }
    private var listeners: [UUID: (Sample) -> Void] = [:]
    private var timer: Timer?
    private var link: CADisplayLink?
    private var frames = 0
    private var lastCPU: Double?
    private var lastAt = Date()
    private var log: FileHandle?

    static var logging: Bool {
        get { UserDefaults.standard.bool(forKey: "perfLogging") }
        set { UserDefaults.standard.set(newValue, forKey: "perfLogging"); shared.update() }
    }
    static let logFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tasky")

    func listen(_ f: @escaping (Sample) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = f
        update()
        return id
    }
    func stop(_ id: UUID) { listeners[id] = nil; update() }

    /// 기록은 --debug일 때만 켠다(일반 실행에서는 재는 일이 없다)
    func update() {
        let want = !listeners.isEmpty || (Debug.isOn && Self.logging)
        if want, timer == nil {
            lastCPU = Self.cpuSeconds()
            lastAt = Date()
            timer = Ticker.every("이 화면 숫자 재기", 1) { [weak self] _ in self?.tick() }
            // 화면 갱신 자체는 늘 60/120이라, 갱신 때마다 펫에 움직이는 애니메이션이 있었는지만 센다(= 펫이 움직인 프레임)
            if let screen = NSScreen.main {
                let l = screen.displayLink(target: self, selector: #selector(frame))
                l.add(to: .main, forMode: .common)
                link = l
            }
        } else if !want, let t = timer {
            t.invalidate()
            timer = nil
            link?.invalidate()
            link = nil
        }
        if Debug.isOn && Self.logging { openLog() } else { try? log?.close(); log = nil }
    }

    @objc private func frame() {
        if windows().contains(where: { $0.isVisible && Self.animations(in: $0.contentView?.layer) > 0 }) { frames += 1 }
    }

    private func tick() {
        let now = Date(), cpu = Self.cpuSeconds()
        let s = Sample(cpu: Self.cpuPercent(prev: lastCPU ?? cpu, now: cpu, seconds: now.timeIntervalSince(lastAt)),
                       memoryMB: Self.memoryMB(), frames: frames,
                       animations: windows().reduce(0) { $0 + Self.animations(in: $1.contentView?.layer) },
                       timers: Ticker.live.reduce(0) { $0 + $1.count })
        lastCPU = cpu
        lastAt = now
        frames = 0
        listeners.values.forEach { $0(s) }
        if Debug.isOn && Self.logging {
            if logDay != Self.day(now) { try? log?.close(); log = nil; openLog() }   // 자정이 지나면 새 파일
            // 디스크가 꽉 차도 앱이 죽지 않게 던지는 쪽 쓰기
            if (try? log?.write(contentsOf: Data(Self.csvLine(now, s).utf8))) == nil { logFailed = true }
        }
    }

    private var logDay = ""
    /// 기록 파일을 열거나 쓰지 못했는지(개발자 탭에 보여 준다)
    private(set) var logFailed = false
    private static func day(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }

    private func openLog() {
        guard log == nil else { return }
        logDay = Self.day(Date())
        let url = Self.logFolder.appendingPathComponent("perf-\(logDay).csv")
        try? FileManager.default.createDirectory(at: Self.logFolder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(Self.csvHeader.utf8))
        }
        log = try? FileHandle(forWritingTo: url)
        _ = try? log?.seekToEnd()
        logFailed = log == nil
    }

    // MARK: 재기(순수 계산은 자체 검사 대상)

    static let csvHeader = "time,cpu,memoryMB,frames,animations,timers\n"
    static func csvLine(_ t: Date, _ s: Sample) -> String {
        String(format: "%@,%.1f,%.1f,%d,%d,%d\n", ISO8601DateFormatter().string(from: t), s.cpu, s.memoryMB, s.frames, s.animations, s.timers)
    }

    static func cpuPercent(prev: Double, now: Double, seconds: Double) -> Double {
        seconds > 0 ? max(0, now - prev) / seconds * 100 : 0
    }

    /// 이 프로세스가 지금까지 쓴 CPU 시간(초, 사용자+시스템)
    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func sec(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return sec(u.ru_utime) + sec(u.ru_stime)
    }

    /// 활성 상태 보기의 '메모리'와 같은 값(phys_footprint)
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return r == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func animations(in layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return (layer.animationKeys()?.count ?? 0) + (layer.sublayers ?? []).reduce(0) { $0 + animations(in: $1) }
    }
}

/// 설정의 '개발자' 탭 화면. 창에 붙어 있는 동안만 값을 받는다.
final class DebugTab: NSStackView {
    private let values = NSTextField(labelWithString: "재는 중…")
    private let timers = NSTextField(wrappingLabelWithString: "")
    private var listener: UUID?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 10
        edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 20, right: 22)
        values.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timers.font = .systemFont(ofSize: 12)
        timers.textColor = .secondaryLabelColor
        timers.preferredMaxLayoutWidth = SettingsTabs.width - 44
        let logCheck = ClosureButton("1초마다 기록 남기기 (CSV)") {}
        logCheck.setButtonType(.switch)
        logCheck.state = PerfSampler.logging ? .on : .off
        logCheck.handler = { [weak logCheck] in PerfSampler.logging = logCheck?.state == .on }
        let open = ClosureButton("로그 폴더 열기") {
            try? FileManager.default.createDirectory(at: PerfSampler.logFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(PerfSampler.logFolder)
        }
        let note = NSTextField(wrappingLabelWithString: "이 앱 자신의 값만 재고 밖으로 보내지 않아요. 오류 제보 때 기록 파일을 붙여 주세요.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = SettingsTabs.width - 44
        let explain = NSTextField(wrappingLabelWithString: "반복해서 하는 일: 펫이 정해진 시간마다 스스로 하는 일이에요(예: 30초마다 졸 시간인지 보기). 개수가 많거나 간격이 짧을수록 CPU와 배터리를 더 써요. 펫이 쉬는데 늘어나 있으면 줄일 곳이에요.")
        explain.font = .systemFont(ofSize: 11)
        explain.textColor = .secondaryLabelColor
        explain.preferredMaxLayoutWidth = SettingsTabs.width - 44
        [values, timers, explain, logCheck, open, note].forEach(addArrangedSubview)
        values.stringValue = "CPU      –\n메모리    –\n움직인 프레임 –\n애니메이션 –\n반복해서 하는 일 –"
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 설정 창을 닫을 때(창이 사라져도 이 함수가 불리지 않을 수 있어 직접 끊는다)
    func stop() {
        if let id = listener { PerfSampler.shared.stop(id) }
        listener = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, listener == nil {
            listener = PerfSampler.shared.listen { [weak self] s in self?.show(s) }
        } else if window == nil, let id = listener {
            PerfSampler.shared.stop(id)
            listener = nil
        }
    }

    private func show(_ s: PerfSampler.Sample) {
        values.stringValue = String(format: "CPU      %.1f%%\n메모리    %.1f MB\n움직인 프레임 %d /초\n애니메이션 %d개\n반복해서 하는 일 %d개",
                                    s.cpu, s.memoryMB, s.frames, s.animations, s.timers)
        timers.stringValue = Ticker.live.map { $0.count > 1 ? "• \($0.name) ×\($0.count)" : "• \($0.name)" }.joined(separator: "\n")
            + (PerfSampler.shared.logFailed && PerfSampler.logging ? "\n기록 파일을 쓰지 못했어요(폴더 권한·디스크 공간 확인)" : "")
    }
}
