// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadHaven",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ThreadHaven", targets: ["ThreadHaven"]),
        .library(name: "ThreadHavenCore", targets: ["ThreadHavenCore"]),
    ],
    targets: [
        .target(
            name: "ThreadHavenCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ThreadHaven",
            dependencies: ["ThreadHavenCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThreadHavenTests",
            dependencies: ["ThreadHaven", "ThreadHavenCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
