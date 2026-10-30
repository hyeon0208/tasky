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

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "captureEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "captureEnabled") }
    }

    static var folder: URL {
        get { UserDefaults.standard.url(forKey: "captureFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop") }
        set { UserDefaults.standard.set(newValue, forKey: "captureFolder") }
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

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
            DispatchQueue.main.async { if let data, let image = NSImage(data: data) { self.captured(image, png: data) } }   // Esc 취소면 파일 없음
        }
        // 메뉴에서 골랐을 때 메뉴가 사라진 뒤에 찍히게
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { try? p.run() }
    }

    private func captured(_ image: NSImage, png: Data) {
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
        NSApp.activate(ignoringOtherApps: true)
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
