// WalletConnectionFlowTests.swift
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
// MARK: - Path A: Auto Connect
// ============================================================================

@Suite("WalletConnectionFlow: Path A — Auto Connect")
struct WalletConnectionAutoConnectTests {

    // Test 1: Auto-connect with session — Connected, isDeployed=true
    @Test("Auto-connect with session — DemoState connected, isDeployed true, no picker")
    @MainActor
    func autoConnectSessionRestored() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult(restoredFromSession: true)
        ops.contextRulesCount = 1
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.autoConnect()

        guard case .connected(let credId, let contractId, let isDeployed, let restored) = result else {
            Issue.record("Expected .connected result")
            return
        }
        #expect(credId == WalletConnectionFixtures.credentialId)
        #expect(contractId == WalletConnectionFixtures.contractId)
        #expect(isDeployed == true)
        #expect(restored == true)
        #expect(deps.state.isConnected == true)
        #expect(deps.state.contractId == WalletConnectionFixtures.contractId)
        #expect(ops.connectWalletCallCount == 1)
        #expect(ops.lastConnectOptions?.prompt == true)
        let hasSuccess = deps.log.entries.contains { $0.level == .success }
        #expect(hasSuccess)
    }

    // Test 2: Auto-connect, contract not deployed on-chain
    @Test("Auto-connect — context rule probe throws, isDeployed=false")
    @MainActor
    func autoConnectContractNotDeployed() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult(restoredFromSession: false)
        ops.contextRulesError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.autoConnect()

        guard case .connected(_, _, let isDeployed, _) = result else {
            Issue.record("Expected .connected result")
            return
        }
        #expect(isDeployed == false)
        #expect(deps.state.isDeployed == false)
    }

    // Test: nil returned from connectWallet — no state change
    @Test("Auto-connect — nil result returns nil, no state change")
    @MainActor
    func autoConnectReturnsNil() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = nil
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.autoConnect()

        #expect(result == nil)
        #expect(deps.state.isConnected == false)
        let hasInfo = deps.log.entries.contains { $0.level == .info }
        #expect(hasInfo)
    }
}

// ============================================================================
// MARK: - Path B: Connect via Indexer
// ============================================================================

@Suite("WalletConnectionFlow: Path B — Connect via Indexer")
struct WalletConnectionIndexerTests {

    // Test 3: Indexer single result — Connected, pop expected
    @Test("Indexer single result — DemoState connected, no picker")
    @MainActor
    func indexerSingleResult() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 1
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectViaIndexer()

        guard case .connected(let credId, _, _, _) = result else {
            Issue.record("Expected .connected result")
            return
        }
        #expect(credId == WalletConnectionFixtures.credentialId)
        #expect(deps.state.isConnected == true)
        #expect(ops.authCallCount == 1)
        #expect(ops.connectWalletCallCount == 1)
        #expect(ops.lastConnectOptions?.credentialId == WalletConnectionFixtures.credentialId)
    }

    // Test 4: Indexer ambiguous — picker candidates match
    @Test("Indexer ambiguous — picker state contains both candidates")
    @MainActor
    func indexerAmbiguousResult() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeAmbiguousResult()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectViaIndexer()

        guard case .ambiguous(let credId, let candidates) = result else {
            Issue.record("Expected .ambiguous result")
            return
        }
        #expect(credId == WalletConnectionFixtures.credentialId)
        #expect(candidates.count == 2)
        #expect(candidates.contains(WalletConnectionFixtures.contractId))
        #expect(candidates.contains(WalletConnectionFixtures.contractId2))
        #expect(deps.state.isConnected == false)
    }

    // Test 5: Indexer no results — nil returned
    @Test("Indexer no results — nil, inline error expected, no state change")
    @MainActor
    func indexerNoResults() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = nil
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectViaIndexer()

        #expect(result == nil)
        #expect(deps.state.isConnected == false)
        let hasError = deps.log.entries.contains { $0.level == .error }
        #expect(hasError)
    }
}

// ============================================================================
// MARK: - Path C: Connect with Address
// ============================================================================

@Suite("WalletConnectionFlow: Path C — Connect with Address")
struct WalletConnectionAddressTests {

    // Test 6: Valid C-address — Connected
    @Test("Valid C-address — DemoState connected, isDeployed true")
    @MainActor
    func validAddressConnects() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 2
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectWithAddress(
            contractAddress: WalletConnectionFixtures.contractId
        )

