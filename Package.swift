// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirSkip",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MenuBarApp", path: "src"),
        .testTarget(name: "AppTests", dependencies: ["MenuBarApp"], path: "tests")
    ]
)
