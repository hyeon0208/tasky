import AppKit
import IOKit.hid

// F31 한영 전환 세부 설정. 근거: intent/F31-한영-전환-세부-설정/{spec,plan}.md

/// Caps를 바꿔 보낼 내부 키(F13–F20)
enum InternalKey: String, CaseIterable {
    case f13, f14, f15, f16, f17, f18, f19, f20

    var title: String { rawValue.uppercased() }
    /// 가상 키 코드(이벤트에서 보이는 값)
    var keyCode: Int64 {
        switch self {
        case .f13: 105
        case .f14: 107
        case .f15: 113
        case .f16: 106
        case .f17: 64
        case .f18: 79
        case .f19: 80
        case .f20: 90
        }
    }
    /// hidutil에 쓰는 HID 사용 값(페이지 7, F13 0x68 … F20 0x6F)
    var hid: UInt64 { 0x7_0000_0068 + UInt64(Self.allCases.firstIndex(of: self)!) }

    private static var cached: InternalKey?
    static var current: InternalKey {
        get {
            if let cached { return cached }
            let k = UserDefaults.standard.string(forKey: "kbInternalKey").flatMap(InternalKey.init) ?? .f18
            cached = k
            return k
        }
        set { cached = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: "kbInternalKey") }
    }
    /// 사용자가 한 번이라도 골랐는지(고른 뒤로만 시스템 단축키를 맞춘다)
    static var chosen: Bool {
        get { UserDefaults.standard.bool(forKey: "kbInternalKeyChosen") }
        set { UserDefaults.standard.set(newValue, forKey: "kbInternalKeyChosen") }
    }
}

