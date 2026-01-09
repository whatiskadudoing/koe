// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoePipeline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoePipeline", targets: ["KoePipeline"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KoePipeline",
            dependencies: []
        )
    ]
)
