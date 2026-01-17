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
        .package(path: "../KoeDomain"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .target(
            name: "KoeAudio",
            dependencies: ["KoeDomain", "FluidAudio"]
        )
    ]
)
