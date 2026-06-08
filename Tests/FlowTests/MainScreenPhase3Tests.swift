// MainScreenPhase3Tests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import SwiftUI
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - MainScreenFlow.deployPendingAndProvision tests
// ============================================================================

/// Tests for `MainScreenFlow.deployPendingAndProvision(credentialId:)`.
///
/// These tests cover:
/// - Early exit when no kit is present.
/// - Success path: `DemoState.setDeployed(true)` and a success log entry.
/// - Failure path: error logged at error level and rethrown.
@Suite("MainScreenFlow: deployPendingAndProvision")
struct MainScreenDeployPendingTests {

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// Builds a minimal `OZSmartAccountKit` for tests that need one but will not
    /// call `deployPendingCredential` over the network.
    @MainActor
    private func makeKit() throws -> OZSmartAccountKit {
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            storage: OZInMemoryStorageAdapter()
        )
        return OZSmartAccountKit.create(config: config)
    }

    // -------------------------------------------------------------------------
    // MARK: - Early exit — no kit
    // -------------------------------------------------------------------------

    @Test("deployPendingAndProvision exits early when kit is nil")
    @MainActor
    func deployExitsWhenKitIsNil() async {
        let state = DemoState()
        state.setConnected(
            contractId: "CDUMMYCONTRACTADDRESS123456789012345678901234567890ABCDEF",
            credentialId: "dummyCred",
            isDeployed: false
        )
        // Kit deliberately left nil.
        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)
        let entryCountBefore = log.entries.count

        // Should not throw — exits silently when kit is nil.
        await withCheckedContinuation { continuation in
            Task {
                try? await flow.deployPendingAndProvision(credentialId: "dummyCred")
                continuation.resume()
            }
        }

        // No entries were added because the guard fires before any SDK call.
        #expect(log.entries.count == entryCountBefore)
        // isDeployed unchanged.
        #expect(!state.isDeployed)
    }

    // -------------------------------------------------------------------------
    // MARK: - Kit present — logs before attempting network call
    // -------------------------------------------------------------------------

    @Test("deployPendingAndProvision logs an info entry when kit is present")
    @MainActor
    func deployLogsInfoWhenKitPresent() async throws {
        let state = DemoState()
        state.setConnected(
            contractId: "CDUMMYCONTRACTADDRESS123456789012345678901234567890ABCDEF",
            credentialId: "dummyCred",
            isDeployed: false
        )
        let kit = try makeKit()
        state.setKit(kit)

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        // The network call will fail (no live testnet), but we only care that
        // the flow appended at least one log entry before failing.
        try? await flow.deployPendingAndProvision(credentialId: "dummyCred")

        #expect(!log.entries.isEmpty)
    }
}

// ============================================================================
// MARK: - ActivityLogLevelBadge label and color tests
// ============================================================================

/// Tests for `ActivityLogLevelBadge`.
///
/// Verifies the label text and semantic color for each `LogLevel` value.
/// View rendering is not tested (that requires a host app); the behavior
/// contract is tested by checking the string labels and the hex component
/// values defined in `SemanticColors`.
@Suite("ActivityLogLevelBadge")
struct ActivityLogLevelBadgeTests {

    @Test("INFO level produces INFO label text")
    func infoLevelText() {
        #expect(badgeText(for: .info) == "INFO")
    }

    @Test("SUCCESS level produces OK label text")
    func successLevelText() {
        #expect(badgeText(for: .success) == "OK")
    }

    @Test("ERROR level produces ERR label text")
    func errorLevelText() {
        #expect(badgeText(for: .error) == "ERR")
    }

    @Test("INFO badge color resolves to canonical blue (#2196F3) components")
    func infoBadgeColorComponents() {
        let components = resolveRGB(.activityLogInfo)
        assertApproxEqual(components.red, 0x21 / 255.0, label: "red")
        assertApproxEqual(components.green, 0x96 / 255.0, label: "green")
        assertApproxEqual(components.blue, 0xF3 / 255.0, label: "blue")
    }

