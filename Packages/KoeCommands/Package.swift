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
        .package(path: "../KoeAudio"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .target(
            name: "KoeCommands",
            dependencies: [
                "KoeDomain",
                "KoeAudio",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        )
    ]
)
