import AppKit

// F11 캐릭터·인터랙션. 근거: intent/F11-캐릭터-인터랙션/{intent,spec,plan,ASSETS}.md

/// 표정 그림 이름. 파일은 영어(`idle.png`) 또는 한국어(`기본.png`) 이름으로 둔다.
enum Pose: String, CaseIterable {
    case idle, blink, sleep, happy, surprised, sad, handup, mouthopen, squish, dangle, walk1, walk2, bowl, grumpy, jump

    var korean: String {
        switch self {
        case .idle: "기본"
        case .blink: "눈감음"
        case .sleep: "졸음"
        case .happy: "행복"
        case .surprised: "놀람"
        case .sad: "슬픔"
        case .handup: "인사"
        case .mouthopen: "입벌림"
        case .squish: "눌림"
        case .dangle: "대롱"
        case .walk1: "걷기"
        case .walk2: "걷기2"
        case .bowl: "명상"
        case .grumpy: "화남"
        case .jump: "점프"
        }
    }

    /// 그림이 없을 때 찾아볼 순서. 기본이 없으면 무표정에 가까운 점프, 그다음 행복.
    var chain: [Pose] {
        let idleChain: [Pose] = [.idle, .jump, .happy]
        switch self {
        case .idle: return idleChain
        case .jump: return [.jump, .happy, .idle]
        case .walk2: return [.walk2, .walk1] + idleChain
        case .bowl: return [.bowl, .sleep] + idleChain
        case .grumpy: return [.grumpy, .sad] + idleChain
        default: return [self] + idleChain
        }
    }
}

/// 캐릭터 한 종의 그림 폴더. 처음 쓸 때 읽어 캐시한다. 하위 폴더(`원본/` 등)는 읽지 않는다.
final class Character {
    static let names: [String: String] = [
        "chick": "병아리", "capybara": "카피바라", "hamster": "햄스터", "seal": "물범", "blueshark": "파란 상어",
        "shiba": "시바", "cat": "고양이", "grayshark": "회색 상어", "bird": "새",
    ]
    static func root(_ base: URL = Paths.support) -> URL { base.appendingPathComponent("Characters") }

    /// 그림이 하나라도 있는 캐릭터 폴더 이름(정렬)
    static func available(in base: URL = Paths.support) -> [String] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root(base), includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !Character(folder: $0).files.isEmpty }
            .map(\.lastPathComponent).sorted()
    }

    let name: String
    private let folder: URL
    /// 있는 표정 → 파일
    let files: [Pose: URL]
    private var cache: [Pose: NSImage] = [:]

    init(folder: URL) {
        self.folder = folder
        name = folder.lastPathComponent
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let byName = Dictionary(urls.filter { $0.pathExtension.lowercased() == "png" }
            .map { ($0.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping, $0) }) { a, _ in a }
        var files: [Pose: URL] = [:]
        for pose in Pose.allCases {
            if let u = byName[pose.rawValue] ?? byName[pose.korean.precomposedStringWithCanonicalMapping] { files[pose] = u }
        }
        self.files = files
    }

    convenience init?(name: String, base: URL = Paths.support) {
        let dir = Self.root(base).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        self.init(folder: dir)
    }

    var displayName: String { Self.names[name] ?? name }

    /// 실제로 쓰일 표정(대신 규칙 적용). 그림이 하나도 맞지 않으면 nil.
    func resolve(_ pose: Pose) -> Pose? { pose.chain.first { files[$0] != nil } }

    /// 기본 그림에서 불투명한 부분(0...1 비율, 아래가 0). 빼꼼·링 위치를 몸 기준으로 잡는 데 쓴다.
    lazy var bodyRect: CGRect = {
        guard let cg = image(.idle)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let w = rep.pixelsWide, h = rep.pixelsHigh, step = max(1, w / 128)
        var minX = w, maxX = 0, minY = h, maxY = 0
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        // 비트맵 y는 위가 0
        return CGRect(x: CGFloat(minX) / CGFloat(w), y: 1 - CGFloat(maxY + step) / CGFloat(h),
                      width: CGFloat(maxX - minX + step) / CGFloat(w), height: CGFloat(maxY - minY + step) / CGFloat(h))
    }()

    func image(_ pose: Pose) -> NSImage? {
        guard let p = resolve(pose), let url = files[p] else { return nil }
        if let img = cache[p] { return img }
        let img = NSImage(contentsOf: url)
        cache[p] = img
        return img
    }
}

/// 머리 위 효과. `Effects/<이름>.png`가 없으면 SF Symbols로 대신한다.
enum Effect: String, CaseIterable {
    case zz, dots, exclaim, question, heart, sweat, sparkle, puff, note, shock