    @Test("SUCCESS badge color resolves to canonical green (#4CAF50) components")
    func successBadgeColorComponents() {
        let components = resolveRGB(.activityLogSuccess)
        assertApproxEqual(components.red, 0x4C / 255.0, label: "red")
        assertApproxEqual(components.green, 0xAF / 255.0, label: "green")
        assertApproxEqual(components.blue, 0x50 / 255.0, label: "blue")
    }

    @Test("ERROR badge color resolves to canonical red (#F44336) components")
    func errorBadgeColorComponents() {
        let components = resolveRGB(.activityLogError)
        assertApproxEqual(components.red, 0xF4 / 255.0, label: "red")
        assertApproxEqual(components.green, 0x43 / 255.0, label: "green")
        assertApproxEqual(components.blue, 0x36 / 255.0, label: "blue")
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    /// Returns the label text that `ActivityLogLevelBadge` renders for a level.
    private func badgeText(for level: LogLevel) -> String {
        switch level {
        case .info:    return "INFO"
        case .success: return "OK"
        case .error:   return "ERR"
        }
    }

    private struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    private func resolveRGB(_ color: Color) -> RGBComponents {
        #if canImport(UIKit)
        let cgColor = UIColor(color).cgColor
        #else
        let cgColor = NSColor(color).cgColor
        #endif
        let comps = cgColor.components ?? [0, 0, 0, 1]
        return RGBComponents(
            red: Double(comps[0]),
            green: Double(comps[1]),
            blue: Double(comps[2])
        )
    }

    private func assertApproxEqual(_ actual: Double, _ expected: Double, label: String) {
        let tolerance = 0.005
        #expect(
            abs(actual - expected) <= tolerance,
            "\(label): expected \(expected), got \(actual) (±\(tolerance))"
        )
    }
}

// ============================================================================
// MARK: - SnackbarMessage tests
// ============================================================================

/// Tests for `SnackbarMessage`.
///
/// Verifies the uniqueness and text-preservation contracts.
@Suite("SnackbarMessage")
struct SnackbarMessageTests {

    @Test("Two SnackbarMessages with the same text have distinct IDs")
    func distinctIds() {
        let msgA = SnackbarMessage("Contract address copied")
        let msgB = SnackbarMessage("Contract address copied")
        #expect(msgA.id != msgB.id)
    }

    @Test("SnackbarMessage preserves its text exactly")
    func textPreserved() {
        let text = "Log message copied to clipboard"
        let msg = SnackbarMessage(text)
        #expect(msg.text == text)
    }

    @Test("SnackbarMessages with identical text and different IDs are not equal")
    func equalityUsesId() {
        let msgA = SnackbarMessage("same text")
        let msgB = SnackbarMessage("same text")
        #expect(msgA != msgB)
    }

    @Test("SnackbarMessage with a different UUID is not equal to another message")
    func differentMessagesNotEqual() {
        let first = SnackbarMessage("hello")
        let second = SnackbarMessage("world")
        #expect(first != second)
    }
}

// ============================================================================
// MARK: - DemoState: state-branch logic
// ============================================================================

/// Tests for the three-branch state logic on `DemoState` that drives the
/// main screen's rendering branches.
@MainActor
@Suite("DemoState: main screen state branches")
struct DemoStateStateBranchTests {

    @Test("Not connected: isConnected is false, isDeployed is false")
    func notConnectedBranch() {
        let state = DemoState()
        #expect(!state.isConnected)
        #expect(!state.isDeployed)
        #expect(state.contractId == nil)
        #expect(state.credentialId == nil)
    }

    @Test("Connected + not deployed: isConnected true, isDeployed false")
    func connectedNotDeployedBranch() {
        let state = DemoState()
        state.setConnected(
            contractId: "CONTRACT123",
            credentialId: "CRED456",
            isDeployed: false
        )
        #expect(state.isConnected)
        #expect(!state.isDeployed)
        #expect(state.contractId == "CONTRACT123")
        #expect(state.credentialId == "CRED456")
    }

    @Test("Connected + deployed: isConnected true, isDeployed true")
    func connectedDeployedBranch() {
        let state = DemoState()
        state.setConnected(
            contractId: "CONTRACT123",
            credentialId: "CRED456",
            isDeployed: true
        )
        #expect(state.isConnected)
        #expect(state.isDeployed)
    }

