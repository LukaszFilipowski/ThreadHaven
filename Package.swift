// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadHaven",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
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
package.dependencies.append(.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.2"))
package.products.insert(.executable(name: "ThreadHaven", targets: ["ThreadHaven"]), at: 0)
package.targets += [
    .executableTarget(
        name: "ThreadHaven",
        dependencies: ["ThreadHavenCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "ThreadHavenTests",
        dependencies: ["ThreadHaven"],
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
#endif

#if os(Linux)
if Context.environment["THREADHAVEN_LINUX_APP"] == "1" {
    package.dependencies.append(
        .package(
            url: "https://git.aparoksha.dev/aparoksha/adwaita-swift",
            revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6"
        )
    )
    package.products.append(.executable(name: "ThreadHavenLinux", targets: ["ThreadHavenLinux"]))
    package.targets.append(
        .executableTarget(
            name: "ThreadHavenLinux",
            dependencies: [
                "ThreadHavenCore",
                .product(name: "Adwaita", package: "adwaita-swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-default-isolation", "MainActor"]),
            ]
        )
    )
}
#endif
