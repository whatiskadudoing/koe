// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeUI", targets: ["KoeUI"])
    ],
    dependencies: [
        .package(path: "../KoeDomain")
    ],
    targets: [
        .target(
            name: "KoeUI",
            dependencies: ["KoeDomain"],
            path: "Sources/KoeUI"
        )
    ]
)