        guard case .connected(_, let contractId, let isDeployed, _) = result else {
            Issue.record("Expected .connected result")
            return
        }
        #expect(contractId == WalletConnectionFixtures.contractId)
        #expect(isDeployed == true)
        #expect(deps.state.isConnected == true)
        #expect(ops.authCallCount == 1)
        #expect(ops.connectWalletCallCount == 1)
        #expect(ops.lastConnectOptions?.contractId == WalletConnectionFixtures.contractId)
    }

    // Test 7 (validation) is enforced at the UI layer by the button's disabled state.
    // Here we test that the address is passed through to the SDK correctly.
    @Test("Address passed to connectWallet with both credentialId and contractId")
    @MainActor
    func addressAndCredentialPassedToSdk() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult(
            credentialId: WalletConnectionFixtures.credentialId2
        )
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 1
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        _ = try await deps.flow.connectWithAddress(
            contractAddress: WalletConnectionFixtures.contractId2
        )

        #expect(ops.lastConnectOptions?.credentialId == WalletConnectionFixtures.credentialId2)
        #expect(ops.lastConnectOptions?.contractId == WalletConnectionFixtures.contractId2)
    }

    // Test 8: Connect fails — nil returned
    @Test("Connect with address fails — nil returned, no state change")
    @MainActor
    func addressConnectFails() async throws {
        let ops = MockConnectionOperations()
        ops.authResult = WalletConnectionFixtures.makeAuthResult()
        ops.connectWalletResult = nil
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.connectWithAddress(
            contractAddress: WalletConnectionFixtures.contractId
        )

        #expect(result == nil)
        #expect(deps.state.isConnected == false)
    }
}

// ============================================================================
// MARK: - Path D: Pending Deployments
// ============================================================================

@Suite("WalletConnectionFlow: Path D — Pending Deployments")
struct WalletConnectionPendingTests {

    // Test 9: Retry success
    @Test("Retry deploy success — DemoState connected, deployed")
    @MainActor
    func retryDeploySuccess() async throws {
        let ops = MockConnectionOperations()
        ops.deployResult = WalletConnectionFixtures.makeDeployPendingResult()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.retryPendingDeploy(
            credentialId: WalletConnectionFixtures.credentialId
        )

        guard case .connected(let credId, let contractId, let isDeployed, _) = result else {
            Issue.record("Expected .connected result")
            return
        }
        #expect(credId == WalletConnectionFixtures.credentialId)
        #expect(contractId == WalletConnectionFixtures.contractId)
        #expect(isDeployed == true)
        #expect(deps.state.isConnected == true)
        #expect(deps.state.isDeployed == true)
        #expect(ops.deployCallCount == 1)
        #expect(ops.lastDeployCredentialId == WalletConnectionFixtures.credentialId)
    }

    // Test 10: Retry failure — throws, no state change
    @Test("Retry deploy failure — throws, no DemoState change")
    @MainActor
    func retryDeployFails() async throws {
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

    // Test 10b: Retry failure — DemoState reconciled to disconnected even if previously connected
    @Test("Retry deploy failure — DemoState reconciled to disconnected")
    @MainActor
    func retryDeployFailureReconcilesDemoState() async {
        let ops = MockConnectionOperations()
        ops.deployError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        // Pre-set connected state to simulate SDK having pre-set it before submission fails.
        deps.state.setConnected(
            contractId: WalletConnectionFixtures.contractId,
            credentialId: WalletConnectionFixtures.credentialId,
            isDeployed: false
        )
        #expect(deps.state.isConnected == true)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.retryPendingDeploy(
                credentialId: WalletConnectionFixtures.credentialId
            )
        }
        #expect(deps.state.isConnected == false)
    }

    // Test 11: Delete success — returns true
    @Test("Delete pending credential — returns true, no state mutation")
    @MainActor
    func deletePendingSuccess() async {
        let ops = MockConnectionOperations()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let success = await deps.flow.deletePendingCredential(
            credentialId: WalletConnectionFixtures.credentialId
        )

        #expect(success == true)
        #expect(ops.deleteCallCount == 1)
        #expect(ops.lastDeleteCredentialId == WalletConnectionFixtures.credentialId)
    }

    // Delete failure — returns false
    @Test("Delete pending credential — SDK throws, returns false")
    @MainActor
    func deletePendingFailure() async {
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

    // Load pending credentials
    @Test("loadPendingCredentials — returns all pending from operations")
    @MainActor
    func loadPendingCredentials() async throws {
        let ops = MockConnectionOperations()
        ops.pendingCredentials = [
            WalletConnectionFixtures.makePendingCredential(credentialId: WalletConnectionFixtures.credentialId),
            WalletConnectionFixtures.makePendingCredential(credentialId: WalletConnectionFixtures.credentialId2)
        ]
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let pending = try await deps.flow.loadPendingCredentials()

        #expect(pending.count == 2)
        #expect(pending[0].credentialId == WalletConnectionFixtures.credentialId)
    }
}

