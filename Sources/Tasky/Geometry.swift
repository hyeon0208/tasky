import AppKit

/// 펫이 화면 어디에 붙어 있는지. 위쪽 가장자리는 메뉴 막대와 겹쳐서 붙지 않는다.
enum Dock: String {
    case free, left, right, bottom, bottomLeft, bottomRight

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
        let x: CGFloat, y: CGFloat
        switch dock {
        case .free: (x, y) = (clampedX, clampedY)
        case .left: (x, y) = (leftX, clampedY)
        case .right: (x, y) = (rightX, clampedY)
        case .bottom: (x, y) = (clampedX, bottomY)
        case .bottomLeft: (x, y) = (leftX, bottomY)
        case .bottomRight: (x, y) = (rightX, bottomY)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
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
            if dock == .bottom, cos(angles.first! * .pi / 180) > cos(angles.last! * .pi / 180) { angles.reverse() }
            result += angles.map { a in
                let r = a * .pi / 180
                return CGPoint(x: c.x + radius * cos(r), y: c.y + radius * sin(r))
            }
            remaining -= n
            ring += 1
        }
        return result
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
        check(Geometry.dock(for: CGRect(x: 600, y: 800, width: 120, height: 84), in: v) == .free, "위쪽은 붙지 않음")

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
            ["session_id": "s1", "hook_event_name": name, "cwd": "/tmp/my-app", "kongpod_tool": "claude"].merging(extra) { $1 }
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
            check(got?["kongpod_tool"] as? String == "codex" && got?["hook_event_name"] as? String == "Stop", "훅이 소켓으로 전달")
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
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.up(code: 79), 0.49)]) == [.toggleInput], "Caps 짧게 → 전환")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.up(code: 79), 0.5)]) == [.toggleCapsLock], "Caps 0.5초 → 대문자 고정")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.down(code: 79, isRepeat: true), 0.3),
                              (.down(code: 79, isRepeat: true), 0.55), (.down(code: 79, isRepeat: true), 0.6), (.up(code: 79), 0.9)]) == [.toggleCapsLock],
              "Caps 누르고 있으면 0.5초에 한 번만 대문자 고정")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.down(code: 0, isRepeat: false), 0.1), (.up(code: 79), 0.2)]).isEmpty, "Caps+다른 키 → 전환 없음")
        check(run(.capsLock, [(.down(code: 79, isRepeat: false), 0), (.down(code: 79, isRepeat: false), 5), (.up(code: 79), 5.1)]) == [.toggleInput], "떼기를 놓쳐도 다음 짧은 누름은 전환")
        var jt = SwitchJudge(key: .capsLock)
        _ = jt.feed(.down(code: 79, isRepeat: false), at: t0)
        check(jt.tick(at: t0.addingTimeInterval(0.5)) == .toggleCapsLock && jt.feed(.up(code: 79), at: t0.addingTimeInterval(0.7)) == nil, "반복 없이도 0.5초에 대문자 고정, 떼면 그만")
        check(run(.rightCommand, [(.flags(code: 55, flags: UInt64(0x100000 | 0x8)), 0), (.flags(code: 54, flags: UInt64(0x100000 | 0x8 | 0x10)), 0.1),
                                  (.flags(code: 54, flags: UInt64(0x100000 | 0x8)), 0.2)]).isEmpty, "왼쪽 ⌘을 누른 채 오른쪽 ⌘ → 전환 없음")
        check(run(.rightCommand, [(rcmdDown, 0), (.down(code: -1, isRepeat: false), 0.1), (rcmdUp, 0.2)]).isEmpty, "⌘-클릭 → 전환 없음")
        check(run(.rightCommand, [(rcmdDown, 0), (rcmdUp, 1.5)]).isEmpty, "오래 누르고 떼면 전환 없음")
        // 매핑 합치기·빼기
        let other: KeyMapping.Entry = ["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2]
        check(KeyMapping.adding([]) == [KeyMapping.ours] && KeyMapping.adding(KeyMapping.adding([other])) == [other, KeyMapping.ours], "매핑 더하기(한 번만, 다른 항목 보존)")
        check(KeyMapping.removing([other, KeyMapping.ours]) == [other], "매핑 빼기(다른 항목 보존)")
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

        print(failures == 0 ? "selftest ok" : "selftest: \(failures) failed")
        return failures == 0 ? 0 : 1
    }
}
