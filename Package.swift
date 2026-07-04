// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gingergarlic",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "gingergarlic",
            path: "Sources/GingerGarlic",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
