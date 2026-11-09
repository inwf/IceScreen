#if os(macOS)
import AppKit
import UserNotifications
import IceCore

@MainActor
final class DetectionActions: NSObject, UNUserNotificationCenterDelegate {
    var onError: ((String) -> Void)?
    var onOpen: ((UUID) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false
    private struct Command {
        let token: UUID
        let process: Process
        let timeout: Task<Void, Never>
    }
    private var commands: [UUID: Command] = [:]

    override init() { super.init(); center.delegate = self }

    func prepareNotifications() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error { self?.onError?(error.localizedDescription) }
                else if !granted { self?.onError?("通知尚未允许，可在系统设置 → 通知 → IceScreen 中开启。浮窗状态提示仍然可用。") }
            }
        }
    }

    func send(_ event: DetectionEvent, session: CaptureSession, preferences: Preferences) {
        if preferences.detectionNotifications {
            let content = UNMutableNotificationContent()
            content.title = session.appName
            content.body = event == .idle ? "\(session.title)：内容已停止变化。" : "\(session.title)：检测到新的画面变化。"
            content.sound = .default
            content.userInfo = ["session": session.id.uuidString]
            let request = UNNotificationRequest(identifier: session.id.uuidString + "." + event.rawValue,
                                                content: content, trigger: nil)
            center.add(request) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async { self?.onError?(error.localizedDescription) }
            }
        }
        let command = preferences.detectionCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, commands[session.id] == nil else { return }
        launch(command, event: event, session: session, timeout: preferences.detectionCommandTimeout)
    }

    private func launch(_ command: String, event: DetectionEvent, session: CaptureSession, timeout: TimeInterval) {
        let id = session.id
        let token = UUID()
        let process = Process()
        process.executableURL = Bundle.main.executableURL!
        process.arguments = ["--run-detection-command", command]
        var environment = ProcessInfo.processInfo.environment
        environment["ICESCREEN_EVENT"] = event.rawValue
        environment["ICESCREEN_APP"] = session.appName
        environment["ICESCREEN_BUNDLE_ID"] = session.bundleID
        environment["ICESCREEN_WINDOW_ID"] = String(session.source.windowID)
        environment["ICESCREEN_WINDOW_TITLE"] = session.title
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.commands[id]?.token == token else { return }
                kill(-process.processIdentifier, SIGKILL)
                self.commands.removeValue(forKey: id)?.timeout.cancel()
                if process.terminationStatus != 0 { self.onError?("检测命令执行失败，退出状态：\(process.terminationStatus)。") }
            }
        }
        do { try process.run() }
        catch { onError?("无法启动检测命令：\(error.localizedDescription)"); return }
        let timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            guard let self, self.commands[id]?.token == token else { return }
            self.stopCommand(id)
            self.onError?("检测命令超过 \(Int(timeout)) 秒，已终止。")
        }
        commands[id] = Command(token: token, process: process, timeout: timer)
    }

    private func stopCommand(_ id: UUID) {
        guard let command = commands.removeValue(forKey: id) else { return }
        command.timeout.cancel()
        command.process.terminationHandler = nil
        let pid = command.process.processIdentifier
        kill(-pid, SIGKILL)
        if command.process.isRunning { kill(pid, SIGKILL) }
    }

    func close(_ id: UUID) {
        stopCommand(id)
        let identifiers = ["idle", "change"].map { id.uuidString + "." + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func shutdown() { Array(commands.keys).forEach { stopCommand($0) } }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let value = response.notification.request.content.userInfo["session"] as? String, let id = UUID(uuidString: value) {
            DispatchQueue.main.async { [weak self] in self?.onOpen?(id) }
        }
        completionHandler()
    }
}
#endif
