import AppKit

// Claude Code·Codex 작업 알림.
// 도구가 실행하는 훅 → `Kongpod --hook <도구>`가 이벤트를 앱 소켓으로 보내고 바로 끝난다.
// 콩깍지는 이벤트만 받으므로 도구의 로그인 방식(구독·API 키)과 상관없고, 계정 정보를 다루지 않는다.

enum Paths {
    static let support: URL = {
        let dir = (ProcessInfo.processInfo.environment["KONGPOD_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Kongpod")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let socket = support.appendingPathComponent("hook.sock").path
    /// 펫이 꺼져 있을 때 훅이 이벤트를 적어 두는 곳
    static let spool = support.appendingPathComponent("spool.jsonl")
}

// MARK: 훅 쪽 (도구가 실행하는 짧은 프로세스)

enum HookClient {
    /// stdin의 이벤트에 도구 이름과 터미널 앱을 붙여 소켓으로 보낸다. 아무것도 출력하지 않고 항상 0으로 끝낸다.
    static func run(tool: String) -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { return 0 }
        payload["kongpod_tool"] = tool
        payload["kongpod_time"] = Date().timeIntervalSince1970
        // 터미널 앱(macOS가 앱에서 실행한 프로세스에 넣어 주는 값). '터미널로 가기'에 쓴다.
        payload["kongpod_app"] = ProcessInfo.processInfo.environment["__CFBundleIdentifier"]
        guard var line = try? JSONSerialization.data(withJSONObject: payload) else { return 0 }
        line.append(0x0A)
        if !send(line) {
            if let h = try? FileHandle(forWritingTo: Paths.spool) {
                h.seekToEndOfFile(); h.write(line); try? h.close()
            } else {
                FileManager.default.createFile(atPath: Paths.spool.path, contents: line, attributes: [.posixPermissions: 0o600])
            }
        }
        return 0
    }

    private static func send(_ data: Data) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un.make(Paths.socket)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return false }
        return data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) } == data.count
    }
}

extension sockaddr_un {
    static func make(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(path.utf8.prefix(buf.count - 1))
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        return addr
    }
}

// MARK: 앱 쪽 소켓

final class HookServer {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let onEvent: ([String: Any]) -> Void

    init(onEvent: @escaping ([String: Any]) -> Void) { self.onEvent = onEvent }

    func start() {
        unlink(Paths.socket)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un.make(Paths.socket)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(Paths.socket, 0o600) == 0, listen(fd, 16) == 0 else { close(fd); return }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    private func acceptOne() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        // 같은 사용자 계정의 프로세스만 받는다
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16_384)
        while data.count < 1_000_000 {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        DispatchQueue.main.async { self.onEvent(obj) }
    }

    /// 펫이 꺼져 있던 동안 쌓인 이벤트
    static func drainSpool() -> [[String: Any]] {
        guard let text = try? String(contentsOf: Paths.spool, encoding: .utf8) else { return [] }
        try? FileManager.default.removeItem(at: Paths.spool)
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }
}

// MARK: 세션 상태

struct AgentSession {
    enum State { case working, waiting, done, failed }
    let id: String
    let tool: String
    var cwd: String
    var state: State
    var updated: Date
    var summary: String?
    var app: String?
    var seen = true
    var whileOff = false

    var name: String {
        "\(URL(fileURLWithPath: cwd).lastPathComponent) · \(tool == "codex" ? "Codex" : "Claude")"
    }
}

final class AgentStore {
    private(set) var sessions: [String: AgentSession] = [:]
    /// 상태가 바뀌어 알릴 만한 세션 (새 상태)
    var onChange: (AgentSession?) -> Void = { _ in }

    var ordered: [AgentSession] {
        sessions.values.sorted { a, b in
            let rank: (AgentSession.State) -> Int = { [.waiting: 0, .failed: 1, .done: 2, .working: 3][$0]! }
            return rank(a.state) != rank(b.state) ? rank(a.state) < rank(b.state) : a.updated > b.updated
        }
    }

    var unseenDone: Int { sessions.values.filter { $0.state == .done && !$0.seen }.count }
    var waiting: Int { sessions.values.filter { $0.state == .waiting }.count }

