#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import IceCore

@MainActor
final class WindowActivation {
    private typealias SetFrontProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32
    private typealias PostFocusEvent = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeRawPointer) -> Int32
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcess = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32

    private static let connection = Result { try WindowActivation() }
    private let library: UnsafeMutableRawPointer
    private let setFrontProcess: SetFrontProcess
    private let postFocusEvent: PostFocusEvent
    private let getWindowID: GetWindowID
    private let getProcess: GetProcess

    private init() throws {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else {
            throw RequestError.message("无法加载系统窗口定位接口。")
        }
        guard let processImage = dlopen(nil, RTLD_LAZY) else {
            dlclose(library)
            throw RequestError.message("无法读取系统进程接口。")
        }
        defer { dlclose(processImage) }
        guard let front = dlsym(library, "_SLPSSetFrontProcessWithOptions"),
              let event = dlsym(library, "SLPSPostEventRecordTo"),
              let window = dlsym(processImage, "_AXUIElementGetWindow"),
              let process = dlsym(processImage, "GetProcessForPID") else {
            dlclose(library)
            throw RequestError.message("当前系统缺少窗口定位接口。")
        }
        self.library = library
        setFrontProcess = unsafeBitCast(front, to: SetFrontProcess.self)
        postFocusEvent = unsafeBitCast(event, to: PostFocusEvent.self)
        getWindowID = unsafeBitCast(window, to: GetWindowID.self)
        getProcess = unsafeBitCast(process, to: GetProcess.self)
    }

    deinit { dlclose(library) }

    static func windowID(of element: AXUIElement) throws -> CGWindowID? {
        let connection = try connection.get()
        var identifier: CGWindowID = 0
        guard connection.getWindowID(element, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }

    static func bringForward(processID: pid_t, windowID: CGWindowID) throws {
        let connection = try connection.get()
        var process = ProcessSerialNumber()
        let lookup = connection.getProcess(processID, &process)
        guard lookup == noErr else { throw RequestError.message("无法取得来源进程（\(lookup)）。") }
        let result = connection.setFrontProcess(&process, windowID, 0x200)
        guard result == noErr else { throw RequestError.message("系统无法置前来源窗口（\(result)）。") }

        // WindowServer 的窗口焦点事件，窗口 ID 使用网络字节序。
        var record = [UInt8](repeating: 0, count: 0xf8)
        record[4] = 0xf8
        record[8] = 1
        record[0x3a] = 0x10
        var identifier = windowID.bigEndian
        withUnsafeBytes(of: &identifier) { record.replaceSubrange(0x3c..<0x40, with: $0) }
        let posted = record.withUnsafeBytes { connection.postFocusEvent(&process, $0.baseAddress!) }
        guard posted == noErr else { throw RequestError.message("系统无法交付来源窗口焦点（\(posted)）。") }
    }
}
#endif
