// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeTranscription",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeTranscription", targets: ["KoeTranscription"])
    ],
    dependencies: [
        .package(path: "../KoeDomain"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0")
    ],
    targets: [
        .target(
            name: "KoeTranscription",
            dependencies: ["KoeDomain", "WhisperKit"]
        )
    ]
)
