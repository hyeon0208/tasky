import AppKit
import Carbon.HIToolbox

// F22 화면 캡처: macOS screencapture를 불러 찍고, 클립보드 복사 + 구석 미리보기. 근거: intent/F22-화면-캡처/

enum CaptureMode: String, CaseIterable {
    case area, window, full

    var title: String {
        switch self { case .area: "영역 캡처"; case .window: "창 캡처"; case .full: "전체 화면 캡처" }
    }

    /// ⌃⇧1 영역, ⌃⇧4 창, ⌃⇧5 전체 (2·3은 스크롤·픽셀 자 자리)
    var defaultKey: (code: UInt32, mods: UInt32) {
        let k = switch self { case .area: kVK_ANSI_1; case .window: kVK_ANSI_4; case .full: kVK_ANSI_5 }
        return (UInt32(k), UInt32(controlKey | shiftKey))
    }

    /// 저장된 키(없으면 기본값). 빈 배열이면 사용자가 지움.
    var key: (code: UInt32, mods: UInt32)? {
        get {
            guard let a = UserDefaults.standard.array(forKey: "captureKey.\(rawValue)") as? [Int] else { return defaultKey }
            return a.count == 2 ? (UInt32(a[0]), UInt32(a[1])) : nil
        }
        nonmutating set { UserDefaults.standard.set(newValue.map { [Int($0.code), Int($0.mods)] } ?? [], forKey: "captureKey.\(rawValue)") }
    }
}

final class Capture {
    static let shared = Capture()
    private(set) var status: [CaptureMode: SnapController.Status] = [:]
    var onChange: () -> Void = {}
    private var preview: CapturePreview?
    private var busy = false   // 고르는 화면이 두 번 뜨지 않게

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "captureEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "captureEnabled") }
    }

    static var folder: URL {
        get { UserDefaults.standard.url(forKey: "captureFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop") }
        set { UserDefaults.standard.set(newValue, forKey: "captureFolder") }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    private static var askedThisRun = false

    static func openPermission() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func setEnabled(_ on: Bool) {
        Self.enabled = on
        if on && !Self.hasPermission { CGRequestScreenCaptureAccess() }
        start()
    }

    /// 켜져 있으면 단축키를 건다. 다른 단축키(클립보드·창 정리)와 겹치면 건너뛴다.
    func start() {
        stop()
        // 켜 둔 채인데 권한이 없으면(서명이 바뀐 뒤 등) 실행마다 한 번 다시 묻는다
        if Self.enabled, !Self.hasPermission, !Self.askedThisRun { Self.askedThisRun = true; CGRequestScreenCaptureAccess() }
        guard Self.enabled else { onChange(); return }
        let system = SystemHotKeys.load()
        var used: [(code: UInt32, mods: UInt32)] = ClipWatcher.enabled ? [(HotKey.keyCode, HotKey.modifiers)] : []
        if SnapController.enabled { used += SnapAction.allCases.compactMap(\.key) }
        for (i, m) in CaptureMode.allCases.enumerated() {
            guard let k = m.key else { status[m] = .off; continue }
            if SystemHotKeys.conflicts(k, in: system) { status[m] = .system; continue }
            if SystemHotKeys.conflicts(k, in: used) { status[m] = .ours; continue }
            used.append(k)
            status[m] = HotKey.shared.add(id: 200 + UInt32(i), keyCode: k.code, modifiers: k.mods) { [weak self] in self?.take(m) } ? .ok : .taken
        }
        onChange()
    }

    func stop() {
        for i in CaptureMode.allCases.indices { HotKey.shared.remove(id: 200 + UInt32(i)) }
        status = [:]
    }

    /// 찍기. 권한이 없으면 찍지 않고 안내한다(권한 없이 찍으면 배경만 나옴).
    func take(_ mode: CaptureMode) {
        guard Self.hasPermission else { askPermission(); return }
        guard !busy else { return }
        busy = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-cap-\(UUID().uuidString).png")
        var args = ["-x"]
        switch mode {
        case .area: args += ["-i", "-s"]
        case .window: args += ["-i", "-w", "-o"]
        case .full: args += ["-R", Self.region(NSScreen.withMouse.frame)]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args + [file.path]
        p.terminationHandler = { _ in
            let data = try? Data(contentsOf: file)
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async { self.busy = false; if let data, let image = NSImage(data: data) { self.captured(image, png: data) } }   // Esc 취소면 파일 없음
        }
        // 메뉴에서 골랐을 때 메뉴가 사라진 뒤에 찍히게
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if (try? p.run()) == nil { self.busy = false } }
    }

    /// F27 10번: 오늘 찍은 캡처(이번 실행 동안, 최근 순, 최대 5장). 날이 바뀌면 비운다
    private(set) var today: [(date: Date, png: Data)] = []
    func todayShots(now: Date = Date()) -> [(date: Date, png: Data)] {
        today.removeAll { !Calendar.current.isDate($0.date, inSameDayAs: now) }
        return today
    }

    /// 띠에서 다시 열기: 클립보드에 넣고 미리보기
    func reopen(_ png: Data) {
        guard let image = NSImage(data: png) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        preview?.close()
        preview = CapturePreview(image: image, png: png)
    }

    private func captured(_ image: NSImage, png: Data) {
        today.insert((Date(), png), at: 0)
        if today.count > 5 { today.removeLast(today.count - 5) }   // 띠에 보이는 5장만 들고 있는다
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        preview?.close()
        preview = CapturePreview(image: image, png: png)
    }

    private func askPermission() {
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요해요"
        alert.informativeText = "시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록에서 Tasky를 켜 주세요. 켠 뒤 Tasky를 다시 열어야 할 수 있어요."
        alert.addButton(withTitle: "권한 열기")
        alert.addButton(withTitle: "닫기")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { Self.openPermission() }
    }

    /// screencapture -R 형식(왼쪽 위 원점, 포인트): "x,y,w,h"
    static func region(_ r: CGRect) -> String {
        let top = (NSScreen.screens.first?.frame.maxY ?? r.maxY) - r.maxY
        return "\(Int(r.minX)),\(Int(top)),\(Int(r.width)),\(Int(r.height))"
    }

    /// "Tasky 캡처 2026-10-30 14.05.12.png", 같은 이름이 있으면 " 2", " 3"…
    static func fileName(_ date: Date, exists: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Tasky 캡처 \(f.string(from: date))"
        var name = base + ".png", n = 2
        while exists(name) { name = "\(base) \(n).png"; n += 1 }
        return name
    }

    /// 저장 폴더에 PNG로. 저장한 파일 주소를 돌려준다.
    @discardableResult
    static func save(_ png: Data) throws -> URL {
        let dir = folder
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(Date()) { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) })
        try png.write(to: url)
        return url
    }
}

