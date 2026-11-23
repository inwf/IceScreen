#if os(macOS)
import AppKit
import CoreServices
import CryptoKit
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

        // 图标可在版本号和安装路径不变时替换，内容摘要用于失效系统注册缓存。
        let iconDigest: String?
        do {
            let iconData = try Data(contentsOf: iconURL)
            iconDigest = SHA256.hash(data: iconData).map { String(format: "%02x", $0) }.joined()
        } catch {
            iconDigest = nil
        }
        let identity = iconDigest.map { digest in
            [bundle.bundleURL.resolvingSymlinksInPath().path,
             bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
             iconName, digest]
        }
        let defaults = UserDefaults.standard
        let key = "IceScreen.registeredApplicationIdentity"
        if let identity, defaults.stringArray(forKey: key) == identity { return }
        // 更新当前应用的系统注册信息；成功后记录，避免每次启动重复注册。
        let status = LSRegisterURL(bundle.bundleURL as CFURL, true)
        if status == noErr, let identity {
            defaults.set(identity, forKey: key)
        } else {
            Logger(subsystem: "org.icescreen.app", category: "ApplicationIdentity")
                .error("Application registration failed with status \(status)")
        }
    }
}
#endif
