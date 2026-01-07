// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeDomain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeDomain", targets: ["KoeDomain"])
    ],
    targets: [
        .target(
            name: "KoeDomain",
            path: "Sources/KoeDomain"
        )
    ]
)
