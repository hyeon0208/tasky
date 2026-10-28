import AppKit
import Quartz

/// 펫 한 마리의 위치·빼꼼 상태, 링, 폴더 서랍, 드롭 변환을 관리한다. 펫마다 하나씩 만든다.
final class PetController: NSObject, PetViewDelegate, NSWindowDelegate {
    let id: String
    /// 크기 배율 (설정: 작게 0.8 · 보통 1 · 크게 1.3)
    private var scale: CGFloat {
        get { (UserDefaults.standard.object(forKey: key("scale")) as? Double).map { CGFloat($0) } ?? 1 }
        set { UserDefaults.standard.set(Double(newValue), forKey: key("scale")); place(animated: false) }
    }
    /// 캐릭터는 정사각 창, 콩깍지는 120×84
    private var petSize: CGSize { CGSize(width: 120 * scale, height: (petView.character?.resolve(.idle) == nil ? 84 : 120) * scale) }
    /// 콩깍지 몸 색. 펫 순서에 따라 민트·살구·라일락·크림(예전에 고른 색이 있으면 그 색). 색 고르기는 F11에서 숨김.
    private var bodyColor: NSColor {
        guard let c = UserDefaults.standard.array(forKey: key("rgb")) as? [Double], c.count == 3 else {
            return PetView.defaultColors[initialColor % PetView.defaultColors.count]
        }
        return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
    }
    /// 캐릭터 폴더 이름, "pod"는 콩깍지. 고른 적이 없으면 그림이 있는 첫 캐릭터.
    private var characterName: String {
        get { UserDefaults.standard.string(forKey: key("character")) ?? Character.available().first ?? "pod" }
        set {
            UserDefaults.standard.set(newValue, forKey: key("character"))
            petView.character = Character(name: newValue)
            place(animated: false)
        }
    }
    /// 다른 펫들(펫끼리 반응용)
    var neighbors: () -> [PetController] = { [] }
    var frame: CGRect { pet.frame }
    /// 화면에서 몸이 차지하는 사각형(캐릭터 둘레의 투명한 부분 제외)
    private var bodyFrame: CGRect {
        let b = petView.bodyUnit, f = pet.frame
        return CGRect(x: f.minX + b.minX * f.width, y: f.minY + b.minY * f.height, width: b.width * f.width, height: b.height * f.height)
    }
    private var pokes = PokeCounter()
    private var lastInteraction = Date()
    private var dragVelocity = CGVector.zero
    private var lastDragTime: Date?
    private var lifeTimers: [Timer] = []
    /// 싱잉볼 쉼 중이면 반응이 끝난 뒤 쉼 자세로 돌아간다
    private var resting = false
    private var calm: Situation { resting ? .rest : .idle }
    private var tossID = 0

    /// 진행 중인 창 이동 애니메이션(던지기·걷기)을 지금 자리에서 멈춘다
    private func stopMoving() {
        NSAnimationContext.runAnimationGroup { $0.duration = 0; pet.animator().setFrame(pet.frame, display: false) }
    }
    private let initialColor: Int
    private let alertsMenu = NSMenu()
    private let pet: FloatingPanel
    private let petView: PetView
    private var ring: FloatingPanel?
    private var outsideClickMonitor: Any?
    private var dragEndTimer: Timer?
    private var bubble: FloatingPanel?
    private let onRemove: (PetController) -> Void

    private var drawer: FloatingPanel?
    private var drawerContent: DrawerController?
    private var hoverKeyTimer: Timer?

    private var dock: Dock = .free
    private var origin: CGPoint = .zero      // 자유 상태 위치(붙었을 때는 가장자리를 따라가는 좌표로 씀)
    private var screenID: Int?
    private var hoverWork: DispatchWorkItem?
    private var lastResults: [URL] = []
    /// 지금 진행 중인 변환 수(작업 구슬용)
    private var convertingCount = 0 { didSet { updateBeads() } }

