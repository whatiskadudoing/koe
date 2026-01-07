// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeAudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeAudio", targets: ["KoeAudio"])
    ],
    dependencies: [
        .package(path: "../KoeDomain")
    ],
    targets: [
        .target(
            name: "KoeAudio",
            dependencies: ["KoeDomain"]
        )
    ]
)
