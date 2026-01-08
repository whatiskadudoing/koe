// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeRefinement",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeRefinement", targets: ["KoeRefinement"])
    ],
    dependencies: [
        .package(path: "../KoeDomain"),
        .package(path: "../KoeCore"),
        // LLM.swift - Local fork with Metal GPU acceleration enabled
        .package(path: "../LLM")
    ],
    targets: [
        .target(
            name: "KoeRefinement",
            dependencies: [
                "KoeDomain",
                "KoeCore",
                .product(name: "LLM", package: "LLM")
            ]
        )
    ]
)
