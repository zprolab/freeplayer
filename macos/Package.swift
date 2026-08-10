// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FreePlayer",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Audio fingerprinting (Chromaprint) + AcoustID online recognition.
        .package(url: "https://github.com/wallisch/ChromaSwift.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "FreePlayer",
            dependencies: [
                .product(name: "ChromaSwift", package: "ChromaSwift"),
            ],
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
