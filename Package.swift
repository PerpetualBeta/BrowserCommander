// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrowserCommander",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BrowserCommander",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        )
    ]
)