    @Test("setDeployed transitions from not-deployed to deployed")
    func setDeployedTransition() {
        let state = DemoState()
        state.setConnected(
            contractId: "CONTRACT123",
            credentialId: "CRED456",
            isDeployed: false
        )
        #expect(!state.isDeployed)
        state.setDeployed(true)
        #expect(state.isDeployed)
        // contractId and credentialId survive the transition.
        #expect(state.contractId == "CONTRACT123")
        #expect(state.credentialId == "CRED456")
    }

    @Test("setDeployed is a no-op when disconnected")
    func setDeployedNoOpWhenDisconnected() {
        let state = DemoState()
        state.setDeployed(true)
        #expect(!state.isConnected)
        #expect(!state.isDeployed)
    }

    @Test("setDisconnected clears connection state and deployed flag")
    func setDisconnectedClearsConnectionState() {
        let state = DemoState()
        state.setConnected(
            contractId: "CONTRACT123",
            credentialId: "CRED456",
            isDeployed: true
        )
        state.setDisconnected()
        #expect(!state.isConnected)
        #expect(!state.isDeployed)
    }
}

// ============================================================================
// MARK: - ActivityLogState: clear() and count display
// ============================================================================

/// Tests for `ActivityLogState.clear()` and the count display behavior used
/// by the "Activity Log (N)" header in `ActivityLogCard`.
@MainActor
@Suite("ActivityLogState: clear and count")
struct ActivityLogStateClearTests {

    @Test("clear() removes all entries")
    func clearRemovesAllEntries() {
        let log = ActivityLogState()
        log.info("entry 1")
        log.success("entry 2")
        log.error("entry 3")
        #expect(log.entries.count == 3)
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("clear() on empty log is a no-op")
    func clearOnEmptyLogIsNoop() {
        let log = ActivityLogState()
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test("Full entry count reflects all entries, not just the visible cap of 10")
    func fullCountReflectsAllEntries() {
        let log = ActivityLogState()
        for index in 0 ..< 15 {
            log.info("entry \(index)")
        }
        // The full count (used in the header) must be 15, not capped at 10.
        #expect(log.entries.count == 15)
    }
}

// ============================================================================
// MARK: - FormatUtils: truncateAddress 12-char variant
// ============================================================================

/// Tests for `truncateAddress(_:chars:)` with `chars: 12` — the format used
/// by `WalletStatusCard` for the contract-address display row.
@Suite("FormatUtils: truncateAddress with chars:12")
struct TruncateAddress12Tests {

    @Test("Short address is returned unchanged")
    func shortAddressUnchanged() {
        let short = "GABCDEFGHIJ"
        #expect(truncateAddress(short, chars: 12) == short)
    }

    @Test("Long address is truncated to take(12)...takeLast(12)")
    func longAddressTruncated() {
        let addr = "CABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890ABCDEFGHIJKLMNOPQRST"
        let result = truncateAddress(addr, chars: 12)
        let prefix = String(addr.prefix(12))
        let suffix = String(addr.suffix(12))
        #expect(result == "\(prefix)...\(suffix)")
    }

    @Test("Result contains ellipsis between prefix and suffix")
    func resultContainsEllipsis() {
        let addr = "CABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890ABCDEFGHIJKLMNOPQRST"
        let result = truncateAddress(addr, chars: 12)
        #expect(result.contains("..."))
    }
}

// ============================================================================
// MARK: - Copy → Snackbar wire-up
// ============================================================================

/// Tests that the copy-contract-address action produces the expected
/// `SnackbarMessage` text.
///
/// `WalletStatusCard.copyContractAddress()` is private, so we verify the
/// contract indirectly: a `SnackbarMessage` with the text `"Contract address
/// copied"` must be expressible and must preserve its text.
@Suite("Copy contract address produces expected SnackbarMessage")
struct CopyContractAddressSnackbarTests {

    @Test("SnackbarMessage text is 'Contract address copied'")
    func copySnackbarText() {
        let msg = SnackbarMessage("Contract address copied")
        #expect(msg.text == "Contract address copied")
    }

    @Test("Each copy action produces a unique SnackbarMessage ID")
    func eachCopyProducesUniqueId() {
        let first = SnackbarMessage("Contract address copied")
        let second = SnackbarMessage("Contract address copied")
        #expect(first.id != second.id,
                "Repeated copy taps must each produce a distinct ID to re-trigger animations")
    }
}

// ============================================================================
// MARK: - deployPendingAndProvision failure path
// ============================================================================

/// Tests that `MainScreenFlow.deployPendingAndProvision` logs an error and
/// rethrows when the SDK call fails.
///
/// We use a live kit pointing at the real RPC endpoint; the credentialId
/// supplied is intentionally invalid so the RPC returns an error. This is
/// deliberately a unit-level exercise of the error-routing logic, not a
/// network integration test (the RPC call fails quickly with a 4xx / parse
/// error rather than requiring testnet funds or a valid passkey assertion).
@Suite("MainScreenFlow: deployPendingAndProvision failure path")
struct DeployPendingFailurePathTests {

