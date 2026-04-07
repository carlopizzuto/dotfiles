// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BWMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BWMenuBar",
            path: "Sources/BWMenuBar"
        ),
        .testTarget(
            name: "BWMenuBarTests",
            dependencies: ["BWMenuBar"],
            path: "Tests/BWMenuBarTests"
        ),
    ]
)