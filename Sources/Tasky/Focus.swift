import Foundation
import Intents

/// F27: macOS 집중 모드가 켜져 있는지. 켜져 있으면 일정·할 일 알림 패널을 띄우지 않는다.
/// INFocusStatusCenter는 권한을 받아야 읽힌다. 받지 못하면(서명·기능 제약 등) 늘 꺼진 것으로 본다.
enum FocusState {
    static var available: Bool { INFocusStatusCenter.default.authorizationStatus == .authorized }
    static var isOn: Bool { available && INFocusStatusCenter.default.focusStatus.isFocused == true }

    /// 번들로 실행했고 설명 키가 있을 때만 권한을 묻는다
    static func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") != nil,
              INFocusStatusCenter.default.authorizationStatus == .notDetermined else { return }
        INFocusStatusCenter.default.requestAuthorization { status in
            NSLog("Tasky 집중 모드 권한: \(status.rawValue)")
        }
    }
}
