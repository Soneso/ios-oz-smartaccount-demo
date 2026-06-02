// WalletConnectionTestSupport.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif

// ============================================================================
// MARK: - Test fixtures
// ============================================================================

enum WalletConnectionFixtures {

    static let contractId = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
    static let contractId2 = "CDCYWK73YTYFJZZSJ5V7EDFNHYBG4QN3VUNG2IGD27KJDDPNCZKBCBXK"
    static let credentialId = "dGVzdC1jcmVkZW50aWFsLWlk"
    static let credentialId2 = "c2Vjb25kLWNyZWRlbnRpYWw"

    static func makeConnectedResult(
        credentialId: String = Self.credentialId,
        contractId: String = Self.contractId,
        restoredFromSession: Bool = false
    ) -> ConnectionResult {
        .connected(
            credentialId: credentialId,
            contractId: contractId,
            isDeployed: false,
            restoredFromSession: restoredFromSession
        )
    }

    static func makeAmbiguousResult(
        credentialId: String = Self.credentialId,
        candidates: [String] = [Self.contractId, Self.contractId2]
    ) -> ConnectionResult {
        .ambiguous(credentialId: credentialId, candidates: candidates)
    }

    static func makeDeployPendingResult(
        contractId: String = Self.contractId
    ) -> PendingDeployResult {
        PendingDeployResult(contractId: contractId, transactionHash: "abc123txhash")
    }

    static func makePendingCredential(
        credentialId: String = Self.credentialId,
        contractId: String? = Self.contractId,
        nickname: String? = nil
    ) -> PendingCredentialInfo {
        PendingCredentialInfo(credentialId: credentialId, contractId: contractId, nickname: nickname)
    }

    static func makeAuthResult(
        credentialId: String = Self.credentialId
    ) -> PasskeyCredential {
        PasskeyCredential(credentialId: credentialId)
    }

    /// Builds a `WalletConnectionFlow` with the given mock, returning the
    /// flow together with the state and log for inspection.
    @MainActor
    static func makeFlow(
        ops: any ConnectionOperationsType,
        mainFlow: MainScreenFlow? = nil
    ) -> WalletConnectionFlowDeps {
        let state = DemoState()
        let log = ActivityLogState()
        let flow = WalletConnectionFlow(
            demoState: state,
            activityLog: log,
            operations: ops,
            mainScreenFlow: mainFlow
        )
        return WalletConnectionFlowDeps(flow: flow, state: state, log: log)
    }
}

// ============================================================================
// MARK: - WalletConnectionFlowDeps
// ============================================================================

struct WalletConnectionFlowDeps {
    let flow: WalletConnectionFlow
    let state: DemoState
    let log: ActivityLogState
}

// ============================================================================
// MARK: - MockConnectionOperations
// ============================================================================

/// Configurable mock for `ConnectionOperationsType`.
///
/// Control return values via the `connect*`, `auth*`, `deploy*`, etc. properties.
/// Records calls so tests can assert on parameters.
final class MockConnectionOperations: ConnectionOperationsType, @unchecked Sendable {

    // Connect wallet
    var connectWalletResult: ConnectionResult?
    var connectWalletError: Error?
    private(set) var connectWalletCallCount: Int = 0
    private(set) var lastConnectOptions: WalletConnectOptions?

    // Authenticate
    var authResult: PasskeyCredential?
    var authError: Error?
    private(set) var authCallCount: Int = 0

    // Deploy pending
    var deployResult: PendingDeployResult?
    var deployError: Error?
    private(set) var deployCallCount: Int = 0
    private(set) var lastDeployCredentialId: String?

    // Pending credentials
    var pendingCredentials: [PendingCredentialInfo] = []
    var pendingCredentialsError: Error?

    // Delete credential
    var deleteError: Error?
    private(set) var deleteCallCount: Int = 0
    private(set) var lastDeleteCredentialId: String?

    // Context rules count (deployed probe)
    var contextRulesCount: UInt32 = 1
    var contextRulesError: Error?

    func connectWallet(options: WalletConnectOptions) async throws -> ConnectionResult? {
        connectWalletCallCount += 1
        lastConnectOptions = options
        if let error = connectWalletError { throw error }
        return connectWalletResult
    }

    func authenticatePasskey() async throws -> PasskeyCredential {
        authCallCount += 1
        if let error = authError { throw error }
        guard let result = authResult else {
            preconditionFailure("MockConnectionOperations: authResult not configured")
        }
        return result
    }

    func deployPendingCredential(
        credentialId: String,
        autoSubmit: Bool,
        autoFund: Bool,
        nativeTokenContract: String?
    ) async throws -> PendingDeployResult {
        deployCallCount += 1
        lastDeployCredentialId = credentialId
        if let error = deployError { throw error }
        guard let result = deployResult else {
            preconditionFailure("MockConnectionOperations: deployResult not configured")
        }
        return result
    }

    func getPendingCredentials() async throws -> [PendingCredentialInfo] {
        if let error = pendingCredentialsError { throw error }
        return pendingCredentials
    }

    func deleteCredential(credentialId: String) async throws {
        deleteCallCount += 1
        lastDeleteCredentialId = credentialId
        if let error = deleteError { throw error }
    }

    func getContextRulesCount() async throws -> UInt32 {
        if let error = contextRulesError { throw error }
        return contextRulesCount
    }
}

// ============================================================================
// MARK: - Test error stubs
// ============================================================================

struct MockCancelledPasskeyError: Error, LocalizedError {
    var errorDescription: String? { "The operation was cancelled by the user." }
}

struct MockNetworkConnectionError: Error, LocalizedError {
    var errorDescription: String? { "Network unreachable: connection timed out." }
}
