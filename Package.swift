// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirSkip",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AirSkip", targets: ["MenuBarApp"])],
    targets: [
        .executableTarget(name: "MenuBarApp", path: "src", resources: [.copy("animation")]),
        .testTarget(name: "AppTests", dependencies: ["MenuBarApp"], path: "tests")
    ]
)
