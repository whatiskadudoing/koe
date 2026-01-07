// swift-tools-version: 5.9
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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperApp",
            dependencies: ["WhisperKit", "HotKey"],
            path: "WhisperApp"
        )
    ]
)
