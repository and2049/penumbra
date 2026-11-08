// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Penumbra",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PenumbraCore"),
        .target(name: "PenumbraSystem", dependencies: ["PenumbraCore"]),
        .testTarget(name: "PenumbraCoreTests", dependencies: ["PenumbraCore"]),
        .testTarget(name: "PenumbraSystemTests", dependencies: ["PenumbraCore", "PenumbraSystem"]),
    ]
)