    private var symbol: String {
        switch self {
        case .zz: "zzz"
        case .dots: "ellipsis.bubble"
        case .exclaim: "exclamationmark"
        case .question: "questionmark"
        case .heart: "heart.fill"
        case .sweat: "drop.fill"
        case .sparkle: "sparkles"
        case .puff: "cloud"
        case .note: "music.note"
        case .shock: "burst"
        }
    }

    private static var cache: [Effect: NSImage] = [:]

    var image: NSImage? {
        if let img = Self.cache[self] { return img }
        let file = Paths.support.appendingPathComponent("Effects/\(rawValue).png")
        let img = NSImage(contentsOf: file) ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .bold)
                .applying(.init(paletteColors: [NSColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1)])))
        Self.cache[self] = img
        return img
    }
}

/// 펫이 놓인 상황. 바탕 상황(대기·졸기·끌기·파일 다가옴·변환 중·쉼·걷기)은 바뀔 때까지 이어지고,
/// 나머지는 잠깐 보였다가 바탕으로 돌아간다.
enum Situation: CaseIterable {
    case idle, sleepy, click, pet, sulk, drag, land, toss, fileNear, converting, converted
    case jobDone, jobWaiting, jobFailed, briefing, rest, walk, friend
}

enum Motion { case none, breathe, breatheSlow, breatheRest, hop, jumpTwice, sway, squish, pendulum, shake, chew, stretch, wave, walk, turn }

struct Reaction: Equatable {
    let pose: Pose
    let motion: Motion
    let effect: Effect?
    /// 0이면 바탕 상황(다음 상황까지 유지)
    let seconds: Double

    /// ASSETS.md 5절의 상황별 동작 표
    static func of(_ s: Situation) -> Reaction {
        switch s {
        case .idle: Reaction(pose: .idle, motion: .breathe, effect: nil, seconds: 0)
        case .sleepy: Reaction(pose: .sleep, motion: .breatheSlow, effect: .zz, seconds: 0)
        case .click: Reaction(pose: .happy, motion: .hop, effect: nil, seconds: 0.5)
        case .pet: Reaction(pose: .happy, motion: .sway, effect: .heart, seconds: 1.2)
        case .sulk: Reaction(pose: .grumpy, motion: .turn, effect: .puff, seconds: 3)
        case .drag: Reaction(pose: .dangle, motion: .pendulum, effect: nil, seconds: 0)
        case .land: Reaction(pose: .squish, motion: .squish, effect: nil, seconds: 0.4)
        case .toss: Reaction(pose: .surprised, motion: .none, effect: .shock, seconds: 0.8)
        case .fileNear: Reaction(pose: .mouthopen, motion: .stretch, effect: nil, seconds: 0)
        case .converting: Reaction(pose: .mouthopen, motion: .chew, effect: nil, seconds: 0)
        case .converted: Reaction(pose: .happy, motion: .hop, effect: .sparkle, seconds: 1.2)
        case .jobDone: Reaction(pose: .jump, motion: .jumpTwice, effect: .note, seconds: 1.2)
        case .jobWaiting: Reaction(pose: .handup, motion: .sway, effect: .exclaim, seconds: 2.5)
        case .jobFailed: Reaction(pose: .sad, motion: .shake, effect: .sweat, seconds: 2.5)
        case .briefing: Reaction(pose: .handup, motion: .wave, effect: nil, seconds: 1.6)
        case .rest: Reaction(pose: .bowl, motion: .breatheRest, effect: nil, seconds: 0)
        case .walk: Reaction(pose: .walk1, motion: .walk, effect: nil, seconds: 0)
        case .friend: Reaction(pose: .happy, motion: .hop, effect: .heart, seconds: 1.5)
        }
    }
}

/// 너무 자주 찌르면 삐침: 3초 안에 5번
struct PokeCounter {
    private(set) var times: [Date] = []
    mutating func poke(at now: Date = Date()) -> Bool {
        times = times.filter { now.timeIntervalSince($0) < 3 } + [now]
        guard times.count >= 5 else { return false }
        times = []
        return true
    }
}

enum Interaction {
    /// 마지막 상호작용 뒤 5분이면 존다
    static func isSleepy(last: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(last) >= 300 }

    /// 던지기: 놓을 때 속도(pt/s)로 미끄러지다 마찰로 멈추는 자리. 화면 안으로 제한한다.
    static func glide(from origin: CGPoint, velocity v: CGVector, size: CGSize, in screen: CGRect) -> CGPoint {
        let travel: CGFloat = 0.25   // 감속이 끝날 때까지 간 거리 = 속도 × 0.25초
        return CGPoint(x: min(max(origin.x + v.dx * travel, screen.minX), screen.maxX - size.width),
                       y: min(max(origin.y + v.dy * travel, screen.minY), screen.maxY - size.height))
    }

    /// 펫끼리 가까움: 가운데 사이가 200pt 안
    static func near(_ a: CGRect, _ b: CGRect) -> Bool { hypot(a.midX - b.midX, a.midY - b.midY) < 200 }
}
