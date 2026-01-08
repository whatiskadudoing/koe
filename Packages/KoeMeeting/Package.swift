// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KoeMeeting",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KoeMeeting", targets: ["KoeMeeting"])
    ],
    dependencies: [
        .package(path: "../KoeDomain"),
        .package(path: "../KoeCore"),
        .package(path: "../KoeStorage")
    ],
    targets: [
        .target(
            name: "KoeMeeting",
            dependencies: ["KoeDomain", "KoeCore", "KoeStorage"]
        )
    ]
)