// ============================================================================
// MARK: - Cancellation
// ============================================================================

@Suite("WalletConnectionFlow: Cancellation")
struct WalletConnectionCancellationTests {

    // Test 12: Cancellation during indexer auth — throws user-cancelled error
    @Test("Indexer — authenticate passkey throws cancelled, propagates")
    @MainActor
    func indexerAuthCancelled() async {
        let ops = MockConnectionOperations()
        ops.authError = MockCancelledPasskeyError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.connectViaIndexer()
        }
        #expect(deps.state.isConnected == false)
    }

    // Test 12b: Cancellation during address auth — throws user-cancelled error
    @Test("Address — authenticate passkey throws cancelled, propagates")
    @MainActor
    func addressAuthCancelled() async {
        let ops = MockConnectionOperations()
        ops.authError = MockCancelledPasskeyError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.connectWithAddress(
                contractAddress: WalletConnectionFixtures.contractId
            )
        }
        #expect(deps.state.isConnected == false)
    }
}

// ============================================================================
// MARK: - Network error
// ============================================================================

@Suite("WalletConnectionFlow: Network Error")
struct WalletConnectionNetworkErrorTests {

    // Test 13: Network error during connectWallet — throws
    @Test("connectWallet network error — throws, no state change")
    @MainActor
    func connectWalletNetworkError() async {
        let ops = MockConnectionOperations()
        ops.connectWalletError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        await #expect(throws: (any Error).self) {
            _ = try await deps.flow.autoConnect()
        }
        #expect(deps.state.isConnected == false)
    }
}

// ============================================================================
// MARK: - Finalize ambiguous
// ============================================================================

@Suite("WalletConnectionFlow: Finalize Ambiguous")
struct WalletConnectionFinalizeTests {

    // Finalize with chosen contract — Connected, no second WebAuthn prompt
    @Test("finalizeAmbiguous — uses supplied credentialId, no authenticate call")
    @MainActor
    func finalizeAmbiguousNoReauth() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 1
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.finalizeAmbiguous(
            credentialId: WalletConnectionFixtures.credentialId,
            contractAddress: WalletConnectionFixtures.contractId
        )

        #expect(result != nil)
        #expect(ops.authCallCount == 0, "finalizeAmbiguous must not re-prompt WebAuthn")
        #expect(ops.connectWalletCallCount == 1)
        #expect(ops.lastConnectOptions?.credentialId == WalletConnectionFixtures.credentialId)
        #expect(ops.lastConnectOptions?.contractId == WalletConnectionFixtures.contractId)
    }
}

// ============================================================================
// MARK: - Deployment probe
// ============================================================================

@Suite("WalletConnectionFlow: isDeployed probe")
struct WalletConnectionDeployedProbeTests {

    // isDeployed = true when contextRulesCount succeeds
    @Test("Context rules count succeeds — isDeployed true")
    @MainActor
    func isDeployedTrue() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesCount = 3
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.autoConnect()
        guard case .connected(_, _, let isDeployed, _) = result else {
            Issue.record("Expected .connected")
            return
        }
        #expect(isDeployed == true)
    }

    // isDeployed = false when RPC throws
    @Test("Context rules count throws — isDeployed false, no error propagation")
    @MainActor
    func isDeployedFalseOnRpcThrow() async throws {
        let ops = MockConnectionOperations()
        ops.connectWalletResult = WalletConnectionFixtures.makeConnectedResult()
        ops.contextRulesError = MockNetworkConnectionError()
        let deps = WalletConnectionFixtures.makeFlow(ops: ops)

        let result = try await deps.flow.autoConnect()
        guard case .connected(_, _, let isDeployed, _) = result else {
            Issue.record("Expected .connected")
            return
        }
        #expect(isDeployed == false)
        #expect(deps.state.isDeployed == false)
    }
}
