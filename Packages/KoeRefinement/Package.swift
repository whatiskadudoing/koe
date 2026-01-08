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
        .package(url: "https://github.com/tattn/LocalLLMClient.git", branch: "main")
    ],
    targets: [
        .target(
            name: "KoeRefinement",
            dependencies: [
                "KoeDomain",
                "KoeCore",
                .product(name: "LocalLLMClient", package: "LocalLLMClient"),
                .product(name: "LocalLLMClientMLX", package: "LocalLLMClient")
            ]
        )
    ]
)
