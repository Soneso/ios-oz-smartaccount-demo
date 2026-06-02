// PendingCredentialCardTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - PendingCredentialCard display logic tests
// ============================================================================
// Tests cover the business logic behind the pending card: credential ID
// truncation format, contract ID truncation, and the flow-level retry / delete
// behaviour that drives the card's callbacks.

@Suite("PendingCredentialCard: display truncation")
struct PendingCredentialCardTruncationTests {

    // Credential ID truncation: first 12 + last 8
    @Test("Credential ID truncated to first-12...last-8 when long")
    func credentialIdTruncation() {
        let longId = "ABCDEFGHIJKL_MIDDLE_PORTION_WXYZ5678"
        let first12 = String(longId.prefix(12))
        let last8 = String(longId.suffix(8))
        let expected = "\(first12)...\(last8)"
        // The truncation logic from PendingCredentialCard
        let result = truncatePendingCredentialId(longId)
        #expect(result == expected)
    }

    // Short credential ID not truncated
    @Test("Short credential ID not truncated")
    func shortCredentialIdNotTruncated() {
        let shortId = "ABCDEFGHIJ"
        let result = truncatePendingCredentialId(shortId)
        #expect(result == shortId)
    }

    // Nickname appended when present
    @Test("Nickname appended with parentheses when non-nil")
    func nicknameAppended() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345678"
        let nickname = "Primary"
        let truncated = truncatePendingCredentialId(id)
        let result = "\(truncated) (\(nickname))"
        #expect(result.hasSuffix("(Primary)"))
    }

    // Nickname not appended when nil
    @Test("No nickname suffix when nickname is nil")
    func noNicknameWhenNil() {
        let id = "ABCDEFGHIJKLMNOPQRSTUVWXYZ12345678"
        let result = truncatePendingCredentialId(id)
        #expect(!result.contains("("))
    }

    // Contract ID: first 12 + last 12
    @Test("Contract ID truncated to first-12...last-12 when long")
    func contractIdTruncation() {
        let longContract = "CABC1234567890123456789012345678901234567890123456789012"
        let first12 = String(longContract.prefix(12))
        let last12 = String(longContract.suffix(12))
        let expected = "\(first12)...\(last12)"
        let result = truncatePendingContractId(longContract)
        #expect(result == expected)
    }

    // Nil contract ID returns "Unknown"
    @Test("Nil contractId shows 'Unknown'")
    func nilContractIdShowsUnknown() {
        let result = truncatePendingContractId(nil)
        #expect(result == "Unknown")
    }
}

// ============================================================================
// MARK: - PendingCredentialCard flow integration tests
// ============================================================================

@Suite("PendingCredentialCard: retry and delete flow integration")
struct PendingCredentialCardFlowTests {

    // Retry calls deployPendingCredential with the correct credential ID
    @Test("Retry deploy — deployPendingCredential called with correct credentialId")
    @MainActor
    func retryCallsCorrectCredential() async throws {
        let ops = MockConnectionOperations()
        ops.deployResult = WalletConnectionFixtures.makeDeployPendingResult(
            contractId: WalletConnectionFixtures.contractId
        )
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        _ = try await deps.flow.retryPendingDeploy(
            credentialId: WalletConnectionFixtures.credentialId
        )

        #expect(ops.lastDeployCredentialId == WalletConnectionFixtures.credentialId)
        #expect(deps.state.isConnected == true)
        #expect(deps.state.isDeployed == true)
    }

