// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperApp", targets: ["WhisperApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
        .package(path: "../Packages/KoeDomain")
    ],
    targets: [
        .executableTarget(
            name: "WhisperApp",
            dependencies: ["WhisperKit", "HotKey", "KoeDomain"],
            path: "WhisperApp"
        )
    ]
)
