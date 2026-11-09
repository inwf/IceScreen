#if os(macOS)
import AppKit
import IceCore

@MainActor
final class MediaController {
    private var process: Process?
    private var input: FileHandle?
    private var readTask: Task<Void, Never>?
    private var generation = 0
    private(set) var snapshots: [MediaSnapshot] = []
    var onChange: (([MediaSnapshot]) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        guard process == nil else { return }
        guard let resources = Bundle.main.resourceURL else { onError?("找不到媒体控制资源。"); return }
        let library = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libIceMediaBridge.dylib")
        let script = resources.appendingPathComponent("media-bridge.pl")
        guard FileManager.default.fileExists(atPath: library.path), FileManager.default.fileExists(atPath: script.path) else {
            onError?("媒体辅助进程缺失，请使用完整的 IceScreen.app。"); return
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
                    if let error = response.error { self.onError?(error) }
                }
                guard let self, !Task.isCancelled, number == self.generation else { return }
                self.stop(); self.onError?("媒体辅助进程已经停止。请在设置中重新开启媒体控制。")
            } catch {
                guard let self, !Task.isCancelled, number == self.generation else { return }
                self.stop(); self.onError?(error.localizedDescription)
            }
        }
    }
    func send(_ request: MediaRequest) {
        guard let input else { return }
        do {
            var data = try JSONEncoder().encode(request); data.append(10)
            try input.write(contentsOf: data)
        } catch { stop(); onError?(error.localizedDescription) }
    }
    func stop() {
        generation += 1; readTask?.cancel(); readTask = nil
        input?.closeFile(); input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; snapshots = []; onChange?([])
    }
}
#endif
