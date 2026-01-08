// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Koe", targets: ["Koe"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
        .package(path: "../Packages/KoeDomain"),
        .package(path: "../Packages/KoeCore"),
        .package(path: "../Packages/KoeAudio"),
        .package(path: "../Packages/KoeTranscription"),
        .package(path: "../Packages/KoeHotkey"),
        .package(path: "../Packages/KoeTextInsertion"),
        .package(path: "../Packages/KoeStorage"),
        .package(path: "../Packages/KoeUI"),
        .package(path: "../Packages/KoeMeeting"),
        .package(path: "../Packages/KoeRefinement"),
        .package(path: "../Packages/KoePipeline")
    ],
    targets: [
        .executableTarget(
            name: "Koe",
            dependencies: [
                "WhisperKit",
                "HotKey",
                "KoeDomain",
                "KoeCore",
                "KoeAudio",
                "KoeTranscription",
                "KoeHotkey",
                "KoeTextInsertion",
                "KoeStorage",
                "KoeUI",
                "KoeMeeting",
                "KoeRefinement",
                "KoePipeline"
            ],
            path: "Koe"
        )
    ]
)
