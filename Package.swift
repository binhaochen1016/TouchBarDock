// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TouchBarDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TouchBarDock",
            path: "Sources/TouchBarDock"
        )
    ]
)
