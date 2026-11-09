// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IceScreen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IceCore", targets: ["IceCore"]),
        .library(name: "IceMediaBridge", type: .dynamic, targets: ["IceMediaBridge"]),
        .executable(name: "IceScreen", targets: ["IceScreen"])
    ],
    targets: [
        .target(name: "IceCore"),
        .target(name: "IceMediaBridge", dependencies: ["IceCore"]),
        .executableTarget(name: "IceScreen", dependencies: ["IceCore"],
            exclude: ["Resources"],
            linkerSettings: [.linkedFramework("SwiftUI", .when(platforms: [.macOS]))]),
        .testTarget(name: "IceCoreTests", dependencies: ["IceCore"])
    ]
)
