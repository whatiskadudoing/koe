// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeCore", targets: ["KoeCore"])
    ],
    targets: [
        .target(name: "KoeCore")
    ]
)