extension NSScreen {
    static var withMouse: NSScreen {
        screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? main ?? screens[0]
    }
}

/// 화면 오른쪽 아래의 미리보기. 6초 뒤 사라지고, 마우스를 올리면 기다린다. 누르면 편집 창, 끌면 파일로 넘긴다.
final class CapturePreview: NSView, NSDraggingSource {
    private let panel: NSPanel
    private let image: NSImage
    private let png: Data
    private var hideWork: DispatchWorkItem?
    private var down: NSPoint?
    private let note = NSTextField(labelWithString: "")

    init(image: NSImage, png: Data) {
        self.image = image
        self.png = png
        let w: CGFloat = 200, h = max(60, min(200, w * image.size.height / max(image.size.width, 1)))
        let v = NSScreen.withMouse.visibleFrame
        panel = NSPanel(contentRect: NSRect(x: v.maxX - w - 16, y: v.minY + 16, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        let iv = NSImageView(frame: bounds)
        iv.image = image
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        addSubview(iv)
        note.font = .systemFont(ofSize: 11, weight: .medium)
        note.textColor = .white
        note.drawsBackground = true
        note.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        note.isHidden = true
        note.frame = NSRect(x: 6, y: 6, width: w - 12, height: 18)
        addSubview(note)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityLabel("캡처 미리보기. 누르면 편집, 끌어서 다른 앱에 놓기")
        panel.contentView = self
        panel.orderFrontRegardless()
        scheduleHide(6)
    }

    required init?(coder: NSCoder) { nil }

    func close() {
        hideWork?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil   // 패널과 뷰가 서로 잡고 있어 끊어야 풀린다
    }

    private func scheduleHide(_ after: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: work)
    }

    override func mouseEntered(with event: NSEvent) { hideWork?.cancel() }
    override func mouseExited(with event: NSEvent) { scheduleHide(3) }
    override func mouseDown(with event: NSEvent) { down = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let d = down, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) > 4 else { return }
        down = nil
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-drag-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Capture.fileName(Date()) { _ in false })
        guard (try? png.write(to: url)) != nil else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
        // 받는 앱이 다 복사할 시간을 두고 지운다
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { try? FileManager.default.removeItem(at: dir) }
    }

    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        close()
        CaptureEditor.show(cg, scale: max(1, CGFloat(cg.width) / max(image.size.width, 1)))
    }

    private func show(_ text: String) {
        note.stringValue = " " + text
        note.isHidden = false
        scheduleHide(1.5)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { close() }
    }
}

