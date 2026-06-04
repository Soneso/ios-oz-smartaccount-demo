// ConnectionDTOs.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - WalletConnectOptions
// ============================================================================

/// Demo-layer equivalent of the SDK's `OZConnectWalletOptions`.
///
/// Isolates `ConnectionOperationsType` from the SDK type so the protocol and
/// its mock implementations do not require `import stellarsdk`. The production
/// adapter `ConnectionOperationsAdapter` converts this to `OZConnectWalletOptions`
/// before forwarding to the SDK.
public struct WalletConnectOptions: Sendable, Equatable {

    /// Credential identifier to connect with directly, or `nil` when the
    /// credential is resolved via a WebAuthn ceremony.
    public let credentialId: String?

    /// Contract address to connect to directly, or `nil` when resolved via the
    /// indexer or derivation cascade.
    public let contractId: String?

    /// When `true`, triggers a WebAuthn ceremony if no valid session exists.
    public let prompt: Bool

    /// Initializes `WalletConnectOptions`.
    public init(credentialId: String? = nil, contractId: String? = nil, prompt: Bool = false) {
        self.credentialId = credentialId
        self.contractId = contractId
        self.prompt = prompt
    }

    /// Converts to the SDK `OZConnectWalletOptions`.
    public func toSDK() -> OZConnectWalletOptions {
        OZConnectWalletOptions(
            credentialId: credentialId,
            contractId: contractId,
            prompt: prompt
        )
    }
}

// ============================================================================
// MARK: - PasskeyCredential
// ============================================================================

/// Demo-layer DTO carrying the credential ID returned by a WebAuthn ceremony.
///
/// Isolates `ConnectionOperationsType` from the SDK's `OZAuthenticatePasskeyResult`,
/// which carries full signature material not needed by the connection flow.
public struct PasskeyCredential: Sendable {

    /// Base64URL-encoded credential identifier produced by the WebAuthn ceremony.
    public let credentialId: String

    /// Initializes a `PasskeyCredential`.
    public init(credentialId: String) {
        self.credentialId = credentialId
    }
}

// ============================================================================
// MARK: - PendingDeployResult
// ============================================================================

/// Demo-layer DTO for the outcome of deploying a pending credential.
///
/// Isolates `ConnectionOperationsType` from the SDK's `OZDeployPendingResult`.
public struct PendingDeployResult: Sendable {

    /// Smart account contract address (`C…` strkey).
    public let contractId: String

    /// Transaction hash, or `nil` when `autoSubmit` was `false`.
    public let transactionHash: String?

    /// Initializes a `PendingDeployResult`.
    public init(contractId: String, transactionHash: String?) {
        self.contractId = contractId
        self.transactionHash = transactionHash
    }
}

// ============================================================================
// MARK: - Conversion helpers
// ============================================================================

extension OZConnectWalletResult {

    /// Maps the SDK `OZConnectWalletResult` to the demo-layer `ConnectionResult`.
    ///
    /// `isDeployed` defaults to `false`; callers that probe on-chain existence
    /// overwrite this in the flow.
    public func toConnectionResult(isDeployed: Bool = false) -> ConnectionResult {
        switch self {
        case .connected(let credentialId, let contractId, let restoredFromSession):
            return .connected(
                credentialId: credentialId,
                contractId: contractId,
                isDeployed: isDeployed,
                restoredFromSession: restoredFromSession
            )
        case .ambiguous(let credentialId, let candidates):
            return .ambiguous(credentialId: credentialId, candidates: candidates)
        }
    }
}

extension OZAuthenticatePasskeyResult {

    /// Maps the SDK `OZAuthenticatePasskeyResult` to `PasskeyCredential`.
    public var asPasskeyCredential: PasskeyCredential {
        PasskeyCredential(credentialId: credentialId)
    }
}

extension OZDeployPendingResult {

    /// Maps the SDK `OZDeployPendingResult` to `PendingDeployResult`.
    public var asPendingDeployResult: PendingDeployResult {
        PendingDeployResult(contractId: contractId, transactionHash: transactionHash)
    }
}
