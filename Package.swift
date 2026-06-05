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
        // Tests run as a plain executable (XCTest/Testing are unavailable under
        // CommandLineTools without Xcode). Run with: swift run SniploopCoreTests
        .executableTarget(name: "SniploopCoreTests", dependencies: ["SniploopCore"]),
    ]
)
