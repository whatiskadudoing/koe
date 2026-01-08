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
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.29.1")
    ],
    targets: [
        .target(
            name: "KoeRefinement",
            dependencies: [
                "KoeDomain",
                "KoeCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ]
        )
    ]
)
