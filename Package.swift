// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IceScreen",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IceCore", targets: ["IceCore"]),
        .executable(name: "IceScreen", targets: ["IceScreen"])
    ],
    targets: [
        .target(name: "IceCore"),
        .executableTarget(name: "IceScreen", dependencies: ["IceCore"],
            exclude: ["Resources"]),
        .testTarget(name: "IceCoreTests", dependencies: ["IceCore"])
    ]
)
