import AppKit
import EventKit

if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }

// 권한 상태 보기(앱 번들로 실행해야 정확함): open -n dist/Tasky.app --args --permissions
if CommandLine.arguments.contains("--permissions") {
    let text = """
    손쉬운 사용: \(AXIsProcessTrusted())  화면 기록: \(CGPreflightScreenCaptureAccess())  입력 모니터링: \(CGPreflightListenEventAccess())
    미리 알림: \(EKEventStore.authorizationStatus(for: .reminder).rawValue)  캘린더: \(EKEventStore.authorizationStatus(for: .event).rawValue)  (3 = 전체 허용)
    번들: \(Bundle.main.bundleIdentifier ?? "없음")  경로: \(Bundle.main.bundlePath)
    """
    try? text.write(toFile: NSTemporaryDirectory() + "tasky-permissions.txt", atomically: true, encoding: .utf8)
    print(text); exit(0)
}

// Claude Code·Codex 훅이 실행: Tasky --hook claude|codex
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--hook" { exit(HookClient.run(tool: CommandLine.arguments[2])) }

// 명령줄에서 연결·끊기: Tasky --connect|--disconnect claude|codex
if CommandLine.arguments.count == 3, ["--connect", "--disconnect"].contains(CommandLine.arguments[1]),
   let tool = HookInstaller.Tool(rawValue: CommandLine.arguments[2]) {
    do {
        try HookInstaller.set(tool, installed: CommandLine.arguments[1] == "--connect")
        print("\(tool.title): \(HookInstaller.isInstalled(tool) ? "연결됨" : "연결 끊김") (\(tool.file.path))")
        exit(0)
    } catch { print("ERROR:", error.localizedDescription); exit(1) }
}

// 변환 확인용: Tasky --convert <작업 이름> <파일...>
if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--convert" {
    guard let op = ConvertOp(rawValue: CommandLine.arguments[2]) else { print("모르는 작업"); exit(2) }
    let urls = CommandLine.arguments.dropFirst(3).map { URL(fileURLWithPath: $0) }
    do { for url in try Converter.convert(op, urls) { print(url.path) } } catch { print("ERROR:", error.localizedDescription); exit(1) }
    exit(0)
}

// 3D 곰 모습 확인: Tasky --render-bear <폴더>
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-bear" {
    Pet3DView.renderSamples(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

RenameMigration.run()   // 옛 이름(Kongpod) 설정·폴더·훅을 처음 한 번 옮긴다
// .app으로 실행할 때만: 훅·로그인 항목이 다른 실행 파일을 가리키면 이 앱으로 고친다(디버그 빌드와 번갈아 바뀌지 않게)
if Bundle.main.bundlePath.hasSuffix(".app") {
    for tool in [HookInstaller.Tool.claude, .codex] where HookInstaller.pointsElsewhere(tool) {
        try? HookInstaller.set(tool, installed: true)
    }
    if LoginItem.isOn { LoginItem.set(true) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 메뉴 막대에만
let controller = App()
app.run()
