import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: make-icon.swift SOURCE_PNG OUTPUT_DIRECTORY")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width == height, width >= 1024 else {
    fatalError("App icon must be a readable square image of at least 1024 pixels")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("AppIcon.iconset")
if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func renderIcon(size: Int, name: String) throws {
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: size]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          image.width == size, image.height == size,
          let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot resize app icon to \(size) pixels")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot encode icon: \(name)") }
}

for points in [16, 32, 128, 256, 512] {
    try renderIcon(size: points, name: "icon_\(points)x\(points).png")
    try renderIcon(size: points * 2, name: "icon_\(points)x\(points)@2x.png")
}
