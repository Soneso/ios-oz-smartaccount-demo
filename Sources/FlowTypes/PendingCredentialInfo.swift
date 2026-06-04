// PendingCredentialInfo.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - PendingCredentialInfo
// ============================================================================

/// Demo-layer view model for a pending credential in the wallet connection
/// screen.
///
/// Contains only the fields the UI needs from `OZStoredCredential`, keeping
/// `WalletConnectionScreenCore` and `PendingCredentialCard` free of a direct
/// `import stellarsdk` dependency.
public struct PendingCredentialInfo: Sendable, Equatable, Hashable {

    /// Base64URL-encoded WebAuthn credential identifier.
    public let credentialId: String

    /// Smart account contract address (`C…` strkey), or `nil` when not yet
    /// derived.
    public let contractId: String?

    /// Optional user-friendly nickname for this credential.
    public let nickname: String?

    /// Initializes a `PendingCredentialInfo`.
    public init(credentialId: String, contractId: String?, nickname: String?) {
        self.credentialId = credentialId
        self.contractId = contractId
        self.nickname = nickname
    }
}

// ============================================================================
// MARK: - Conversion
// ============================================================================

extension PendingCredentialInfo {

    /// Converts an `OZStoredCredential` into the demo DTO, projecting only the
    /// fields the pending-deployment UI requires.
    public init(_ credential: OZStoredCredential) {
        self.credentialId = credential.credentialId
        self.contractId = credential.contractId
        self.nickname = credential.nickname
    }
}

extension Array where Element == OZStoredCredential {

    /// Maps an array of `OZStoredCredential` to `[PendingCredentialInfo]`.
    public func asPendingInfo() -> [PendingCredentialInfo] {
        map { PendingCredentialInfo($0) }
    }
}
