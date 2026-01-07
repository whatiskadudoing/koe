// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeTextInsertion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeTextInsertion", targets: ["KoeTextInsertion"])
    ],
    dependencies: [
        .package(path: "../KoeDomain")
    ],
    targets: [
        .target(
            name: "KoeTextInsertion",
            dependencies: ["KoeDomain"],
            path: "Sources/KoeTextInsertion"
        )
    ]
)
