// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "coordination-server",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Hummingbird 2.x — product is `Hummingbird`. 2.25.0 is the current
        // stable release (verified via the GitHub releases API at authoring).
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0")
    ],
    targets: [
        .target(
            name: "CoordinationServerCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ]
        ),
        .executableTarget(
            name: "coordination-server",
            dependencies: [
                "CoordinationServerCore",
                .product(name: "Hummingbird", package: "hummingbird")
            ]
        ),
        .testTarget(
            name: "CoordinationServerCoreTests",
            dependencies: [
                "CoordinationServerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        )
    ]
)
