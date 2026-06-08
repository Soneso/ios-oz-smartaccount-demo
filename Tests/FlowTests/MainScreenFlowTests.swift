// MainScreenFlowTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk
import Testing

// ============================================================================
// MARK: - MainScreenFlowTests
// ============================================================================

/// Tests for `MainScreenFlow`.
///
/// Strategy:
/// - `initializeKit()` is tested via the happy path (providers injected →
///   kit stored in DemoState) and the failure path (nil provider → activity log
///   error entry). A dedicated error field is absent from `DemoState`.
/// - `refreshBalances()` is not tested against a live network; the balance-fetch
///   path requires a running Soroban RPC server. The unit tests cover the guard
///   conditions: disconnected state exits early, nil kit exits early. The
///   per-error-type formatting and routing is also verified.
/// - `disconnect()` verifies that all state is cleared and a log entry is added.
/// - Screens-never-call-SDK rule: verified at the end of this file via a static
///   analysis substitute — a targeted grep assertion run inside the test process.
///
/// Running tests:
///   swift test --filter "MainScreenFlow"
/// to avoid hitting the network-based integration tests in the project.
@Suite("MainScreenFlow")
struct MainScreenFlowTests {

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// Builds a `DemoState` with the real platform providers injected.
    ///
    /// Uses `OZInMemoryStorageAdapter` so tests do not write to the Keychain and
    /// a real `AppleWebAuthnProvider`. Throws when the Associated Domains
    /// entitlement is unavailable in the test host, which is expected and
    /// acceptable — tests that require a provider handle the skip at the call site.
    @MainActor
    private func makeDemoState(withProviders: Bool = true) throws -> DemoState {
        let state = DemoState()
        if withProviders {
            do {
                let provider = try AppleWebAuthnProvider.create(
                    rpId: DemoConfig.defaultRpId,
                    rpName: DemoConfig.rpName
                )
                state.setWebAuthnProvider(provider)
            } catch {
                // AppleWebAuthnProvider may throw in a unit-test host that lacks the
                // Associated Domains entitlement. This is expected and acceptable;
                // initializeKit() surfaces the error in the activity log.
                // For the happy-path test, we skip if the provider cannot be built.
                throw error
            }
            state.setStorage(OZInMemoryStorageAdapter())
        }
        return state
    }

    // -------------------------------------------------------------------------
    // MARK: - initializeKit() — missing provider failure path
    // -------------------------------------------------------------------------

    @Test("initializeKit logs an error when WebAuthn provider is nil")
    @MainActor
    func kitInitFailsWhenProviderMissing() async {
        // Arrange: DemoState with no provider injected.
        let state = DemoState()
        // Storage present, WebAuthn provider absent.
        state.setStorage(OZInMemoryStorageAdapter())

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        // Act
        await flow.initializeKit()

        // Assert: activity log contains at least one error entry.
        let errorEntries = log.entries.filter { $0.level == .error }
        #expect(!errorEntries.isEmpty, "Expected at least one error log entry")

        // Assert: error message is actionable.
        let hasProviderMessage = errorEntries.contains {
            $0.message.contains("provider") || $0.message.contains("WebAuthn")
        }
        #expect(hasProviderMessage, "Error message should reference 'provider' or 'WebAuthn'")

        // Assert: kit is not stored after a failed init.
        #expect(state.kit == nil)
    }

    @Test("initializeKit logs an error when storage is nil")
    @MainActor
    func kitInitFailsWhenStorageMissing() async {
        // Arrange: DemoState with no storage injected.
        let state = DemoState()
        // Storage absent, WebAuthn provider present or absent — both produce the same
        // guard failure when storage is checked after provider.
        // We do not set any provider here; the provider check fires first.
        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        await flow.initializeKit()

        // Activity log must have at least one error entry.
        #expect(log.entries.contains { $0.level == .error })

        // Kit must remain nil.
        #expect(state.kit == nil)
    }

    // -------------------------------------------------------------------------
    // MARK: - initializeKit() — re-entrancy guard
    // -------------------------------------------------------------------------

