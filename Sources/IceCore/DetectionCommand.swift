import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum DetectionCommand {
    /// 让用户命令及其子进程共享独立的进程组，关闭和超时可以一起终止。
    public static func execute(_ command: String) -> Never {
        if getpgrp() != getpid(), setpgid(0, 0) != 0 { exit(71) }
        let values = ["sh", "-c", command].map { value in value.withCString { strdup($0)! } }
        var arguments: [UnsafeMutablePointer<CChar>?] = values + [nil]
        execv("/bin/sh", &arguments)
        values.forEach { free($0) }
        exit(71)
    }
}
