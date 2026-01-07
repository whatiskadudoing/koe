// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeHotkey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeHotkey", targets: ["KoeHotkey"])
    ],
    dependencies: [
        .package(path: "../KoeDomain"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1")
    ],
    targets: [
        .target(
            name: "KoeHotkey",
            dependencies: ["KoeDomain", "HotKey"]
        )
    ]
)