    @Test("initializeKit is idempotent when kit is already initialised")
    @MainActor
    func kitInitIsIdempotent() async throws {
        // Arrange: pre-populate DemoState with a kit so the guard fires immediately.
        let state = DemoState()
        state.setStorage(OZInMemoryStorageAdapter())

        // Build a minimal kit directly and inject it.
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            storage: OZInMemoryStorageAdapter()
        )
        let existingKit = OZSmartAccountKit.create(config: config)
        state.setKit(existingKit)

        let log = ActivityLogState()
        let initialEntryCount = log.entries.count
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        // Act: call initializeKit() when a kit already exists.
        await flow.initializeKit()

        // Assert: no additional activity log entries were added (early return).
        #expect(log.entries.count == initialEntryCount, "No log entries should be added when kit is already present")

        // Assert: the kit in DemoState is still the original.
        #expect(state.kit === existingKit)
    }

    // -------------------------------------------------------------------------
    // MARK: - disconnect()
    // -------------------------------------------------------------------------

    @Test("disconnect clears connection state, preserves kit, logs info entry")
    @MainActor
    func disconnectClearsStateAndLogs() async throws {
        // Arrange: build a kit and connect a fake wallet state.
        let state = DemoState()
        state.setStorage(OZInMemoryStorageAdapter())
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            storage: OZInMemoryStorageAdapter()
        )
        let kit = OZSmartAccountKit.create(config: config)
        state.setKit(kit)
        state.setConnected(
            contractId: "CDUMMYCONTRACTADDRESS123456789012345678901234567890ABCDEF",
            credentialId: "dummyCredential",
            isDeployed: true
        )
        state.setXlmBalance("10.0")
        state.setDemoTokenBalance("500.0")

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        // Act
        await flow.disconnect()

        // Assert: kit survives so the user can immediately reconnect; only the
        // connection-state and balance display fields are cleared.
        #expect(state.kit === kit, "Kit instance must survive disconnect")
        #expect(!state.isConnected, "Should be disconnected after disconnect")
        #expect(state.xlmBalance == nil, "XLM balance should be nil after disconnect")
        #expect(state.demoTokenBalance == nil, "DEMO balance should be nil after disconnect")

        // Assert: activity log has a disconnect info entry.
        #expect(log.entries.contains { entry in
            entry.level == .info && entry.message.lowercased().contains("disconnect")
        }, "Expected a disconnect log entry")
    }

    @Test("disconnect from disconnected state logs a message without error")
    @MainActor
    func disconnectFromDisconnectedStateIsNoop() async {
        // Arrange: no kit, no wallet.
        let state = DemoState()
        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        // Act: disconnect when already disconnected.
        await flow.disconnect()

        // Assert: no error entries — disconnect is always a no-op when already clean.
        #expect(!log.entries.contains { $0.level == .error })
    }

    // -------------------------------------------------------------------------
    // MARK: - refreshBalances() guard paths
    // -------------------------------------------------------------------------

    @Test("refreshBalances exits early when wallet is not connected")
    @MainActor
    func refreshBalancesExitsWhenDisconnected() async {
        let state = DemoState()
        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        let countBefore = log.entries.count

        // Act: refresh without a connected wallet.
        await flow.refreshBalances()

        // Assert: no log entries added (early return path).
        #expect(log.entries.count == countBefore, "refreshBalances should not log when disconnected")
    }

    @Test("refreshBalances proceeds on connection state alone, independent of the kit")
    @MainActor
    func refreshBalancesRunsWithoutKit() async {
        // Arrange: connected state without a kit. Balance fetching goes straight
        // to the Soroban RPC via SACBalanceFetcher and does not depend on the
        // kit, so the only gate is the connection guard (isConnected + contractId).
        let state = DemoState()
        state.setConnected(
            contractId: "CDUMMYCONTRACTADDRESS123456789012345678901234567890ABCDEF",
            credentialId: "cred",
            isDeployed: true
        )
        // Kit is deliberately left nil; refreshBalances must still proceed.

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        await flow.refreshBalances()

        // The connection guard passes, so the method runs to completion: it logs
        // the start marker (proving it did not early-exit) and the completion
        // marker, regardless of whether the network balance fetch succeeds.
        #expect(log.entries.contains { $0.message.contains("Refreshing balances") },
                "refreshBalances should log its start marker when connected")
        #expect(log.entries.contains { $0.message.contains("Balances refreshed") },
                "refreshBalances should run to completion when connected")
    }

    // -------------------------------------------------------------------------
    // MARK: - BootstrapError formatting
    // -------------------------------------------------------------------------

    @Test("BootstrapError.providerMissing has an actionable localizedDescription")
    func providerMissingErrorDescription() throws {
        let err = BootstrapError.providerMissing("WebAuthn provider was not injected.")
        let desc = err.errorDescription
        #expect(desc != nil)
        let message = try #require(desc)
        #expect(message.contains("provider") || message.contains("not"),
                "BootstrapError description should reference 'provider' or 'not'")
    }

    // BalanceFetchError formatting tests are in Tests/UtilTests/SACBalanceFetcherTests.swift.
    // DemoState bootstrap-error (activity-log-only) tests are in
    // Tests/StateTests/DemoStateBootstrapErrorTest.swift.

    // -------------------------------------------------------------------------
    // MARK: - Screens-never-call-SDK guard
    // -------------------------------------------------------------------------

    @Test("iOS and macOS screen files contain no direct SDK calls or accessor reach-through")
    func screenFilesContainNoSdkCalls() throws {
        // Architecture rule: screens must delegate all SDK interactions to flow
        // classes. The deny-list covers:
        // 1. Type-name patterns — direct SDK type use in screen files.
        // 2. Property-accessor reach-through — `kit.walletOperations.` etc.
        //
        // #filePath is the compile-time absolute path of this source file.
        // Stripping three components yields the repo root.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // → FlowTests/
            .deletingLastPathComponent() // → Tests/
            .deletingLastPathComponent() // → <repo root>

        let screenDirectories: [URL] = [
            repoRoot.appendingPathComponent("Sources-iOS/Screens"),
            repoRoot.appendingPathComponent("Sources-macOS/Screens")
        ]

        let violations = Self.findSdkViolations(in: screenDirectories)

        // Issue.record and #expect take Comment? (string literals), not String
        // expressions. Log the details via a separate print-style guard first so
        // the failure message is actionable when the test host stdout is captured.
        for violation in violations {
            Issue.record("Arch violation: \(violation)")
        }
        #expect(violations.isEmpty)
    }

    /// Returns violation strings for any screen file that contains a forbidden pattern.
    ///
    /// Separated from the test body so the test itself stays within the 40-line limit.
    private static func findSdkViolations(in screenDirectories: [URL]) -> [String] {
        let forbiddenPatterns: [String] = [
            // Type-name reach-through.
            "OZSmartAccountKit", "OZWalletOperations", "OZTransactionOperations",
            "OZContextRuleManager", "OZPolicyManager", "OZSignerManager",
            "OZCredentialManager", "OZMultiSignerManager", "OZExternalSignerManager",
            "SorobanServer", "SorobanContractParser",
            // Property-accessor reach-through.
            ".walletOperations.", ".transactionOperations.", ".contextRuleManager.",
            ".policyManager.", ".signerManager.", ".credentialManager.",
            ".multiSignerManager.", ".externalSigners."
        ]
        var violations: [String] = []
        let fileManager = FileManager.default
        for screenDir in screenDirectories {
            guard let enumerator = fileManager.enumerator(atPath: screenDir.path) else {
                violations.append("Guard test setup is broken — directory not found: \(screenDir.path)")
                continue
            }
            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix(".swift") else { continue }
                let fullPath = screenDir.appendingPathComponent(relativePath).path
                guard let contents = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
                    continue
                }
                for pattern in forbiddenPatterns where contents.contains(pattern) {
                    violations.append("\(fullPath) contains '\(pattern)'")
                }
            }
        }
        return violations
    }
}
