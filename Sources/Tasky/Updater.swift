import AppKit
import Sparkle

/// F29 자동 업데이트(Sparkle). appcast는 저장소의 appcast.xml을 raw URL로 읽고, 내려받은 파일은 EdDSA로 검증한다.
/// .app으로 실행했고 Info.plist에 공개 키가 있을 때만 켠다(`swift build`로 띄운 개발 빌드는 업데이트하지 않음).
enum Updater {
    static let controller: SPUStandardUpdaterController? = {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    static var isAvailable: Bool { controller != nil }
    static func checkNow() { controller?.checkForUpdates(nil) }
    static var automatic: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
