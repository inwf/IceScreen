#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import IceCore

struct SourceFocusPending: Error {
    let operation: String
}

@MainActor
final class WindowActivation {
    private typealias SetFrontProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32
    private typealias PostFocusEvent = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeRawPointer) -> Int32
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcess = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let connection = Result { try WindowActivation() }
    private let library: UnsafeMutableRawPointer
    private let setFrontProcess: SetFrontProcess
    private let postFocusEvent: PostFocusEvent
    private let getWindowID: GetWindowID
    private let getProcess: GetProcess
    private let mainConnection: MainConnection
    private let copyWindowSpaces: CopyWindowSpaces
    private let copyDisplaySpaces: CopyDisplaySpaces

    private init() throws {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else {
            throw RequestError.message(L10n.text("无法加载系统窗口定位接口。", "Unable to load the system window focus interface."))
        }
        guard let processImage = dlopen(nil, RTLD_LAZY) else {
            dlclose(library)
            throw RequestError.message(L10n.text("无法读取系统进程接口。", "Unable to load the system process interface."))
        }
        defer { dlclose(processImage) }
        guard let front = dlsym(library, "_SLPSSetFrontProcessWithOptions"),
              let event = dlsym(library, "SLPSPostEventRecordTo"),
              let window = dlsym(processImage, "_AXUIElementGetWindow"),
              let process = dlsym(processImage, "GetProcessForPID"),
              let main = dlsym(library, "SLSMainConnectionID"),
              let spaces = dlsym(library, "SLSCopySpacesForWindows"),
              let displays = dlsym(library, "SLSCopyManagedDisplaySpaces") else {
            dlclose(library)
            throw RequestError.message(L10n.text("当前系统缺少窗口定位接口。", "The window focus interface is unavailable on this system."))
        }
        self.library = library
        setFrontProcess = unsafeBitCast(front, to: SetFrontProcess.self)
        postFocusEvent = unsafeBitCast(event, to: PostFocusEvent.self)
        getWindowID = unsafeBitCast(window, to: GetWindowID.self)
        getProcess = unsafeBitCast(process, to: GetProcess.self)
        mainConnection = unsafeBitCast(main, to: MainConnection.self)
        copyWindowSpaces = unsafeBitCast(spaces, to: CopyWindowSpaces.self)
        copyDisplaySpaces = unsafeBitCast(displays, to: CopyDisplaySpaces.self)
    }

    deinit { dlclose(library) }

    static func windowID(of element: AXUIElement) throws -> CGWindowID? {
        let connection = try connection.get()
        var identifier: CGWindowID = 0
        let status = connection.getWindowID(element, &identifier)
        if status == .cannotComplete { throw SourceFocusPending(operation: L10n.text("读取来源窗口标识", "Read source window ID")) }
        guard status == .success, identifier != 0 else { return nil }
        return identifier
    }

    static func bringForward(processID: pid_t, windowID: CGWindowID) throws {
        let connection = try connection.get()
        var process = ProcessSerialNumber()
        let lookup = connection.getProcess(processID, &process)
        guard lookup == noErr else { throw RequestError.message(L10n.text("无法取得来源进程（\(lookup)）。", "Unable to find the source process (\(lookup)).")) }
        let result = connection.setFrontProcess(&process, windowID, 0x200)
        guard result == noErr else { throw RequestError.message(L10n.text("系统无法置前来源窗口（\(result)）。", "The system could not bring the source window forward (\(result)).")) }

        // WindowServer 的窗口焦点事件，窗口 ID 使用网络字节序。
        var record = [UInt8](repeating: 0, count: 0xf8)
        record[4] = 0xf8
        record[8] = 1
        record[0x3a] = 0x10
        var identifier = windowID.bigEndian
        withUnsafeBytes(of: &identifier) { record.replaceSubrange(0x3c..<0x40, with: $0) }
        let posted = record.withUnsafeBytes { connection.postFocusEvent(&process, $0.baseAddress!) }
        guard posted == noErr else { throw RequestError.message(L10n.text("系统无法交付来源窗口焦点（\(posted)）。", "The system could not focus the source window (\(posted)).")) }
    }

    static func spaceIDs(for windowID: CGWindowID) throws -> [UInt64] {
        let connection = try connection.get()
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let value = connection.copyWindowSpaces(connection.mainConnection(), 0x7, windows)?.takeRetainedValue(),
              let spaces = value as? [NSNumber] else {
            throw RequestError.message(L10n.text("无法读取来源窗口所在桌面。", "Unable to read the source window’s Space."))
        }
        return spaces.map(\.uint64Value)
    }

    static func visibleSpaceIDs() throws -> [UInt64] {
        let connection = try connection.get()
        guard let value = connection.copyDisplaySpaces(connection.mainConnection())?.takeRetainedValue(),
              let displays = value as? [[String: Any]], !displays.isEmpty else {
            throw RequestError.message(L10n.text("无法读取当前显示器的桌面状态。", "Unable to read the current display’s Space state."))
        }
        return try displays.map { display in
            guard let space = display["Current Space"] as? [String: Any],
                  let identifier = space["id64"] as? NSNumber else {
                throw RequestError.message(L10n.text("系统返回的当前桌面状态不完整。", "The system returned incomplete current Space information."))
            }
            return identifier.uint64Value
        }
    }

    static func isOnVisibleSpace(_ windowID: CGWindowID) throws -> Bool {
        let visible = Set(try visibleSpaceIDs())
        return try spaceIDs(for: windowID).contains { visible.contains($0) }
    }
}
#endif
