// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shadowmatt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Shadowmatt", targets: ["Shadowmatt"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Shadowmatt",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/Shadowmatt",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
