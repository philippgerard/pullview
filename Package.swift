// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PullView",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PullViewCore"),
        .executableTarget(name: "PullView", dependencies: ["PullViewCore"]),
        .testTarget(name: "PullViewCoreTests", dependencies: ["PullViewCore"]),
        .testTarget(name: "PullViewScreenshots", dependencies: ["PullView", "PullViewCore"]),
    ]
)
