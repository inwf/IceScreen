import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func renderIcon(size: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: CGRect(x: 56, y: 56, width: 912, height: 912), xRadius: 210, yRadius: 210)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.26, alpha: 1),
                              ending: NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.43, alpha: 1))!
    gradient.draw(in: background, angle: 50)
    NSColor(calibratedRed: 0.61, green: 0.89, blue: 0.93, alpha: 0.32).setStroke()
    let back = NSBezierPath(roundedRect: CGRect(x: 228, y: 338, width: 530, height: 420), xRadius: 52, yRadius: 52)
    back.lineWidth = 24
    back.stroke()
    NSColor(calibratedRed: 0.70, green: 0.97, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 392, y: 240, width: 420, height: 330), xRadius: 42, yRadius: 42).fill()
    NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.32, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 420, y: 310, width: 364, height: 232), xRadius: 20, yRadius: 20).fill()
    NSBezierPath(ovalIn: CGRect(x: 428, y: 266, width: 16, height: 16)).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: output.appendingPathComponent(name))
}

for points in [16, 32, 128, 256, 512] {
    try renderIcon(size: points, name: "icon_\(points)x\(points).png")
    try renderIcon(size: points * 2, name: "icon_\(points)x\(points)@2x.png")
}