/// F27 10번 C: 오늘 찍은 캡처 띠. 원형 메뉴 '캡처' 칸에서 열린다. 썸네일을 누르면 다시 미리보기(클립보드에도 복사),
/// 아래 버튼으로 새로 찍기. 포커스를 뺏지 않고, 바깥을 누르면 닫힌다.
final class CaptureStrip {
    static let shared = CaptureStrip()
    private var panel: FloatingPanel?
    private var monitor: Any?

    func toggle(near body: CGRect, in v: CGRect) {
        if panel != nil { close(); return }
        let shots = Capture.shared.todayShots()
        let thumb = CGSize(width: 96, height: 64), gap: CGFloat = 10
        let count = max(1, min(shots.count, 5))
        let w = max(320, CGFloat(count) * (thumb.width + gap) - gap + 32), h: CGFloat = 46 + thumb.height + 54
        let p = FloatingPanel(size: CGSize(width: w, height: h))
        p.appearance = NSAppearance(named: .darkAqua)
        var x = body.midX - w / 2, y = body.minY - h - 8
        if y < v.minY + 8 { y = body.maxY + 8 }
        x = min(max(x, v.minX + 8), v.maxX - w - 8)
        p.setFrame(CGRect(x: x, y: min(y, v.maxY - h - 8), width: w, height: h), display: false)
        let root = NSView(frame: CGRect(origin: .zero, size: p.frame.size))
        let glass = makeGlass(cornerRadius: 18, frame: root.bounds)
        root.addSubview(glass)
        let title = NSTextField(labelWithString: shots.isEmpty ? "오늘 찍은 캡처가 없어요" : "오늘 찍은 캡처 \(shots.count)장")
        title.font = .systemFont(ofSize: 13, weight: .bold); title.textColor = .white
        title.frame = CGRect(x: 16, y: h - 32, width: w - 32, height: 18)
        root.addSubview(title)
        let tf = DateFormatter(); tf.dateFormat = "H:mm"
        for (i, shot) in shots.prefix(5).enumerated() {
            let b = ClosureButton("") { [weak self] in Capture.shared.reopen(shot.png); self?.close() }
            b.isBordered = false; b.imageScaling = .scaleProportionallyUpOrDown
            b.image = NSImage(data: shot.png)
            b.wantsLayer = true; b.layer?.cornerRadius = 8; b.layer?.masksToBounds = true
            b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            b.toolTip = tf.string(from: shot.date) + " · 누르면 다시 열고 복사해요"
            b.frame = CGRect(x: 16 + CGFloat(i) * (thumb.width + gap), y: 54, width: thumb.width, height: thumb.height)
            root.addSubview(b)
        }
        if shots.isEmpty {
            let note = NSTextField(labelWithString: "아래에서 바로 찍어 보세요.")
            note.font = .systemFont(ofSize: 12); note.textColor = .white.withAlphaComponent(0.6)
            note.frame = CGRect(x: 16, y: 54 + thumb.height / 2 - 8, width: w - 32, height: 16)
            root.addSubview(note)
        }
        let modes: [(String, CaptureMode)] = [("영역", .area), ("창", .window), ("전체", .full)]
        let bw = (w - 32 - 16) / 3
        for (i, m) in modes.enumerated() {
            let b = PillButton("\(m.0) 찍기", primary: i == 0) { [weak self] in self?.close(); Capture.shared.take(m.1) }
            b.frame = CGRect(x: 16 + CGFloat(i) * (bw + 8), y: 12, width: bw, height: 30)
            root.addSubview(b)
        }
        p.contentView = root
        p.orderFrontRegardless()
        panel = p
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    func close() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel?.orderOut(nil); panel = nil
    }
}
