// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "reference-agent",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/Soneso/stellar-ios-mac-sdk.git", from: "3.6.1")
    ],
    targets: [
        // Library carrying all agent logic so the orchestration is unit-testable
        // through injected protocols, with no top-level entry-point code.
        .target(
            name: "ReferenceAgentCore",
            dependencies: [
                .product(name: "stellarsdk", package: "stellar-ios-mac-sdk")
            ]
        ),
        // Thin executable: parses the environment gates and dispatches into the
        // core library. Run with `swift run reference-agent`.
        .executableTarget(
            name: "reference-agent",
            dependencies: [
                "ReferenceAgentCore"
            ]
        ),
        .testTarget(
            name: "ReferenceAgentCoreTests",
            dependencies: [
                "ReferenceAgentCore",
                .product(name: "stellarsdk", package: "stellar-ios-mac-sdk")
            ]
        )
    ]
)