    /// `index`는 몇 번째 펫인지. 색과, 처음 놓일 자리를 조금씩 비키는 데 쓴다.
    init(id: String, index: Int, onAdd: @escaping () -> Void, onRemove: @escaping (PetController) -> Void) {
        self.id = id
        self.onRemove = onRemove
        initialColor = index
        pet = FloatingPanel(size: CGSize(width: 120, height: 84))
        petView = PetView(frame: CGRect(origin: .zero, size: CGSize(width: 120, height: 84)))
        super.init()
        pet.contentView = petView
        petView.delegate = self
        petView.bodyColor = bodyColor
        petView.character = Character(name: characterName)
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("새 깍지 부르기", onAdd))
        menu.addItem(ClosureMenuItem("이 깍지 보내기") { [weak self] in self.map(onRemove) })
        menu.addItem(.separator())
        let alertsItem = NSMenuItem(title: "작업 알림 받기", action: nil, keyEquivalent: "")
        for (value, title) in Self.alertTools {
            let item = ClosureMenuItem(title) { [weak self] in self?.alertTool = value }
            item.representedObject = value
            alertsMenu.addItem(item)
        }
        alertsItem.submenu = alertsMenu
        menu.addItem(alertsItem)
        petView.menu = menu
        restore(index: index)
        refreshAlertsMenu()
        place(animated: false)
        pet.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place(animated: true) }
        NotificationCenter.default.addObserver(forName: ClockMode.changed, object: nil, queue: .main) { [weak self] _ in
            self?.updateClock()
            self?.agentsChanged(nil, announce: false)   // 구슬 켜기·끄기도 같은 알림
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] _ in self?.updateBeads()   // 맨 앞 앱이 바뀌면 큰 구슬이 바뀐다
        }
        DispatchQueue.main.async { [weak self] in self?.updateClock() }
        lifeTimers = [
            Ticker.every("졸 시간인지 보기", 30) { [weak self] _ in
                guard let self, self.petView.base == .idle, Interaction.isSleepy(last: self.lastInteraction) else { return }
                self.petView.react(.sleepy)
            },
        ]
    }

    /// 펫을 화면에서 치우고 저장한 위치를 지운다.
    func dismiss() {
        hideClock()
        beadsPanel?.orderOut(nil)
        beadsPanel = nil
        briefingWindow?.close()
        closeRing()
        closeDrawer()
        closeAgentList()
        closeSettings()
        hoverKeyTimer?.invalidate()
        lifeTimers.forEach { $0.invalidate() }
        petView.character = nil
        bubble?.orderOut(nil)
        pet.orderOut(nil)
        for key in ["dock", "originX", "originY", "screen"] { UserDefaults.standard.removeObject(forKey: "pet.\(id).\(key)") }
    }

    func setVisible(_ visible: Bool) {
        if !visible { briefingWindow?.close() }
        defer { updateClock(); updateBeads() }
        closeRing()
        closeDrawer()
        if !visible { closeSettings() }
        if visible { pet.orderFrontRegardless() } else { pet.orderOut(nil) }
    }

    var isVisible: Bool { pet.isVisible }

    // MARK: 위치

    /// 저장한 모니터가 없으면(분리됨) 주 화면의 같은 자리로.
    private var screen: NSScreen {
        NSScreen.screens.first { $0.number == screenID } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place(animated: Bool, out: CGFloat = 0) {
        let f = Geometry.frame(size: petSize, origin: origin, dock: dock, in: screen.visibleFrame, out: out, body: petView.bodyUnit)
        petView.mirrored = dock.mirrored
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.22; pet.animator().setFrame(f, display: true) }
        } else {
            pet.setFrame(f, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.25 : 0)) { [weak self] in self?.placeClock(); self?.placeBeads() }
    }

    func petDragged(by delta: CGVector) {
        closeRing()
        if petView.base != .drag {
            touched()
            stopMoving()   // 던지기·걷기 중에 잡으면 그 자리에서 멈춘다
            tossID += 1
            petView.react(.drag)
        }
        let now = Date()
        if let last = lastDragTime, now.timeIntervalSince(last) > 0 {
            let dt = now.timeIntervalSince(last)
            // 최근 움직임에 무게를 둔 속도(pt/s)
            dragVelocity = CGVector(dx: dragVelocity.dx * 0.5 + delta.dx / dt * 0.5, dy: dragVelocity.dy * 0.5 + delta.dy / dt * 0.5)
        }
        lastDragTime = now
        var f = pet.frame
        f.origin.x += delta.dx
        f.origin.y += delta.dy
        pet.setFrame(f, display: true)
    }

    func petDragEnded() {
        petView.react(calm)
        let recent = lastDragTime.map { Date().timeIntervalSince($0) < 0.1 } ?? false
        let v = dragVelocity
        lastDragTime = nil
        dragVelocity = .zero
        // 빠르게 놓으면 던지기: 미끄러지다 화면 안에서 멈춘다
        if recent, hypot(v.dx, v.dy) > 900, petView.showsCharacter, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let s = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screen
            let target = Interaction.glide(from: pet.frame.origin, velocity: v, size: pet.frame.size, in: s.visibleFrame)
            petView.react(.toss)
            let id = tossID
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.45
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pet.animator().setFrame(CGRect(origin: target, size: pet.frame.size), display: true)
            }) { [weak self] in if let self, self.tossID == id, self.petView.base != .drag { self.settle() } }
        } else {
            petView.react(.land)
            settle()
        }
    }

    /// 놓은 자리에서 가장자리 붙기·저장·펫끼리 반응
    private func settle() {
        let mouse = NSEvent.mouseLocation
        let s = NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen
        screenID = s.number
        dock = Geometry.dock(for: bodyFrame, in: s.visibleFrame)
        origin = pet.frame.origin
        place(animated: true)
        save()
        if petView.showsCharacter, let other = neighbors().first(where: { $0 !== self && $0.isVisible && Interaction.near(pet.frame, $0.frame) }) {
            petView.react(.friend)
            other.greet()
        }
    }

    func greet() { petView.react(.friend) }
    func bowlStruck() { petView.flash(.note) }

    /// 상호작용이 있으면 졸음 시계를 처음으로, 졸고 있으면 깬다
    private func touched() {
        lastInteraction = Date()
        if petView.base == .sleepy { petView.base = .idle }
    }

    func petRubbed() {
        touched()
        petView.react(.pet)
    }

    func petHover(_ inside: Bool) {
        if inside { touched() }
        hovering = inside
        updateClock()
        hoverWork?.cancel()
        hoverKeyTimer?.invalidate()
        hoverKeyTimer = nil
        if inside {
            // 서랍 키를 누르고 있는지는 호버하는 동안만 확인한다(전역 키 감지 없음)
            // .default: 메뉴가 열린 동안 ⌥로 서랍이 열리지 않게
            hoverKeyTimer = Ticker.every("서랍 열기 키 눌렸는지 보기", 0.1, mode: .default) { [weak self] _ in
                guard let self, NSEvent.modifierFlags.contains(self.drawerKey) else { return }
                self.openDrawer(pinned: false)
            }
        }
        guard dock.isDocked, ring == nil, drawer == nil else { return }
        if inside {
            let work = DispatchWorkItem { [weak self] in self?.place(animated: true, out: 1) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            place(animated: true)
        }
    }

    private func togglePeek() {
        if dock.isDocked {
            dock = .free
            let v = screen.visibleFrame
            origin = CGPoint(x: min(pet.frame.minX, v.maxX - petSize.width - 40),
                             y: max(pet.frame.minY, v.minY + 40))
        } else {
            dock = pet.frame.midX > screen.visibleFrame.midX ? .bottomRight : .bottomLeft
        }
        place(animated: true)
        save()
    }

    // MARK: 링

    // MARK: 작업 알림

    var agents: AgentStore?
    static let alertTools = [("all", "전부"), ("claude", "Claude만"), ("codex", "Codex만")]
    /// 이 펫이 알림을 받을 도구: "all" | "claude" | "codex"
    var alertTool: String {
        get { UserDefaults.standard.string(forKey: key("alertTool")) ?? "all" }
        set {
            UserDefaults.standard.set(newValue, forKey: key("alertTool"))
            refreshAlertsMenu()
            agentsChanged(nil, announce: false)
        }
    }
    private func refreshAlertsMenu() {
        alertsMenu.items.forEach { $0.state = ($0.representedObject as? String) == alertTool ? .on : .off }
    }
    func accepts(_ tool: String) -> Bool { Self.accepts(alertTool, tool: tool) }
    static func accepts(_ setting: String, tool: String) -> Bool { setting == "all" || setting == tool }

    // MARK: 귀환 브리핑 (F8)

    private var briefing = Briefing()
    /// 이 펫에서 끝난 변환(시각, 결과). 브리핑에 쓴다. 최근 50개.
    private var conversions: [(Date, [URL])] = []
    private var briefingWindow: BriefingWindow?

    func leaveBriefing() { briefing.leave() }

    /// 돌아옴: 이 펫이 받는 도구의 작업과 이 펫의 변환만 모은다. 새로 생기면 손을 흔든다.
    func collectBriefing() {
        let sessions = (agents?.ordered ?? []).filter { accepts($0.tool) }
        if briefing.collect(sessions: sessions, conversions: conversions) > 0, pet.isVisible { petView.react(.briefing) }
    }

    private func openBriefing() {
        closeRing()
        guard briefingWindow == nil else { return }
        let shown = briefing.items
        briefingWindow = BriefingWindow(items: shown, nextTo: pet.frame, in: screen.visibleFrame) { [weak self] in
            self?.briefing.remove(shown)
            self?.briefingWindow = nil
        }
        follow(briefingWindow?.panel)
    }
    private var agentPanel: FloatingPanel?
    private var agentList: AgentListController?
    private var agentClickMonitor: Any?
    private var doneBurst: (count: Int, since: Date)?

    /// 몸 안 콩알은 이 펫이 받는 도구의 작업만 보여준다. 말풍선·알림음은 `announce`일 때만.
    func agentsChanged(_ s: AgentSession?, announce: Bool) {
        guard let agents else { return }
        petView.beans = BeadsSetting.on ? [] : agents.ordered.filter { accepts($0.tool) }.prefix(5).map { $0.state.color }
        updateBeads()
        agentList?.reload()
        guard announce, let s, pet.isVisible, s.state != .working else { return }
        petView.react(s.state == .waiting ? .jobWaiting : s.state == .failed ? .jobFailed : .jobDone)
        var title: String
        var body = s.summary
        switch s.state {
        case .waiting:
            title = "\(s.name)이 기다려요"
            body = "터미널에서 승인하거나 답해 주세요."
        case .failed:
            title = "\(s.name) 실패했어요"
        default:
            title = "\(s.name) 끝났어요"
            // 1분 안에 여러 개가 끝나면 한 번에 묶어서
            if let burst = doneBurst, Date().timeIntervalSince(burst.since) < 60 {
                doneBurst = (burst.count + 1, burst.since)
                title = "끝난 작업 \(burst.count + 1)개"
                body = "가장 최근: \(s.name)"
            } else {
                doneBurst = (1, Date())
            }
        }
        if s.whileOff { title += " (펫이 꺼져 있던 동안)" }
        var actions: [AlertCard.Action] = []
        if let app = s.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            actions.append(.init(title: "터미널로 가기") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) })
        }
        actions.append(.init(title: "목록 보기") { [weak self] in self?.openAgentList() })
        alertCard.show(session: s, title: title, body: body, actions: actions, near: pet.frame, in: screen.visibleFrame)
        follow(alertCard.panel)
    }

    private let alertCard = AlertCard()

    // MARK: 싱잉볼 쉼 (F6)

    var onBowl: ((PetController) -> Void)?
    /// 싱잉볼 창을 붙일 기준: 펫 창 위치와 화면의 쓸 수 있는 영역
    var petWindow: NSWindow { pet }
    var anchor: (frame: CGRect, visible: CGRect) { (pet.frame, screen.visibleFrame) }
    /// 펫에서 나온 창은 펫을 끌면 함께 움직인다
    func follow(_ window: NSWindow?) {
        guard let window, window.isVisible else { return }
        pet.addChildWindow(window, ordered: .above)
    }

    func dismissAlert() { alertCard.dismiss() }

    // MARK: 시계 말풍선 (시안 '커서 올리면 말풍선', 초 단위)

    private var clock: (panel: FloatingPanel, label: NSTextField, timer: Timer)?
    private var hovering = false

    private func updateClock() {
        let show = pet.isVisible && (ClockMode.current == .always || (ClockMode.current == .hover && hovering))
        guard show else { hideClock(); return }
        if clock == nil { showClock() }
        clock?.label.stringValue = ClockMode.text(Date())   // 설정을 바꾸면 바로 반영
        placeClock()
        placeBeads()   // 시계가 생기거나 없어지면 구슬 자리도 바뀐다
    }

    private func showClock() {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        let size = CGSize(width: 116, height: 34)   // "오후 12:00:00" + 꼬리
        let panel = FloatingPanel(size: size)
        panel.ignoresMouseEvents = true   // 펫을 누르거나 끄는 데 방해되지 않게
        let box = ClockBubble(frame: CGRect(origin: .zero, size: size))
        label.frame = CGRect(x: 0, y: 12, width: size.width, height: 17)
        box.addSubview(label)
        panel.contentView = box
        panel.orderFrontRegardless()
        follow(panel)
        let tick = { label.stringValue = ClockMode.text(Date()) }
        tick()
        // 다음 초가 바뀌는 순간에 맞춰 1초마다(늦게 바뀌어 보이지 않게)
        let timer = Ticker.every("시계 초 넘기기", 1, from: Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970))) { _ in tick() }
        clock = (panel, label, timer)
    }

    // MARK: 작업 구슬 (F14)

    private var beadsPanel: FloatingPanel?
    private var beadsView: BeadsView?

    private func hideBeads() {
        beadsPanel?.orderOut(nil)
        beadsPanel = nil
        beadsView = nil
        petView.lean(0)
    }

    private func updateBeads() {
        guard BeadsSetting.on, pet.isVisible, let agents else { hideBeads(); return }
        let beads = BeadModel.beads(sessions: agents.ordered, converting: convertingCount,
                                    frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, accepts: accepts)
        if beads.isEmpty { hideBeads(); return }
        if beadsPanel == nil {
            let size = CGSize(width: 280, height: BeadsView.labelHeight + BeadsView.big + 12)
            let panel = FloatingPanel(size: size)
            let view = BeadsView(frame: CGRect(origin: .zero, size: size))
            view.onClick = { [weak self] in self?.openAgentList() }
            panel.contentView = view
            panel.orderFrontRegardless()
            follow(panel)
            beadsPanel = panel
            beadsView = view
        }
        beadsView?.beads = beads
        placeBeads()
        // 내 차례 구슬이 옆에 있으면 그쪽으로 기운다(큰 구슬이 기다리면 똑바로 위를 본다)
        if let view = beadsView, let panel = beadsPanel, let x = view.waitingX, !(beads.first { $0.kind == .waiting }?.big ?? false) {
            petView.lean(panel.frame.minX + x < bodyFrame.midX ? -1 : 1)   // 화면 가장자리에서 패널이 밀려도 몸 가운데 기준
        } else {
            petView.lean(0)
        }
    }

    private func placeBeads() {
        guard let panel = beadsPanel else { return }
        let v = screen.visibleFrame, body = bodyFrame
        let shown = body.intersection(v).isNull ? body : body.intersection(v)
        let top = clock?.panel.frame.maxY ?? shown.maxY + 2
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: min(max(shown.midX - size.width / 2, v.minX), v.maxX - size.width),
                                     y: min(top - BeadsView.labelHeight + 2, v.maxY - size.height)))
    }

    private func placeClock() {
        guard let clock else { return }
        let body = bodyFrame, size = clock.panel.frame.size
        let v = screen.visibleFrame
        let shown = body.intersection(v).isNull ? body : body.intersection(v)   // 빼꼼 중이면 보이는 몸 위에
        clock.panel.setFrameOrigin(CGPoint(x: min(max(shown.midX - size.width / 2, v.minX + 4), v.maxX - size.width - 4),
                                           y: min(shown.maxY + 4, v.maxY - size.height)))
    }

    private func hideClock() {
        guard let clock else { return }
        clock.timer.invalidate()
        clock.panel.orderOut(nil)
        defer { placeBeads() }   // 시계 자리가 비면 구슬이 내려온다
        self.clock = nil
    }

    func setResting(_ on: Bool) {
        petView.breathing = on
        petView.holdingBowl = on
        resting = on
        if on { stopMoving() }
        petView.react(calm)
    }

    func openAgentList() {
        guard agentPanel == nil, let agents else { return }
        closeRing()
        closeDrawer()
        let size = CGSize(width: 420, height: 380)
        let v = screen.visibleFrame
        let shown = pet.frame.intersection(v)
        let c = Geometry.visibleCenter(of: pet.frame, in: v)
        var x = c.x > v.midX ? shown.minX - size.width - 8 : shown.maxX + 8
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(c.y - size.height / 2, v.minY + 8), v.maxY - size.height - 8)
        let panel = FloatingPanel(size: size)
        panel.keyable = true
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
        let list = AgentListController(size: size, store: agents) { [weak self] in self?.closeAgentList() }
        panel.contentView = list.view
        panel.orderFrontRegardless()
        agentPanel = panel
        follow(panel)
        agentList = list
        agents.markSeen()
        petView.beans = BeadsSetting.on ? [] : agents.ordered.filter { accepts($0.tool) }.prefix(5).map { $0.state.color }
        updateBeads()
        agentClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.closeAgentList() }
    }

    private func closeAgentList() {
        if let m = agentClickMonitor { NSEvent.removeMonitor(m); agentClickMonitor = nil }
        agentPanel?.orderOut(nil)
        agentPanel = nil
        agentList = nil
    }

    func petClicked() {
        drawerOutsideClick()   // 펫을 눌러도 바깥 클릭처럼 닫는다(끌기는 닫지 않고 함께 움직임)
        touched()
        stopMoving()
        if petView.showsCharacter, pokes.poke() { closeRing(); petView.react(.sulk); return }
        if ring != nil { closeRing() } else { petView.react(.click); openRing(slots: mainSlots, acceptsFiles: false) }
    }

    private var mainSlots: [Slot] {
        let waiting = agents?.waiting ?? 0, done = agents?.unseenDone ?? 0
        // 상황 칸: 그 사이 N건 > 기다리는 작업 > 끝난 작업 > 변환 결과 > 쓰다듬기
        let first: Slot =
            !briefing.items.isEmpty ? Slot(title: "그 사이 \(briefing.items.count)건", symbol: "sun.horizon") { [weak self] in self?.openBriefing() }
            : waiting > 0 ? Slot(title: "기다리는 작업 \(waiting)", symbol: "exclamationmark.bubble", badge: waiting) { [weak self] in self?.openAgentList() }
            : done > 0 ? Slot(title: "끝난 작업 \(done)", symbol: "checkmark.seal") { [weak self] in self?.openAgentList() }
            : !lastResults.isEmpty ? Slot(title: "변환 결과 보기", symbol: "checkmark.circle") { [weak self] in self?.revealResults() }
            : Slot(title: "쓰다듬기", symbol: "hand.wave") { [weak self] in self?.petRubbed() }
        return [
            first,
            // 편지 쓰기·편지함은 F7(보류) 동안 뺀다
            Slot(title: "폴더 서랍", symbol: "folder") { [weak self] in self?.openDrawer(pinned: false) },
            Slot(title: "싱잉볼", symbol: "bell") { [weak self] in if let self { self.onBowl?(self) } },
            Slot(title: "작업 알림", symbol: "checklist") { [weak self] in self?.openAgentList() },
            Slot(title: dock.isDocked ? "빼꼼 그만" : "빼꼼", symbol: "eye") { [weak self] in self?.togglePeek() },
            Slot(title: "설정", symbol: "gearshape") { [weak self] in self?.openSettings() },
        ]
    }

    private func openRing(slots: [Slot], acceptsFiles: Bool) {
        closeRing()
        hoverWork?.cancel()
        let v = screen.visibleFrame
        let body = bodyFrame
        let center = Geometry.visibleCenter(of: body, in: v)
        let bodySize = max(body.width, body.height)
        let roomAbove = v.maxY - center.y > 96 + max(0, bodySize - 80) * 0.6 + 40
        let points = Geometry.slotCenters(count: slots.count, dock: dock, center: center, size: bodySize, roomAbove: roomAbove)
        let pad: CGFloat = 70
        let xs = points.map(\.x) + [center.x], ys = points.map(\.y) + [center.y, body.minY - 40]   // 펫 아래 이름표 자리
        let rect = CGRect(x: xs.min()! - pad, y: ys.min()! - pad,
                          width: xs.max()! - xs.min()! + pad * 2, height: ys.max()! - ys.min()! + pad * 2)

        let panel = FloatingPanel(size: rect.size)
        panel.keyable = !acceptsFiles   // 끌기 중에는 키 창을 바꾸지 않는다
        panel.delegate = self
        panel.setFrame(rect, display: false)
        let view = RingView(frame: CGRect(origin: .zero, size: rect.size))
        view.slots = slots
        view.origin = CGPoint(x: center.x - rect.minX, y: center.y - rect.minY)
        if dock == .free && roomAbove { view.labelTop = body.minY - rect.minY - 8 }
        view.centers = points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
        view.acceptsFiles = acceptsFiles
        view.onClose = { [weak self] in self?.closeRing() }
        panel.contentView = view
        if acceptsFiles {
            panel.orderFrontRegardless()
            // 칸이 아닌 곳에 놓거나 끌기를 취소하면 링을 닫는다
            dragEndTimer = Ticker.every("파일 끌기 끝났는지 보기", 0.2) { [weak self] _ in
                if NSEvent.pressedMouseButtons == 0 { self?.closeRing() }
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            // 링 밖(다른 앱)을 클릭하면 닫는다. 마우스 클릭만 보므로 손쉬운 사용 권한이 필요 없다.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closeRing()
            }
        }
        pet.orderFrontRegardless()   // 펫이 링 위에 오도록
        ring = panel
    }

    private func closeRing() {
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        if petView.base == .fileNear { petView.react(calm) }
        guard let panel = ring else { return }
        ring = nil
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel.delegate = nil
        panel.orderOut(nil)
        if dock.isDocked, !pet.frame.contains(NSEvent.mouseLocation) { place(animated: true) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === ring { closeRing() }
    }

    // MARK: 드롭 변환

    func petFilesEntered(_ urls: [URL]) {
        touched()
        stopMoving()
        closeDrawer()
        if dock.isDocked { place(animated: true, out: 1) }
        openRing(slots: convertSlots(for: urls), acceptsFiles: true)
        petView.react(.fileNear)
    }

    func petFilesDroppedOnBody() {
        closeRing()
        say("둘레의 칸 위에 놓아 주세요")
    }

    private func convertSlots(for urls: [URL]) -> [Slot] {
        let use = UserDefaults.standard.dictionary(forKey: "convertUse") as? [String: Int] ?? [:]
        // 이 Mac에서 자주 쓴 변환이 위쪽(앞쪽) 칸에 온다
        let ops = ConvertOp.options(for: urls).enumerated()
            .sorted { (use[$0.element.rawValue] ?? 0, -$0.offset) > (use[$1.element.rawValue] ?? 0, -$1.offset) }
            .map(\.element)
        var slots = ops.map { op in Slot(title: op.title, symbol: op.symbol) { [weak self] in self?.convert(op, urls) } }

        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if !folders.isEmpty, folders.count == urls.count {
            slots.append(Slot(title: "서랍에 저장", symbol: "folder.badge.plus") { [weak self] in
                let reasons = folders.compactMap { DrawerStore.shared.add($0) }
                self?.say(reasons.first ?? "서랍에 넣었어요")
            })
        }
        if slots.isEmpty {
            slots.append(Slot(title: "이 형식은 아직 못 바꿔요", symbol: "questionmark") {})
        }
        return slots
    }

    private func convert(_ op: ConvertOp, _ urls: [URL]) {
        var use = UserDefaults.standard.dictionary(forKey: "convertUse") as? [String: Int] ?? [:]
        use[op.rawValue, default: 0] += 1
        UserDefaults.standard.set(use, forKey: "convertUse")

        say("\(op.title) 바꾸는 중… (\(urls.count)개)")
        petView.react(.converting)
        convertingCount += 1
        Converter.run(op, urls) { [weak self] outputs, errors in
            guard let self else { return }
            self.convertingCount -= 1
            if self.petView.base == .converting { self.petView.react(self.calm) }
            if !outputs.isEmpty {
                self.lastResults = outputs
                self.conversions = Array((self.conversions + [(Date(), outputs)]).suffix(50))
            }
            if errors.isEmpty {
                self.petView.react(.converted)
                self.say("다 바꿨어요. 링 첫 칸에서 결과를 볼 수 있어요")
            } else {
                self.say(outputs.isEmpty ? errors[0] : "\(outputs.count)개 성공, \(errors.count)개 실패: \(errors[0])", seconds: 4)
            }
        }
    }

    private func revealResults() {
        NSWorkspace.shared.activateFileViewerSelecting(lastResults)
        lastResults = []
    }

    // MARK: 폴더 서랍

    /// 서랍을 여는 키 (설정에서 바꾼다)
    static let drawerKeys: [(id: String, title: String, flag: NSEvent.ModifierFlags)] = [
        ("option", "⌥ Option", .option), ("control", "⌃ Control", .control),
        ("command", "⌘ Command", .command), ("shift", "⇧ Shift", .shift),
    ]

    private var drawerKey: NSEvent.ModifierFlags {
        let id = UserDefaults.standard.string(forKey: "drawerKey")
        return Self.drawerKeys.first { $0.id == id }?.flag ?? .option
    }

    // MARK: 설정

    private var settingsPanel: FloatingPanel?
    private var settingsKeepAlive: [AnyObject] = []
    private var settingsMonitor: Any?

    private func openSettings() {
        guard settingsPanel == nil else { return }
        closeRing()

        func popup(_ items: [String], selected: Int, _ pick: @escaping (Int) -> Void) -> NSPopUpButton {
            let p = NSPopUpButton()
            let menu = NSMenu()
            for (i, title) in items.enumerated() { menu.addItem(ClosureMenuItem(title) { pick(i) }) }
            p.menu = menu
            p.selectItem(at: max(selected, 0))
            return p
        }
        func check(_ on: Bool, _ toggle: @escaping (Bool) -> Void) -> NSButton {
            let b = ClosureButton("") {}
            b.setButtonType(.switch)
            b.title = ""
            b.state = on ? .on : .off
            b.handler = { [weak b] in toggle(b?.state == .on) }
            return b
        }
        let toolButtons = [HookInstaller.Tool.claude, .codex].map { tool -> NSButton in
            let b = ClosureButton("") {}
            func refresh() { b.title = HookInstaller.isInstalled(tool) ? "연결 끊기" : "연결" }
            refresh()
            b.handler = { _ = HookInstaller.confirmAndSet(tool, install: !HookInstaller.isInstalled(tool)); refresh() }
            return b
        }

        // 크기: 가로로 누운 볼륨 노브처럼 끌어서 조절
        let sizeSlider = NSSlider(value: Double(scale), minValue: 0.6, maxValue: 1.8, target: nil, action: nil)
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let sizeHandler = ClosureButton("") {}
        sizeHandler.handler = { [weak self, weak sizeSlider] in if let v = sizeSlider?.doubleValue { self?.scale = CGFloat(v) } }
        sizeSlider.target = sizeHandler
        sizeSlider.action = #selector(ClosureButton.performClick(_:))
        settingsKeepAlive = [sizeHandler]
        let small = NSImageView(image: NSImage(systemSymbolName: "leaf", accessibilityDescription: "작게")!)
        let large = NSImageView(image: NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "크게")!)
        large.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        let sizeRow = NSStackView(views: [small, sizeSlider, large])
        sizeRow.spacing = 6

        // 원형 메뉴 칸의 투명도(모든 펫 공통)
        let glassSlider = NSSlider(value: RingView.transparency, minValue: 0, maxValue: 1, target: nil, action: nil)
        glassSlider.isContinuous = true
        glassSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let glassHandler = ClosureButton("") {}
        let ringPreview = RingPreview()
        glassHandler.handler = { [weak glassSlider, weak ringPreview] in
            if let v = glassSlider?.doubleValue { RingView.transparency = v; ringPreview?.refresh() }
        }
        glassSlider.target = glassHandler
        glassSlider.action = #selector(ClosureButton.performClick(_:))
        settingsKeepAlive.append(glassHandler)
        let glassRow = NSStackView(views: [NSTextField(labelWithString: "불투명"), glassSlider, NSTextField(labelWithString: "투명")])
        glassRow.spacing = 6

        // 캐릭터: 콩깍지 + 그림이 있는 캐릭터
        let chars = ["pod"] + Character.available()
        let charPopup = popup(chars.map { $0 == "pod" ? "콩깍지" : Character.names[$0] ?? $0 },
                              selected: chars.firstIndex(of: characterName) ?? 0) { [weak self] in self?.characterName = chars[$0] }

        func hint(_ text: String) -> NSTextField {
            let t = NSTextField(labelWithString: text)
            t.font = .systemFont(ofSize: 11)
            t.textColor = .secondaryLabelColor
            return t
        }
        let label = NSTextField.init(labelWithString:)

        // 키보드(F12, 모든 펫 공통): 한영 전환 상태 줄과 키 반복 슬라이더
        let kbStatus = hint("")
        let permissionButton = ClosureButton("권한 열기") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
        func refreshKeyboard() {
            let ks = KeySwitcher.shared
            // 권한을 준 뒤 설정을 다시 열면 그때 감지를 시작한다
            if KeySwitcher.enabled, ks.hasPermission, !ks.running { ks.apply() }
            if ks.running, !ks.hasPermission { ks.stop() }   // 권한을 거둔 뒤 Caps Lock이 먹통이 되지 않게
            permissionButton.isHidden = !(KeySwitcher.enabled && !ks.hasPermission)
            kbStatus.stringValue =
                !KeySwitcher.enabled ? "켜면 입력 모니터링 권한을 물어요"
                : !ks.hasPermission ? "입력 모니터링 권한이 필요해요"
                : !InputSources.available ? "한국어·영문 입력 소스를 모두 켜 주세요"
                : KeySwitcher.key == .capsLock ? "길게 누르면 대문자 고정. 비정상 종료 뒤엔 다시 켜거나 재시동하면 돌아와요"
                : "그 키만 눌렀다 떼면 바뀌어요"
        }
        refreshKeyboard()
        let kbStatusRow = NSStackView(views: [kbStatus, permissionButton])
        kbStatusRow.spacing = 6
        func repeatRow(_ key: String) -> NSView {
            let r = KeyRepeat.range(key)
            let value = min(max(KeyRepeat.read(key) ?? KeyRepeat.fallback(key), r.lowerBound), r.upperBound)
            let ms = hint("")
            func show(_ v: Int) { ms.stringValue = "약 \(KeyRepeat.ms(v))ms" }
            show(value)
            let slider = NSSlider(value: Double(value),
                                  minValue: Double(r.lowerBound), maxValue: Double(r.upperBound), target: nil, action: nil)
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let handler = ClosureButton("") {}
            handler.handler = { [weak slider] in
                guard let v = slider.map({ Int($0.doubleValue.rounded()) }) else { return }
                KeyRepeat.set(key, v)
                show(v)
            }
            slider.target = handler
            slider.action = #selector(ClosureButton.performClick(_:))
            settingsKeepAlive.append(handler)
            let row = NSStackView(views: [hint("빠름"), slider, hint("느림"), ms])
            row.spacing = 6
            return row
        }
        let initialRow = repeatRow(KeyRepeat.initial), rateRow = repeatRow(KeyRepeat.rate)
        let restoreButton = ClosureButton("되돌리기") { [weak self] in
            KeyRepeat.restore()
            self?.closeSettings()   // 슬라이더를 되돌린 값으로 다시 그리도록 닫는다
        }
        let keyTest = KeyTestField()
        settingsKeepAlive.append(keyTest)
        let bowlSlider = NSSlider(value: Double(BowlSynth.userVolume), minValue: 0, maxValue: 1, target: nil, action: nil)
        bowlSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let bowlHandler = ClosureButton("") {}
        bowlHandler.handler = { [weak bowlSlider] in if let v = bowlSlider?.floatValue { BowlSynth.userVolume = v } }
        bowlSlider.target = bowlHandler
        bowlSlider.action = #selector(ClosureButton.performClick(_:))
        settingsKeepAlive.append(bowlHandler)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드"
        func permission(_ on: Bool) -> NSTextField {
            let t = NSTextField(labelWithString: on ? "허용됨" : "허용 안 됨")
            t.textColor = on ? .systemGreen : .secondaryLabelColor
            return t
        }
        let tabs = [
            SettingsTab(id: "general", title: "일반", symbol: "gearshape", content: SettingsTabs.grid([(nil, [
                [label("컴퓨터를 켤 때 함께 실행"), check(LoginItem.isOn) { LoginItem.set($0) }],
                [label("원형 메뉴 투명도"), glassRow],
                [NSView(), ringPreview],
                [label("폴더 서랍 열기 키"),
                 popup(Self.drawerKeys.map(\.title), selected: Self.drawerKeys.firstIndex { $0.id == UserDefaults.standard.string(forKey: "drawerKey") } ?? 0) {
                     UserDefaults.standard.set(Self.drawerKeys[$0].id, forKey: "drawerKey") }],
                [NSView(), hint("이 키를 누른 채로 펫 위에 커서를 올리면 클릭 없이 폴더 서랍이 열려요")],
                [label("싱잉볼 소리"), bowlSlider],
                [label("시계 말풍선"), popup(ClockMode.allCases.map(\.title), selected: ClockMode.allCases.firstIndex(of: .current) ?? 0) {
                    ClockMode.current = ClockMode.allCases[$0] }],
                [label("24시간제"), check(ClockMode.hour24) { ClockMode.hour24 = $0 }],
                [label("작업 구슬 보이기"), check(BeadsSetting.on) { BeadsSetting.on = $0 }],
                [label("초 보이기"), check(ClockMode.showSeconds) { ClockMode.showSeconds = $0 }],
            ])])),
            SettingsTab(id: "pet", title: "깍지", symbol: "leaf", content: SettingsTabs.grid([("이 깍지만", [
                [label("크기"), sizeRow],
                [label("캐릭터"), charPopup],
                [label("이 깍지가 받을 알림"),
                 popup(Self.alertTools.map(\.1), selected: Self.alertTools.firstIndex { $0.0 == alertTool } ?? 0) { [weak self] in
                     self?.alertTool = Self.alertTools[$0].0 }],
            ])])),
            SettingsTab(id: "alerts", title: "작업 알림", symbol: "bell", content: SettingsTabs.grid([(nil, [
                [label("알림음"), check(AlertCard.soundOn) { AlertCard.soundOn = $0 }],
                [label("Claude Code"), toolButtons[0]],
                [label("Codex"), toolButtons[1]],
            ])])),
            SettingsTab(id: "keyboard", title: "키보드", symbol: "keyboard", content: SettingsTabs.grid([
                ("바로 테스트", [[label(""), keyTest]]),
                ("한영 전환 · 키 반복", [
                [label("한영 전환"), check(KeySwitcher.enabled) { on in
                    KeySwitcher.enabled = on
                    KeySwitcher.shared.apply(ask: on)
                    refreshKeyboard()
                }],
                [label("전환 키"), popup(SwitchKey.allCases.map(\.title), selected: SwitchKey.allCases.firstIndex(of: KeySwitcher.key) ?? 0) {
                    KeySwitcher.key = SwitchKey.allCases[$0]
                    KeySwitcher.shared.apply()
                    refreshKeyboard()
                }],
                [NSView(), kbStatusRow],
                [label("반복 시작까지"), initialRow],
                [label("반복 속도"), rateRow],
                [NSView(), hint("바로 적용돼요. 다시 로그인해도 유지돼요")],
                [NSView(), restoreButton],
                ]),
            ])),
        ] + (Debug.isOn ? [SettingsTab(id: "debug", title: "개발자", symbol: "hammer", content: {
                let d = DebugTab()
                settingsKeepAlive.append(d)
                return d
            }())] : []) + [
            SettingsTab(id: "about", title: "정보", symbol: "info.circle", content: SettingsTabs.grid([(nil, [
                [label("버전"), NSTextField(labelWithString: version)],
                [label("입력 모니터링"), permission(CGPreflightListenEventAccess())],
                [label("손쉬운 사용"), permission(AXIsProcessTrusted())],
            ])])),
        ]
        let tabView = SettingsTabs(tabs: tabs)
        let size = tabView.frame.size
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(tabView)

        let v = screen.visibleFrame
        let shown = pet.frame.intersection(v).isNull ? pet.frame : pet.frame.intersection(v)
        let x = min(max(shown.midX - size.width / 2, v.minX + 8), v.maxX - size.width - 8)
        let y = shown.maxY + 8 + size.height <= v.maxY ? shown.maxY + 8 : max(shown.minY - size.height - 8, v.minY + 8)
        let panel = FloatingPanel(size: size)
        panel.keyable = true
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
        panel.contentView = effect
        panel.orderFrontRegardless()
        settingsPanel = panel
        follow(panel)
        // 탭을 바꾸면 위쪽을 고정한 채 높이를 내용에 맞춘다
        tabView.autoresizingMask = [.minYMargin]   // 창이 커지고 작아지는 동안 탭 줄은 위에 붙어 있다
        tabView.onResize = { [weak panel, weak effect, weak tabView] size in
            guard let panel, let effect, let tabView else { return }
            var f = panel.frame
            f.origin.y = max(f.maxY - size.height, v.minY + 8)   // 화면 아래로 넘치면 위로 올린다
            f.size = size
            tabView.frame.origin.y = effect.bounds.height - size.height
            panel.setFrame(f, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        // 바깥(다른 앱)을 클릭하면 닫는다
        settingsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.closeSettings() }
    }

    private func closeSettings() {
        if let m = settingsMonitor { NSEvent.removeMonitor(m); settingsMonitor = nil }
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        settingsKeepAlive.compactMap { $0 as? KeyTestField }.forEach { $0.stop() }
        settingsKeepAlive.compactMap { $0 as? DebugTab }.forEach { $0.stop() }
        settingsKeepAlive = []
    }

    private func openDrawer(pinned: Bool) {
        hoverKeyTimer?.invalidate()
        hoverKeyTimer = nil
        guard drawer == nil else { return }
        closeRing()
        let store = DrawerStore.shared
        store.pinned = pinned

        // 크기는 마지막으로 쓴 크기를 기억한다. 처음에는 칼럼 3개가 넉넉히 보이는 크기.
        let v = screen.visibleFrame
        let d = UserDefaults.standard
        let size = CGSize(
            width: min(d.double(forKey: "drawerW") > 0 ? d.double(forKey: "drawerW")
                       : DrawerController.sideWidth + 1 + 3 * DrawerController.columnWidth, v.width - 16),
            height: min(d.double(forKey: "drawerH") > 0 ? d.double(forKey: "drawerH") : 560, v.height - 16))
        let shown = pet.frame.intersection(v)
        let c = Geometry.visibleCenter(of: pet.frame, in: v)
        // 펫이 화면 오른쪽에 있으면 서랍은 펫 왼쪽에 열리고, 넓어질 때 왼쪽으로 자란다
        let growsLeft = c.x > v.midX
        var x = growsLeft ? shown.minX - size.width - 8 : shown.maxX + 8
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
        let y = min(max(c.y - size.height / 2, v.minY + 8), v.maxY - size.height - 8)

        let panel = FloatingPanel(size: size)
        panel.keyable = true            // 클릭하면 키 입력(스페이스, Esc)을 받는다. 열 때는 포커스를 가져가지 않는다
        panel.styleMask.insert(.resizable)
        panel.minSize = CGSize(width: DrawerController.sideWidth + 2 * DrawerController.columnWidth, height: 320)
        panel.isMovable = true
        panel.isMovableByWindowBackground = true   // 빈 곳(아래 막대 등)을 끌어 옮긴다
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
        let content = DrawerController(size: size, onClose: { [weak self] in self?.closeDrawer() })
        // 더 깊이 들어가 칼럼이 모자라면 넓힌다(줄이지는 않는다)
        content.onWantWidth = { [weak panel] width in
            guard let panel, width > panel.frame.width else { return }
            let w = min(width, v.width - 16)
            var f = panel.frame
            if growsLeft { f.origin.x = f.maxX - w }
            f.size.width = w
            f.origin.x = min(max(f.origin.x, v.minX + 8), v.maxX - w - 8)
            panel.setFrame(f, display: true)
        }
        panel.contentView = content.view
        content.updateLayout()
        panel.orderFrontRegardless()
        drawer = panel
        drawerContent = content
        follow(panel)   // 펫을 끌면 함께 움직인다
        drawerResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak content] _ in content?.updateLayout() }

        // 서랍 밖을 클릭하면 닫는다(고정하면 안 닫힘). 다른 앱 클릭과 이 앱의 다른 창 클릭을 모두 본다.
        drawerMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.drawerOutsideClick()
            },
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
                if let self, let drawer = self.drawer, e.window !== drawer, e.window !== self.pet, !(e.window is QLPreviewPanel), NSApp.modalWindow == nil {
                    self.drawerOutsideClick()
                }
                return e
            },
        ].compactMap { $0 }
    }

    private var drawerMonitors: [Any] = []
    private var drawerResizeObserver: Any?

    private func drawerOutsideClick() {
        if !DrawerStore.shared.pinned { closeDrawer() }
    }

    private func closeDrawer() {
        drawerMonitors.forEach(NSEvent.removeMonitor)
        drawerMonitors = []
        if let o = drawerResizeObserver { NotificationCenter.default.removeObserver(o); drawerResizeObserver = nil }
        if let drawer {
            UserDefaults.standard.set(drawer.frame.width, forKey: "drawerW")
            UserDefaults.standard.set(drawer.frame.height, forKey: "drawerH")
        }
        drawer?.orderOut(nil)
        drawer = nil
        drawerContent = nil
        if dock.isDocked, !pet.frame.contains(NSEvent.mouseLocation) { place(animated: true) }
    }

    // MARK: 말풍선


    private func say(_ text: String, seconds: Double = 1.8) {
        bubble?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        let size = CGSize(width: min(label.intrinsicContentSize.width + 20, 420), height: 26)
        let panel = FloatingPanel(size: size)
        let box = NSView(frame: CGRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        box.layer?.cornerRadius = 8
        label.frame = CGRect(x: 10, y: 5, width: size.width - 20, height: 16)
        box.addSubview(label)
        panel.contentView = box
        let v = screen.visibleFrame
        let c = Geometry.visibleCenter(of: pet.frame, in: v)
        let x = min(max(c.x - size.width / 2, v.minX + 8), v.maxX - size.width - 8)
        panel.setFrameOrigin(CGPoint(x: x, y: min(max(pet.frame.maxY, v.minY) + 6, v.maxY - size.height)))
        panel.orderFrontRegardless()
        bubble = panel
        follow(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.bubble === panel { self?.bubble = nil }
        }
    }

    // MARK: 저장 (펫마다 따로)

    private func key(_ name: String) -> String { "pet.\(id).\(name)" }

    private func save() {
        let d = UserDefaults.standard
        d.set(dock.rawValue, forKey: key("dock"))
        d.set(origin.x, forKey: key("originX"))
        d.set(origin.y, forKey: key("originY"))
        d.set(screenID, forKey: key("screen"))
    }

    private func restore(index: Int) {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: key("dock")), let saved = Dock(rawValue: raw) {
            dock = saved
            origin = CGPoint(x: d.double(forKey: key("originX")), y: d.double(forKey: key("originY")))
            screenID = d.object(forKey: key("screen")) as? Int
        } else {
            // 처음에는 화면 정중앙. 여러 마리면 겹치지 않게 조금씩 비켜 선다.
            dock = .free
            let v = screen.visibleFrame
            let shift = CGFloat(index % 6) * 40
            origin = CGPoint(x: v.midX - petSize.width / 2 + shift, y: v.midY - petSize.height / 2 - shift)
        }
    }
}

