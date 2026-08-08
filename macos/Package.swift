// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FreePlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FreePlayer",
            path: "Sources/FreePlayer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Accelerate"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "FreePlayerTests",
            dependencies: ["FreePlayer"],
            path: "Tests/FreePlayerTests"
        ),
    ]
)
