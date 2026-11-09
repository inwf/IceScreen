#if os(macOS)
import Foundation

@MainActor
final class MediaSeekAutomation {
    static let positionProperties = [
        "com.apple.Music": "player position", "com.apple.TV": "player position",
        "com.spotify.client": "player position", "com.swinsian.Swinsian": "player position",
        "org.videolan.vlc": "current time"
    ]
    private var pending: [String: Double] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var processes: [String: Process] = [:]
    private var generation = 0
    var onError: ((String) -> Void)?
    var onComplete: (() -> Void)?

    func seek(bundle: String, position: Double) {
        guard Self.positionProperties[bundle] != nil, position.isFinite, position >= 0 else { return }
        pending[bundle] = position
        guard tasks[bundle] == nil else { return }
        let number = generation
        tasks[bundle] = Task { [weak self] in
            guard let self else { return }
            defer { if number == self.generation { self.tasks[bundle] = nil } }
            while number == self.generation, !Task.isCancelled, let position = self.pending.removeValue(forKey: bundle) {
                await self.execute(bundle: bundle, position: position, generation: number)
            }
        }
    }
    private func execute(bundle: String, position: Double, generation number: Int) async {
        guard let property = Self.positionProperties[bundle] else { return }
        let value = bundle == "org.videolan.vlc" ? String(Int(position.rounded()))
            : String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        let script = "with timeout of 20 seconds\nif application id \"\(bundle)\" is running then\n"
            + "tell application id \"\(bundle)\" to set \(property) to \(value)\nend if\nend timeout"
        let process = Process(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do { try process.run() }
        catch { onError?(error.localizedDescription); return }
        processes[bundle] = process
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer { timeout.cancel(); if number == generation { processes[bundle] = nil } }
        do {
            var message = ""
            for try await line in errors.fileHandleForReading.bytes.lines { message += line + "\n" }
            while process.isRunning && !Task.isCancelled { try await Task.sleep(for: .milliseconds(20)) }
            guard !Task.isCancelled else { return }
            if process.terminationStatus != 0 {
                pending[bundle] = nil
                onError?("无法调整来源进度，请检查系统设置中的自动化权限。\n" + message.trimmingCharacters(in: .whitespacesAndNewlines))
            } else { onComplete?() }
        } catch { if !Task.isCancelled { onError?(error.localizedDescription) } }
    }
    func stop() {
        generation += 1
        pending.removeAll()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        processes.values.filter(\.isRunning).forEach { $0.terminate() }; processes.removeAll()
    }
}
#endif