enum SwitchOptions {
    /// ① Caps를 0.5초 누르면 대문자 고정(기본 켬)
    static var longPressCaps: Bool {
        get { UserDefaults.standard.object(forKey: "kbLongPressCaps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "kbLongPressCaps") }
    }
    /// ② 전환할 때 대문자 고정을 그대로 둔다(기본 끔 = 전환하면 대문자 고정을 끈다)
    static var keepCaps: Bool {
        get { UserDefaults.standard.bool(forKey: "kbKeepCaps") }
        set { UserDefaults.standard.set(newValue, forKey: "kbKeepCaps") }
    }
}

/// 시스템 '이전 입력 소스 선택'(60)·'다음 입력 소스 선택'(61) 단축키
enum SystemShortcut {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    static let fnFlag = 0x800000

    static func all() -> [String: Any] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
    }

    /// 켜진 항목의 (키 코드, 수정키). 읽지 못하면 nil
    static func binding(_ entry: Any?) -> (code: Int, mods: Int)? {
        guard let e = entry as? [String: Any], (e["enabled"] as? NSNumber)?.boolValue == true,
              let p = (e["value"] as? [String: Any])?["parameters"] as? [NSNumber], p.count == 3 else { return nil }
        return (p[1].intValue, p[2].intValue)
    }

    /// 60·61 중 켜진 것이 수정키 없는(fn 표시만) 그 키인지
    static func matches(_ code: Int64, in d: [String: Any]) -> Bool {
        ["60", "61"].contains { id in
            guard let b = binding(d[id]) else { return false }
            return Int64(b.code) == code && b.mods & ~fnFlag == 0
        }
    }

    /// 60·61 말고 다른 켜진 시스템 단축키가 수정키 없이 그 키를 쓰는지
    static func usedByOthers(_ code: Int64, in d: [String: Any]) -> Bool {
        d.contains { id, v in
            guard id != "60", id != "61", let b = binding(v) else { return false }
            return Int64(b.code) == code && b.mods & ~fnFlag == 0
        }
    }

    private static var savedKey: String { "kbHotkey60Original" }

    /// 60을 그 키로 맞춘다(처음 바꿀 때 원래 값을 저장)
    static func ensure(_ k: InternalKey) {
        var d = all()
        // 원래 단축키가 바로 그 키면(예: F19로 바꿨다가 F18로 돌아옴) 원래대로 되돌린다
        if let saved = UserDefaults.standard.data(forKey: savedKey), !saved.isEmpty,
           let original = try? PropertyListSerialization.propertyList(from: saved, format: nil),
           matches(k.keyCode, in: ["60": original]) { restore(); return }
        if matches(k.keyCode, in: d) { return }
        if UserDefaults.standard.data(forKey: savedKey) == nil {
            let original = d["60"].flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) } ?? Data()
            UserDefaults.standard.set(original, forKey: savedKey)
        }
        d["60"] = ["enabled": true, "value": ["parameters": [65535, Int(k.keyCode), fnFlag], "type": "standard"]] as [String: Any]
        write(d)
        if Debug.isOn { diag("시스템 단축키 60을 %@로 맞춤", k.title) }
    }

    /// 저장해 둔 원래 값으로 되돌린다(저장한 게 없으면 아무것도 안 함)
    static func restore() {
        guard let saved = UserDefaults.standard.data(forKey: savedKey) else { return }
        var d = all()
        d["60"] = saved.isEmpty ? nil : try? PropertyListSerialization.propertyList(from: saved, format: nil)
        write(d)
        UserDefaults.standard.removeObject(forKey: savedKey)
        if Debug.isOn { diag("시스템 단축키 60을 원래대로 되돌림") }
    }

    private static func write(_ d: [String: Any]) {
        CFPreferencesSetAppValue(key, d as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        // 로그아웃 없이 바로 적용
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        p.arguments = ["-u"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

/// 키보드별 설정(④)
enum DeviceUse: String, CaseIterable {
    case off, `default`, on
    var title: String {
        switch self {
        case .off: "끔"
        case .default: "기본값"
        case .on: "켬"
        }
    }
}

struct KeyboardDevice: Equatable {
    let vendor: Int
    let product: Int
    let name: String
    /// 내장 키보드는 vid·pid가 0이라 'Built-In'으로 구분한다
    var builtIn = false
    var id: String { builtIn ? "builtin" : "\(vendor):\(product)" }
    /// hidutil --matching 값(그 키보드의 키보드 기능만)
    var matching: String {
        builtIn ? #"{"Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6}"#
            : #"{"VendorID":\#(vendor),"ProductID":\#(product),"PrimaryUsagePage":1,"PrimaryUsage":6}"#
    }
}

enum Keyboards {
    /// 지금 연결된 키보드(vid:pid로 하나씩)
    static func connected() -> [KeyboardDevice] {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 6] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { return [] }
        var out: [KeyboardDevice] = []
        for d in set {
            let v = (IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let p = (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let name = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "키보드 \(v):\(p)"
            let builtIn = (IOHIDDeviceGetProperty(d, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue ?? false
            let k = KeyboardDevice(vendor: v, product: p, name: name, builtIn: builtIn)
            if builtIn || v != 0 || p != 0, !out.contains(where: { $0.id == k.id }) { out.append(k) }
        }
        return out.sorted { $0.name < $1.name }
    }

    typealias Config = [String: String]   // name, use, key
    static var saved: [String: Config] {
        get { UserDefaults.standard.dictionary(forKey: "kbDevices") as? [String: Config] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "kbDevices") }
    }

    /// 연결된 키보드를 기억한다(이름은 최신으로)
    static func remember(_ list: [KeyboardDevice]) {
        var s = saved
        for k in list { s[k.id, default: [:]]["name"] = k.name }
        if s != saved { saved = s }
    }

    static func use(_ id: String) -> DeviceUse { saved[id]?["use"].flatMap(DeviceUse.init) ?? .default }
    /// nil = 기본값(전체 '쓸 키')
    static func key(_ id: String) -> SwitchKey? { saved[id]?["key"].flatMap(SwitchKey.init) }
    static func set(_ id: String, use: DeviceUse) { var s = saved; s[id, default: [:]]["use"] = use.rawValue; saved = s }
    static func set(_ id: String, key: SwitchKey?) { var s = saved; s[id, default: [:]]["key"] = key?.rawValue; saved = s }
    static func forget(_ id: String) { var s = saved; s[id] = nil; saved = s }

    /// 장치의 실효 설정: 켜져 있으면 쓸 키, 꺼져 있으면 nil
    static func effectiveKey(_ id: String, globalOn: Bool, globalKey: SwitchKey) -> SwitchKey? {
        let u = use(id)
        guard u == .on || (u == .default && globalOn) else { return nil }
        return key(id) ?? globalKey
    }

    /// 감지할 키들. 키보드를 찾지 못하면 전체 설정 하나만
    static func activeKeys(_ devices: [KeyboardDevice], globalOn: Bool, globalKey: SwitchKey) -> [SwitchKey] {
        if devices.isEmpty { return globalOn ? [globalKey] : [] }
        let keys = Set(devices.compactMap { effectiveKey($0.id, globalOn: globalOn, globalKey: globalKey) })
        return SwitchKey.allCases.filter(keys.contains)
    }
}
