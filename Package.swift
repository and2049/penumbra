// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Penumbra",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PenumbraCore"),
        .testTarget(name: "PenumbraCoreTests", dependencies: ["PenumbraCore"]),
    ]
)
