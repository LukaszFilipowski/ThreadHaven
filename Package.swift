// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadHaven",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ThreadHaven",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
