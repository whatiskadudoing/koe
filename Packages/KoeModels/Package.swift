// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeModels",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeModels", targets: ["KoeModels"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KoeModels",
            dependencies: []
        )
    ]
)
