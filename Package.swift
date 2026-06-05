// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sniploop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "SniploopCore"),
        .executableTarget(
            name: "Sniploop",
            dependencies: [
                "SniploopCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "SniploopCoreTests", dependencies: ["SniploopCore"]),
    ]
)
