#if os(macOS)
import AppKit
import IceCore

@MainActor
final class MediaController {
    private var process: Process?
    private var input: FileHandle?
    private var readTask: Task<Void, Never>?
    private var generation = 0
    private let automation = MediaSeekAutomation()
    private(set) var snapshots: [MediaSnapshot] = []
    var onChange: (([MediaSnapshot]) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        guard process == nil else { return }
        automation.onError = { [weak self] in self?.onError?($0) }
        automation.onComplete = { [weak self] in self?.send(.init(action: "refresh")) }
        guard let resources = Bundle.main.resourceURL else { onError?(L10n.text("找不到媒体控制资源。", "Media control resources were not found.")); return }
        let library = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libIceMediaBridge.dylib")
        let script = resources.appendingPathComponent("media-bridge.pl")
        guard FileManager.default.fileExists(atPath: library.path), FileManager.default.fileExists(atPath: script.path) else {
            onError?(L10n.text("媒体辅助进程缺失，请使用完整的 IceScreen.app。", "The media helper is missing. Use the complete IceScreen.app bundle.")); return
        }
        let child = Process(), output = Pipe(), commands = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [script.path, library.path]
        child.standardInput = commands; child.standardOutput = output
        child.standardError = FileHandle.standardError
        generation += 1
        let number = generation
        do { try child.run() }
        catch { onError?(error.localizedDescription); return }
        process = child; input = commands.fileHandleForWriting
        readTask = Task { [weak self] in
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard let self, !Task.isCancelled, number == self.generation else { return }
                    let response = try JSONDecoder().decode(MediaResponse.self, from: Data(line.utf8))
                    if let snapshots = response.snapshots { self.snapshots = snapshots; self.onChange?(snapshots) }
                    if let code = response.errorCode { self.onError?(code.localizedDescription) }
                    else if let error = response.error { self.onError?(error) }
                }
                guard let self, !Task.isCancelled, number == self.generation else { return }
                self.stop(); self.onError?(L10n.text("媒体辅助进程已经停止。请在设置中重新开启媒体控制。", "The media helper stopped. Enable media controls again in Settings."))
            } catch {
                guard let self, !Task.isCancelled, number == self.generation else { return }
                self.stop(); self.onError?(error.localizedDescription)
            }
        }
    }
    func send(_ request: MediaRequest) {
        guard let input else { return }
        if request.action == "seek", let position = request.position,
           let source = snapshots.first(where: { $0.id == request.id }),
           let bundle = [source.parentBundleID, source.bundleID].compactMap({ $0 }).first(where: { MediaSeekAutomation.positionProperties[$0] != nil }) {
            automation.seek(bundle: bundle, position: position)
            return
        }
        do {
            var data = try JSONEncoder().encode(request); data.append(10)
            try input.write(contentsOf: data)
        } catch { stop(); onError?(error.localizedDescription) }
    }
    func stop() {
        automation.stop()
        generation += 1; readTask?.cancel(); readTask = nil
        input?.closeFile(); input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; snapshots = []; onChange?([])
    }
}
#endif
