#if os(macOS)
import Foundation
import SwiftUI
import ImageIO
import CoreVideo

struct AppearanceImage {
    let id = UUID()
    let name: String
    let pixels: CVPixelBuffer

    static func load(from url: URL) throws -> AppearanceImage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImageError.unreadable }
        try Task.checkCancellation()
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw ImageError.allocation }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw ImageError.allocation }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw ImageError.allocation
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return AppearanceImage(name: url.lastPathComponent, pixels: buffer)
    }

    enum ImageError: LocalizedError {
        case unreadable, allocation
        var errorDescription: String? {
            switch self {
            case .unreadable: return "无法解码这张图片。请选择可读取的 PNG、JPEG、HEIC 或其他系统支持的图片。"
            case .allocation: return "无法分配图片预览所需的内存。"
            }
        }
    }
}

@MainActor
final class AppearanceImageStore: ObservableObject {
    @Published private(set) var image: AppearanceImage?
    @Published private(set) var isLoading = false
    @Published var error: String?
    private var task: Task<Void, Never>?

    func load(_ url: URL) {
        cancelLoading()
        error = nil
        isLoading = true
        let worker = Task.detached(priority: .userInitiated) { try AppearanceImage.load(from: url) }
        task = Task {
            await withTaskCancellationHandler {
                do {
                    let loaded = try await worker.value
                    guard !Task.isCancelled else { return }
                    image = loaded
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                }
                isLoading = false
                task = nil
            } onCancel: { worker.cancel() }
        }
    }

    func cancelLoading() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    func reset() {
        cancelLoading()
        image = nil
        error = nil
    }
}
#endif
