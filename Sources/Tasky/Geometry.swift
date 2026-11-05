import AppKit

/// 펫이 화면 어디에 붙어 있는지. 위쪽은 메뉴 막대 바로 아래(F20).
enum Dock: String {
    case free, left, right, bottom, bottomLeft, bottomRight, top

    var isDocked: Bool { self != .free }
    /// 눈이 화면 안쪽을 보도록 그림을 뒤집어야 하는지
    var mirrored: Bool { self == .left || self == .bottomLeft }
}

enum Geometry {
    static let snap: CGFloat = 24

    static func dock(for frame: CGRect, in v: CGRect) -> Dock {
        let nearL = frame.minX <= v.minX + snap
        let nearR = frame.maxX >= v.maxX - snap
        let nearB = frame.minY <= v.minY + snap
        if frame.maxY >= v.maxY - snap, !nearL, !nearR { return .top }   // 위 구석은 옆으로
        switch (nearL, nearR, nearB) {
        case (true, _, true): return .bottomLeft
        case (_, true, true): return .bottomRight
        case (true, _, _): return .left
        case (_, true, _): return .right
        case (_, _, true): return .bottom
        default: return .free
        }
    }

    /// 자유 상태면 화면 안으로 끌어오고, 붙은 상태면 몸 대부분을 화면 밖으로 숨긴다.
    /// `out`(0...1)은 호버 때 고개를 더 내미는 정도. `body`는 창 안에서 몸이 차지하는 부분(0...1 비율)이고,
    /// 숨기는 정도와 화면 안 제한은 창이 아니라 몸 기준이다(캐릭터 그림은 둘레가 투명해서).
    static func frame(size: CGSize, origin: CGPoint, dock: Dock, in v: CGRect, out: CGFloat = 0,
                      body b: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> CGRect {
        let bx = b.minX * size.width, bw = b.width * size.width
        let by = b.minY * size.height, bh = b.height * size.height
        let showX = bw * (0.38 + 0.3 * out)
        let showY = bh * (0.45 + 0.3 * out)
        let clampedX = min(max(origin.x, v.minX - bx), v.maxX - bx - bw)
        let clampedY = min(max(origin.y, v.minY - by), v.maxY - by - bh)
        let leftX = v.minX + showX - bx - bw, rightX = v.maxX - showX - bx, bottomY = v.minY + showY - by - bh
        let topY = v.maxY - showY - by
        let x: CGFloat, y: CGFloat
        switch dock {
        case .free: (x, y) = (clampedX, clampedY)
        case .left: (x, y) = (leftX, clampedY)
        case .right: (x, y) = (rightX, clampedY)
        case .bottom: (x, y) = (clampedX, bottomY)
        case .top: (x, y) = (clampedX, topY)
        case .bottomLeft: (x, y) = (leftX, bottomY)
        case .bottomRight: (x, y) = (rightX, bottomY)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// F20 빼꼼 아일랜드: 붙은 펫 창이 되는 알약. 옆·구석은 세로, 아래는 가로.
    static func islandSize(dock: Dock, expanded: Bool, chips: CGFloat = 0) -> CGSize {
        switch (dock == .bottom || dock == .top, expanded) {
        case (true, false): CGSize(width: max(96, 40 + chips + 12), height: 30)   // F26: 칩만큼 길어진다
        case (true, true): CGSize(width: 280, height: 120)    // F27: 아래로 펼치는 '미니 오늘'
        case (false, false): CGSize(width: 30, height: 96)
        case (false, true): CGSize(width: 250, height: 150)   // F27: 옆으로 서랍처럼
        }
    }

    /// 화면 끝에서 4pt 안쪽. 펼쳐도 같은 끝에 붙은 채 안쪽으로 커진다. `center`는 붙기 전 펫 가운데(끝을 따라가는 자리).
    static func islandFrame(dock: Dock, expanded: Bool, center c: CGPoint, in v: CGRect, chips: CGFloat = 0) -> CGRect {
        let inset: CGFloat = 4
        var s = islandSize(dock: dock, expanded: expanded, chips: chips)
        s = CGSize(width: min(s.width, v.width - inset * 2), height: min(s.height, v.height - inset * 2))
        let clampX = min(max(c.x - s.width / 2, v.minX + inset), v.maxX - inset - s.width)
        let clampY = min(max(c.y - s.height / 2, v.minY + inset), v.maxY - inset - s.height)
        let left = v.minX + inset, right = v.maxX - inset - s.width, low = min(v.minY + 40, v.maxY - inset - s.height)
        let o: CGPoint = switch dock {
        case .left: CGPoint(x: left, y: clampY)
        case .right: CGPoint(x: right, y: clampY)
        case .bottom: CGPoint(x: clampX, y: v.minY + inset)
        case .top: CGPoint(x: clampX, y: v.maxY - inset - s.height)
        case .bottomLeft: CGPoint(x: left, y: low)
        case .bottomRight: CGPoint(x: right, y: low)
        case .free: CGPoint(x: clampX, y: clampY)
        }
        return CGRect(origin: o, size: s)
    }

    /// F20 알약에서 여는 링: 알약 안쪽으로 한 겹 부채꼴. 칸끼리 `gap` 이상, 알약에서 `clear` 이상 떨어지는 가장 작은 반지름.
    static func fanCenters(count: Int, dock: Dock, pill p: CGRect, gap: CGFloat = 66, clear: CGFloat = 36) -> [CGPoint] {
        guard count > 0 else { return [] }
        let base: Double = switch dock {
        case .left: 0
        case .right: 180
        case .bottom: 90
        case .top: 270
        case .bottomLeft: 35   // 구석 알약은 화면 아래가 가까워 위로 치우친다
        case .bottomRight: 145
        case .free: 90
        }
        let span = min(160.0, 26.0 * Double(count - 1))
        let step = count > 1 ? span / Double(count - 1) : 0
        let c = CGPoint(x: p.midX, y: p.midY), avoid = p.insetBy(dx: -clear, dy: -clear)
        var r = count > 1 ? Double(gap) / (2 * sin(step / 2 * .pi / 180)) : 0
        while true {
            let pts = (0..<count).map { i -> CGPoint in
                let a = (base + span / 2 - step * Double(i)) * .pi / 180
                return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
            if !pts.contains(where: avoid.contains) || r > 800 { return pts }
            r += 4
        }
    }

    /// 링의 칸 중심점. 자유 상태는 위쪽 반원(첫 칸이 왼쪽 끝), 가장자리는 반원, 구석은 부채꼴이며 넘치면 바깥 겹으로.
    /// `size`는 펫 몸의 크기. 몸이 클수록 첫 겹이 바깥으로 물러난다(칸끼리 겹치지 않는 최소 반지름은 지킨다).
    static func slotCenters(count: Int, dock: Dock, center c: CGPoint, size: CGFloat = 80, roomAbove: Bool = true) -> [CGPoint] {
        let grow = max(0, Double(size) - 80) * 0.6
        if dock == .free {
            // 위쪽 반원(190°→-10°)에 펼쳐 펫 아래 화면을 가리지 않는다. 위 공간이 없으면 아래로 뒤집는다.
            var result: [CGPoint] = []
            var ring = 0
            while result.count < count {
                let n = min(count - result.count, 7 + ring * 2)
                let radius: Double = 96 + grow + Double(ring) * 50
                result += (0..<n).map { i in
                    let deg = n == 1 ? 90 : 190 - 200 * Double(i) / Double(n - 1)
                    let a = deg * .pi / 180
                    return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a) * (roomAbove ? 1 : -1))
                }
                ring += 1
            }
            return result
        }
        let corner = dock == .bottomLeft || dock == .bottomRight
        let base: Double = switch dock {
        case .left: 0
        case .right: 180
        case .bottom: 90
        case .top: 270
        case .bottomLeft: 45
        default: 135
        }
        let span: Double = corner ? 62 : 150
        let capacity = corner ? 4 : 5
        var result: [CGPoint] = []
        var ring = 0
        var remaining = count
        while remaining > 0 {
            let n = min(remaining, capacity + ring) // 바깥 겹은 둘레가 길어 한 칸 더
            let radius = (corner ? 112 : 88) + grow + Double(ring) * 50
            var angles = (0..<n).map { j in
                n == 1 ? base : base - span / 2 + span * Double(j) / Double(n - 1)
            }
            if sin(angles.first! * .pi / 180) < sin(angles.last! * .pi / 180) { angles.reverse() }
            if dock == .bottom || dock == .top, cos(angles.first! * .pi / 180) > cos(angles.last! * .pi / 180) { angles.reverse() }
            result += angles.map { a in
                let r = a * .pi / 180
                return CGPoint(x: c.x + radius * cos(r), y: c.y + radius * sin(r))
            }
            remaining -= n
            ring += 1
        }
        return result
    }

    /// F27 반원 칸: `base` 방향(도, 90 = 위)을 가운데로 200° 펼친다
    static func halfRing(count: Int, center c: CGPoint, radius: Double, base: Double) -> [CGPoint] {
        (0..<count).map { i in
            let deg = count == 1 ? base : base + 100 - 200 * Double(i) / Double(count - 1)
            let a = deg * .pi / 180
            return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        }
    }

    /// F27: 반원을 펼 방향. 화면 안에 들어가고 다른 패널과 겹치지 않는 첫 방향(위·아래·오른쪽·왼쪽 순, 위가 좁으면 아래 먼저).
    /// 모두 겹치면 화면 안에 드는 첫 방향
    static func ringDirection(center c: CGPoint, radius: Double, in v: CGRect, occupied: [CGRect], preferUp: Bool) -> Double {
        let order: [Double] = preferUp ? [90, 270, 0, 180] : [270, 90, 0, 180]
        func area(_ base: Double) -> CGRect {
            let pts = halfRing(count: 7, center: c, radius: radius, base: base)
            let xs = pts.map(\.x), ys = pts.map(\.y), r: CGFloat = 30
            return CGRect(x: xs.min()! - r, y: ys.min()! - r, width: xs.max()! - xs.min()! + r * 2, height: ys.max()! - ys.min()! + r * 2)
        }
        let fits = order.filter { v.contains(area($0)) }
        return fits.first { b in !occupied.contains { $0.intersects(area(b)) } } ?? fits.first ?? order[0]
    }

    /// 펫 창에서 화면에 보이는 부분의 가운데. 링의 중심으로 쓴다.
    static func visibleCenter(of frame: CGRect, in v: CGRect) -> CGPoint {
        let r = frame.intersection(v)
        return r.isNull ? CGPoint(x: frame.midX, y: frame.midY) : CGPoint(x: r.midX, y: r.midY)
    }
}

/// `Tasky --selftest`로 실행하는 최소 검증.
enum SelfTest {
    static func run() -> Int32 {
        let v = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 120, height: 84)
        func check(_ ok: Bool, _ what: String) { if !ok { print("FAIL:", what); failures += 1 } }
        var failures = 0

        check(Geometry.dock(for: CGRect(x: 1330, y: 5, width: 120, height: 84), in: v) == .bottomRight, "오른쪽 아래 구석")
        check(Geometry.dock(for: CGRect(x: 5, y: 400, width: 120, height: 84), in: v) == .left, "왼쪽 가장자리")
        check(Geometry.dock(for: CGRect(x: 600, y: 400, width: 120, height: 84), in: v) == .free, "화면 가운데")
        check(Geometry.dock(for: CGRect(x: 600, y: 800, width: 120, height: 84), in: v) == .top, "위쪽도 붙음(F20)")

        let free = Geometry.frame(size: size, origin: CGPoint(x: 2000, y: -50), dock: .free, in: v)
        check(v.contains(free), "자유 상태는 화면 안으로")

        for dock in [Dock.left, .right, .bottom, .bottomLeft, .bottomRight] {
            let f = Geometry.frame(size: size, origin: CGPoint(x: 600, y: 400), dock: dock, in: v)
            let shown = f.intersection(v)
            check(!shown.isNull && shown.width * shown.height < size.width * size.height * 0.5, "\(dock) 절반 넘게 숨김")
            let c = Geometry.visibleCenter(of: f, in: v)
            for count in [8, 13] {   // 13 = 이미지 변환 링(칸이 가장 많음)
                let slots = Geometry.slotCenters(count: count, dock: dock, center: c)
                check(slots.count == count, "\(dock) 칸 \(count)개")
                check(slots.allSatisfy { v.insetBy(dx: 20, dy: 20).contains($0) }, "\(dock) 칸이 화면 안")
                for i in slots.indices { for j in slots.indices where j > i {
                    check(hypot(slots[i].x - slots[j].x, slots[i].y - slots[j].y) >= 40, "\(dock) \(count)칸 중 \(i),\(j) 겹침")
                } }
            }
        }
        let many = Geometry.slotCenters(count: 13, dock: .free, center: CGPoint(x: 700, y: 430))
        for i in many.indices { for j in many.indices where j > i {
            check(hypot(many[i].x - many[j].x, many[i].y - many[j].y) >= 40, "free 13칸 중 \(i),\(j) 겹침")
        } }
        let ring = Geometry.slotCenters(count: 8, dock: .free, center: CGPoint(x: 500, y: 500))
        check(ring.allSatisfy { $0.y > 500 - 20 }, "떠 있으면 펫 위쪽 반원(양 끝 10°만 살짝 아래)")
        for i in ring.indices { for j in ring.indices where j > i {
            check(hypot(ring[i].x - ring[j].x, ring[i].y - ring[j].y) >= 50, "free 8칸 중 \(i),\(j) 너무 가까움")
        } }
        check(Set(Geometry.slotCenters(count: 9, dock: .free, center: .zero).map { Int(hypot($0.x, $0.y).rounded()) }).count == 2, "7개 넘으면 두 겹")
        check(Geometry.slotCenters(count: 6, dock: .free, center: CGPoint(x: 500, y: 500), roomAbove: false).allSatisfy { $0.y < 500 + 20 }, "위 공간 없으면 아래로")

        // 작업 알림: 상태 전환
        let store = AgentStore()
        var announced: [AgentSession.State] = []
        store.onChange = { if let s = $0 { announced.append(s.state) } }
        func ev(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            ["session_id": "s1", "hook_event_name": name, "cwd": "/tmp/my-app", "tasky_tool": "claude"].merging(extra) { $1 }
        }
        store.apply(ev("UserPromptSubmit"))
        store.apply(ev("Notification", ["notification_type": "idle_prompt"]))
        check(store.sessions["claude:s1"]?.state == .working, "idle_prompt는 무시")
        store.apply(ev("Notification", ["notification_type": "permission_prompt"]))
        store.apply(ev("PostToolUse"))
        store.apply(ev("Stop", ["last_assistant_message": "1\n2\n3\n4"]))
        check(announced == [.working, .waiting, .working, .done], "상태 전환 \(announced)")
        check(store.sessions["claude:s1"]?.summary == "1\n2\n3", "요약은 3줄")
        check(store.unseenDone == 1 && store.sessions["claude:s1"]?.name == "my-app · Claude", "끝난 작업 1, 이름")
        store.apply(ev("SessionEnd"))
        check(store.sessions.isEmpty, "세션 종료")

        // 훅 → 소켓 → 앱 (TASKY_HOME 임시 폴더에서)
        if ProcessInfo.processInfo.environment["TASKY_HOME"] != nil {
            // 이름 바꾸기: 옛 Kongpod 실행 파일을 가리키는 훅을 찾아 새 것으로 갈아 끼운다
            let file = HookInstaller.Tool.claude.file
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"/old/Kongpod\" --hook claude"},{"type":"command","command":"other"}]}]}}"#.utf8).write(to: file)
            check(HookInstaller.pointsToLegacy(.claude), "옛 훅 찾기")
            try? HookInstaller.set(.claude, installed: true)
            let after = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            check(!HookInstaller.pointsToLegacy(.claude) && HookInstaller.isInstalled(.claude) && after.contains("other"), "옛 훅을 새 것으로, 다른 훅은 그대로")
            try? FileManager.default.removeItem(at: file)
            var got: [String: Any]?
            let server = HookServer { got = $0 }
            server.start()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            p.arguments = ["--hook", "codex"]
            let pipe = Pipe()
            p.standardInput = pipe
            try? p.run()
            pipe.fileHandleForWriting.write(Data(#"{"session_id":"x","hook_event_name":"Stop","cwd":"/tmp/a"}"#.utf8))
            try? pipe.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(3)
            while got == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            check(got?["tasky_tool"] as? String == "codex" && got?["hook_event_name"] as? String == "Stop", "훅이 소켓으로 전달")
        }

        // F6 싱잉볼: 알림 보류 규칙, 소리 세기, 오디오 엔진 켜고 끄기
        var rest = RestSession(start: Date())
        check(RestSession.route(.done) == .hold && RestSession.route(.failed) == .hold, "끝남·실패는 보류")
        check(RestSession.route(.waiting) == .small && RestSession.route(.working) == .none, "승인 대기는 작게, 일하는 중은 없음")
        rest.hold("a"); rest.hold("a"); rest.hold("b")
        check(rest.held == ["a", "b"], "보류는 중복 없이")
        check(BowlSynth.targetLevel(angularSpeed: 0) == 0 && BowlSynth.targetLevel(angularSpeed: 0.3) == 0, "느리면 울리지 않음")
        check(BowlSynth.targetLevel(angularSpeed: 3) == 1 && BowlSynth.targetLevel(angularSpeed: -3) == 1, "적당한 속도에서 가장 큼(방향 무관)")
        check(BowlSynth.targetLevel(angularSpeed: 1.5) < 1 && BowlSynth.targetLevel(angularSpeed: 12) < 1, "느리거나 너무 빠르면 작음")
        let d = BowlSynth.decayFactor(sampleRate: 44_100, seconds: 6)
        check(abs(powf(d, 6 * 44_100) - 0.01) < 0.001, "치기 소리는 6초에 1/100로 줄어듦")
        // 쉼 안·밖의 알림 결정 (App이 쓰는 함수 그대로)
        func session(_ st: AgentSession.State, _ id: String) -> AgentSession {
            AgentSession(id: id, tool: "claude", cwd: "/tmp/x", state: st, updated: Date())
        }
        var none: RestSession? = nil
        check(RestSession.shouldAnnounce(&none, session(.done, "x")), "쉼 밖 알림은 그대로")
        var resting: RestSession? = RestSession(start: Date())
        check(!RestSession.shouldAnnounce(&resting, session(.done, "d")) && resting?.held == ["d"], "쉬는 중 끝남 → 알림 없음, 보류 1건")
        check(!RestSession.shouldAnnounce(&resting, session(.waiting, "w")) && resting?.held == ["d"], "쉬는 중 승인 대기 → 알림 없음, 보류 추가 없음")
        let synth = BowlSynth()
        do {
            try synth.start()
            synth.volume = 0
            synth.strike()
            check(synth.isRunning, "오디오 엔진 시작")
            synth.stop()
            check(!synth.isRunning, "오디오 엔진 정지")
        } catch { print("NOTE: 오디오 출력 장치가 없어 엔진 검사를 건너뜀 (\(error.localizedDescription))") }

        // F8 귀환 브리핑: 모으기 규칙
        let away = Date(timeIntervalSince1970: 10_000)
        func ses(_ st: AgentSession.State, _ id: String, _ t: Double, tool: String = "claude") -> AgentSession {
            AgentSession(id: id, tool: tool, cwd: "/tmp/\(id)", state: st, updated: Date(timeIntervalSince1970: t))
        }
        var b = Briefing()
        check(b.collect(sessions: [ses(.done, "x", 20_000)], conversions: []) == 0 && b.items.isEmpty, "비운 적 없으면 모으지 않음")
        b.leave(at: away)
        b.leave(at: away.addingTimeInterval(500))
        check(b.awaySince == away, "겹친 자리 비움은 처음 시각 유지")
        let added = b.collect(sessions: [
            ses(.done, "old", 9_000), ses(.done, "new", 10_100), ses(.failed, "bad", 10_200),
            ses(.waiting, "wait", 5_000), ses(.working, "busy", 10_300),
        ], conversions: [(Date(timeIntervalSince1970: 9_999), [URL(fileURLWithPath: "/tmp/a")]),
                         (Date(timeIntervalSince1970: 10_050), [URL(fileURLWithPath: "/tmp/b")])])
        func kinds(_ b: Briefing) -> [String] {
            b.items.map { if case .agent(let s) = $0 { s.id } else if case .conversion(_, let u) = $0 { u[0].lastPathComponent } else { "?" } }
        }
        check(added == 4 && kinds(b) == ["wait", "bad", "new", "b"], "포함·제외·순서 \(kinds(b))")
        check(b.awaySince == nil && b.collect(sessions: [ses(.done, "z", 99_999)], conversions: []) == 0, "한 번 모으면 다음 돌아옴까지 0건")
        b.leave(at: away)
        b.collect(sessions: [ses(.done, "wait", 10_400)], conversions: [])
        let waitItem = b.items.first { if case .agent(let s) = $0 { s.id == "wait" } else { false } }
        check(kinds(b).filter { $0 == "wait" }.count == 1 && waitItem?.group == 2, "같은 세션은 하나(최신 상태로 묶음 이동)")
        let shown = b.items
        b.leave(at: away)
        b.collect(sessions: [ses(.done, "later", 10_500)], conversions: [])
        b.remove(shown)
        check(kinds(b) == ["later"], "닫으면 보여 준 항목만 비움(창이 열린 사이 새로 모인 것은 남음)")
        b.clear()
        check(b.items.isEmpty, "비움")
        b.leave(at: away)
        check(b.collect(sessions: [ses(.done, "old2", 9_000)], conversions: []) == 0 && b.items.isEmpty, "그 사이 일이 없으면 0건")

        // 자리 비움 출처: 뚜껑 닫기(잠금→잠자기→깨어나기→잠금 해제)는 잠금 해제에서 돌아옴
        var aw = AwayState()
        check(aw.start("lock") && !aw.start("sleep") && !aw.end("sleep") && aw.end("lock"), "잠금+잠자기는 잠금 해제에서 돌아옴")
        check(aw.start("rest") && !aw.start("lock") && !aw.end("lock") && aw.end("rest"), "쉼 중 잠금 해제는 아직 돌아옴 아님")
        check(!aw.end("sleep") && aw.sources.isEmpty, "시작 없이 온 끝은 무시")
        let only = [ses(.done, "c", 1, tool: "claude"), ses(.done, "x", 1, tool: "codex")].filter { PetController.accepts("claude", tool: $0.tool) }
        check(only.map(\.id) == ["c"] && PetController.accepts("all", tool: "codex"), "펫 도구 설정에 맞는 작업만")

        // F11 캐릭터: 그림 찾기(임시 폴더)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-f11-\(UUID().uuidString)")
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        func put(_ path: String) {
            let u = Character.root(home).appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: u)
        }
        // macOS 파일 이름은 자모가 분리된(NFD) 형태로 올 수 있다
        put("chick/" + "행복".decomposedStringWithCanonicalMapping + ".png")
        put("chick/점프.png"); put("chick/sad.png"); put("chick/원본/기본.png")
        put("empty/notes.txt")
        let chick = Character(name: "chick", base: home)
        check(chick?.files[.happy] != nil && chick?.files[.sad] != nil, "한국어·영어 이름 모두 찾기")
        check(chick?.files[.idle] == nil, "원본/ 하위 폴더는 읽지 않음")
        check(chick?.resolve(.idle) == .jump && chick?.resolve(.blink) == .jump, "기본이 없으면 점프로")
        check(chick?.resolve(.grumpy) == .sad && chick?.resolve(.bowl) == .jump, "대신 규칙: 화남→슬픔, 명상→졸음→기본→점프")
        check(chick?.image(.happy) != nil, "그림 읽기")
        check(Character.available(in: home) == ["chick"], "그림 없는 폴더는 목록에서 빠짐")
        check(Character(name: "nothing", base: home) == nil, "없는 캐릭터")
        try? FileManager.default.removeItem(at: home)

        // F11 반응 표와 판정
        let held: Set<Situation> = [.idle, .sleepy, .drag, .fileNear, .converting, .rest, .walk]
        check(Situation.allCases.allSatisfy { (Reaction.of($0).seconds == 0) == held.contains($0) }, "바탕 상황만 계속, 나머지는 잠깐")
        check(Reaction.of(.jobDone).pose == .jump && Reaction.of(.jobWaiting).effect == .exclaim && Reaction.of(.sleepy).effect == .zz, "상황 표")
        var pk = PokeCounter()
        let t0 = Date(timeIntervalSince1970: 1000)
        check((0..<4).map { pk.poke(at: t0.addingTimeInterval(Double($0) * 0.5)) } == [false, false, false, false], "4번은 괜찮음")
        check(pk.poke(at: t0.addingTimeInterval(2)), "3초 안 5번이면 삐침")
        check(!pk.poke(at: t0.addingTimeInterval(2.1)) && pk.times.count == 1, "삐친 뒤 처음부터")
        var pk2 = PokeCounter()
        check(![0, 1, 2, 3, 4].map { pk2.poke(at: t0.addingTimeInterval(Double($0) * 0.8)) }.contains(true), "3초를 넘겨 5번은 삐치지 않음")
        check(!Interaction.isSleepy(last: t0, now: t0.addingTimeInterval(299)) && Interaction.isSleepy(last: t0, now: t0.addingTimeInterval(300)), "5분이면 졸기")
        let sq = CGSize(width: 120, height: 120)
        let g = Interaction.glide(from: CGPoint(x: 1300, y: 10), velocity: CGVector(dx: 5000, dy: -5000), size: sq, in: v)
        check(g == CGPoint(x: v.maxX - 120, y: v.minY), "던지기는 화면 안에서 멈춤")
        check(Interaction.glide(from: CGPoint(x: 500, y: 400), velocity: CGVector(dx: 400, dy: 0), size: sq, in: v).x == 600, "던지기 감속 거리")
        check(Interaction.near(CGRect(x: 0, y: 0, width: 120, height: 120), CGRect(x: 150, y: 0, width: 120, height: 120))
              && !Interaction.near(CGRect(x: 0, y: 0, width: 120, height: 120), CGRect(x: 250, y: 0, width: 120, height: 120)), "펫끼리 거리")
        check(Geometry.dock(for: CGRect(x: 1330, y: 5, width: 120, height: 120), in: v) == .bottomRight
              && Geometry.frame(size: sq, origin: .zero, dock: .bottomRight, in: v).maxX > v.maxX, "정사각 창도 구석 빼꼼")
        // 몸이 창 가운데 절반만 차지해도, 빼꼼하면 몸의 38%가 화면에 보인다
        let half = CGRect(x: 0.25, y: 0, width: 0.5, height: 0.7)
        let pr = Geometry.frame(size: sq, origin: .zero, dock: .right, in: v, body: half)
        check(abs((v.maxX - (pr.minX + 0.25 * 120)) - 0.38 * 60) < 0.01, "빼꼼은 몸 기준으로 보인다")
        let pb = Geometry.frame(size: sq, origin: .zero, dock: .bottom, in: v, body: half)
        check(abs((pb.minY + 0.7 * 120 - v.minY) - 0.45 * 84) < 0.01, "아래 빼꼼은 머리쪽 45%")
        check(Geometry.slotCenters(count: 8, dock: .free, center: .zero, size: 200)[0].x < Geometry.slotCenters(count: 8, dock: .free, center: .zero)[0].x, "큰 펫은 링도 커짐")

        // F12 키보드: 판정
        func run(_ key: SwitchKey, _ events: [(KeyEvent, Double)]) -> [SwitchAction] {
            var j = SwitchJudge(key: key)
            return events.compactMap { j.feed($0.0, at: t0.addingTimeInterval($0.1)) }
        }
        let rcmdDown = KeyEvent.flags(code: 54, flags: 0x100000 | 0x10), rcmdUp = KeyEvent.flags(code: 54, flags: 0)
        check(run(.rightCommand, [(rcmdDown, 0), (rcmdUp, 0.1)]) == [.toggleInput], "오른쪽 ⌘ 혼자 → 전환")
        check(run(.rightCommand, [(rcmdDown, 0), (.down(code: 8, isRepeat: false), 0.05), (.up(code: 8), 0.08), (rcmdUp, 0.1)]).isEmpty, "⌘C → 전환 없음")
        check(run(.rightCommand, [(.flags(code: 55, flags: UInt64(0x100000 | 0x8)), 0), (.flags(code: 55, flags: 0), 0.1)]).isEmpty, "왼쪽 ⌘ 무시")
        check(run(.rightOption, [(.flags(code: 61, flags: UInt64(0x80000 | 0x40)), 0), (.flags(code: 61, flags: 0), 0.1)]) == [.toggleInput], "오른쪽 ⌥ 혼자 → 전환")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.up(code: 79), 0.49)]) == [.toggleInput], "Caps 짧게 → 누르는 순간 전환")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.up(code: 79), 0.5)]) == [.toggleInput, .capsInstead], "Caps 0.5초 → 전환 되돌리고 대문자 고정")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.down(code: 79, isRepeat: true), 0.3),
                              (.down(code: 79, isRepeat: true), 0.55), (.down(code: 79, isRepeat: true), 0.6), (.up(code: 79), 0.9)]) == [.toggleInput, .capsInstead],
              "Caps 누르고 있으면 0.5초에 한 번만 대문자 고정")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.down(code: 0, isRepeat: false), 0.05), (.up(code: 79), 0.08)]) == [.toggleInput], "빠르게 치다 Caps와 다음 글자가 겹쳐도 전환(씹힘 없음)")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.up(code: 79), 0.05), (.down(code: 79, isRepeat: false), 0.1), (.up(code: 79), 0.15)]) == [.toggleInput, .toggleInput], "연타 두 번 → 두 번 전환")
        var jt = SwitchJudge(key: .capsLock)
        _ = jt.feed(.down(code: 79, isRepeat: false), at: t0)
        check(jt.tick(at: t0.addingTimeInterval(0.5)) == .capsInstead && jt.feed(.up(code: 79), at: t0.addingTimeInterval(0.7)) == nil, "반복 없이도 0.5초에 대문자 고정, 떼면 그만")
        check(run(.rightCommand, [(.flags(code: 55, flags: UInt64(0x100000 | 0x8)), 0), (.flags(code: 54, flags: UInt64(0x100000 | 0x8 | 0x10)), 0.1),
                                  (.flags(code: 54, flags: UInt64(0x100000 | 0x8)), 0.2)]).isEmpty, "왼쪽 ⌘을 누른 채 오른쪽 ⌘ → 전환 없음")
        check(run(.rightCommand, [(rcmdDown, 0), (.down(code: -1, isRepeat: false), 0.1), (rcmdUp, 0.2)]).isEmpty, "⌘-클릭 → 전환 없음")
        check(run(.rightCommand, [(rcmdDown, 0), (rcmdUp, 1.5)]).isEmpty, "오래 누르고 떼면 전환 없음")
        // 매핑 합치기·빼기
        let other: KeyMapping.Entry = ["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2]
        check(KeyMapping.adding([]) == [KeyMapping.ours] && KeyMapping.adding(KeyMapping.adding([other])) == [other, KeyMapping.ours], "매핑 더하기(한 번만, 다른 항목 보존)")
        check(KeyMapping.removing([other, KeyMapping.ours]) == [other], "매핑 빼기(다른 항목 보존)")
        let multi = "RegistryID  Key   Value\n10000cba5   UserKeyMapping   (\n)\n10000cc5c   UserKeyMapping   (\n    {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\n"
        check(KeyMapping.parse(KeyMapping.firstBlock(multi)) == [], "키보드별 출력: 첫 장치 목록만(빈 목록)")
        check(KeyMapping.parse(KeyMapping.firstBlock("x   UserKeyMapping   (\n    {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\ny   UserKeyMapping   (\n)")) == [KeyMapping.ours], "키보드별 출력: 첫 장치 항목 읽기")
        check(KeyMapping.parse("(null)") == [] && KeyMapping.parse("{ weird }") == nil
              && KeyMapping.parse("(\n    {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)") == [KeyMapping.ours],
              "hidutil 출력 읽기")
        // 입력 소스, 키 반복
        let ko = InputSourceInfo(id: "ko", languages: ["ko"], asciiCapable: false), abc = InputSourceInfo(id: "abc", languages: ["en"], asciiCapable: true)
        check(InputSources.pair([abc, ko]).map { [$0.ko, $0.en] } == ["ko", "abc"] && InputSources.pair([abc]) == nil, "한국어·영문 찾기")
        check(InputSources.nextIsKorean(reportedKorean: true, last: nil, now: t0) == false
              && InputSources.nextIsKorean(reportedKorean: true, last: (false, t0), now: t0.addingTimeInterval(0.2)) == true
              && InputSources.nextIsKorean(reportedKorean: true, last: (false, t0), now: t0.addingTimeInterval(2)) == false,
              "연타: 바로 전에 고른 쪽 기준으로 뒤집기")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let noon = Date(timeIntervalSince1970: 3 * 3600 + 7 * 60 + 9)   // 서울 12:07:09
        check(ClockMode.text(noon, hour24: false, seconds: true, calendar: cal) == "오후 12:07:09"
              && ClockMode.text(noon.addingTimeInterval(-12 * 3600), hour24: false, seconds: true, calendar: cal) == "오전 12:07:09", "시계 글자(정오·자정)")
        check(ClockMode.text(noon.addingTimeInterval(3 * 3600), hour24: true, seconds: true, calendar: cal) == "15:07:09"
              && ClockMode.text(noon, hour24: true, seconds: false, calendar: cal) == "12:07", "시계 24시간제·초 끄기")
        // F16 클립보드
        var ch = ClipHistory(limit: 2)
        ch.insert(ClipItem(kind: .text, text: "하나"))
        ch.insert(ClipItem(kind: .text, text: "Two"))
        ch.items[1].pinned = true
        ch.insert(ClipItem(kind: .text, text: "셋"))
        ch.insert(ClipItem(kind: .text, text: "넷"))
        check(ch.items.map { $0.text ?? "" } == ["넷", "셋", "하나"], "개수 넘으면 오래된 것부터, 고정은 남음")
        ch.insert(ClipItem(kind: .text, text: "셋"))
        check(ch.items.map { $0.text ?? "" } == ["셋", "넷", "하나"], "같은 내용은 맨 위로")
        check(ch.search("two").isEmpty && ch.search("하").first?.text == "하나" && ch.search("").first?.pinned == true, "검색·고정 먼저")
        check(ClipHistory.isConcealed(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
              && !ClipHistory.isConcealed(types: ["public.utf8-plain-text"]), "숨김 복사 판정")
        let clipDir = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-clip-\(UUID().uuidString)")
        let store1 = ClipStore(folder: clipDir)
        store1.add(ClipItem(kind: .files, files: ["/tmp/a.txt"]))
        store1.save()
        check(ClipStore(folder: clipDir).history.items.first?.files == ["/tmp/a.txt"], "기록 저장·읽기")
        try? FileManager.default.removeItem(at: clipDir)

        // F20 빼꼼 아일랜드
        do {
            let v = CGRect(x: 0, y: 0, width: 1440, height: 900), c = CGPoint(x: 30, y: 450)
            check(Geometry.islandFrame(dock: .left, expanded: false, center: c, in: v) == CGRect(x: 4, y: 402, width: 30, height: 96), "아일랜드 왼쪽 접힘")
            let t = Geometry.islandFrame(dock: .top, expanded: true, center: CGPoint(x: 720, y: 890), in: v)
            check(t.maxY == 896 && t.width == 280, "아일랜드 위 가로, 펼쳐도 위 끝(아래로 미니 오늘)")
            check(Geometry.dock(for: CGRect(x: 600, y: 820, width: 120, height: 84), in: v) == .top, "위 가장자리 붙기")
            check(Geometry.dock(for: CGRect(x: 2, y: 820, width: 120, height: 84), in: v) == .left, "왼쪽 위 구석은 왼쪽")
            let e = Geometry.islandFrame(dock: .left, expanded: true, center: c, in: v)
            check(e.minX == 4 && e.size == CGSize(width: 250, height: 150), "아일랜드 왼쪽 펼침은 같은 끝(옆으로 서랍처럼)")
            let r = Geometry.islandFrame(dock: .right, expanded: true, center: CGPoint(x: 1400, y: 450), in: v)
            check(r.maxX == 1436, "아일랜드 오른쪽 펼침은 오른쪽 끝")
            let b = Geometry.islandFrame(dock: .bottom, expanded: true, center: CGPoint(x: 720, y: 10), in: v)
            check(b.minY == 4 && b.midX == 720 && b.size == CGSize(width: 280, height: 120), "아일랜드 아래 가로")
            let bl = Geometry.islandFrame(dock: .bottomLeft, expanded: false, center: .zero, in: v)
            check(bl.minX == 4 && bl.minY == 40 && bl.height == 96, "구석은 옆 세로 알약, 아래 40pt")
            let top = Geometry.islandFrame(dock: .right, expanded: true, center: CGPoint(x: 1400, y: 899), in: v)
            check(top.maxY == 896, "아일랜드 위쪽 끝 안")
            let small = CGRect(x: 0, y: 0, width: 1024, height: 640)
            for d in [Dock.left, .right, .bottom, .top, .bottomLeft, .bottomRight] {
                for ex in [false, true] {
                    let f = Geometry.islandFrame(dock: d, expanded: ex, center: CGPoint(x: 2000, y: -50), in: small)
                    check(small.contains(f), "아일랜드 작은 화면 안 \(d) \(ex)")
                }
            }
        }
        // F20 알약 링: 한 겹 부채꼴, 칸끼리 겹치지 않고 알약을 가리지 않음
        do {
            let v = CGRect(x: 0, y: 0, width: 1440, height: 900)
            for d in [Dock.top, .left, .right, .bottom, .bottomLeft] {
                let pill = Geometry.islandFrame(dock: d, expanded: false, center: CGPoint(x: 720, y: 450), in: v)
                let pts = Geometry.fanCenters(count: 7, dock: d, pill: pill)
                let r = pts.map { hypot($0.x - pill.midX, $0.y - pill.midY) }
                check(r.max()! - r.min()! < 0.5, "알약 링 한 겹 \(d)")
                check(zip(pts, pts.dropFirst()).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) >= 65 }, "알약 링 칸 간격 \(d)")
                check(!pts.contains(where: pill.insetBy(dx: -35, dy: -35).contains), "알약 링이 알약을 가리지 않음 \(d)")
            }
            let top = Geometry.fanCenters(count: 7, dock: .top, pill: Geometry.islandFrame(dock: .top, expanded: false, center: CGPoint(x: 720, y: 900), in: v))
            check(top.allSatisfy { $0.y < 896 - 30 }, "위 알약 링은 아래로")
        }
        // F21 링 칸 순서
        do {
            let ids = ["status", "drawer", "bowl", "clipboard", "settings"]
            check(RingOrder.apply(saved: [], ids: ids) == ids, "링 순서 저장 없으면 기본")
            check(RingOrder.apply(saved: ["settings", "status", "drawer", "bowl", "clipboard"], ids: ids) == ["settings", "status", "drawer", "bowl", "clipboard"], "링 순서 저장대로")
            check(RingOrder.apply(saved: ["drawer", "status", "old", "settings"], ids: ids) == ["drawer", "bowl", "clipboard", "status", "settings"], "링 새 칸은 기본 앞 칸 뒤에, 없어진 칸 무시")
            check(RingOrder.move([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4], "링 칸 뒤로 옮기기")
            check(RingOrder.move([1, 2, 3, 4], from: 3, to: 1) == [1, 4, 2, 3], "링 칸 앞으로 옮기기")
        }
        // F22 화면 캡처: 저장 이름·겹칠 때 번호
        do {
            var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 30; c.hour = 14; c.minute = 5; c.second = 12
            let d = Calendar.current.date(from: c)!
            check(Capture.fileName(d) { _ in false } == "Tasky 캡처 2026-10-30 14.05.12.png", "캡처 저장 이름")
            let taken: Set = ["Tasky 캡처 2026-10-30 14.05.12.png", "Tasky 캡처 2026-10-30 14.05.12 2.png"]
            check(Capture.fileName(d) { taken.contains($0) } == "Tasky 캡처 2026-10-30 14.05.12 3.png", "캡처 이름 겹치면 번호")
        }
        // F22 편집 창: 결과 크기·그린 자리 픽셀·자르기
        do {
            let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            let base = ctx.makeImage()!
            func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
                let c = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
                let p = c.data!.assumingMemoryBound(to: UInt8.self) + ((img.height - 1 - y) * img.width + x) * 4
                return (p[0], p[1], p[2])
            }
            let arrow = Mark(tool: .arrow, a: CGPoint(x: 10, y: 50), b: CGPoint(x: 90, y: 50))
            let out = MarkRender.image(base: base, marks: [arrow], scale: 1)!
            check(out.width == 100 && out.height == 100, "편집 결과 크기 = 원본")
            check(pixel(out, 40, 50).1 < 200, "화살표 자리 픽셀이 바뀜")
            check(pixel(out, 40, 90) == (255, 255, 255), "화살표 밖은 그대로")
            let cropped = MarkRender.image(base: base, marks: [arrow, Mark(tool: .crop, a: CGPoint(x: 20, y: 20), b: CGPoint(x: 60, y: 50))], scale: 1)!
            check(cropped.width == 40 && cropped.height == 30, "자르기 크기")
            check(MarkRender.image(base: base, marks: [Mark(tool: .mosaic, a: .zero, b: CGPoint(x: 50, y: 50)),
                                                       Mark(tool: .spotlight, a: CGPoint(x: 60, y: 60), b: CGPoint(x: 90, y: 90))], scale: 1) != nil, "모자이크·스포트라이트 그리기")
            check(pixel(MarkRender.image(base: base, marks: [Mark(tool: .spotlight, a: CGPoint(x: 60, y: 60), b: CGPoint(x: 90, y: 90))], scale: 1)!, 10, 10).0 < 200,
                  "스포트라이트 밖은 어두움")
            let text = NSImage(size: NSSize(width: 400, height: 80), flipped: false) { r in
                NSColor.white.setFill(); r.fill()
                NSAttributedString(string: "Tasky 캡처", attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 10, y: 15))
                return true
            }.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let read = CaptureEditor.recognize(text).joined()
            check(read.contains("Tasky") && read.contains("캡처"), "글자 인식: \(read)")
        }
        // F23 잠 안 자기
        do {
            let now = Date(timeIntervalSince1970: 0)
            check(Awake.end(minutes: 0, from: now) == nil, "영원히는 끝 없음")
            check(Awake.end(minutes: 720, from: now) == now.addingTimeInterval(43200), "12시간 끝 시각")
            check(Awake.left(42 * 60) == "남은 42분", "남은 분")
            check(Awake.left(41 * 60 + 1) == "남은 42분", "남은 분 올림")
            check(Awake.left(65 * 60) == "남은 1시간 5분", "남은 시간·분")
            check(Awake.left(720 * 60) == "남은 12시간", "남은 시간")
            check(Awake.left(5) == "남은 1분", "1분 미만")
        }
        // F18 3D 곰: 스프링·모션
        var sp = Spring(stiffness: 120, damping: 14)
        var peak = 0.0
        for _ in 0..<240 { sp.step(to: 1, dt: 1.0 / 60); peak = max(peak, sp.value) }
        check(abs(sp.value - 1) < 0.01 && peak > 1 && peak < 1.3, "3D 스프링이 넘쳤다가 목표로 돌아옴 \(peak)")
        var stiff = Spring(); stiff.step(to: 1, dt: 0.1)
        check(stiff.value.isFinite && abs(stiff.value) < 2, "3D 스프링 큰 dt에도 안정")
        let far = BearMotion.pose(.idle, t: 1, look: CGPoint(x: 1, y: 0), lean: 0, facingRight: false, reduce: false)
        check(abs(far.headYaw - BearPose.headYawLimit) < 1e-9, "3D 고개는 커서 쪽 최대 25°")
        check(BearMotion.pose(.drag, t: 0.3, look: .zero, lean: 0, facingRight: false, reduce: true).bodyTilt == 0
              && BearMotion.pose(.drag, t: 0.3, look: .zero, lean: 0, facingRight: false, reduce: false).bodyTilt != 0, "3D 동작 줄이기면 대롱대롱 없음")
        check(BearMotion.pose(.sleepy, t: 1, look: .zero, lean: 0, facingRight: false, reduce: false).eyes < 0.2, "3D 졸면 눈 감음")

        // F15 창 정리: 영역 계산·순환·가장자리·좌표
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let win = CGRect(x: 100, y: 100, width: 500, height: 400)
        check(SnapMath.rect(.leftHalf, area: area, current: win) == CGRect(x: 0, y: 0, width: 720, height: 900), "창 정리 왼쪽 반")
        check(SnapMath.rect(.rightHalf, area: area, current: win) == CGRect(x: 720, y: 0, width: 720, height: 900), "창 정리 오른쪽 반")
        check(SnapMath.rect(.topLeft, area: area, current: win) == CGRect(x: 0, y: 450, width: 720, height: 450), "창 정리 왼쪽 위 4분의 1")
        check(SnapMath.rect(.centerThird, area: area, current: win) == CGRect(x: 480, y: 0, width: 480, height: 900), "창 정리 가운데 3분의 1")
        check(SnapMath.rect(.lastTwoThirds, area: area, current: win) == CGRect(x: 480, y: 0, width: 960, height: 900), "창 정리 오른쪽 3분의 2")
        check(SnapMath.rect(.smaller, area: area, current: CGRect(x: 100, y: 100, width: 800, height: 600)) == CGRect(x: 130, y: 130, width: 740, height: 540), "창 정리 작게")
        check(SnapMath.rect(.larger, area: area, current: CGRect(x: 0, y: 100, width: 800, height: 600)) == CGRect(x: 0, y: 70, width: 860, height: 660), "창 정리 크게(화면 안으로)")
        check(SnapMath.rect(.smaller, area: area, current: CGRect(x: 0, y: 0, width: 210, height: 160)) == CGRect(x: 5, y: 5, width: 200, height: 150), "창 정리 작게 최소 크기")
        do {   // 바탕화면 보기 키
            var d = DesktopKey.State()
            check(d.handle(.press, at: 0) == [.startHoldTimer] && d.handle(.holdTimer, at: 0.25) == [.toggle], "꾹 누르면 바탕화면")
            check(d.handle(.press, at: 0.3) == [], "누르는 동안 반복 입력 무시")
            check(d.handle(.release, at: 1) == [.toggle], "떼면 돌아옴")
            check(d.handle(.press, at: 2) == [.startHoldTimer] && d.handle(.release, at: 2.1) == [.cancelHoldTimer], "짧게 한 번은 그대로")
            check(d.handle(.press, at: 2.3) == [.toggle] && d.handle(.release, at: 2.4) == [.cancelHoldTimer], "두 번 누르면 바탕화면에 머묾")
            check(d.handle(.holdTimer, at: 2.6) == [], "머무는 중 타이머 무시")
            check(d.handle(.press, at: 5) == [.toggle], "머무는 중 다시 누르면 돌아옴")
            _ = d.handle(.release, at: 5.1)
            check(d.handle(.press, at: 5.3) == [.startHoldTimer], "돌아온 직후 누름은 두 번 누르기로 보지 않음")
        }
        let shifted = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        check(SnapMath.rect(.bottomHalf, area: shifted, current: win) == CGRect(x: 1440, y: 25, width: 1920, height: 527.5), "창 정리 원점이 0이 아닌 화면")
        var cyc = CGRect.zero, widths: [CGFloat] = []
        for _ in 0..<4 { cyc = SnapMath.rect(.leftHalf, area: area, current: cyc)!; widths.append(cyc.width) }
        check(widths == [720, 960, 480, 720], "창 정리 반쪽 순환 1/2→2/3→1/3→1/2 \(widths)")
        check(!SnapController.displayRect(cur: area, from: area, to: CGRect(x: 1440, y: 0, width: 1280, height: 800)).origin.x.isNaN, "창 정리 최대화 창을 작은 모니터로(NaN 없음)")
        let scr = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check(SnapMath.edge(CGPoint(x: 3, y: 450), screen: scr) == .leftHalf, "창 정리 왼쪽 가장자리")
        check(SnapMath.edge(CGPoint(x: 2, y: 890), screen: scr) == .topLeft, "창 정리 왼쪽 위 모서리")
        check(SnapMath.edge(CGPoint(x: 720, y: 898), screen: scr) == .maximize, "창 정리 위 가장자리 = 최대화")
        check(SnapMath.edge(CGPoint(x: 720, y: 450), screen: scr) == nil, "창 정리 가운데는 없음")
        let upper = CGRect(x: 200, y: 900, width: 800, height: 600)   // 주 화면 위에 놓인 모니터의 창
        check(SnapMath.flip(SnapMath.flip(upper, primaryHeight: 900), primaryHeight: 900) == upper && SnapMath.flip(upper, primaryHeight: 900).minY == -600, "창 정리 좌표 왕복")
        let spaceLeft: [(code: UInt32, mods: UInt32)] = [(123, 0x1000)]   // ⌃← (Space 이동)
        check(SystemHotKeys.conflicts((123, 0x1000), in: spaceLeft), "창 정리 시스템 단축키와 같으면 겹침")
        check(!SystemHotKeys.conflicts(SnapAction.leftHalf.defaultKey, in: spaceLeft), "창 정리 ⌃⌥←는 ⌃←와 안 겹침")
        print("시스템 단축키(켜진 것):", SystemHotKeys.load().count, "개, 기본 창 정리 키와 겹침:",
              SnapAction.allCases.filter { SystemHotKeys.conflicts($0.defaultKey, in: SystemHotKeys.load()) }.map(\.title))

        // F14 작업 구슬
        let beadNow = Date()
        func ses(_ id: String, _ st: AgentSession.State, tool: String = "claude", app: String? = nil, seen: Bool = true, ago: Double = 0) -> AgentSession {
            var x = AgentSession(id: id, tool: tool, cwd: "/tmp/\(id)", state: st, updated: beadNow.addingTimeInterval(-ago), summary: nil, app: app)
            x.seen = seen
            return x
        }
        let mix = [ses("a", .working), ses("b", .working, ago: 5), ses("c", .waiting), ses("d", .done, seen: false), ses("e", .done)]
        check(BeadModel.beads(sessions: mix, converting: 0, frontApp: nil, accepts: { _ in true }).count == 4, "본 끝남은 구슬에서 빠짐")
        let front = BeadModel.beads(sessions: [ses("a", .working, app: "term", ago: 10), ses("b", .working, app: "term"), ses("c", .waiting)],
                                    converting: 0, frontApp: "term", accepts: { _ in true })
        check(front.filter(\.big).count == 1 && front.first { $0.big }?.title.hasPrefix("b") == true, "앞 앱의 가장 최근 세션만 큰 구슬")
        let six = BeadModel.beads(sessions: (0..<6).map { ses("s\($0)", .working) }, converting: 0, frontApp: nil, accepts: { _ in true })
        check(six.count == 4 && six.last?.kind == .more(3), "6개면 3개 + \"+3\"")
        check(BeadModel.beads(sessions: [ses("x", .working, tool: "codex")], converting: 1, frontApp: nil, accepts: { $0 == "claude" }).map(\.tag) == ["⇄"],
              "받지 않는 도구는 빠지고 변환은 남음")
        // F17
        let t1 = Ticker.every("검사", 100) { _ in }, t2 = Ticker.every("검사", 100) { _ in }
        check(Ticker.live.first { $0.name == "검사 (100초마다)" }?.count == 2, "타이머 2개 셈")
        t1.invalidate()
        check(Ticker.live.first { $0.name == "검사 (100초마다)" }?.count == 1, "멈춘 타이머는 빠짐")
        t2.invalidate()
        let o = Ticker.once("검사 한 번", 100) { _ in }
        check(Ticker.live.contains { $0.name == "검사 한 번 (한 번)" }, "한 번 타이머도 셈")
        o.invalidate()
        check(!Ticker.live.contains { $0.name.hasPrefix("검사 한 번") }, "한 번 타이머 끝나면 빠짐")
        check(PerfSampler.cpuPercent(prev: 1.0, now: 1.25, seconds: 1) == 25, "CPU % 계산")
        check(PerfSampler.csvLine(Date(timeIntervalSince1970: 0), .init(cpu: 1.25, memoryMB: 40, frames: 60, animations: 3, timers: 4))
              == "1970-01-01T00:00:00Z,1.2,40.0,60,3,4\n" || PerfSampler.csvLine(Date(timeIntervalSince1970: 0), .init(cpu: 1.25, memoryMB: 40, frames: 60, animations: 3, timers: 4)) == "1970-01-01T00:00:00Z,1.3,40.0,60,3,4\n", "CSV 한 줄")
        check(PerfSampler.memoryMB() > 1, "메모리 읽기")
        check(KeyRepeat.ms(15) == 250 && KeyRepeat.ms(2) == 33 && KeyRepeat.nanoseconds(2) == 33_333_333, "ms 변환(1/60초)")
        check(KeyRepeat.original(stored: nil, current: 15) == 15 && KeyRepeat.original(stored: 15, current: 10) == 15
              && KeyRepeat.original(stored: nil, current: nil) == -1, "원래 값은 처음 한 번만")
        check(KeyRepeat.restoreValue(-1) == nil && KeyRepeat.restoreValue(15) == 15, "원래 없었으면 지운다")

        // F24 QuickParse (기준: 2026-11-03 화 10:00)
        do {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
            let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10))!
            func d(_ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0, y: Int = 2026) -> Date {
                cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
            }
            let cases: [(String, QuickParse.Result)] = [
                ("내일 3시 치과", .init(title: "치과", date: d(11, 4, 15), hasTime: true)),
                ("오전 9시 반 회의", .init(title: "회의", date: d(11, 4, 9, 30), hasTime: true)),   // 오늘 그 시각이 지났으면 내일
                ("오늘 오전 9시 회의", .init(title: "회의", date: d(11, 3, 9), hasTime: true)),   // 날을 쓰면 그대로
                ("3시간 운동", .init(title: "3시간 운동", date: nil, hasTime: false)),
                ("3시 반찬 만들기", .init(title: "반찬 만들기", date: d(11, 3, 15), hasTime: true)),
                ("밤 12시 정리", .init(title: "정리", date: d(11, 4, 0), hasTime: true)),
                ("내일배움카드 신청", .init(title: "내일배움카드 신청", date: nil, hasTime: false)),
                ("모레 장보기", .init(title: "장보기", date: d(11, 5), hasTime: false)),
                ("다음 주 금요일 저녁 7시 저녁 약속", .init(title: "저녁 약속", date: d(11, 13, 19), hasTime: true)),
                ("금요일 보고서", .init(title: "보고서", date: d(11, 6), hasTime: false)),
                ("12월 1일 생일", .init(title: "생일", date: d(12, 1), hasTime: false)),
                ("11/20 마감", .init(title: "마감", date: d(11, 20), hasTime: false)),
                ("3월 2일 개학", .init(title: "개학", date: d(3, 2, y: 2027), hasTime: false)),
                ("3일 뒤 택배", .init(title: "택배", date: d(11, 6), hasTime: false)),
                ("14:30 통화", .init(title: "통화", date: d(11, 3, 14, 30), hasTime: true)),
                ("밤 11시 20분 정리", .init(title: "정리", date: d(11, 3, 23, 20), hasTime: true)),
                ("10시 산책", .init(title: "산책", date: d(11, 3, 10), hasTime: true)),
                ("책 읽기", .init(title: "책 읽기", date: nil, hasTime: false)),
            ]
            for (text, want) in cases {
                let got = QuickParse.parse(text, now: now, calendar: cal)
                check(got == want, "QuickParse \(text): \(got)")
            }
            // 묶음 나누기·알릴 항목 고르기
            func it(_ id: String, _ date: Date?, time: Bool = true) -> TaskItem { TaskItem(id: id, title: id, date: date, hasTime: time, isEvent: false) }
            let items = [it("어제", d(11, 2, 9)), it("오늘", d(11, 3, 20)), it("내일", d(11, 4, 9)), it("없음", nil, time: false),
                         it("곧", now.addingTimeInterval(30)), it("지남", now.addingTimeInterval(-30)), it("날만", d(11, 3), time: false)]
            let g = TaskLogic.groups(items, now: now, calendar: cal)
            check(g.today.map(\.id) == ["어제", "날만", "지남", "곧", "오늘"], "할 일 묶음: 오늘(지난 것 포함, 시간 순) \(g.today.map(\.id))")
            check(g.upcoming.map(\.id) == ["내일"] && g.undated.map(\.id) == ["없음"], "할 일 묶음: 다가오는 일·날짜 없음")
            var ev = it("일정", d(11, 3, 11)); ev.isEvent = true
            check(TaskLogic.pending(items + [ev], now: now, calendar: cal).map(\.id) == ["어제", "날만", "지남", "곧", "오늘", "없음"],
                  "남은 할 일: 오늘·날짜 없음, 일정·내일 제외")
            check(TaskLogic.due(items, now: now, alerted: []).map(\.id) == ["곧", "지남"], "알릴 항목: 2분 전~1분 뒤·시간 있는 것만")
            let key = TaskLogic.alertKey(items[4], at: items[4].date)!
            check(TaskLogic.due(items, now: now, alerted: [key]).map(\.id) == ["지남"], "알릴 항목: 이미 알린 것 제외")
            check(TaskLogic.due(items, now: now, alerted: [key], snoozed: ["곧": now.addingTimeInterval(600)]).map(\.id) == ["지남"], "알릴 항목: 미룬 것은 아직")
            check(TaskLogic.due(items, now: now.addingTimeInterval(590), alerted: [key], snoozed: ["곧": now.addingTimeInterval(600)]).map(\.id) == ["곧"], "알릴 항목: 미룬 시각에 다시")
            // 번들 밖(.build/debug)에서는 권한을 요청하지 않는다(설명 키가 없으면 앱이 죽을 수 있음)
            if Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") == nil {
                check(!TaskStore.canAsk(.reminder) && !TaskStore.canAsk(.event), "번들 밖에서는 권한 요청 안 함")
            }
            let bad = QuickParse.parse("2/30 메모", now: now, calendar: cal)
            check(bad.title.contains("2/30"), "QuickParse 없는 날은 제목에 남김: \(bad)")
            let en = QuickParse.parse("call mom tomorrow at 5pm", now: now, calendar: cal)
            check(en.hasTime && en.date != nil && en.title == "call mom", "QuickParse 대체(NSDataDetector): \(en)")
            let dateOnly = QuickParse.parse("dentist Dec 5", now: now, calendar: cal)
            check(dateOnly.date != nil && !dateOnly.hasTime, "QuickParse 날짜만 있으면 시간 없음: \(dateOnly)")
        }

        // F26 할 일 창 진행·완료 문구
        check(TaskLogic.progress(done: 2, left: 2) == (0.5, "오늘 2/4") && TaskLogic.progress(done: 0, left: 0).fraction == 0, "할 일 진행 막대")
        check(DoneToast.text("치과") == "‘치과’ 끝냈어요", "완료 토스트 문구")
        // F27 일정·할 일 알림 시각
        do {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let ev = TaskItem(id: "e", title: "치과", date: start, hasTime: true, isEvent: true)
            func at(_ min: Double) -> Date { start.addingTimeInterval(min * 60) }
            check(TaskLogic.eventAlerts([ev], now: at(-61), sent: []).isEmpty, "일정 알림: 1시간 전보다 이르면 없음")
            let h = TaskLogic.eventAlerts([ev], now: at(-60), sent: [])
            check(h.map(\.minutes) == [60], "일정 알림: 1시간 전")
            let sent = Set(h.flatMap(\.keys))
            check(TaskLogic.eventAlerts([ev], now: at(-45), sent: sent).isEmpty, "일정 알림: 같은 단계는 한 번")
            check(TaskLogic.eventAlerts([ev], now: at(-30), sent: sent).isEmpty, "일정 알림: 30분 전 알림은 없음(사용자가 직접 미룸)")
            check(TaskLogic.eventAlerts([ev], now: at(0.5), sent: sent).map(\.minutes) == [0], "일정 알림: 정각")
            let late = TaskLogic.eventAlerts([ev], now: at(0.5), sent: [])
            check(late.map(\.minutes) == [0] && late[0].keys.count == 2, "일정 알림: 늦게 켜지면 가장 최근 단계 하나만, 앞 단계도 보낸 것으로")
            check(TaskAlerts.pruned(["e@\(Int(start.timeIntervalSince1970))#60", "old@1000#0", "x"], now: start) == ["e@\(Int(start.timeIntervalSince1970))#60", "x"], "알림 기록: 이틀 지난 것만 버림")
            check(TaskAlertPanel.minutesText(90) == "1시간 30분" && TaskAlertPanel.minutesText(60) == "1시간" && TaskAlertPanel.minutesText(5) == "5분", "미루기 시간 글")
            check(TaskLogic.eventAlerts([ev], now: at(3), sent: []).isEmpty, "일정 알림: 시작 2분 뒤부터는 없음")
            var todo = ev; todo.isEvent = false
            check(TaskLogic.eventAlerts([todo], now: at(0), sent: []).isEmpty, "일정 알림: 할 일은 제외")
            check(TaskLogic.eventLead(start: start, now: at(-60)) == "1시간 뒤 일정" && TaskLogic.eventLead(start: start, now: at(-30)) == "30분 뒤 일정"
                  && TaskLogic.eventLead(start: start, now: at(-90)) == "1시간 30분 뒤 일정" && TaskLogic.eventLead(start: start, now: at(0)) == "지금 시작해요", "일정 알림 윗줄 문구")
            check(TaskLogic.nudgeDue(remaining: 2, last: at(-60), now: at(0), minutes: 60) && !TaskLogic.nudgeDue(remaining: 2, last: at(-59), now: at(0), minutes: 60), "할 일 알림: N분마다")
            check(!TaskLogic.nudgeDue(remaining: 0, last: at(-600), now: at(0), minutes: 60) && !TaskLogic.nudgeDue(remaining: 3, last: at(-600), now: at(0), minutes: 0), "할 일 알림: 남은 게 없거나 끄면 없음")
            let d = UserDefaults.standard
            let saved = (d.object(forKey: "eventDays"), d.object(forKey: "nudgeMinutes"))
            d.removeObject(forKey: "eventDays"); d.removeObject(forKey: "nudgeMinutes")
            check(TaskStore.eventDays == 7 && TaskStore.nudgeMinutes == 60, "설정 기본값: 일정 7일 · 할 일 60분")
            d.set(saved.0, forKey: "eventDays"); d.set(saved.1, forKey: "nudgeMinutes")
            let far = TaskItem(id: "f", title: "여행", date: start.addingTimeInterval(86400 * 8), hasTime: true, isEvent: true)
            check(TaskLogic.upcomingEvents([ev, far], now: at(-30), days: 7).map(\.id) == ["e"] && TaskLogic.upcomingEvents([ev], now: at(10), days: 7).isEmpty, "오늘 카드 일정: 기간 안·지난 것 제외")
            check(TaskAlertPanel.texts(.nudge([ev, ev]), now: at(-5)).lead == "남은 할 일 2개", "알림 패널: 남은 할 일 문구")
        }
        // F27 원형 메뉴 방향
        do {
            let v = CGRect(x: 0, y: 0, width: 1440, height: 900), c = CGPoint(x: 720, y: 450)
            check(Geometry.ringDirection(center: c, radius: 96, in: v, occupied: [], preferUp: true) == 90, "원형 메뉴: 기본은 위")
            check(Geometry.ringDirection(center: c, radius: 96, in: v, occupied: [CGRect(x: 600, y: 520, width: 300, height: 200)], preferUp: true) == 270, "원형 메뉴: 위에 패널이 있으면 아래")
            check(Geometry.ringDirection(center: c, radius: 96, in: v, occupied: [CGRect(x: 500, y: 520, width: 160, height: 200), CGRect(x: 500, y: 180, width: 160, height: 200)], preferUp: true) == 0, "원형 메뉴: 위아래가 막히면 옆")
            check(Geometry.ringDirection(center: CGPoint(x: 720, y: 880), radius: 96, in: v, occupied: [], preferUp: false) == 270, "원형 메뉴: 화면 위 끝이면 아래")
            let h = Geometry.halfRing(count: 6, center: c, radius: 100, base: 90)
            check(h.count == 6 && h.allSatisfy { $0.y >= c.y - 20 }, "원형 메뉴: 반원 6칸")
            check(ClockMode.allCases.map(\.title) == ["항상", "갖다대면", "안 봄"], "받침대 보기 3가지")
        }
        // F27 변환 칸
        do {
            func ops(_ names: [String]) -> [ConvertOp] { ConvertOp.options(for: names.map { URL(fileURLWithPath: "/tmp/" + $0) }) }
            check(!ops(["a.png"]).contains(.toPNG) && ops(["a.png"]).contains(.toJPEG) && ops(["a.png"]).contains(.imagesToPDF), "변환: PNG는 PNG 칸 없음, 1장도 PDF")
            check(!ops(["a.jpg"]).contains(.toJPEG) && !ops(["a.tif"]).contains(.toTIFF), "변환: jpg·tif도 같은 형식으로 봄")
            check(ops(["a.pdf"]).contains(.pdfToDOCX) && ops(["a.pdf"]).contains(.pdfSplit) && !ops(["a.pdf"]).contains(.pdfMerge) && ops(["a.pdf", "b.pdf"]).contains(.pdfMerge), "변환: PDF 칸, 여럿이면 합치기")
            check(ops(["a.csv"]) == [.csvToXLSX, .sheetToPDF, .zip] && ops(["a.xlsx"]) == [.sheetToCSV, .sheetToPDF, .zip], "변환: 표 칸")
            check(!ops(["a.mov"]).contains(.toMOV) && ops(["a.mov"]).contains(.posterFrame) && !ops(["a.m4a"]).contains(.toM4A) && ops(["a.m4a"]).contains(.toAIFF), "변환: 영상·오디오 같은 형식 빼기")
            check(!ops(["a.docx"]).contains(.docToDOCX) && ops(["a.docx"]).contains(.docToODT), "변환: 문서 ODT")
            check(ConvertOp.pdfToDOCX.note == "글자만" && ConvertOp.sheetToPDF.note == "단순 표", "변환: 품질 제한 칸 설명")
            check(XLSX.parseCSV("\u{FEFF}a,\"b,c\"\r\n\"x\"\"y\",2\n") == [["a", "b,c"], ["x\"y", "2"]], "CSV 읽기: 따옴표·쉼표·BOM")
            let xml = XLSX.sheetXML([["이름", "3", "007"]])
            check(xml.contains("<c r=\"B1\"><v>3</v></c>") && xml.contains("<t xml:space=\"preserve\">007</t>") && xml.contains("이름"), "엑셀 쓰기: 숫자·앞 0 글자")
        }
        // F27 원형 변환 배치·맞추기
        do {
            let one = WheelMath.layout(formats: 4, actions: 2, start: 90, span: 360)
            check(one.count == 6 && Set(one.map(\.r1)) == [WheelMath.single.r1], "변환 원: 7개 이하 고리 하나")
            let two = WheelMath.layout(formats: 5, actions: 7, start: 90, span: 360)
            check(two.prefix(5).allSatisfy { $0.r1 == WheelMath.inner.r1 } && two.suffix(7).allSatisfy { $0.r1 == WheelMath.outer.r1 }, "변환 원: 넘으면 두 고리(안 형식·밖 동작)")
            check(WheelMath.slot(CGPoint(x: 5, y: 100), one) == 0 && WheelMath.slot(CGPoint(x: -5, y: 100), one) == 5, "변환 원: 위 칸 맞추기(시계 방향)")
            check(WheelMath.slot(CGPoint(x: 10, y: 10), one) == nil && WheelMath.slot(CGPoint(x: 0, y: 300), one) == nil, "변환 원: 가운데·바깥은 칸 아님")
            check(WheelMath.slot(CGPoint(x: 5, y: 80), two) == 0 && WheelMath.slot(CGPoint(x: 5, y: 150), two) == 5, "변환 원: 안·밖 고리 구분")
            let v = CGRect(x: 0, y: 0, width: 1440, height: 900)
            check(WheelMath.arc(center: CGPoint(x: 720, y: 450), in: v, reach: 194) == (90, 360) && WheelMath.arc(center: CGPoint(x: 720, y: 60), in: v, reach: 194) == (180, 180), "변환 원: 화면 아래 끝이면 위 반원")
            let half = WheelMath.layout(formats: 3, actions: 0, start: 180, span: 180)
            check(WheelMath.slot(CGPoint(x: -100, y: 10), half) == 0 && WheelMath.slot(CGPoint(x: 100, y: 10), half) == 2 && WheelMath.slot(CGPoint(x: 0, y: -100), half) == nil, "변환 원: 반원 맞추기")
        }
        // F27 서랍 최근 파일
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("tasky-recent-\(UUID().uuidString)/프로젝트")
            try? fm.createDirectory(at: root.appendingPathComponent("a/b/c/d"), withIntermediateDirectories: true)
            let now = Date()
            func make(_ path: String, ago days: Double) {
                let u = root.appendingPathComponent(path)
                fm.createFile(atPath: u.path, contents: Data("x".utf8))
                try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86400)], ofItemAtPath: u.path)
            }
            make("new.txt", ago: 0.1); make("a/mid.txt", ago: 2); make("old.txt", ago: 9); make(".hidden", ago: 0); make("a/b/c/d/deep.txt", ago: 0)
            let r = RecentFiles.collect(roots: [root], now: now)
            check(r.map { $0.url.lastPathComponent } == ["new.txt", "mid.txt"] && r.last?.folder == "프로젝트/a", "서랍 최근: 7일 안·숨김·깊이 제외, 최신 순, 폴더 이름")
            try? fm.removeItem(at: root.deletingLastPathComponent())
        }
        // F27 클립보드: 고정은 칩 줄에, 검색하면 목록에도
        do {
            var a = ClipItem(kind: .text, text: "a"); a.pinned = true
            let b = ClipItem(kind: .text, text: "b")
            check(ClipWindow.listed([a, b], query: "").count == 2, "클립보드: 고정 항목도 목록에(키보드로 고르기)")
        }
        check(SnapController.isHelpChord([.control, .option]) && SnapController.isHelpChord([.control, .option, .capsLock]) && !SnapController.isHelpChord([.control, .option, .shift]) && !SnapController.isHelpChord([.control]), "창 정리 도움말: ⌃⌥만")
        // F27 작업 알림: 승인 대기만 패널
        check(AgentAlert.showsPanel(.waiting) && !AgentAlert.showsPanel(.done) && !AgentAlert.showsPanel(.failed) && !AgentAlert.showsPanel(.working), "작업 알림: 승인 대기만 패널")
        check(AgentAlert.askText(["tool_name": "Bash", "tool_input": ["command": "rm -rf build\necho"]]) == "Bash · rm -rf build", "승인 내용: 도구 · 명령 첫 줄")
        check(AgentAlert.askText(["message": "Claude needs your permission"]) == "Claude needs your permission" && AgentAlert.askText([:]) == nil, "승인 내용: 안내 문구")
        // F26 메뉴 막대 제목
        do {
            var g = Glance(); g.tasks = 3; g.tasksOn = true; g.next = "2:00 치과"
            check(g.menuTitle == "3 · 2:00 치과", "메뉴 막대 제목: \(g.menuTitle)")
            var e = Glance(); e.next = "2:00 치과"
            check(e.menuTitle == "2:00 치과" && Glance().menuTitle.isEmpty, "메뉴 막대 제목: 할 일 꺼지면 일정만")
        }
        // F26 칩 내용
        do {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
            let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 13, minute: 52))!
            func at(_ h: Int, _ m: Int, day: Int = 4) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }
            let items = [TaskItem(id: "a", title: "장보기", date: at(9, 0), hasTime: false, isEvent: false),
                         TaskItem(id: "b", title: "책 읽기", date: nil, hasTime: false, isEvent: false),
                         TaskItem(id: "c", title: "회의", date: at(11, 0), hasTime: true, isEvent: true),
                         TaskItem(id: "d", title: "치과", date: at(14, 0), hasTime: true, isEvent: true),
                         TaskItem(id: "e", title: "저녁", date: at(19, 0), hasTime: true, isEvent: true),
                         TaskItem(id: "f", title: "내일 일정", date: at(9, 0, day: 5), hasTime: true, isEvent: true)]
            let g = Glance.make(items: items, states: [.working, .done, .waiting], now: now, calendar: cal)
            check(g.tasks == 2, "칩: 남은 할 일 2(일정 제외)")
            check(g.next == "2:00 치과", "칩: 다음 일정은 오늘 가장 가까운 것 \(g.next)")
            check(g.dots == [.waiting, .done], "칩: 상태 점은 급한 순, 하는 중 제외")
            check(Glance.make(items: [], states: [], now: now, calendar: cal).isEmpty, "칩: 없으면 비어 있음")
            var ag = Glance(); ag.dots = [.done, .done]
            var aw = Glance(); aw.dots = [.waiting, .done]
            check(ag.isEmpty && aw.dots.first == .waiting, "배지: 작업 상태는 칩이 아니라 곰 배지(가장 급한 상태 색)")
            check(Glance.make(items: [], tasksOn: true, states: [], now: now, calendar: cal).isEmpty, "칩: 할 일 0개면 칩 없음(H2)")
            var withClock = Glance(); withClock.tasks = 1
            let w0 = GlanceChips.width(withClock); withClock.clock = "13:15:51"
            check(GlanceChips.width(withClock) > w0 && Glance(clock: "1:00").isEmpty, "칩: 시계를 합치면 길어지고, 시계만으로는 비어 있음(H1)")
            // F26 빠른 실행 후보
            let qa = QuickRun.candidates("내일 3시 치과", tasks: [], clips: [], now: now, calendar: cal)
            if case let .add(t, d, hasTime)? = qa.first?.kind { check(t == "치과" && hasTime && d != nil, "빠른 실행: 날짜 → 일정 추가 먼저") } else { check(false, "빠른 실행: 날짜 → 일정 추가 먼저 \(qa.first?.title ?? "")") }
            check(QuickRun.candidates("캡처", tasks: [], clips: [], now: now, calendar: cal).first?.kind == .command("capture.area"), "빠른 실행: 캡처 → 영역 캡처")
            check(QuickRun.candidates("왼쪽 반", tasks: [], clips: [], now: now, calendar: cal).first?.kind == .command("snap.leftHalf"), "빠른 실행: 왼쪽 반 → 창 정리")
            for t in ["창문 닦기", "잠옷 사기", "복사기 수리"] {   // 명령 단어가 든 할 일은 명령이 먼저 오면 안 된다
                check(QuickRun.candidates(t, tasks: [], clips: [], now: now, calendar: cal).first?.kind == .add(title: t, date: nil, hasTime: false), "빠른 실행: \(t) → 할 일 추가 먼저")
            }
            func qw(_ t: TaskItem) -> String { QuickRun.when(t, now: now, calendar: cal).text }
            check(qw(TaskItem(id: "p", title: "x", date: at(9, 0, day: 1), hasTime: true, isEvent: true)) == "지난 일정 · 3일 전", "빠른 실행: 지난 일정")
            check(qw(TaskItem(id: "p", title: "x", date: at(9, 0, day: 3), hasTime: false, isEvent: false)) == "놓친 할 일 · 어제", "빠른 실행: 놓친 할 일")
            check(qw(TaskItem(id: "p", title: "x", date: at(9, 0, day: 3), hasTime: false, isEvent: false, done: true)).hasPrefix("끝낸 할 일"), "빠른 실행: 끝낸 할 일")
            check(qw(TaskItem(id: "p", title: "x", date: at(9, 0, day: 9), hasTime: true, isEvent: true)).hasPrefix("5일 뒤 · 11/9"), "빠른 실행: 앞으로 \(qw(TaskItem(id: "p", title: "x", date: at(9, 0, day: 9), hasTime: true, isEvent: true)))")
            let qm = QuickRun.candidates("회의", tasks: items, clips: ["회의록 링크"], now: now, calendar: cal)
            check(qm.first?.kind == .task("c", isEvent: true) && qm.contains { $0.kind == .clip(0) } && qm.last?.kind == .add(title: "회의", date: nil, hasTime: false), "빠른 실행: 검색 → 할 일·클립보드, 맨 뒤 할 일 추가")
            check(Geometry.islandSize(dock: .top, expanded: false, chips: 200).width > Geometry.islandSize(dock: .top, expanded: false).width, "알약: 칩만큼 길어짐")
        }

        // F26 세션 제목·끝남 알림 판정
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-title-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            func write(_ name: String, _ lines: [String]) -> String {
                let u = dir.appendingPathComponent(name); try? lines.joined(separator: "\n").write(to: u, atomically: true, encoding: .utf8); return u.path
            }
            let both = write("a.jsonl", [#"{"type":"user","message":"hi"}"#, #"{"type":"ai-title","aiTitle":"옛 제목"}"#,
                                         #"{"type":"custom-title","customTitle":"플레이리스트 개발"}"#, #"{"type":"ai-title","aiTitle":"새 자동 제목"}"#])
            check(SessionTitle.read(both) == "플레이리스트 개발", "세션 제목: 직접 바꾼 이름 먼저")
            let ai = write("b.jsonl", [#"{"type":"ai-title","aiTitle":"옛 제목"}"#, #"{"type":"ai-title","aiTitle":"Daymelo 자동화"}"#])
            check(SessionTitle.read(ai) == "Daymelo 자동화", "세션 제목: 마지막 자동 제목")
            let cut = write("d.jsonl", ["가", #"{"type":"ai-title","aiTitle":"한글 중간에서 잘림"}"#])
            let cutSize = (try? FileManager.default.attributesOfItem(atPath: cut)[.size] as? Int) ?? 0
            check(SessionTitle.read(cut, tail: cutSize - 1) == "한글 중간에서 잘림", "세션 제목: 한글 글자 중간부터 읽어도 제목을 찾음")
            check(SessionTitle.read(write("c.jsonl", [#"{"type":"user"}"#])) == nil && SessionTitle.read(dir.appendingPathComponent("없음").path) == nil, "세션 제목: 없으면 nil")
            try? FileManager.default.removeItem(at: dir)
        }

        print(failures == 0 ? "selftest ok" : "selftest: \(failures) failed")
        return failures == 0 ? 0 : 1
    }
}
