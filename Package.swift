// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Penumbra",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Penumbra", targets: ["Penumbra"]),
        .executable(name: "penumbractl", targets: ["penumbractl"]),
    ],
    targets: [
        .target(name: "PenumbraCore"),
        .target(name: "PenumbraSystem", dependencies: ["PenumbraCore"]),
        .executableTarget(name: "Penumbra", dependencies: ["PenumbraCore", "PenumbraSystem"]),
        .executableTarget(name: "penumbractl", dependencies: ["PenumbraCore", "PenumbraSystem"]),
        .testTarget(name: "PenumbraCoreTests", dependencies: ["PenumbraCore"]),
        .testTarget(name: "PenumbraSystemTests", dependencies: ["PenumbraCore", "PenumbraSystem"]),
    ]
)
