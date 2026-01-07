// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeStorage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeStorage", targets: ["KoeStorage"])
    ],
    dependencies: [
        .package(path: "../KoeDomain")
    ],
    targets: [
        .target(
            name: "KoeStorage",
            dependencies: ["KoeDomain"],
            path: "Sources/KoeStorage"
        )
    ]
)
