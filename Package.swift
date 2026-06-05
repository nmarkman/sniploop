// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sniploop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SniploopCore"),
        .executableTarget(
            name: "Sniploop",
            dependencies: ["SniploopCore"]
        ),
        .testTarget(name: "SniploopCoreTests", dependencies: ["SniploopCore"]),
    ]
)
