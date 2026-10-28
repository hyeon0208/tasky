import AppKit

if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }

// Claude Code·Codex 훅이 실행: Kongpod --hook claude|codex
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--hook" { exit(HookClient.run(tool: CommandLine.arguments[2])) }

// 명령줄에서 연결·끊기: Kongpod --connect|--disconnect claude|codex
if CommandLine.arguments.count == 3, ["--connect", "--disconnect"].contains(CommandLine.arguments[1]),
   let tool = HookInstaller.Tool(rawValue: CommandLine.arguments[2]) {
    do {
        try HookInstaller.set(tool, installed: CommandLine.arguments[1] == "--connect")
        print("\(tool.title): \(HookInstaller.isInstalled(tool) ? "연결됨" : "연결 끊김") (\(tool.file.path))")
        exit(0)
    } catch { print("ERROR:", error.localizedDescription); exit(1) }
}

// 변환 확인용: Kongpod --convert <작업 이름> <파일...>
if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--convert" {
    guard let op = ConvertOp(rawValue: CommandLine.arguments[2]) else { print("모르는 작업"); exit(2) }
    let urls = CommandLine.arguments.dropFirst(3).map { URL(fileURLWithPath: $0) }
    do { for url in try Converter.convert(op, urls) { print(url.path) } } catch { print("ERROR:", error.localizedDescription); exit(1) }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 메뉴 막대에만
let controller = App()
app.run()
