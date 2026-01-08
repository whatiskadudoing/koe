// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeCommands",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeCommands", targets: ["KoeCommands"])
    ],
    dependencies: [
        .package(path: "../KoeDomain"),
        .package(path: "../KoeAudio")
    ],
    targets: [
        .target(
            name: "KoeCommands",
            dependencies: ["KoeDomain", "KoeAudio"]
        )
    ]
)