    func apply(_ e: [String: Any], offline: Bool = false) {
        guard let id = e["session_id"] as? String, let event = e["hook_event_name"] as? String else { return }
        let tool = e["kongpod_tool"] as? String ?? "claude"
        let key = "\(tool):\(id)"
        let time = (e["kongpod_time"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        var s = sessions[key] ?? AgentSession(id: key, tool: tool, cwd: e["cwd"] as? String ?? "?", state: .working, updated: time)
        if let cwd = e["cwd"] as? String { s.cwd = cwd }
        if let app = e["kongpod_app"] as? String { s.app = app }
        s.updated = time
        s.whileOff = offline

        let before = sessions[key]?.state
        switch event {
        case "SessionStart", "UserPromptSubmit", "PostToolUse":
            s.state = .working
        case "Notification":
            guard ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog"].contains(e["notification_type"] as? String ?? "") else { return }
            s.state = .waiting
        case "PermissionRequest":   // Codex: 승인을 물으려 함
            s.state = .waiting
        case "Stop":
            s.state = .done
            s.seen = false
            s.summary = (e["last_assistant_message"] as? String).map(Self.firstLines)
        case "StopFailure":
            s.state = .failed
            s.seen = false
        case "SessionEnd":
            sessions[key] = nil
            onChange(nil)
            return
        default:
            return
        }
        sessions[key] = s
        onChange(before == s.state && event != "Stop" ? nil : s)
    }

    func markSeen() { for k in sessions.keys where sessions[k]!.state != .working { sessions[k]!.seen = true } }

    func remove(_ id: String) { sessions[id] = nil; onChange(nil) }

    private static func firstLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).prefix(3).joined(separator: "\n")
    }
}

// MARK: 훅 연결·끊기

/// 사용자의 도구 설정 파일에 우리 훅만 넣고 뺀다. 바꾸기 전에 백업을 남기고, 다른 훅은 건드리지 않는다.
enum HookInstaller {
    enum Tool: String { case claude, codex
        var title: String { self == .claude ? "Claude Code" : "Codex" }
        var file: URL {
            // KONGPOD_HOME: 검증할 때 실제 설정 파일 대신 임시 폴더를 쓰기 위함
            let home = ProcessInfo.processInfo.environment["KONGPOD_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser
            return self == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
        }
        /// 이벤트 이름 → matcher(없으면 nil)
        var events: [(String, String?)] {
            switch self {
            case .claude: [("SessionStart", nil), ("UserPromptSubmit", nil), ("PostToolUse", nil),
                           ("Notification", "permission_prompt|elicitation_dialog|elicitation_url_dialog"),
                           ("Stop", nil), ("StopFailure", nil), ("SessionEnd", nil)]
            case .codex: [("SessionStart", nil), ("UserPromptSubmit", nil), ("PostToolUse", nil),
                          ("PermissionRequest", nil), ("Stop", nil)]
            }
        }
    }

    private static func command(_ tool: Tool) -> String {
        "\"\(Bundle.main.executablePath ?? CommandLine.arguments[0])\" --hook \(tool.rawValue)"
    }

    private static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains("Kongpod\" --hook") == true
    }

    private static func read(_ tool: Tool) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: tool.file.path) else { return [:] }
        let data = try Data(contentsOf: tool.file)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvertError("\(tool.file.lastPathComponent)을 읽을 수 없어요")
        }
        return obj
    }

    static func isInstalled(_ tool: Tool) -> Bool {
        guard let hooks = (try? read(tool))?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { (($0 as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [Any]) ?? []).contains(where: isOurs) } }
    }

    /// 바뀔 내용 설명 (확인 창에 보여준다)
    static func preview(_ tool: Tool, install: Bool) -> String {
        let names = tool.events.map(\.0).joined(separator: ", ")
        return install
            ? "\(tool.file.path)에 콩깍지 훅을 추가해요.\n이벤트: \(names)\n\n기존 내용은 백업해 두고, 다른 훅은 그대로 둬요. 훅은 이벤트를 펫에게 보내기만 하고 작업을 기다리게 하지 않아요."
            : "\(tool.file.path)에서 콩깍지 훅만 빼요. 바꾸기 전에 백업해 둬요."
    }

    static func set(_ tool: Tool, installed: Bool) throws {
        var root = try read(tool)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // 먼저 우리 것을 모두 뺀다(다시 넣을 때 중복되지 않게)
        for (event, value) in hooks {
            var groups = (value as? [[String: Any]]) ?? []
            groups = groups.compactMap { g in
                var g = g
                let rest = ((g["hooks"] as? [Any]) ?? []).filter { !isOurs($0) }
                if rest.isEmpty { return nil }
                g["hooks"] = rest
                return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        if installed {
            for (event, matcher) in tool.events {
                var group: [String: Any] = ["hooks": [["type": "command", "command": command(tool), "async": true, "timeout": 10]]]
                if let matcher { group["matcher"] = matcher }
                hooks[event] = ((hooks[event] as? [[String: Any]]) ?? []) + [group]
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks

        let fm = FileManager.default
        var permissions = 0o600
        if fm.fileExists(atPath: tool.file.path) {
            permissions = (try? fm.attributesOfItem(atPath: tool.file.path)[.posixPermissions] as? Int) ?? 0o600
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            let backup = tool.file.appendingPathExtension("kongpod-backup-\(stamp)-\(UUID().uuidString.prefix(4))")
            try fm.copyItem(at: tool.file, to: backup)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        } else {
            try fm.createDirectory(at: tool.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: tool.file, options: .atomic)
        // 원래 권한 유지 (설정 파일에 토큰 등이 있을 수 있다)
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: tool.file.path)
    }
}
