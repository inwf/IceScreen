#if os(macOS)
import AppKit
import CoreServices
import OSLog

enum ApplicationIdentity {
    @MainActor static func prepare() {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app" else { return }
        guard let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              let iconURL = bundle.url(forResource: iconName, withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            preconditionFailure("Application bundle is missing its declared icon")
        }
        NSApp.applicationIconImage = image

        let identity = [bundle.bundleURL.resolvingSymlinksInPath().path,
                        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                        iconName]
        let defaults = UserDefaults.standard
        let key = "IceScreen.registeredApplicationIdentity"
        guard defaults.stringArray(forKey: key) != identity else { return }
        // 更新当前应用的系统注册信息；成功后记录，避免每次启动重复注册。
        let status = LSRegisterURL(bundle.bundleURL as CFURL, true)
        if status == noErr {
            defaults.set(identity, forKey: key)
        } else {
            Logger(subsystem: "org.icescreen.app", category: "ApplicationIdentity")
                .error("Application registration failed with status \(status)")
        }
    }
}
#endif
