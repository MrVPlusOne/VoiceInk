// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceInkLogic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceInkLogic", targets: ["VoiceInkLogic"])
    ],
    targets: [
        .target(
            name: "VoiceInkLogic",
            path: "VoiceInk/Logic"
        ),
        .testTarget(
            name: "VoiceInkLogicTests",
            dependencies: ["VoiceInkLogic"],
            path: "VoiceInkLogicTests"
        )
    ]
)
