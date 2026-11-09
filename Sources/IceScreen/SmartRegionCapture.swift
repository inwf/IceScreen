#if os(macOS)
import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import IceCore

enum SmartRegionCapture {
    @MainActor static func detect(source: SCWindow, at point: CGPoint) async throws -> Viewport {
        let normalized = CGPoint(x: (point.x - source.frame.minX) / source.frame.width,
                                 y: (point.y - source.frame.minY) / source.frame.height)
        let semantic = accessibleRegions(source: source, at: point)
        let config = SCStreamConfiguration()
        let scale = min(1, 1280 / max(source.frame.width, source.frame.height))
        config.width = max(2, Int(source.frame.width * scale))
        config.height = max(2, Int(source.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: source), configuration: config)
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 24
            request.minimumConfidence = 0.65
            request.minimumAspectRatio = 0.08
            request.maximumAspectRatio = 1
            request.minimumSize = 0.06
            request.quadratureTolerance = 8
            try VNImageRequestHandler(cgImage: image).perform([request])
            let rectangles = (request.results ?? []).map { CaptureCandidate(rect: SmartCapture.fromVision($0.boundingBox)) }
            let selection = SmartCapture.select(at: normalized, candidates: semantic + rectangles)
            guard !(semantic + rectangles).isEmpty else { return selection }
            return trimLetterbox(image, selection: selection, point: normalized)
        }.value
    }

    @MainActor private static func accessibleRegions(source: SCWindow, at point: CGPoint) -> [CaptureCandidate] {
        guard AXIsProcessTrusted(), let pid = source.owningApplication?.processID else { return [] }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.08)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element) == .success else { return [] }
        let roles: Set<String> = ["AXImage", "AXVideo", "AXTable", "AXTextArea", "AXScrollArea"]
        var result: [CaptureCandidate] = []
        for _ in 0..<8 {
            guard let current = element else { break }
            var role: CFTypeRef?, position: CFTypeRef?, size: CFTypeRef?, parent: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if roles.contains(role as? String ?? "") {
                AXUIElementCopyAttributeValue(current, kAXPositionAttribute as CFString, &position)
                AXUIElementCopyAttributeValue(current, kAXSizeAttribute as CFString, &size)
                if let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var p = CGPoint.zero, s = CGSize.zero
                    AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &p)
                    AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &s)
                    let rect = CGRect(x: (p.x - source.frame.minX) / source.frame.width,
                                      y: (p.y - source.frame.minY) / source.frame.height,
                                      width: s.width / source.frame.width, height: s.height / source.frame.height)
                    result.append(.init(rect: rect, semantic: role as? String != "AXScrollArea"))
                }
            }
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return result
    }

    private static func trimLetterbox(_ image: CGImage, selection: Viewport, point: CGPoint) -> Viewport {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return selection }
        let r = selection.sourceRect(in: CGSize(width: width, height: height)).integral
        var left = max(0, Int(r.minX)), right = min(width - 1, Int(r.maxX) - 1)
        var top = max(0, Int(r.minY)), bottom = min(height - 1, Int(r.maxY) - 1)
        guard right - left > 20, bottom - top > 20 else { return selection }
        func uniform(_ values: [UInt8]) -> Bool {
            let black = values.filter { $0 <= 14 }.count
            let white = values.filter { $0 >= 242 }.count
            return max(black, white) >= Int(Double(values.count) * 0.99)
        }
        let maxY = max(1, (bottom - top) / 5), maxX = max(1, (right - left) / 5)
        var t = 0, b = 0, l = 0, rr = 0
        while t < maxY && uniform(Array(pixels[((top + t) * width + left)...((top + t) * width + right)])) { t += 1 }
        while b < maxY && uniform(Array(pixels[((bottom - b) * width + left)...((bottom - b) * width + right)])) { b += 1 }
        // 对称边框且能找到内容边界时才裁切，避免将白色页面当成边框。
        if t >= 2 && b >= 2 && t < maxY && b < maxY && abs(t - b) <= max(3, (t + b) / 5) { top += t; bottom -= b }
        while l < maxX && uniform((top...bottom).map { pixels[$0 * width + left + l] }) { l += 1 }
        while rr < maxX && uniform((top...bottom).map { pixels[$0 * width + right - rr] }) { rr += 1 }
        if l >= 2 && rr >= 2 && l < maxX && rr < maxX && abs(l - rr) <= max(3, (l + rr) / 5) { left += l; right -= rr }
        let trimmed = CGRect(x: Double(left) / Double(width), y: Double(top) / Double(height),
                             width: Double(right - left + 1) / Double(width), height: Double(bottom - top + 1) / Double(height))
        return trimmed.contains(point) ? Viewport(rect: trimmed) : selection
    }
}
#endif