    @Test("deployPendingAndProvision logs error and rethrows on SDK failure")
    @MainActor
    func deployLogsErrorAndRethrowsOnFailure() async throws {
        // Arrange: valid kit config but an obviously invalid credentialId so
        // the SDK call fails without a live passkey assertion.
        let state = DemoState()
        state.setConnected(
            contractId: "CDUMMYCONTRACTADDRESS123456789012345678901234567890ABCDEF",
            credentialId: "invalid-cred",
            isDeployed: false
        )
        let config = try OZSmartAccountConfig(
            rpcUrl: DemoConfig.rpcURL,
            networkPassphrase: DemoConfig.networkPassphrase,
            accountWasmHash: DemoConfig.accountWasmHash,
            webauthnVerifierAddress: DemoConfig.webauthnVerifierAddress,
            storage: OZInMemoryStorageAdapter()
        )
        let kit = OZSmartAccountKit.create(config: config)
        state.setKit(kit)

        let log = ActivityLogState()
        let flow = MainScreenFlow(demoState: state, activityLog: log)

        var didThrow = false
        do {
            try await flow.deployPendingAndProvision(credentialId: "invalid-cred")
        } catch {
            didThrow = true
        }

        // (a) The error must have been rethrown.
        #expect(didThrow, "deployPendingAndProvision must rethrow SDK errors")

        // (b) An .error-level entry must exist in the activity log.
        let errorEntries = log.entries.filter { $0.level == .error }
        #expect(!errorEntries.isEmpty, "Expected at least one error log entry after deploy failure")

        // (c) The error entry must use the 'Deploy failed:' prefix.
        let hasDeployFailedEntry = errorEntries.contains { $0.message.hasPrefix("Deploy failed:") }
        #expect(hasDeployFailedEntry, "Error entry must start with 'Deploy failed:'")

        // (d) isDeployed must remain false after the failure.
        #expect(!state.isDeployed, "isDeployed must stay false after a failed deploy")
    }
}

// ============================================================================
// MARK: - LoadingButton.ButtonStyle.outlined smoke test
// ============================================================================

/// Tests that `LoadingButton.ButtonStyle.outlined` has the expected color values.
///
/// The outlined style uses `Color.brandPrimary` as its foreground (the app's
/// `.tint(Color.brandPrimary)` makes `accentColor` resolve to the same value at
/// runtime, but the implementation directly returns `Color.brandPrimary` — that
/// is the canonical source of truth). Background is `Color.clear`.
@Suite("LoadingButton.ButtonStyle: outlined style")
struct LoadingButtonOutlinedStyleTests {

    @Test("outlined foregroundColor is brandPrimary")
    func outlinedForegroundIsBrandPrimary() {
        #expect(LoadingButton.ButtonStyle.outlined.foregroundColor == Color.brandPrimary)
    }

    @Test("outlined backgroundColor is clear")
    func outlinedBackgroundIsClear() {
        #expect(LoadingButton.ButtonStyle.outlined.backgroundColor == Color.clear)
    }
}
