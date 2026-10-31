// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadHaven",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "threadhaven-stats", targets: ["threadhaven-stats"]),
        .library(name: "ThreadHavenCore", targets: ["ThreadHavenCore"]),
    ],
    targets: [
        .target(
            name: "ThreadHavenCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "threadhaven-stats",
            dependencies: ["ThreadHavenCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThreadHavenCoreTests",
            dependencies: ["ThreadHavenCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

#if os(macOS)
package.products.insert(.executable(name: "ThreadHaven", targets: ["ThreadHaven"]), at: 0)
package.targets += [
    .executableTarget(
        name: "ThreadHaven",
        dependencies: ["ThreadHavenCore"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "ThreadHavenTests",
        dependencies: ["ThreadHaven"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
#endif