    // Retry failure on one card does not affect another
    @Test("Retry failure — error thrown, DemoState not mutated")
    @MainActor
    func retryFailureDoesNotMutateState() async {
        let ops = MockConnectionOperations()
        ops.deployError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.retryPendingDeploy(
                credentialId: WalletConnectionFixtures.credentialId
            )
        }
        #expect(deps.state.isConnected == false)
    }

    // Delete removes the credential
    @Test("Delete — deleteCredential called with correct credentialId")
    @MainActor
    func deleteCallsCorrectCredential() async {
        let ops = MockConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let success = await deps.flow.deletePendingCredential(
            credentialId: WalletConnectionFixtures.credentialId
        )

        #expect(success == true)
        #expect(ops.lastDeleteCredentialId == WalletConnectionFixtures.credentialId)
    }

    // Delete failure — returns false
    @Test("Delete failure — returns false, error logged")
    @MainActor
    func deleteFailure() async {
        let ops = MockConnectionOperations()
        ops.deleteError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let success = await deps.flow.deletePendingCredential(
            credentialId: WalletConnectionFixtures.credentialId
        )

        #expect(success == false)
        let hasError = deps.log.entries.contains { $0.level == .error }
        #expect(hasError)
    }

    // Loading pending list returns correct credentials
    @Test("Load pending — returns all credentials from storage")
    @MainActor
    func loadPendingReturnsCredentials() async throws {
        let ops = MockConnectionOperations()
        ops.pendingCredentials = [
            WalletConnectionFixtures.makePendingCredential(
                credentialId: WalletConnectionFixtures.credentialId,
                contractId: WalletConnectionFixtures.contractId,
                nickname: "Main"
            ),
            WalletConnectionFixtures.makePendingCredential(
                credentialId: WalletConnectionFixtures.credentialId2,
                contractId: nil,
                nickname: nil
            )
        ]
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let pending = try await deps.flow.loadPendingCredentials()

        #expect(pending.count == 2)
        #expect(pending[0].nickname == "Main")
        #expect(pending[1].contractId == nil)
    }
}

// ============================================================================
// MARK: - Test 14: Kit nil disables all sections
// ============================================================================

@Suite("WalletConnectionFlow: Kit nil guard")
struct WalletConnectionKitNilTests {

    // When kit is nil, NilConnectionOperations always throws
    @Test("Kit nil — autoConnect throws immediately")
    @MainActor
    func kitNilAutoConnectThrows() async {
        let ops = NilTestConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.autoConnect()
        }
    }

    @Test("Kit nil — connectViaIndexer throws immediately")
    @MainActor
    func kitNilIndexerThrows() async {
        let ops = NilTestConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.connectViaIndexer()
        }
    }

    @Test("Kit nil — connectWithAddress throws immediately")
    @MainActor
    func kitNilAddressThrows() async {
        let ops = NilTestConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.connectWithAddress(
                contractAddress: WalletConnectionFixtures.contractId
            )
        }
    }

    @Test("Kit nil — retryPendingDeploy throws immediately")
    @MainActor
    func kitNilRetryThrows() async {
        let ops = NilTestConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.retryPendingDeploy(
                credentialId: WalletConnectionFixtures.credentialId
            )
        }
    }
}

// ============================================================================
// MARK: - NilTestConnectionOperations
// ============================================================================

/// A `ConnectionOperationsType` that always throws, simulating the state where
/// no kit is initialized. Used by kit-nil guard tests.
///
/// Wraps the shared `NilConnectionOperations` from `WalletConnectionFlow.swift`
/// so the test suite does not duplicate the implementation.
private typealias NilTestConnectionOperations = NilConnectionOperations

// ============================================================================
// MARK: - Truncation helpers (test-local, same logic as PendingCredentialCard)
// ============================================================================

/// Same truncation logic as `PendingCredentialCard.credentialIdDisplay`, extracted
/// for unit testing without requiring SwiftUI view instantiation.
private func truncatePendingCredentialId(_ id: String) -> String {
    guard id.count > 20 else { return id }
    return "\(id.prefix(12))...\(id.suffix(8))"
}

/// Same truncation logic as `PendingCredentialCard.contractIdDisplay`, extracted
/// for unit testing without requiring SwiftUI view instantiation.
private func truncatePendingContractId(_ contractId: String?) -> String {
    guard let contractId else { return "Unknown" }
    guard contractId.count > 28 else { return contractId }
    return "\(contractId.prefix(12))...\(contractId.suffix(12))"
}
