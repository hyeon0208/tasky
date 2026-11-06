import AppKit
import EventKit
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
    private var petSize: CGSize { CGSize(width: 120 * scale, height: (petView.isSquare ? 120 : 84) * scale) }
    /// 콩깍지 몸 색. 펫 순서에 따라 민트·살구·라일락·크림(예전에 고른 색이 있으면 그 색). 색 고르기는 F11에서 숨김.
    private var bodyColor: NSColor {
        guard let c = UserDefaults.standard.array(forKey: key("rgb")) as? [Double], c.count == 3 else {
            return PetView.defaultColors[initialColor % PetView.defaultColors.count]
        }
        return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
    }
    /// 캐릭터 폴더 이름, "pod"는 콩깍지, "bear3d"는 3D 곰(기본, F18).
    private var characterName: String {
        get { "bear3d" }   // F28: 캐릭터는 테디(3D 곰) 하나만(사용자 결정 2026-11-06)
        set {
            UserDefaults.standard.removeObject(forKey: key("character"))
            applyCharacter()
            place(animated: false)
        }
    }
    private func applyCharacter() {
        let name = characterName
        petView.character = name == "bear3d" ? nil : Character(name: name)
        if name == "bear3d" { if petView.bear == nil { petView.bear = Pet3DView(frame: petView.bounds) } } else { petView.bear = nil }
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
    private var dragOrigin: CGPoint?   // 잡았을 때 펫 위치
    private var lastDragDelta = CGVector.zero
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

    private var drawer: FloatingPanel?
    private var drawerContent: DrawerController?
    private var hoverKeyTimer: Timer?

    private var dock: Dock = .free
    private var origin: CGPoint = .zero      // 자유 상태 위치(붙었을 때는 가장자리를 따라가는 좌표로 씀)
    private var screenID: Int?
    private var hoverWork: DispatchWorkItem?
    /// 지금 진행 중인 변환 수(작업 구슬용)
    private var convertingCount = 0 { didSet { updateBeads() } }

    /// `index`는 몇 번째 펫인지. 색과, 처음 놓일 자리를 조금씩 비키는 데 쓴다.
    init(id: String, index: Int) {
        self.id = id
        initialColor = index
        pet = FloatingPanel(size: CGSize(width: 120, height: 84))
        petView = PetView(frame: CGRect(origin: .zero, size: CGSize(width: 120, height: 84)))
        super.init()
        pet.contentView = petView
        petView.delegate = self
        petView.bodyColor = bodyColor
        applyCharacter()
        let menu = NSMenu()
        let alertsItem = NSMenuItem(title: "작업 알림 받기", action: nil, keyEquivalent: "")
        for (value, title) in Self.alertTools {
            let item = ClosureMenuItem(title) { [weak self] in self?.alertTool = value }
            item.representedObject = value
            alertsMenu.addItem(item)
        }
        alertsItem.submenu = alertsMenu
        // F27 피드백: 오른쪽 클릭 = 핵심 기능 메뉴(AI 작업 알림은 꺼 둠)
        for (title, run) in coreMenuItems() { menu.addItem(title.isEmpty ? .separator() : ClosureMenuItem(title) { DispatchQueue.main.async(execute: run) }) }
        if AgentFeature.enabled { menu.addItem(.separator()); menu.addItem(alertsItem) }
        petView.menu = menu
        restore(index: index)
        refreshAlertsMenu()
        place(animated: false)
        pet.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place(animated: true) }
        NotificationCenter.default.addObserver(forName: TaskStore.changedNote, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.updateTaskBadge()
            if self.standEvents.panel != nil, !TaskWindow.shared.isEditing { self.showStandEvents() }   // 체크·고친 결과를 목록에 반영
            if self.dock.isDocked, self.ring == nil, !self.hovering { self.place(animated: true) }   // 칩만큼 알약 길이가 바뀐다
        }
        // F26: 칩의 '다음 일정'·남은 수는 시간이 지나면 바뀐다(1분마다 다시 그림)
        chipTimer = Ticker.every("칩 시간 갱신", 60) { [weak self] _ in
            guard let self else { return }
            self.updateTaskBadge()
            if self.dock.isDocked, self.ring == nil, !self.hovering { self.place(animated: true) }
        }
        NotificationCenter.default.addObserver(forName: ClockMode.changed, object: nil, queue: .main) { [weak self] _ in
            self?.updateClock()
            self?.agentsChanged(nil, announce: false)   // 구슬 켜기·끄기도 같은 알림
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.updateBeads()   // 맨 앞 앱이 바뀌면 큰 구슬이 바뀐다
        }
        DispatchQueue.main.async { [weak self] in self?.updateClock() }
        lifeTimers = [
            Ticker.every("졸 시간인지 보기", 30) { [weak self] _ in
                guard let self, self.petView.base == .idle, Interaction.isSleepy(last: self.lastInteraction) else { return }
                self.petView.react(.sleepy)
            },
            Ticker.every("알약 시계 갱신", 15) { [weak self] _ in   // 펼친 알약의 분 단위 시계
                guard let self, let i = self.petView.island, i.expanded else { return }
                self.petView.island = self.islandContent(expanded: true)
            },
        ]
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
    var isDocked: Bool { dock.isDocked }

    // MARK: 위치

    /// 저장한 모니터가 없으면(분리됨) 주 화면의 같은 자리로.
    private var screen: NSScreen {
        NSScreen.screens.first { $0.number == screenID } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place(animated: Bool, out: CGFloat = 0) {
        let f: CGRect
        if dock.isDocked {   // F20: 붙으면 펫 창이 알약이 된다. 호버(out)·새 알림이면 펼침
            let expanded = out > 0 || alertOpen
            petView.island = islandContent(expanded: expanded)
            let c = CGPoint(x: origin.x + petSize.width / 2, y: origin.y + petSize.height / 2)
            f = Geometry.islandFrame(dock: dock, expanded: expanded, center: c, in: screen.visibleFrame, chips: GlanceChips.width(glance))
        } else {
            petView.island = nil
            f = Geometry.frame(size: petSize, origin: origin, dock: dock, in: screen.visibleFrame, out: out, body: petView.bodyUnit)
        }
        petView.mirrored = dock.mirrored
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup {
                $0.duration = dock.isDocked ? 0.2 : 0.22
                $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pet.animator().setFrame(f, display: true)
            }
        } else {
            pet.setFrame(f, display: true)
        }
        // 붙으면 시계·구슬은 알약 안에 있으므로 숨기고, 떨어지면 다시
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.25 : 0)) { [weak self] in self?.updateClock(); self?.updateBeads() }
    }

    /// 새 알림으로 잠깐 펼친 상태와 알약 테두리 색(커서를 올리면 지운다)
    private var alertOpen = false
    private var alertBorder: NSColor?
    private var alertOpenID = 0

    /// 알약 내용: 작업 색 점(급한 순 3개 + 나머지 수), 시계, 가장 급한 작업 한 줄
    private func islandContent(expanded: Bool) -> PetView.Island {
        let rank: [AgentSession.State: Int] = [.waiting: 0, .failed: 1, .done: 2, .working: 3]
        let shown = (agents?.ordered ?? []).filter { accepts($0.tool) && ($0.state != .done || !$0.seen) }
            .sorted { rank[$0.state]! < rank[$1.state]! }
        var i = PetView.Island(vertical: dock != .bottom && dock != .top, expanded: expanded, dots: shown.prefix(3).map { $0.state.color },
                               extra: max(shown.count - 3, 0), clock: ClockMode.text(Date(), seconds: false), border: alertBorder)
        i.glance = glance
        i.dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tasks = pendingTasks
        i.rows = Array((tasks.map(\.title) + (i.glance.next.isEmpty ? [] : [i.glance.next])).prefix(3))
        // F27: '끝남' 같은 문구는 알약에 넣지 않는다. 허락 기다림만 한 줄로, 나머지는 할 일 요약
        if let top = shown.first, top.state == .waiting {
            i.line = "\(top.shortName) 허락을 기다려요"
            i.lineColor = top.state.color
        } else {
            i.line = tasks.isEmpty ? "오늘 할 일을 다 했어요" : "할 일 \(tasks.count)개 남았어요"
            i.lineColor = tasks.isEmpty ? .secondaryLabelColor : .systemOrange
        }
        return i
    }

    func petDragged(by delta: CGVector) {
        closeRing()
        if petView.base != .drag {
            touched()
            stopMoving()   // 던지기·걷기 중에 잡으면 그 자리에서 멈춘다
            tossID += 1
            petView.react(.drag)
            if dock.isDocked {   // 알약을 잡으면 보통 펫 크기로 돌아와 커서 아래에 온다
                TodayCard.shared.close()   // 알약 기준으로 놓인 카드는 닫는다
                dock = .free
                hoverWork?.cancel()
                petView.island = nil
                let m = NSEvent.mouseLocation, s = petSize
                stopMoving()   // 펼침 애니메이션이 돌고 있으면 멈춘다
                pet.setFrame(CGRect(x: m.x - s.width / 2, y: m.y - s.height / 2, width: s.width, height: s.height), display: true)
                dragOrigin = CGPoint(x: pet.frame.minX - delta.dx, y: pet.frame.minY - delta.dy)
                lastDragDelta = .zero
            }
        }
        if dragOrigin == nil { dragOrigin = pet.frame.origin; lastDragDelta = .zero }
        let step = CGVector(dx: delta.dx - lastDragDelta.dx, dy: delta.dy - lastDragDelta.dy)
        lastDragDelta = delta
        let now = Date()
        if let last = lastDragTime, now.timeIntervalSince(last) > 0 {
            let dt = now.timeIntervalSince(last)
            // 최근 움직임에 무게를 둔 속도(pt/s)
            dragVelocity = CGVector(dx: dragVelocity.dx * 0.5 + step.dx / dt * 0.5, dy: dragVelocity.dy * 0.5 + step.dy / dt * 0.5)
        }
        lastDragTime = now
        var f = pet.frame
        f.origin = CGPoint(x: dragOrigin!.x + delta.dx, y: dragOrigin!.y + delta.dy)   // 커서가 잡은 자리에 붙어 있게
        pet.setFrame(f, display: true)
    }

    func petDragEnded() {
        dragOrigin = nil
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
        // 받침대 구슬로 커서를 옮기는 중이면 아직 '봤다'로 치지 않는다(구슬을 누를 수 있게)
        if inside { touched() } else if !(stand?.panel.frame.contains(NSEvent.mouseLocation) ?? false) { seeAgents() }   // 올렸다 떼면 '봤다'(올린 동안은 구슬을 누를 수 있게 남김)
        scheduleHoverRing(inside)
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
        if inside { alertBorder = nil }
        if inside {
            let work = DispatchWorkItem { [weak self] in self?.place(animated: true, out: 1) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            // 오른쪽·위에 붙은 알약은 펼칠 때 창이 커서 쪽으로 옮겨 가며 나갔다 들어온 신호가 잘못 올 수 있다.
            // 잠깐 기다렸다 커서가 정말 알약 밖일 때만 접는다(안 그러면 펼침·접힘이 반복됨).
            collapseWhenOutside()
        }
    }

    /// 커서가 알약 밖으로 나갈 때까지 0.25초마다 보고 접는다(다시 들어온 신호가 오면 취소됨)
    private func collapseWhenOutside() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dock.isDocked, self.ring == nil, self.drawer == nil else { return }
            if self.pet.frame.contains(NSEvent.mouseLocation) { self.collapseWhenOutside(); return }
            self.place(animated: true)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func togglePeek() {
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

    private(set) var briefing = Briefing()
    /// 이 펫에서 끝난 변환(시각, 결과). 브리핑에 쓴다. 최근 50개.
    private var conversions: [(Date, [URL])] = []
    private var briefingWindow: BriefingWindow?

    func leaveBriefing() { briefing.leave() }

    /// 돌아옴: 이 펫이 받는 도구의 작업과 이 펫의 변환만 모은다. 새로 생기면 손을 흔든다.
    func collectBriefing() {
        let sessions = (agents?.ordered ?? []).filter { accepts($0.tool) }
        if briefing.collect(sessions: sessions, conversions: conversions) > 0, pet.isVisible { petView.react(.briefing) }
    }

    func openBriefing() {
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

    /// 몸 안 콩알은 이 펫이 받는 도구의 작업만 보여준다. 말풍선·알림음은 `announce`일 때만.
    func agentsChanged(_ s: AgentSession?, announce: Bool) {
        guard let agents else { return }
        petView.beans = []   // F26: 구슬 대신 머리 위 칩
        updateBeads()
        updateTaskBadge()
        agentList?.reload()
        if dock.isDocked, ring == nil, !hovering { place(animated: true) } else if let i = petView.island { petView.island = islandContent(expanded: i.expanded) }
        // AI 작업 기능이 꺼져 있으면 곰도 반응하지 않는다(짧은 답마다 '끝남' 반응하던 것)
        guard AgentFeature.enabled, announce, let s, pet.isVisible || App.petsHidden, s.state != .working else { return }
        petView.react(s.state == .waiting ? .jobWaiting : s.state == .failed ? .jobFailed : .jobDone)
        // F27: 패널은 승인이 필요할 때만. 끝남·실패는 상태 구슬과 작업 목록에서 본다
        guard AgentAlert.showsPanel(s.state) else { return }
        if dock.isDocked, pet.isVisible {   // 알약: 상태 색 테두리 + 3초 펼침
            alertBorder = s.state.color
            alertOpen = true
            alertOpenID += 1
            let id = alertOpenID
            place(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.alertOpenID == id else { return }
                self.alertOpen = false
                if !self.hovering, self.dock.isDocked, self.ring == nil, self.drawer == nil { self.place(animated: true) }
            }
        }
        var title = "\(s.shortName) 작업이 허락을 기다려요"
        if s.whileOff { title += " (펫이 꺼져 있던 동안)" }
        presentAlert(s, title: title, body: s.ask ?? "터미널에서 승인하거나 답해 주세요.")
    }

    private func presentAlert(_ s: AgentSession, title: String, body: String?) {
        var actions: [AlertCard.Action] = []
        if let app = s.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            actions.append(.init(title: "터미널로 가기") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) })
        }
        actions.append(.init(title: "목록 보기") { [weak self] in self?.openAgentList() })
        // 알약이면 펼친 알약을 피해서(옆 알약은 옆에)
        // F26: 메뉴 막대만 쓰면 상태 칸 아래에
        if !pet.isVisible, let bar = App.menuBarAnchor() {
            alertCard.show(session: s, title: title, body: body, actions: actions, near: bar.frame, in: bar.visible)
            return
        }
        let v = screen.visibleFrame, c = CGPoint(x: pet.frame.midX, y: pet.frame.midY)
        let near = dock.isDocked ? Geometry.islandFrame(dock: dock, expanded: true, center: c, in: v) : pet.frame
        let side: CGFloat = !dock.isDocked || dock == .top || dock == .bottom ? 0 : dock.mirrored ? 1 : -1
        alertCard.show(session: s, title: title, body: body, actions: actions, near: near, in: v, beside: side)
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

    /// 클립보드에 새로 복사됨: 잠깐 받아 드는 반응 + 앞부분 쪽지
    func copied(_ item: ClipItem) {
        guard UserDefaults.standard.object(forKey: "clipReact") as? Bool ?? true else { return }
        petView.react(.fileNear)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if let self, self.petView.base == .fileNear { self.petView.react(self.calm) }
        }
        let p = item.preview
        say("📋 " + (p.count > 20 ? String(p.prefix(20)) + "…" : p), seconds: 1.5)
    }

    // MARK: 시계 말풍선 (시안 '커서 올리면 말풍선', 초 단위)

    private var hovering = false

    // MARK: 받침대 (F27 1번: 곰 발밑 유리 받침 — 시계·할 일·다음 일정·상태 구슬)

    private var stand: (panel: FloatingPanel, view: StandView, timer: Timer)?
    /// 가장 급한 작업 상태(구슬 색). 받침대가 숨어 있어도 기억한다
    private var agentState: AgentSession.State?

    /// 받침대를 보일지: 설정 '알림 디스플레이 보기' — 항상 / 갖다대면(곰이나 받침대 위에 커서) / 안 봄
    /// 오늘 카드가 받침대 자리에서 열려 있는 동안 숨김
    private var standHidden = false

    private func updateClock() {
        if standHidden { return }
        if ring != nil { hideClock(); return }   // 원형 메뉴가 열려 있으면 받침대는 숨긴다(아래 칸과 겹침)
        let overStand = (stand.map { $0.panel.frame.contains(NSEvent.mouseLocation) } ?? false) || (standEvents.panel?.frame.contains(NSEvent.mouseLocation) ?? false)
        let show = pet.isVisible && !dock.isDocked && (ClockMode.current == .always || (ClockMode.current == .hover && (hovering || overStand)))
        guard show else { hideClock(); return }
        if stand == nil { showClock() }
        updateTaskBadge()
    }

    private func showClock() {
        let panel = FloatingPanel(size: CGSize(width: 200, height: StandView.height))
        let view = StandView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.orb.onClick = { [weak self] in self?.openBadgeSession() }
        view.onEnter = { [weak self] in self?.showStandEvents() }
        view.onExit = { [weak self] in
            guard let self else { return }
            self.hideStandEventsIfOutside()
            if !self.hovering { self.seeAgents() }
            self.updateClock()
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        follow(panel)
        // 다음 초가 바뀌는 순간에 맞춰 1초마다(늦게 바뀌어 보이지 않게)
        let timer = Ticker.every("시계 초 넘기기", 1, from: Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970))) { [weak view] _ in
            view?.clock = ClockMode.text(Date())
        }
        stand = (panel, view, timer)
    }

    // MARK: 남은 할 일 (F24)

    private var chipTimer: Timer?
    deinit { chipTimer?.invalidate() }
    private var pendingTasks: [TaskItem] { TaskStore.anyOn ? TaskLogic.pending(TaskStore.shared.items, now: Date()) : [] }
    /// F26: 칩 내용(남은 할 일·다음 일정·작업 점)
    private var glance: Glance {
        Glance.make(items: TaskStore.anyOn ? TaskStore.shared.items : [], tasksOn: TaskStore.anyOn,
                    states: (agents?.ordered ?? []).filter { accepts($0.tool) && ($0.state != .done || !$0.seen) }.map(\.state), now: Date())
    }

    /// 곰을 누르거나 올렸다 떼면 끝난 작업을 본 것으로 친다(F26 6차). 내 차례·실패는 남는다
    private func seeAgents() {
        guard let agents, agentState != nil else { return }
        agents.markSeen(accepts); updateTaskBadge()
    }

    /// 구슬 누르기: 가장 급한 작업의 터미널을 앞으로
    private func openBadgeSession() {
        guard let agents, let st = agentState,
              let s = agents.ordered.first(where: { accepts($0.tool) && $0.state == st && ($0.state != .done || !$0.seen) }) else { return }
        if let app = s.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        agents.markSeen(accepts); updateTaskBadge()
    }

    /// 받침대 내용과 자리
    private func updateTaskBadge() {
        let g = glance
        agentState = AgentFeature.enabled ? g.dots.first : nil
        guard let (panel, view) = stand.map({ ($0.panel, $0.view) }) else { return }
        view.clock = ClockMode.text(Date())
        view.glance = g
        view.orb.state = agentState
        panel.ignoresMouseEvents = false   // 커서를 올리면 오늘 남은 일정 목록(곰 아래라 곰을 가리지 않음)
        let size = view.fittingSize
        let body = bodyFrame, v = screen.visibleFrame
        let shown = body.intersection(v).isNull ? body : body.intersection(v)
        let y = max(v.minY, shown.minY - size.height - 2)   // 곰 바로 아래(곰 클릭·드롭을 가리지 않게)
        panel.setFrame(CGRect(x: min(max(shown.midX - size.width / 2, v.minX + 4), v.maxX - size.width - 4),
                              y: y, width: size.width, height: size.height), display: true)
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
        guard BeadsSetting.on, pet.isVisible, !dock.isDocked, let agents else { hideBeads(); return }
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
        let top = shown.maxY + 2
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: min(max(shown.midX - size.width / 2, v.minX), v.maxX - size.width),
                                     y: min(top - BeadsView.labelHeight + 2, v.maxY - size.height)))
    }

    private func placeClock() { updateTaskBadge() }

    /// F28 11차 B: 받침대 아래 오늘 남은 일정 목록
    private let standEvents = StandEvents()
    private func showStandEvents() {
        guard let stand else { return }
        let now = Date(), end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let list = TaskStore.anyOn ? TaskLogic.upcomingEvents(TaskStore.shared.items, now: now, days: 1).filter { $0.hasTime && ($0.date ?? end) < end } : []
        let todos = TaskStore.anyOn ? TaskLogic.pending(TaskStore.shared.items, now: now) : []
        standEvents.show(list, todos: todos, below: stand.panel.frame, parent: pet) { [weak self] in self?.hideStandEventsIfOutside(); self?.updateClock() }
    }
    private func hideStandEventsIfOutside() {
        let m = NSEvent.mouseLocation
        if stand?.panel.frame.contains(m) == true || standEvents.panel?.frame.contains(m) == true || TaskWindow.shared.isEditing { return }
        standEvents.hide()
    }

    private func hideClock() {
        standEvents.hide()
        guard let stand else { return }
        stand.timer.invalidate()
        stand.panel.orderOut(nil)
        self.stand = nil
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
        agents.markSeen(accepts)
        updateTaskBadge()
        petView.beans = []
        updateBeads()
        agentClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.closeAgentList() }
    }

    private func closeAgentList() {
        if let m = agentClickMonitor { NSEvent.removeMonitor(m); agentClickMonitor = nil }
        agentPanel?.orderOut(nil)
        agentPanel = nil
        agentList = nil
    }

    /// F27 피드백: 두 번 누르기 → 오늘 카드(빠른 실행은 원형 메뉴·단축키로)
    func petDoubleClicked() {
        hoverRingWork?.cancel()
        touched()
        stopMoving()
        closeRing()
        petView.react(.click)
        if petView.island?.expanded == true { place(animated: false) }
        openToday()
    }

    /// 오른쪽 클릭 메뉴: 자주 쓰는 기능("" = 구분선)
    private func coreMenuItems() -> [(String, () -> Void)] {
        [("오늘 카드", { [weak self] in self?.openToday() }),
         ("빠른 실행", { [weak self] in self?.openQuickRun() }),
         ("할 일 창", { TaskWindow.shared.open() }),
         ("", {}),
         ("폴더 서랍", { [weak self] in self?.openDrawer(pinned: false) }),
         ("오늘 찍은 캡처", { [weak self] in self?.openCaptureStrip() }),
         ("영역 캡처", { Capture.shared.take(.area) }),
         ("클립보드 기록", { ClipWindow.shared.open() }),
         ("", {}),
         ("잠 안 자기 켜기·끄기", { Awake.shared.isOn ? Awake.shared.stop() : Awake.shared.start(minutes: Awake.minutes) }),
         ("빼꼼", { [weak self] in self?.togglePeek() }),
         ("설정…", { [weak self] in self?.openSettings() })]
    }

    /// F27 10번: 원형 메뉴 '캡처' — 오늘 찍은 캡처 띠
    func openCaptureStrip() { CaptureStrip.shared.toggle(near: bodyFrame, in: screen.visibleFrame) }

    /// 빠른 실행(4단계에서 명령 바). 그 전까지는 한 줄 입력이 있는 할 일 창을 연다.
    func openQuickRun() { QuickRunWindow.shared.open() }

    func petClicked() {
        seeAgents()
        hoverRingWork?.cancel()
        drawerOutsideClick()   // 펫을 눌러도 바깥 클릭처럼 닫는다(끌기는 닫지 않고 함께 움직임)
        touched()
        stopMoving()
        if petView.showsCharacter, pokes.poke() { closeRing(); petView.react(.sulk); return }
        if ring != nil { closeRing(); return }   // 다시 누르면 닫기
        petView.react(.click)
        if petView.island?.expanded == true { place(animated: false) }
        TodayCard.shared.close()
        openRing(slots: mainSlots, acceptsFiles: false)   // F27 피드백: 한 번 누르기 = 원형 메뉴
    }

    /// F26: 한 번 누르기 = 오늘 카드. 꺼내 둔 곰은 아래에, 펫을 옮기면 따라온다
    private func openToday() {
        TodayCard.shared.showsAgents = AgentFeature.enabled
        TodayCard.shared.agentRows = { [weak self] in
            guard let self, let agents = self.agents else { return [] }
            let rank: [AgentSession.State: Int] = [.waiting: 0, .failed: 1, .working: 2, .done: 3]
            return agents.ordered.filter { self.accepts($0.tool) && ($0.state != .done || !$0.seen) }
                .sorted { rank[$0.state]! < rank[$1.state]! }
                .map { ($0.shortName, $0.state == .waiting ? "허락 기다림" : $0.state == .failed ? "실패" : $0.state == .working ? "하는 중" : "끝남", $0.state.color) }
        }
        TodayCard.shared.onOpenAgents = { [weak self] in self?.openAgentList() }
        TodayCard.shared.onOpenSettings = { [weak self] in self?.openSettings() }   // 누른 펫의 설정
        TodayCard.shared.footer = [("설정", { [weak self] in self?.openSettings() })]
        // F27 10차 A+F: 받침대가 있으면 그 자리에서 카드로 자라나고, 열린 동안 받침대는 숨긴다
        if TodayCard.shared.isOpen { TodayCard.shared.close(); return }
        if stand == nil, dock == .free, pet.isVisible { showClock(); updateTaskBadge() }
        let from = dock == .free ? stand?.panel.frame : nil
        TodayCard.shared.onClose = { [weak self] in self?.standHidden = false; self?.updateClock() }
        TodayCard.shared.open(near: { [weak self] in self?.bodyFrame ?? .zero }, in: screen.visibleFrame, below: dock == .free, parent: pet, growFrom: from)
        if from != nil { standHidden = true; stand?.panel.orderOut(nil) }
    }

    /// F27 3번 A: 반원 6칸(오늘 카드·빠른 실행·폴더 서랍·캡처·작업 목록·잠 안 자기). 이름표는 가리킨 칸 하나만.
    /// 빼꼼·그 사이 소식·설정은 메뉴 막대에서.
    private var mainSlots: [Slot] {
        let waitingCount = agents?.waiting ?? 0
        let slots = [
            Slot(title: pendingTasks.isEmpty ? "오늘 카드" : "오늘 카드 · 할 일 \(pendingTasks.count)", symbol: "sun.max.fill", badge: pendingTasks.isEmpty ? nil : pendingTasks.count, id: "today", color: .systemOrange) { [weak self] in self?.openToday() },
            Slot(title: "빠른 실행", symbol: "bolt.fill", id: "quickrun", color: .systemYellow) { [weak self] in self?.openQuickRun() },
            Slot(title: "폴더 서랍", symbol: "folder.fill", id: "drawer", color: .systemBlue) { [weak self] in self?.openDrawer(pinned: false) },
            Slot(title: "캡처", symbol: "camera.viewfinder", id: "capture", color: .systemPink) { [weak self] in self?.openCaptureStrip() },
            Slot(title: Awake.shared.isOn ? "잠 안 자기 켜짐" : "잠 안 자기", symbol: "cup.and.saucer.fill", id: "awake", color: .systemBrown) {
                Awake.shared.isOn ? Awake.shared.stop() : Awake.shared.start(minutes: Awake.minutes)
            },
            Slot(title: "설정", symbol: "gearshape.fill", id: "settings", color: .systemGray) { [weak self] in self?.openSettings() },
        ] + (AgentFeature.enabled ? [Slot(title: "작업 목록", symbol: "terminal", badge: waitingCount > 0 ? waitingCount : nil, id: "agents", color: .systemGreen) { [weak self] in self?.openAgentList() }] : [])
        // F21: 사용자가 옮긴 순서
        let order = RingOrder.apply(saved: UserDefaults.standard.stringArray(forKey: RingOrder.key) ?? [], ids: slots.map(\.id))
        return order.compactMap { id in slots.first { $0.id == id } }
    }

    /// 다른 패널 창(오늘 카드·서랍·알림 등)이 차지한 자리. 원형 메뉴가 피한다
    private var occupiedFrames: [CGRect] {
        let mine: [NSWindow?] = [pet, stand?.panel, ring]
        return NSApp.windows.filter { w in w.isVisible && w.level >= .floating && w.frame.width > 60 && !mine.contains { $0 === w } }.map(\.frame)
    }

    /// F26: 마우스를 올리고 0.35초 머물면 원형 메뉴(포커스를 뺏지 않는 링, 커서가 떠나면 닫힘)
    private var hoverRingWork: DispatchWorkItem?
    static let hoverDelay = 0.35
    /// F27 피드백: 원형 메뉴는 누를 때만(올려서 열기는 끔, 코드는 남김)
    static let hoverRingOn = false
    private var hoverRingTimer: Timer?
    private func scheduleHoverRing(_ inside: Bool) {
        hoverRingWork?.cancel()
        guard Self.hoverRingOn, inside, ring == nil, drawer == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering, self.ring == nil, self.drawer == nil, self.dragOrigin == nil,
                  NSEvent.pressedMouseButtons == 0, self.petView.base != .drag else { return }
            self.openRing(slots: self.mainSlots, acceptsFiles: false, byHover: true)
        }
        hoverRingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    private func openRing(slots: [Slot], acceptsFiles: Bool, byHover: Bool = false) {
        closeRing()
        hoverWork?.cancel()
        hideClock()
        if petView.island?.expanded == true { place(animated: false) }   // 펼친 알약에서 열면 먼저 접는다(링은 접힌 알약 기준)
        let v = screen.visibleFrame
        let body = bodyFrame
        let center = Geometry.visibleCenter(of: body, in: v)
        let bodySize = max(body.width, body.height)
        var roomAbove = v.maxY - center.y > 96 + max(0, bodySize - 80) * 0.6 + 40
        var points = Geometry.slotCenters(count: slots.count, dock: dock, center: center, size: bodySize, roomAbove: roomAbove)
        var labelBelow = roomAbove   // 이름표 하나: 칸이 위면 몸 아래, 아니면 몸 위
        if dock == .free {
            // F27: 다른 패널과 겹치지 않는 쪽(위·아래·왼쪽·오른쪽)으로 반원을 편다
            let radius = 96 + max(0, Double(bodySize) - 80) * 0.6
            let base = Geometry.ringDirection(center: center, radius: radius, in: v, occupied: occupiedFrames, preferUp: roomAbove)
            points = Geometry.halfRing(count: slots.count, center: center, radius: radius, base: base)
            roomAbove = base == 90
            labelBelow = base != 270
        }
        if petView.island != nil {   // 알약: 접힌 알약 안쪽으로 한 겹 부채꼴
            roomAbove = false
            points = Geometry.fanCenters(count: slots.count, dock: dock, pill: body)
        }
        let pad: CGFloat = 70
        let xs = points.map(\.x) + [center.x], ys = points.map(\.y) + [center.y, body.minY - 40, body.maxY + 40]   // 펫 아래·위 이름표 자리
        let rect = CGRect(x: xs.min()! - pad, y: ys.min()! - pad,
                          width: xs.max()! - xs.min()! + pad * 2, height: ys.max()! - ys.min()! + pad * 2)

        let panel = FloatingPanel(size: rect.size)
        panel.keyable = !acceptsFiles   // 끌기 중에는 키 창을 바꾸지 않는다
        panel.delegate = self
        panel.setFrame(rect, display: false)
        let view = RingView(frame: CGRect(origin: .zero, size: rect.size))
        view.slots = slots
        view.alwaysLabels = false   // F27: 이름표는 가리킨 칸 하나만, 한 곳에
        view.origin = CGPoint(x: center.x - rect.minX, y: center.y - rect.minY)
        if dock == .free { view.labelTop = labelBelow ? body.minY - rect.minY - 8 : body.maxY - rect.minY + 34 }
        view.centers = points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
        view.acceptsFiles = acceptsFiles
        view.onClose = { [weak self] in self?.closeRing() }
        if !acceptsFiles { view.onReorder = { UserDefaults.standard.set($0, forKey: RingOrder.key) } }
        panel.contentView = view
        if acceptsFiles {
            panel.orderFrontRegardless()
            // 칸이 아닌 곳에 놓거나 끌기를 취소하면 링을 닫는다
            dragEndTimer = Ticker.every("파일 끌기 끝났는지 보기", 0.2) { [weak self] _ in
                if NSEvent.pressedMouseButtons == 0 { self?.closeRing() }
            }
        } else if byHover {
            // 올려서 연 링은 키 창이 되지 않는다(쓰던 앱의 입력을 뺏지 않게). 커서가 링·펫 밖으로 나가면 닫는다.
            panel.keyable = false
            panel.orderFrontRegardless()
            hoverRingTimer = Ticker.every("올려서 연 링 닫기", 0.2) { [weak self] _ in
                guard let self, let ring = self.ring else { return }
                let m = NSEvent.mouseLocation
                if !ring.frame.insetBy(dx: -8, dy: -8).contains(m), !self.pet.frame.contains(m) { self.closeRing() }
            }
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closeRing()
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
        hoverRingTimer?.invalidate()
        hoverRingTimer = nil
        if petView.base == .fileNear { petView.react(calm) }
        guard let panel = ring else { return }
        ring = nil
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel.delegate = nil
        panel.orderOut(nil)
        if dock.isDocked, !pet.frame.contains(NSEvent.mouseLocation) { place(animated: true) }
        updateClock()
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
        closeRing()
        // F27: 원형 변환 — 곰 위에 둥근 칸
        let center = Geometry.visibleCenter(of: bodyFrame, in: screen.visibleFrame)
        wheel.open(items: convertItems(for: urls), files: urls, center: center, in: screen.visibleFrame) { [weak self] in
            self?.say("둘레의 칸 위에 놓아 주세요")
        }
        petView.react(.fileNear)
    }

    func petFilesDroppedOnBody() {
        wheel.close()
        say("둘레의 칸 위에 놓아 주세요")
    }

    private let wheel = ConvertWheel()

    private func convertItems(for urls: [URL]) -> [WheelItem] {
        var items = ConvertOp.options(for: urls).map { op in
            WheelItem(title: op.short, note: op.note, isFormat: op.isFormat, detail: op.title + "\n원본은 그대로") { [weak self] in self?.convert(op, urls) }
        }
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if !folders.isEmpty, folders.count == urls.count {
            items.append(WheelItem(title: "서랍에 저장", isFormat: false, detail: "고정 폴더로") { [weak self] in
                let reasons = folders.compactMap { DrawerStore.shared.add($0) }
                self?.wheel.close()
                self?.say(reasons.first ?? "서랍에 넣었어요")
            })
        }
        if items.count <= 1, ConvertOp.options(for: urls) == [.zip] {
            items.insert(WheelItem(title: "다른 변환 없음", isFormat: false, detail: "이 형식은 아직 못 바꿔요") { [weak self] in self?.wheel.close() }, at: 0)
        }
        return items
    }

    private func convert(_ op: ConvertOp, _ urls: [URL]) {
        var use = UserDefaults.standard.dictionary(forKey: "convertUse") as? [String: Int] ?? [:]
        use[op.rawValue, default: 0] += 1
        UserDefaults.standard.set(use, forKey: "convertUse")

        say("\(op.title) 바꾸는 중… (\(urls.count)개)")
        wheel.showWorking(op.short)
        petView.react(.converting)
        convertingCount += 1
        Converter.run(op, urls) { [weak self] outputs, errors in
            guard let self else { return }
            if self.wheel.isWorking { self.wheel.close() }   // 그 사이 새로 연 원은 닫지 않는다
            self.convertingCount -= 1
            if self.petView.base == .converting { self.petView.react(self.calm) }
            if !outputs.isEmpty {
                self.conversions = Array((self.conversions + [(Date(), outputs)]).suffix(50))
            }
            if errors.isEmpty {
                self.petView.react(.converted)
                self.say("다 바꿨어요. 원본 옆에 ‘(깍지)’로 저장했어요")
            } else {
                self.say(outputs.isEmpty ? errors[0] : "\(outputs.count)개 성공, \(errors.count)개 실패: \(errors[0])", seconds: 4)
            }
        }
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

    /// 메뉴 막대에서: 펫이 숨어 있어도 연다(화면 가운데)
    func openSettingsFromMenu() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

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
        func check(_ on: Bool, _ toggle: @escaping (Bool) -> Void) -> NSView { SettingsTabs.toggle(on, toggle) }
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
                repeatDemo.restart()
            }
            slider.target = handler
            slider.action = #selector(ClosureButton.performClick(_:))
            settingsKeepAlive.append(handler)
            let row = NSStackView(views: [hint("빠름"), slider, hint("느림"), ms])
            row.spacing = 6
            return row
        }
        let repeatDemo = KeyRepeatDemo(frame: CGRect(x: 0, y: 0, width: 360, height: 54))
        settingsKeepAlive.append(repeatDemo)
        let initialRow = repeatRow(KeyRepeat.initial), rateRow = repeatRow(KeyRepeat.rate)
        let restoreButton = ClosureButton("처음 값으로") { [weak self] in
            KeyRepeat.restore()
            self?.closeSettings()   // 슬라이더를 되돌린 값으로 다시 그리도록 닫는다
        }
        let keyTest = KeyTestField()
        settingsKeepAlive.append(keyTest)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드"
        func link(_ title: String, _ url: String) -> NSView {
            let b = ClosureButton(title) { NSWorkspace.shared.open(URL(string: url)!) }
            b.bezelStyle = .inline
            return b
        }
        func permission(_ on: Bool) -> NSTextField {
            let t = NSTextField(labelWithString: on ? "허용됨" : "허용 안 됨")
            t.textColor = on ? .systemGreen : .secondaryLabelColor
            return t
        }
        let tabs = [
            SettingsTab(id: "general", title: "일반", symbol: "gearshape", content: SettingsTabs.grid([(nil, [
                [label("로그인할 때 Tasky 열기"), check(LoginItem.isOn) { LoginItem.set($0) }],
                [label("원형 메뉴 버튼 투명도"), glassRow, hint("곰을 한 번 누르면 나오는 반원 메뉴 버튼이에요. 투명할수록 뒤 화면이 비쳐요.")],
                [NSView(), ringPreview],
                [label("폴더 서랍 바로 열기"),
                 popup(Self.drawerKeys.map(\.title), selected: Self.drawerKeys.firstIndex { $0.id == UserDefaults.standard.string(forKey: "drawerKey") } ?? 0) {
                     UserDefaults.standard.set(Self.drawerKeys[$0].id, forKey: "drawerKey") }],
                [NSView(), hint("이 키를 누른 채 곰에 커서를 올리면 자주 가는 폴더 서랍이 열려요. 파일을 끌고 올 때 이 키를 누르고 있으면 서랍에 바로 넣을 수 있어요.")],
                // F26: 싱잉볼은 꺼 둠(원형 메뉴에서도 뺐다) — 소리 크기 설정도 숨긴다
                [label("보이는 방식"), popup(["곰과 알약", "메뉴 막대만"], selected: App.petsHidden ? 1 : 0) { App.petsHidden = $0 == 1 },
                 hint("메뉴 막대만: 곰을 숨기고 화면 맨 위 메뉴 막대에 할 일 수·다음 일정을 보여 줘요. 기능은 메뉴 막대 아이콘에서 써요.")],
                [label("펫 움직임 끄기"), check(Pet3DView.still) { Pet3DView.still = $0 }, hint("3D 곰이 가만히 멈춰 CPU를 아껴요")],
                [label("원형 메뉴 순서"), ClosureButton("처음대로") { UserDefaults.standard.removeObject(forKey: RingOrder.key) },
                 hint("칸을 0.3초 꾹 눌러 들고 옮길 수 있어요")],
                [label("알림 디스플레이 보기"), popup(ClockMode.allCases.map(\.title), selected: ClockMode.allCases.firstIndex(of: .current) ?? 0) {
                    ClockMode.current = ClockMode.allCases[$0] }],
                [NSView(), hint("곰 발밑 유리 받침대(시계·남은 할 일·다음 일정)를 언제 보일지예요. 갖다대면: 곰에 커서를 올렸을 때만. 곰을 두 번 누르면 받침대가 오늘 카드로 커져요.")],
                [label("24시간제로 보기"), check(ClockMode.hour24) { ClockMode.hour24 = $0 }],
                // F26: 작업 구슬은 꺼 둠(머리 위 칩으로 대신): 펫 위에 작업 구슬 설정
                [label("초까지 보기"), check(ClockMode.showSeconds) { ClockMode.showSeconds = $0 }],
            ])])),
            SettingsTab(id: "pet", title: "펫", symbol: "pawprint", content: SettingsTabs.grid([("이 펫에만 적용 — 펫이 여러 마리면 지금 연 펫만 바뀌어요", [
                [label("크기"), sizeRow],
            ] + (AgentFeature.enabled ? [
                [label("이 펫이 알려 줄 작업"),
                 popup(Self.alertTools.map(\.1), selected: Self.alertTools.firstIndex { $0.0 == alertTool } ?? 0) { [weak self] in
                     self?.alertTool = Self.alertTools[$0].0 }],
            ] : []))])),
            // F27 피드백: AI 작업 기능은 꺼 둠(코드는 남김)
            SettingsTab(id: "alerts", title: "작업 알림", symbol: "bell", content: SettingsTabs.grid([(nil, [
                [label("알림 소리"), check(AlertCard.soundOn) { AlertCard.soundOn = $0 }],
                [label("Claude Code 연결"), toolButtons[0], hint("내 승인이 필요할 때만 펫이 알려요. 끝남·실패는 받침대의 상태 구슬(곰에 커서를 올리면 보임)과 메뉴 막대 '작업 목록'에서 봐요.")],
                [label("Codex 연결"), toolButtons[1], hint("내 승인이 필요할 때만 펫이 알려요. 끝남·실패는 곰의 상태 구슬과 메뉴 막대 '작업 목록'에서 봐요.")],
            ])])),
            SettingsTab(id: "keyboard", title: "키보드", symbol: "keyboard", content: SettingsTabs.grid([
                ("여기서 쳐 보기", [[NSView(), keyTest]]),
                ("한영 전환", [
                [label("한 키로 한영 바꾸기"), check(KeySwitcher.enabled) { on in
                    KeySwitcher.enabled = on
                    KeySwitcher.shared.apply(ask: on)
                    refreshKeyboard()
                }],
                [label("쓸 키"), popup(SwitchKey.allCases.map(\.title), selected: SwitchKey.allCases.firstIndex(of: KeySwitcher.key) ?? 0) {
                    KeySwitcher.key = SwitchKey.allCases[$0]
                    KeySwitcher.shared.apply()
                    refreshKeyboard()
                }],
                [NSView(), kbStatusRow],
                [NSView(), hint("Caps Lock: 짧게 누르면 한/영, 0.5초 꾹 누르면 대문자 고정. 누르는 순간 바뀌어서 빠르게 쳐도 씹히지 않아요(손쉬운 사용 권한이 켜져 있으면 바뀐 뒤에 다음 글자가 들어가요). 다른 한영 전환 앱과 함께 켜 두면 서로 부딪혀요.")],
                ]), ("키 반복", [
                [label("꾹 누르고 반복이 시작될 때까지"), initialRow],
                [NSView(), hint("키(예: ㅋ, ←, ⌫)를 누른 채로 있을 때, 두 번째 글자가 나오기까지 기다리는 시간이에요. 짧을수록 꾹 누르자마자 반복돼요.")],
                [label("반복 빠르기"), rateRow],
                [NSView(), hint("반복이 시작된 뒤 글자가 하나씩 나오는 간격이에요. 짧을수록 ⌫로 빨리 지우고 ←→로 빨리 움직여요.")],
                [label("미리보기"), repeatDemo],
                [NSView(), hint("키를 꾹 눌렀을 때 지금 값으로 글자가 어떻게 나오는지 보여 줘요(실제 키 입력 아님). 바로 적용되고 계속 유지돼요. 일부 앱은 다시 열어야 적용돼요.")],
                [NSView(), restoreButton],
                ]),
            ])),
            SettingsTab(id: "clipboard", title: "클립보드", symbol: "doc.on.clipboard", content: clipboardSettings()),
            SettingsTab(id: "snap", title: "창 정리", symbol: "rectangle.split.2x1", content: snapSettings()),
            SettingsTab(id: "capture", title: "화면 캡처", symbol: "camera.viewfinder", content: captureSettings()),
            SettingsTab(id: "tasks", title: "할 일·일정", symbol: "checklist.checked", content: taskSettings()),
        ] + (Debug.isOn ? [SettingsTab(id: "debug", title: "개발자", symbol: "hammer", content: {
                let d = DebugTab()
                settingsKeepAlive.append(d)
                return d
            }())] : []) + [
            SettingsTab(id: "about", title: "정보", symbol: "info.circle", content: SettingsTabs.grid([(nil, [
                [label("버전"), NSTextField(labelWithString: version)],
            ] + (Updater.isAvailable ? [
                [label("업데이트"), ClosureButton("지금 확인") { Updater.checkNow() }],
                [label("자동으로 확인"), SettingsTabs.toggle(Updater.automatic) { Updater.automatic = $0 }, hint("새 버전이 나오면 알려 줘요")],
            ] : []) + [
                [label("만든 곳"), link("github.com/hyeon0208/tasky", "https://github.com/hyeon0208/tasky"), hint("MIT 라이선스 · 버그와 제안은 GitHub 이슈로")],
                [label("데이터 저장 위치"), NSTextField(labelWithString: "이 Mac에만"), hint("설정·클립보드 기록·서랍은 이 Mac에만 저장되고 어디로도 보내지 않아요. 할 일·일정은 macOS '미리 알림'·'캘린더' 앱에 저장돼요.")],
            ]), ("권한 — 쓰는 기능을 켰을 때만 물어요", [
                [label("입력 모니터링"), permission(CGPreflightListenEventAccess()), hint("한 키로 한영 바꾸기: 어떤 키를 눌렀는지만 판단하고 저장·전송하지 않아요")],
                [label("손쉬운 사용"), permission(AXIsProcessTrusted()), hint("창 정리: 다른 앱 창의 위치·크기를 바꿔요")],
                [label("화면 기록"), permission(CGPreflightScreenCaptureAccess()), hint("화면 캡처")],
                [label("미리 알림"), permission(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess), hint("할 일 읽기·추가·끝내기")],
                [label("캘린더"), permission(EKEventStore.authorizationStatus(for: .event) == .fullAccess), hint("일정 읽기·추가·고치기")],
                [label("집중 모드 상태"), permission(FocusState.available), hint("집중 모드일 때 일정·할 일 알림을 띄우지 않으려고 켜져 있는지만 봐요")],
                [NSView(), ClosureButton("시스템 설정의 개인정보 보호 열기") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }],
            ]), ("단축키 한눈에", [
                [label("빠른 실행"), NSTextField(labelWithString: QuickRun.keyTitle.isEmpty ? "꺼짐" : QuickRun.keyTitle)],
                [label("클립보드 기록"), NSTextField(labelWithString: ClipWatcher.enabled ? HotKey.title() : "꺼짐")],
                [label("화면 캡처"), NSTextField(labelWithString: Capture.enabled ? CaptureMode.allCases.compactMap { m in m.key.map { m.title + " " + HotKey.title(keyCode: $0.code, modifiers: $0.mods) } }.joined(separator: " · ") : "꺼짐")],
                [label("창 정리"), NSTextField(labelWithString: SnapController.enabled ? "⌃⌥를 누르고 있으면 도움말" : "꺼짐")],
                [label("곰"), NSTextField(labelWithString: "한 번 누르기: 원형 메뉴 · 두 번: 오늘 카드 · 오른쪽 클릭: 기능 메뉴")],
            ])])),
        ]
        let tabView = SettingsTabs(tabs: tabs.filter { AgentFeature.enabled || $0.id != "alerts" })
        let size = tabView.frame.size
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(tabView)

        let v = (pet.isVisible ? screen : NSScreen.main ?? screen).visibleFrame
        // 알약은 접힌 크기 기준(펼친 채 열어도 접히면 붙어 있게)
        let petFrame = dock.isDocked ? Geometry.islandFrame(dock: dock, expanded: false, center: CGPoint(x: pet.frame.midX, y: pet.frame.midY), in: v) : pet.frame
        let shown = petFrame.intersection(v).isNull ? petFrame : petFrame.intersection(v)
        // 펫 위, 안 되면 아래, 둘 다 넘치면 화면 가운데. 옆에 붙은 알약은 알약 옆에(알약이 설정 창을 가리지 않게)
        var x = min(max(shown.midX - size.width / 2, v.minX + 8), v.maxX - size.width - 8)
        var y = shown.maxY + 8 + size.height <= v.maxY ? shown.maxY + 8
            : shown.minY - size.height - 8 >= v.minY ? shown.minY - size.height - 8 : v.midY - size.height / 2
        if dock.isDocked && dock != .top && dock != .bottom {
            x = dock.mirrored ? shown.maxX + 8 : shown.minX - size.width - 8
            y = min(max(shown.midY - size.height / 2, v.minY + 8), v.maxY - size.height - 8)
        }
        let origin = pet.isVisible ? CGPoint(x: x, y: y) : CGPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2)   // 펫이 숨어 있으면 화면 가운데
        let panel = FloatingPanel(size: size)
        panel.keyable = true
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        panel.contentView = effect
        panel.orderFrontRegardless()
        settingsPanel = panel
        if pet.isVisible { follow(panel) }
        // 바깥(다른 앱)을 클릭하면 닫는다
        settingsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in self?.closeSettings() }
    }

    /// 설정 '창 정리' 탭 (F15)
    private func snapSettings() -> NSView {
        func label(_ t: String) -> NSTextField { NSTextField(labelWithString: t) }
        func note(_ t: String) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: t)
            f.font = .systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            f.preferredMaxLayoutWidth = 320
            return f
        }
        func check(_ on: Bool, _ toggle: @escaping (Bool) -> Void) -> NSView { SettingsTabs.toggle(on, toggle) }
        let status = note("")
        let openPermission = ClosureButton("권한 열기") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        let statusRow = NSStackView(views: [status, openPermission])
        var rows: [(SnapAction, NSButton, NSTextField)] = []
        func keyTitle(_ a: SnapAction) -> String { a.key.map { HotKey.title(keyCode: $0.code, modifiers: $0.mods) } ?? "없음" }
        func refresh() {
            let snap = SnapController.shared
            let apps = SnapController.runningSnapApps()
            openPermission.isHidden = !SnapController.enabled || AXIsProcessTrusted()
            status.stringValue = !SnapController.enabled ? "꺼져 있어요. 켜면 '손쉬운 사용' 권한을 요청해요."
                : !AXIsProcessTrusted() ? "손쉬운 사용 권한을 기다리고 있어요. 권한을 주면 바로 켜져요."
                : apps.isEmpty ? "켜져 있어요. 창을 화면 가장자리로 끌어도 맞춰져요."
                : "\(apps.joined(separator: ", "))이(가) 켜져 있어 같은 단축키는 겹칠 수 있어요."
            for (a, button, mark) in rows {
                button.title = keyTitle(a)
                switch snap.status[a] {
                case .system?: mark.stringValue = "겹침(시스템)"; mark.textColor = .systemRed
                case .taken?: mark.stringValue = "겹침(다른 앱)"; mark.textColor = .systemRed
                case .ours?: mark.stringValue = "겹침(Tasky 안)"; mark.textColor = .systemRed
                default: mark.stringValue = ""
                }
            }
        }
        var keyRows: [[NSView]] = []
        for a in SnapAction.allCases {
            let mark = NSTextField(labelWithString: "")
            mark.font = .systemFont(ofSize: 11)
            let record = ClosureButton(keyTitle(a)) {}
            record.handler = { [weak self, weak record] in
                self?.stopKeyRecorder()
                record?.title = "키를 누르세요…"
                HotKey.shared.unregister()
                SnapController.shared.stop()
                self?.keyRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    self?.stopKeyRecorder()
                    // Esc 취소, ⌫만 누르면 지우기. ⌘·⌃·⌥ 중 하나는 있어야 한다
                    if e.keyCode == 51 && e.modifierFlags.intersection([.command, .control, .option]).isEmpty { a.key = nil }
                    else if e.keyCode != 53, !e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                        a.key = (UInt32(e.keyCode), HotKey.carbonModifiers(e.modifierFlags))
                    }
                    SnapController.shared.start()
                    return nil
                }
            }
            let reset = ClosureButton("기본") { a.key = a.defaultKey; SnapController.shared.start() }
            rows.append((a, record, mark))
            keyRows.append([label(a.title), NSStackView(views: [record, reset, mark])])
        }
        SnapController.shared.onChange = { refresh() }
        refresh()
        return SettingsTabs.grid([(nil, [
            [label("단축키로 창 정리"), check(SnapController.enabled) { SnapController.shared.setEnabled($0) }, note("켜면 '손쉬운 사용' 권한을 물어요")],
            [NSView(), statusRow],
            [label("화면 끝으로 끌어 맞추기"), check(SnapController.dragOn) { SnapController.dragOn = $0 }, note("창을 왼쪽·오른쪽·위 끝이나 모서리로 끌어요")],
            [NSView(), note("단축키 버튼을 누르고 새 키를 누르세요. ⌫는 지우기, Esc는 취소예요.")],
        ] + keyRows)])
    }

    /// 설정 '화면 캡처' 탭 (F22)
    private func captureSettings() -> NSView {
        func label(_ t: String) -> NSTextField { NSTextField(labelWithString: t) }
        func note(_ t: String) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: t)
            f.font = .systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            f.preferredMaxLayoutWidth = 320
            return f
        }
        let status = note("")
        let openPermission = ClosureButton("권한 열기") { Capture.openPermission() }
        let folder = ClosureButton(Capture.folder.lastPathComponent) {}
        folder.handler = { [weak folder] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.directoryURL = Capture.folder
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url { Capture.folder = url; folder?.title = url.lastPathComponent }
        }
        var rows: [(CaptureMode, NSButton, NSTextField)] = []
        func keyTitle(_ m: CaptureMode) -> String { m.key.map { HotKey.title(keyCode: $0.code, modifiers: $0.mods) } ?? "없음" }
        func refresh() {
            let granted = Capture.hasPermission
            openPermission.isHidden = granted
            status.stringValue = !Capture.enabled ? "단축키가 꺼져 있어요. 메뉴 막대 메뉴로는 언제든 찍을 수 있어요."
                : granted ? "켜져 있어요. 찍으면 클립보드에 복사되고 오른쪽 아래에 미리보기가 떠요."
                : "화면 기록 권한이 필요해요. 권한을 켠 뒤 Tasky를 다시 열어야 할 수 있어요."
            for (m, button, mark) in rows {
                button.title = keyTitle(m)
                switch Capture.shared.status[m] {
                case .system?: mark.stringValue = "겹침(시스템)"; mark.textColor = .systemRed
                case .taken?: mark.stringValue = "겹침(다른 앱)"; mark.textColor = .systemRed
                case .ours?: mark.stringValue = "겹침(Tasky 안)"; mark.textColor = .systemRed
                default: mark.stringValue = ""
                }
            }
        }
        var keyRows: [[NSView]] = []
        for m in CaptureMode.allCases {
            let mark = NSTextField(labelWithString: "")
            mark.font = .systemFont(ofSize: 11)
            let record = ClosureButton(keyTitle(m)) {}
            record.handler = { [weak self, weak record] in
                self?.stopKeyRecorder()
                record?.title = "키를 누르세요…"
                HotKey.shared.unregister()
                SnapController.shared.stop()
                Capture.shared.stop()
                self?.keyRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    self?.stopKeyRecorder()
                    // Esc 취소, ⌫만 누르면 지우기. ⌘·⌃·⌥ 중 하나는 있어야 한다
                    if e.keyCode == 51 && e.modifierFlags.intersection([.command, .control, .option]).isEmpty { m.key = nil }
                    else if e.keyCode != 53, !e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                        m.key = (UInt32(e.keyCode), HotKey.carbonModifiers(e.modifierFlags))
                    }
                    Capture.shared.start()
                    return nil
                }
            }
            let reset = ClosureButton("기본") { m.key = m.defaultKey; Capture.shared.start() }
            rows.append((m, record, mark))
            keyRows.append([label(m.title), NSStackView(views: [record, reset, mark])])
        }
        Capture.shared.onChange = { refresh() }
        refresh()
        return SettingsTabs.grid([(nil, [
            [label("단축키로 화면 캡처"), SettingsTabs.toggle(Capture.enabled) { Capture.shared.setEnabled($0) }, note("켜면 '화면 기록' 권한을 물어요")],
            [NSView(), NSStackView(views: [status, openPermission])],
            [NSView(), note("단축키 버튼을 누르고 새 키를 누르세요. ⌫는 지우기, Esc는 취소예요.")],
        ] + keyRows + [
            [label("저장 폴더"), folder, note("편집 창에서 ⌘S를 누르면 여기에 PNG로 저장해요")],
        ])])
    }

    /// 설정 '할 일·일정' 탭 (F24)
    private func taskSettings() -> NSView {
        func label(_ t: String) -> NSTextField { NSTextField(labelWithString: t) }
        func note(_ t: String) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: t)
            f.font = .systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            f.preferredMaxLayoutWidth = 320
            return f
        }
        let store = TaskStore.shared
        let nudges = [0, 15, 30, 60, 120]
        func choice(_ titles: [String], selected: Int, _ pick: @escaping (Int) -> Void) -> NSPopUpButton {
            let p = NSPopUpButton()
            for (i, t) in titles.enumerated() { p.menu?.addItem(ClosureMenuItem(t) { pick(i) }) }
            p.selectItem(at: selected)
            return p
        }
        func status(_ type: EKEntityType, on: Bool) -> String {
            !on ? "꺼져 있어요" : !TaskStore.canAsk(type) ? "앱으로 실행해야 해요(dist/Tasky.app)"
                : TaskStore.granted(type) ? "켜져 있어요" : "권한이 필요해요. 권한을 켠 뒤 Tasky를 다시 열어야 할 수 있어요."
        }
        let remStatus = note(""), evStatus = note("")
        let remOpen = ClosureButton("권한 열기") { TaskStore.openPermission(.reminder) }
        let evOpen = ClosureButton("권한 열기") { TaskStore.openPermission(.event) }
        let remList = NSPopUpButton(), evList = NSPopUpButton()
        func fill(_ popup: NSPopUpButton, _ cals: [EKCalendar], selected: EKCalendar?, key: String) {
            popup.removeAllItems()
            for c in cals {
                let item = ClosureMenuItem(c.title) { UserDefaults.standard.set(c.calendarIdentifier, forKey: key) }
                popup.menu?.addItem(item)
                if c.calendarIdentifier == selected?.calendarIdentifier { popup.select(item) }
            }
            popup.isEnabled = !cals.isEmpty
        }
        func refresh() {
            remStatus.stringValue = status(.reminder, on: TaskStore.remindersOn)
            evStatus.stringValue = status(.event, on: TaskStore.eventsOn)
            remOpen.isHidden = !TaskStore.remindersOn || !TaskStore.canAsk(.reminder) || TaskStore.granted(.reminder)
            evOpen.isHidden = !TaskStore.eventsOn || !TaskStore.canAsk(.event) || TaskStore.granted(.event)
            fill(remList, TaskStore.granted(.reminder) ? store.store.calendars(for: .reminder).filter(\.allowsContentModifications) : [], selected: store.reminderCalendar(), key: "tasksReminderList")
            fill(evList, TaskStore.granted(.event) ? store.store.calendars(for: .event).filter(\.allowsContentModifications) : [],
                 selected: store.eventCalendar(), key: "tasksEventCalendar")
        }
        refresh()
        // F26 빠른 실행 단축키
        func quickTitle() -> String { QuickRun.key.map { HotKey.title(keyCode: $0.code, modifiers: $0.mods) } ?? "없음" }
        let quickMark = NSTextField(labelWithString: ""); quickMark.font = .systemFont(ofSize: 11); quickMark.textColor = .systemRed
        let quickKey = ClosureButton(quickTitle()) {}
        func quickRefresh() {
            quickKey.title = quickTitle()
            quickMark.stringValue = QuickRun.status == .system ? "겹침(시스템)" : QuickRun.status == .taken ? "겹침(다른 앱)" : ""
        }
        quickKey.handler = { [weak self, weak quickKey] in
            self?.stopKeyRecorder()
            quickKey?.title = "키를 누르세요…"
            HotKey.shared.remove(id: QuickRun.hotKeyID)
            self?.keyRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                self?.stopKeyRecorder()
                if e.keyCode == 51 && e.modifierFlags.intersection([.command, .control, .option]).isEmpty { QuickRun.key = nil }
                else if e.keyCode != 53, !e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    QuickRun.key = (UInt32(e.keyCode), HotKey.carbonModifiers(e.modifierFlags))
                }
                QuickRun.register(); quickRefresh()
                return nil
            }
        }
        let quickReset = ClosureButton("기본") { UserDefaults.standard.removeObject(forKey: "quickRunKey"); QuickRun.register(); quickRefresh() }
        quickRefresh()
        return SettingsTabs.grid([(nil, [
            [label("할 일"), SettingsTabs.toggle(TaskStore.remindersOn) { on in store.setEnabled(.reminder, on) { refresh() } }, note("Tasky의 할 일은 Mac에 들어 있는 '미리 알림' 앱에 저장돼요. 그래서 iPhone 미리 알림에도 똑같이 보여요. 켜면 '미리 알림' 권한을 물어요.")],
            [NSView(), NSStackView(views: [remStatus, remOpen])],
            [label("할 일 저장할 목록"), remList],
            [NSView(), note("'미리 알림' 앱에는 '미리 알림'·'업무'처럼 목록이 여러 개 있을 수 있어요. 오늘 카드나 빠른 실행에서 새 할 일을 적으면 여기서 고른 목록에 들어가요. 할 일을 보여 줄 때는 모든 목록을 함께 보여 줘요.")],
            [label("일정"), SettingsTabs.toggle(TaskStore.eventsOn) { on in store.setEnabled(.event, on) { refresh() } }, note("일정은 Mac의 '캘린더' 앱(iCloud·Google 계정 포함)에서 읽고 저장해요. 켜면 '캘린더' 권한을 물어요.")],
            [NSView(), NSStackView(views: [evStatus, evOpen])],
            [label("일정 저장할 캘린더"), evList],
            [NSView(), note("'캘린더' 앱에는 '집'·'직장'·Google 계정처럼 캘린더가 여러 개 있어요. 시간이 있는 입력(예: 내일 3시 치과)은 일정으로 저장되는데, 그때 들어갈 캘린더를 고르는 곳이에요. 볼 때는 모든 캘린더를 함께 보여 줘요.")],
            [label("일정 볼 기간"), choice((1...7).map { "\($0)일" }, selected: TaskStore.eventDays - 1) { TaskStore.eventDays = $0 + 1 }],
            [NSView(), note("오늘 카드의 '일정' 칸에 오늘부터 며칠 뒤 일정까지 보여 줄지예요.")],
            [label("할 일 알려 주기"), choice(nudges.map { $0 == 0 ? "끄기" : "\($0)분마다" }, selected: nudges.firstIndex(of: TaskStore.nudgeMinutes) ?? 3) { TaskStore.nudgeMinutes = nudges[$0] }],
            [NSView(), note("일정은 1시간 전에 알리고(다시 알려 줄 시간은 알림에서 고름), '알겠어요(알림 끄기)'를 누르지 않았으면 시작할 때 한 번 더 알려 줘요. 남은 할 일은 정한 간격마다 곰 옆에 알려 줘요. macOS 집중 모드가 켜져 있으면 띄우지 않아요.")],
            [label("알릴 때 소리"), SettingsTabs.toggle(TaskStore.soundOn) { TaskStore.soundOn = $0 }],
            [NSView(), note("시간이 된 항목은 macOS 알림으로도 와요. Tasky가 켜져 있으면 곰도 알려 줘요.")],
            [label("빠른 실행 단축키"), NSStackView(views: [quickKey, quickReset, quickMark])],
            [NSView(), note("어느 앱에서든 이 키를 누르면 화면 가운데에 명령 바가 떠요. 할 일·일정 적기, 기능 실행(캡처·창 정리 등), 할 일·클립보드 찾기를 한 줄로 해요.")],
            [NSView(), note("할 일 적기·기능 실행·찾기를 한 줄로 해요. 곰을 두 번 눌러도 열려요. ⌘P는 거의 모든 앱의 '프린트'라 ⌘⇧P를 기본으로 했어요.")],
        ])])
    }

    /// F24: 시간이 된 할 일·일정
    func taskDue(_ item: TaskNotice) {
        let bar = pet.isVisible ? nil : App.menuBarAnchor()   // F26: 메뉴 막대만 쓰면 상태 칸 아래에
        guard pet.isVisible || bar != nil else { return }
        petView.react(.jobWaiting)
        if TaskStore.soundOn { NSSound(named: "Glass")?.play() }
        TaskAlertPanel.show(item, nextTo: bar?.frame ?? pet.frame, in: bar?.visible ?? screen.visibleFrame)
    }

    /// 설정 '클립보드' 탭
    private func clipboardSettings() -> NSView {
        func check(_ on: Bool, _ toggle: @escaping (Bool) -> Void) -> NSView { SettingsTabs.toggle(on, toggle) }
        func note(_ t: String) -> NSTextField {
            let f = NSTextField(wrappingLabelWithString: t)
            f.font = .systemFont(ofSize: 11)
            f.textColor = .secondaryLabelColor
            f.preferredMaxLayoutWidth = 320
            return f
        }
        let status = note("")
        func refresh() {
            status.stringValue = !ClipWatcher.enabled ? "꺼져 있어요"
                : HotKey.shared.registered ? "\(HotKey.title())로 기록 창을 열어요. 크롬 개발자 도구·Finder의 같은 단축키는 가려져요."
                : "\(HotKey.title())는 다른 앱이 쓰고 있어요. 다른 키를 골라 주세요."
        }
        refresh()
        let record = ClosureButton(HotKey.title()) {}
        record.handler = { [weak self, weak record] in
            self?.stopKeyRecorder()   // 두 번 눌러도 듣는 것은 하나
            record?.title = "키를 누르세요…"
            HotKey.shared.unregister()
            SnapController.shared.stop()
            self?.keyRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                self?.stopKeyRecorder()
                let mods = HotKey.carbonModifiers(e.modifierFlags)
                // Esc는 취소. ⌘·⌃·⌥ 중 하나는 있어야 한다(⇧만이면 대문자 입력을 빼앗음)
                if e.keyCode != 53, !e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    HotKey.keyCode = UInt32(e.keyCode)
                    HotKey.modifiers = mods
                    HotKey.shared.register()
                }
                record?.title = HotKey.title()
                refresh()
                return nil
            }
        }
        let limit = NSPopUpButton()
        let counts = [10, 20, 50, 100, 200]
        limit.addItems(withTitles: counts.map { "\($0)개" })
        limit.selectItem(at: counts.firstIndex(of: ClipStore.limit) ?? 2)
        let limitHandler = ClosureButton("") {}
        limitHandler.handler = { [weak limit] in if let i = limit?.indexOfSelectedItem { ClipStore.limit = counts[i] } }
        limit.target = limitHandler
        limit.action = #selector(ClosureButton.performClick(_:))
        settingsKeepAlive.append(limitHandler)
        let clear = ClosureButton("고정 빼고 지우기") { ClipStore.shared.update { $0.items.removeAll { !$0.pinned } } }
        let clearAll = ClosureButton("모두 지우기") { ClipStore.shared.update { $0.items.removeAll() } }
        let clearRow = NSStackView(views: [clear, clearAll])
        func label(_ t: String) -> NSTextField { NSTextField(labelWithString: t) }
        return SettingsTabs.grid([(nil, [
            [label("복사한 것 기록하기"), check(ClipWatcher.enabled) { on in
                ClipWatcher.enabled = on
                if on { HotKey.shared.register() } else { HotKey.shared.unregister() }
                refresh()
            }],
            [label("기록 열기 단축키"), record],
            [NSView(), status],
            [label("최대 기록 수"), limit, note("고정한 것은 세지 않아요")],
            [label("복사하면 펫이 받아 들기"), check(UserDefaults.standard.object(forKey: "clipReact") as? Bool ?? true) {
                UserDefaults.standard.set($0, forKey: "clipReact") }],
            [label("기록 지우기"), clearRow],
            [NSView(), note("비밀번호 관리자가 숨김 표시한 복사는 기록하지 않아요. 기록은 이 Mac에만 저장돼요.")],
        ])])
    }

    private var keyRecorder: Any?
    private func stopKeyRecorder() {
        if let m = keyRecorder {
            NSEvent.removeMonitor(m)
            // 녹화 동안 멈춘 단축키를 다시 건다(등록된 키는 녹화 칸까지 오지 않음)
            HotKey.shared.register()
            SnapController.shared.start()
            Capture.shared.start()
        }
        keyRecorder = nil
    }

    private func closeSettings() {
        stopKeyRecorder()
        SnapController.shared.onChange = {}
        Capture.shared.onChange = {}
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
        var y = min(max(c.y - size.height / 2, v.minY + 8), v.maxY - size.height - 8)
        if dock == .top {   // 위(노치) 알약: 접힌 알약 바로 아래, 가운데 맞춤
            let pill = Geometry.islandFrame(dock: .top, expanded: false, center: c, in: v)
            x = pill.midX - size.width / 2
            y = max(pill.minY - size.height - 8, v.minY + 8)
        }
        x = min(max(x, v.minX + 8), v.maxX - size.width - 8)

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
    private var statusMenu = NSMenu()
    private var bearIcon: NSImage?
    private var awakeItem: NSMenuItem?
    private var todayItem: NSMenuItem?
    private var briefingItem: NSMenuItem?
    private var peekItem: NSMenuItem?
    private var quickRunItem: NSMenuItem?
    private var captureItem: NSMenuItem?
    private var steamTimer: Timer?
    private var counter: Int

    private let agents = AgentStore()
    private var server: HookServer?

    override init() {
        counter = UserDefaults.standard.integer(forKey: "petCounter")
        super.init()
        let ids = UserDefaults.standard.stringArray(forKey: "pets") ?? []
        if let id = ids.first { spawn(id: id) }   // 펫은 한 마리(사용자 결정 2026-10-30). 예전에 부른 다른 펫은 띄우지 않는다
        if pets.isEmpty { addPet() }
        if App.petsHidden { pets.forEach { $0.setVisible(false) } }
        setUpStatusItem()

        // 알림은 그 도구를 받는 펫 중 첫 번째(보이는 펫)가 알린다. 받는 펫이 없으면 첫 번째 펫이 알려 놓치지 않게 한다.
        // 쉬는 중(F6)에는 끝남·실패를 보류하고, 승인 대기는 싱잉볼 창 한 줄로만 보여 준다(모든 펫 공통).
        agents.onChange = { [weak self] s in
            guard let self else { return }
            let announce = s.map { RestSession.shouldAnnounce(&self.rest, $0) } ?? true
            if self.rest != nil { self.bowl?.update(waiting: self.agents.waiting) }
            let target = announce ? s.flatMap { s in self.pets.first { $0.isVisible && $0.accepts(s.tool) } ?? self.pets.first } : nil
            self.pets.forEach { $0.agentsChanged(s, announce: $0 === target) }
            self.refreshStatusTitle()
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
        // F16 클립보드: 감시·단축키, 복사하면 보이는 첫 펫이 받아 든다
        ClipWatcher.shared.onCopy = { [weak self] item in self?.pets.first { $0.isVisible }?.copied(item) }
        ClipWatcher.shared.apply()
        HotKey.shared.onPress = { ClipWindow.shared.toggle() }
        HotKey.shared.register()
        // F26 빠른 실행(⌘⇧P)
        QuickRun.onPress = { QuickRunWindow.shared.toggle() }
        QuickRunWindow.shared.runCommand = { [weak self] id in
            switch id {
            case "settings": (self?.pets.first { $0.isVisible } ?? self?.pets.first)?.openSettingsFromMenu()   // 메뉴 막대만이면 펫이 숨어 있다
            case "awake": Awake.shared.isOn ? Awake.shared.stop() : Awake.shared.start(minutes: Awake.minutes)
            default: break
            }
        }
        QuickRun.register()
        SnapController.shared.start()   // F15: 켜져 있을 때만 단축키·마우스 감시
        Capture.shared.start()   // F22: 켜져 있을 때만 단축키
        FocusState.start()
        TaskAlerts.shared.onDue = { [weak self] item in self?.pets.first { $0.isVisible }?.taskDue(item) }
        TaskStore.shared.start()   // F24: 켜져 있고 권한이 있을 때만 읽는다(권한 창은 띄우지 않음)
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

    /// F26 보이는 방식(곰과 알약 / 메뉴 막대만)이 바뀜
    static let viewModeChanged = Notification.Name("TaskyViewModeChanged")
    /// 메뉴 막대만 쓸 때 상태 칸 자리(알림·오늘 카드를 그 아래에). 아니면 nil
    static var menuBarAnchor: () -> (frame: CGRect, visible: CGRect)? = { nil }
    static var petsHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "petsHidden") }
        set {
            UserDefaults.standard.set(newValue, forKey: "petsHidden")
            NotificationCenter.default.post(name: viewModeChanged, object: nil)
        }
    }

    func addPet() {
        spawn(id: UUID().uuidString)
        saveList()
    }

    private func spawn(id: String) {
        let index = counter
        counter += 1
        UserDefaults.standard.set(counter, forKey: "petCounter")
        let pet = PetController(id: id, index: index)
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

    private func saveList() { UserDefaults.standard.set(pets.map(\.id), forKey: "pets") }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 앱 아이콘의 곰 윤곽(흑백 템플릿, 다크 모드에서 자동 반전). 없으면 체크 기호.
        // Bundle.module은 묶음을 못 찾으면 앱을 멈추므로 직접 찾는다(.build 밖으로 옮겨도 안전)
        let res = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0?.appendingPathComponent("Tasky_Tasky.bundle") }
            .compactMap(Bundle.init(url:)).first
        let logo = res?.image(forResource: "MenuBarIcon") ?? NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        logo?.isTemplate = true
        logo?.size = NSSize(width: 18, height: 18)
        logo?.accessibilityDescription = "Tasky"
        statusItem.button?.image = logo
        bearIcon = logo
        let menu = statusMenu
        // F26: 맨 위 — 오늘 보기(할 일 수·다음 일정), 빠른 실행
        let today = ClosureMenuItem("오늘 보기") { [weak self] in
            DispatchQueue.main.async { self?.openTodayFromMenuBar() }   // 메뉴가 닫힌 뒤 연다
        }
        menu.addItem(today)
        todayItem = today
        menu.addItem(ClosureMenuItem("빠른 실행") { DispatchQueue.main.async { QuickRunWindow.shared.open() } })
        quickRunItem = menu.items.last
        // F27: 원형 메뉴에서 빠진 것과 작업 목록(승인 대기 외 작업은 여기서 본다)
        if AgentFeature.enabled { menu.addItem(ClosureMenuItem("작업 목록") { [weak self] in DispatchQueue.main.async { (self?.pets.first { $0.isVisible } ?? self?.pets.first)?.openAgentList() } }) }
        let away = ClosureMenuItem("그 사이 소식") { [weak self] in DispatchQueue.main.async { self?.pets.first { $0.isVisible }?.openBriefing() } }
        menu.addItem(away)
        briefingItem = away
        menu.addItem(ClosureMenuItem("빼꼼") { [weak self] in DispatchQueue.main.async { self?.pets.first { $0.isVisible }?.togglePeek() } })
        peekItem = menu.items.last
        menu.addItem(.separator())
        // F23 잠 안 자기: 고르면 그 시간으로 바로 켜진다
        let awake = NSMenuItem(title: "잠 안 자기", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for c in Awake.choices { sub.addItem(ClosureMenuItem(c.title) { Awake.shared.start(minutes: c.minutes) }) }
        sub.addItem(.separator())
        sub.addItem(ClosureMenuItem("끄기") { Awake.shared.stop() })
        awake.submenu = sub
        menu.addItem(awake)
        awakeItem = awake
        // F22 화면 캡처: 단축키는 표시만(메뉴가 열려 있을 때만 동작)
        let capture = NSMenuItem(title: "화면 캡처", action: nil, keyEquivalent: "")
        let capSub = NSMenu()
        for m in CaptureMode.allCases { capSub.addItem(ClosureMenuItem(m.title) { Capture.shared.take(m) }) }
        capture.submenu = capSub
        menu.addItem(capture)
        captureItem = capture
        menu.addItem(.separator())
        let sound = ClosureMenuItem("작업 알림음") {}
        sound.state = AlertCard.soundOn ? .on : .off
        sound.handler = { [weak sound] in
            AlertCard.soundOn.toggle()
            sound?.state = AlertCard.soundOn ? .on : .off
        }
        menu.addItem(sound)
        // 바탕화면에서 펫을 숨겨 두고 메뉴 막대로만 쓸 수 있다(다시 켜도 기억)
        let shown = ClosureMenuItem("펫 보이기") {}
        shown.state = App.petsHidden ? .off : .on
        shown.handler = { [weak self, weak shown] in
            App.petsHidden.toggle()
            shown?.state = App.petsHidden ? .off : .on
        }
        NotificationCenter.default.addObserver(forName: App.viewModeChanged, object: nil, queue: .main) { [weak self, weak shown] _ in
            shown?.state = App.petsHidden ? .off : .on
            TodayCard.shared.close()
            self?.pets.forEach { $0.setVisible(!App.petsHidden) }
            self?.refreshStatusTitle()
        }
        menu.addItem(shown)
        let still = ClosureMenuItem("펫 움직임 끄기 (CPU 절약)") {}
        still.state = Pet3DView.still ? .on : .off
        still.handler = { [weak still] in
            Pet3DView.still.toggle()
            still?.state = Pet3DView.still ? .on : .off
        }
        menu.addItem(still)
        menu.addItem(.separator())
        let settings = ClosureMenuItem("설정…") { [weak self] in self?.pets.first?.openSettingsFromMenu() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Tasky 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // 왼쪽 클릭은 메뉴, 오른쪽(⌃)클릭은 메뉴 없이 잠 안 자기 켜기/끄기
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Awake.shared.onChange = { [weak self] in self?.awakeChanged() }
        // F26 메뉴 막대만: 상태 칸 제목(할 일 수 · 다음 일정 · 작업 점)
        App.menuBarAnchor = { [weak self] in
            guard App.petsHidden, let b = self?.statusItem.button, let w = b.window else { return nil }
            let f = w.convertToScreen(b.convert(b.bounds, to: nil))
            let s = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main
            return (f, s?.visibleFrame ?? f)
        }
        NotificationCenter.default.addObserver(forName: TaskStore.changedNote, object: nil, queue: .main) { [weak self] _ in self?.refreshStatusTitle() }
        titleTimer = Ticker.every("메뉴 막대 제목 갱신", 60) { [weak self] _ in self?.refreshStatusTitle() }
        refreshStatusTitle()
    }

    private var titleTimer: Timer?

    func refreshStatusTitle() {
        guard let b = statusItem?.button else { return }
        guard App.petsHidden else { b.title = ""; b.imagePosition = .imageOnly; return }
        let g = Glance.make(items: TaskStore.anyOn ? TaskStore.shared.items : [], tasksOn: TaskStore.anyOn,
                            states: agents.ordered.filter { $0.state != .done || !$0.seen }.map(\.state), now: Date())
        let font = NSFont.menuBarFont(ofSize: 0)
        let t = NSMutableAttributedString(string: g.menuTitle.isEmpty ? "" : " " + g.menuTitle, attributes: [.font: font])
        for s in g.dots { t.append(NSAttributedString(string: " ●", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: Glance.color(s), .baselineOffset: 1])) }
        b.attributedTitle = t
        b.imagePosition = t.length == 0 ? .imageOnly : .imageLeading
    }

    @objc private func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            Awake.shared.isOn ? Awake.shared.stop() : Awake.shared.start(minutes: Awake.minutes)
            return
        }
        showStatusMenu()
    }

    /// F26 메뉴 막대만: 메뉴 맨 위 '오늘 보기'에서 연다(상태 칸 아래)
    private func openTodayFromMenuBar() {
        guard let bar = App.menuBarAnchor() else { return }
        TodayCard.shared.onOpenSettings = { [weak self] in self?.pets.first?.openSettingsFromMenu() }
        TodayCard.shared.footer = [("설정", { [weak self] in self?.pets.first?.openSettingsFromMenu() })]
        TodayCard.shared.open(near: { App.menuBarAnchor()?.frame ?? bar.frame }, in: bar.visible, below: true, parent: nil)
    }

    private func showStatusMenu() {
        refreshAwakeMenu()
        refreshCaptureMenu()
        refreshTopMenu()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// 메뉴를 열 때마다 지금 단축키를 옆에 표시한다(켜져 있고 한 글자 키일 때만)
    private func refreshCaptureMenu() {
        for (item, m) in zip(captureItem?.submenu?.items ?? [], CaptureMode.allCases) {
            let key = Capture.enabled ? m.key : nil
            let ch = key.map { HotKey.title(keyCode: $0.code, modifiers: 0) } ?? ""
            item.keyEquivalent = ch.count == 1 ? ch.lowercased() : ""
            item.keyEquivalentModifierMask = key.map { HotKey.cocoaModifiers($0.mods) } ?? []
        }
    }

    /// '오늘 보기 — 할 일 3 · 2:00 치과', 빠른 실행 옆에 지금 단축키. 오늘 카드는 메뉴 막대만일 때만(펫이면 곰을 누르면 된다)
    private func refreshTopMenu() {
        let g = Glance.make(items: TaskStore.anyOn ? TaskStore.shared.items : [], tasksOn: TaskStore.anyOn, states: [], now: Date())
        todayItem?.title = g.menuTitle.isEmpty ? "오늘 보기" : "오늘 보기 — " + g.menuTitle
        todayItem?.isHidden = !App.petsHidden
        quickRunItem?.title = QuickRun.keyTitle.isEmpty ? "빠른 실행" : "빠른 실행  " + QuickRun.keyTitle
        let pet = pets.first { $0.isVisible }
        let away = pet?.briefing.items.count ?? 0
        briefingItem?.title = "그 사이 소식 \(away)건"
        briefingItem?.isHidden = away == 0
        peekItem?.title = pet?.isDocked == true ? "빼꼼 그만" : "빼꼼"
        peekItem?.isHidden = pet == nil
    }

    private func refreshAwakeMenu() {
        let a = Awake.shared
        awakeItem?.title = a.end.map { "잠 안 자기 (\(Awake.left($0.timeIntervalSinceNow)))" } ?? (a.isOn ? "잠 안 자기 (켜짐)" : "잠 안 자기")
        for item in awakeItem?.submenu?.items ?? [] {
            let m = Awake.choices.first { $0.title == item.title }?.minutes
            item.state = a.isOn && m == Awake.minutes ? .on : .off
        }
    }

    private func awakeChanged() {
        steamTimer?.invalidate(); steamTimer = nil
        guard Awake.shared.isOn else { statusItem.button?.image = bearIcon; return }
        statusItem.button?.image = AwakeIcon.image(bear: bearIcon, steam: 2)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // 3초 주기: 김 없음 → 낮게 → 높게
        var frame = 0
        steamTimer = Ticker.every("잠 안 자기 김", 1) { [weak self] _ in
            frame = (frame + 1) % 3
            self?.statusItem.button?.image = AwakeIcon.image(bear: self?.bearIcon, steam: frame)
        }
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

/// F28: 키 반복 미리보기. 지금 설정(시작까지·간격)으로 'ㅋ'가 이어지는 모습을 되풀이해 보여 준다
final class KeyRepeatDemo: NSView {
    private let text = NSTextField(labelWithString: "")
    private let key = NSTextField(labelWithString: "ㅋ")
    private var timer: Timer?
    override init(frame: NSRect) {
        super.init(frame: frame)
        key.font = .systemFont(ofSize: 13, weight: .bold); key.alignment = .center
        key.wantsLayer = true; key.layer?.cornerRadius = 6; key.layer?.borderWidth = 1
        key.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        key.frame = CGRect(x: 0, y: 16, width: 28, height: 22)
        text.font = .monospacedSystemFont(ofSize: 13, weight: .medium); text.lineBreakMode = .byClipping
        text.frame = CGRect(x: 40, y: 18, width: frame.width - 40, height: 18)
        addSubview(key); addSubview(text)
        widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        restart()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    override func viewDidMoveToWindow() { if window == nil { timer?.invalidate(); timer = nil } else if timer == nil { restart() } }

    /// 눌림(1.6초) → 쉼(0.8초)을 되풀이. 첫 글자 → 시작까지 기다림 → 간격마다 한 글자
    func restart() {
        timer?.invalidate()
        let initial = Double(KeyRepeat.ms(KeyRepeat.read(KeyRepeat.initial) ?? KeyRepeat.fallback(KeyRepeat.initial))) / 1000
        let rate = max(0.015, Double(KeyRepeat.ms(KeyRepeat.read(KeyRepeat.rate) ?? KeyRepeat.fallback(KeyRepeat.rate))) / 1000)
        let start = Date()
        timer = Ticker.every("키 반복 미리보기", 1.0 / 60) { [weak self] _ in
            guard let self else { return }
            let t = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 2.4)
            let down = t < 1.6
            let n = !down ? 0 : t < initial ? 1 : 1 + Int((t - initial) / rate) + 1
            self.key.layer?.backgroundColor = (down ? NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.clear).cgColor
            self.text.stringValue = down ? String(repeating: "ㅋ", count: min(n, 40)) : ""
        }
    }
}
