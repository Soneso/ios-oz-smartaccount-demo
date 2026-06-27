// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "reference-agent",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // TEMPORARY local override to the sa-improvements branch of the SDK
        // clone, which carries connectToContract (headless smart-account
        // connect) and the auto-fund RPC-visibility poll fix. Neither is in a
        // released tag yet. Switch to a published version before release.
        .package(path: "../../stellar-ios-mac-sdk")
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
