// DemoTokenTypes.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// MARK: - DemoTokenServiceError

/// Errors thrown by `DemoTokenService`.
public enum DemoTokenServiceError: Error, Sendable {

    /// The service was initialised with a non-testnet network passphrase.
    ///
    /// The DEMO token admin keypair is derived from a publicly-visible seed string.
    /// Deploying on any network other than testnet would expose admin control of a
    /// token with real monetary value. The service refuses to proceed on mainnet or
    /// futurenet to make this explicit at initialisation time.
    case notTestnet

    /// The deterministic admin keypair could not be derived from the seed.
    case adminKeyDerivationFailed(reason: String)

    /// The deploy transaction failed on-chain.
    case deployFailed(reason: String)

    /// The mint invocation failed on-chain.
    case mintFailed(reason: String)

    /// The deployed contract address did not match the pre-derived address.
    case addressMismatch(expected: String, actual: String)
}

extension DemoTokenServiceError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notTestnet:
            return "DemoTokenService only works on Stellar testnet. " +
                   "The admin keypair is publicly derivable — never use this service on mainnet."
        case .adminKeyDerivationFailed(let reason):
            return "Failed to derive DEMO token admin keypair: \(reason)"
        case .deployFailed(let reason):
            return "DEMO token contract deployment failed: \(reason)"
        case .mintFailed(let reason):
            return "DEMO token mint failed: \(reason)"
        case .addressMismatch(let expected, let actual):
            return "Deployed contract address (\(actual)) does not match pre-derived address " +
                   "(\(expected)). This indicates a derivation bug."
        }
    }
}

// MARK: - DemoTokenResult

/// Result of `DemoTokenService.ensureTokenAndMint`.
public struct DemoTokenResult: Sendable {

    /// The DEMO token contract address (C-address).
    public let tokenContractId: String

    /// Number of stroops minted in this call.
    public let amountMinted: Int64

    /// True if the contract was already deployed before this call; false if newly deployed.
    public let alreadyExisted: Bool

    public init(tokenContractId: String, amountMinted: Int64, alreadyExisted: Bool) {
        self.tokenContractId = tokenContractId
        self.amountMinted = amountMinted
        self.alreadyExisted = alreadyExisted
    }
}