/// 메뉴 막대 아이콘과 펫 목록. 펫 ID 목록을 저장해 다음 실행 때 같은 펫들을 다시 띄운다.
final class App: NSObject {
    private var pets: [PetController] = []
    private var statusItem: NSStatusItem!
    private var counter: Int

    private let agents = AgentStore()
    private var server: HookServer?

    override init() {
        counter = UserDefaults.standard.integer(forKey: "petCounter")
        super.init()
        let ids = UserDefaults.standard.stringArray(forKey: "pets") ?? []
        for id in ids { spawn(id: id) }
        if pets.isEmpty { addPet() }
        setUpStatusItem()

        // 알림은 그 도구를 받는 펫 중 첫 번째(보이는 펫)가 알린다. 받는 펫이 없으면 첫 번째 펫이 알려 놓치지 않게 한다.
        // 쉬는 중(F6)에는 끝남·실패를 보류하고, 승인 대기는 싱잉볼 창 한 줄로만 보여 준다(모든 펫 공통).
        agents.onChange = { [weak self] s in
            guard let self else { return }
            let announce = s.map { RestSession.shouldAnnounce(&self.rest, $0) } ?? true
            if self.rest != nil { self.bowl?.update(waiting: self.agents.waiting) }
            let target = announce ? s.flatMap { s in self.pets.first { $0.isVisible && $0.accepts(s.tool) } ?? self.pets.first } : nil
            self.pets.forEach { $0.agentsChanged(s, announce: $0 === target) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.synth.stop()
            KeySwitcher.shared.stop()
        }
        // F12: 켜 두었으면 감지 시작(권한 창은 띄우지 않음), 꺼져 있으면 비정상 종료 뒤 남은 Caps Lock 바꿈을 지운다
        KeySwitcher.shared.apply()
        KeySwitcher.cleanUpOnSignals()
        PerfSampler.shared.windows = { [weak self] in self?.pets.map(\.petWindow) ?? [] }
        PerfSampler.shared.update()   // --debug이고 기록이 켜져 있으면 바로 기록 시작
        for e in HookServer.drainSpool() { agents.apply(e, offline: true) }
        server = HookServer { [weak self] e in self?.agents.apply(e) }
        server?.start()

        // F8: 자리 비움 감지. 화면 잠금은 비공식 알림(앞으로 바뀌면 잠금 후 브리핑만 빠짐), 잠자기는 공식 알림.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.awayStart("lock") }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.awayEnd("lock") }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.awayStart("sleep") }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.awayEnd("sleep") }
    }

    func addPet() {
        spawn(id: UUID().uuidString)
        saveList()
    }

    private func spawn(id: String) {
        let index = counter
        counter += 1
        UserDefaults.standard.set(counter, forKey: "petCounter")
        let pet = PetController(id: id, index: index,
                                onAdd: { [weak self] in self?.addPet() },
                                onRemove: { [weak self] in self?.remove($0) })
        pet.agents = agents
        pet.onBowl = { [weak self] in self?.openBowl(from: $0) }
        pet.neighbors = { [weak self] in self?.pets ?? [] }
        pets.append(pet)
        pet.agentsChanged(nil, announce: false)
    }

    // MARK: 자리 비움 (F8)

    private var away = AwayState()

    private func awayStart(_ source: String) {
        if away.start(source) { pets.forEach { $0.leaveBriefing() } }
    }

    private func awayEnd(_ source: String) {
        if away.end(source) { pets.forEach { $0.collectBriefing() } }
    }

    // MARK: 싱잉볼 쉼 (F6)

    private var rest: RestSession?
    private var bowl: BowlWindow?
    private let synth = BowlSynth()
    private weak var restPet: PetController?

    /// 원형 메뉴 '싱잉볼' → 펫 옆 창을 열고 바로 쉼을 시작한다
    private func openBowl(from pet: PetController) {
        if let bowl { bowl.panel.orderFrontRegardless(); return }
        restPet = pet
        let a = pet.anchor
        let window = BowlWindow(nextTo: a.frame, in: a.visible,
                                onStop: { [weak self] in self?.endRest() },
                                onOpenList: { [weak self] in self?.listPet()?.openAgentList() })
        window.bowl.onStrike = { [weak self] in
            self?.synth.strike()
            self?.restPet?.bowlStruck()
        }
        window.bowl.onRub = { [weak self] in self?.synth.rub(angularSpeed: $0) }
        bowl = window
        pet.follow(window.panel)
        rest = RestSession(start: Date())
        do { try synth.start(); synth.volume = BowlSynth.userVolume } catch { window.showSoundError() }
        pets.forEach { $0.setResting(true); $0.dismissAlert() }
        awayStart("rest")
        window.update(waiting: agents.waiting)
    }

    /// 그만두기·Esc 모두 여기로
    private func endRest() {
        guard rest != nil else { bowl?.close(); bowl = nil; return }
        rest = nil
        pets.forEach { $0.setResting(false) }
        // 그만두면 끝 울림 없이 창을 바로 닫고 소리는 짧게 줄여 끈다(뚝 끊김 방지)
        bowl?.close()
        bowl = nil
        synth.fadeOutAndStop()
        // 쉼 중 보류는 알림을 막는 데만 쓰고, 그 사이 일은 브리핑(F8)이 보여 준다
        awayEnd("rest")
    }

    /// 쉼을 시작한 펫, 없으면(보냈거나 숨김) 첫 번째 보이는 펫
    private func listPet() -> PetController? {
        if let restPet, restPet.isVisible { return restPet }
        return pets.first { $0.isVisible } ?? pets.first
    }

    private func remove(_ pet: PetController) {
        pet.dismiss()
        pets.removeAll { $0 === pet }
        saveList()
    }

    private func saveList() { UserDefaults.standard.set(pets.map(\.id), forKey: "pets") }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Tasky")
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("새 깍지 부르기") { [weak self] in self?.addPet() })
        let sound = ClosureMenuItem("작업 알림음") {}
        sound.state = AlertCard.soundOn ? .on : .off
        sound.handler = { [weak sound] in
            AlertCard.soundOn.toggle()
            sound?.state = AlertCard.soundOn ? .on : .off
        }
        menu.addItem(sound)
        menu.addItem(ClosureMenuItem("깍지 모두 숨기기/보이기") { [weak self] in
            guard let self else { return }
            let show = !self.pets.contains { $0.isVisible }
            self.pets.forEach { $0.setVisible(show) }
        })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Tasky 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

/// 클로저로 동작하는 메뉴 항목
final class ClosureMenuItem: NSMenuItem {
    var handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

private extension NSScreen {
    var number: Int? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue }
}

/// 컴퓨터를 켤 때(로그인할 때) 함께 실행. 앱 번들이 아니라서 macOS 로그인 항목 API 대신
/// 사용자 LaunchAgent 파일로 처리한다.
/// shortcut: 지금 실행 파일 경로를 기록하므로 .build를 지우거나 옮기면 다시 켜야 한다, .app으로 포장하면 SMAppService로 바꾼다.
enum LoginItem {
    static let plist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.tasky.pet.plist")

    static var isOn: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func set(_ on: Bool) {
        if !on { try? FileManager.default.removeItem(at: plist); return }
        let dict: [String: Any] = [
            "Label": "com.tasky.pet",
            "ProgramArguments": [Bundle.main.executablePath ?? CommandLine.arguments[0]],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (dict as NSDictionary).write(to: plist, atomically: true)
    }
}
