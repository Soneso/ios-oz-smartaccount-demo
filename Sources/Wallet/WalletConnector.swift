// WalletConnector.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - WalletMetadata
// ============================================================================

/// Descriptive metadata for a connected external wallet.
///
/// Returned by ``WalletConnector/walletMetadata`` after a successful connection.
/// Displayed in the pairing confirmation sheet and the multi-signer signer picker.
public struct WalletMetadata: Sendable, Equatable {

    /// Human-readable wallet display name.
    public let name: String

    /// Website URL for the wallet, if provided by the wallet during pairing.
    public let url: String?

    /// URL string for the wallet's icon image, if provided.
    public let iconUrl: String?

    /// Initializes a new `WalletMetadata`.
    public init(name: String, url: String? = nil, iconUrl: String? = nil) {
        self.name = name
        self.url = url
        self.iconUrl = iconUrl
    }
}

// ============================================================================
// MARK: - SignedAuthEntry
// ============================================================================

/// The result of asking an external wallet to sign an OZ smart-account auth entry.
///
/// For Ed25519 wallets, the wallet signs `SHA-256(preimage)` where `preimage` is the
/// raw `HashIDPreimage::SorobanAuthorization` XDR that was passed in `authEntryXdr`.
/// The SDK's `OZExternalSignerManager.verifyExternalWalletSignature` verifies the
/// returned signature before accepting it — the adapter does not add a second check.
public struct SignedAuthEntry: Sendable, Equatable {

    /// Base64-encoded signature returned by the wallet.
    ///
    /// For Ed25519 wallets this is the raw 64-byte Ed25519 signature over
    /// `SHA-256(HashIDPreimage XDR)` in base64.
    public let signedAuthEntry: String

    /// Stellar G-address of the signer that produced the signature.
    public let signerAddress: String

    /// Initializes a new `SignedAuthEntry`.
    public init(signedAuthEntry: String, signerAddress: String) {
        self.signedAuthEntry = signedAuthEntry
        self.signerAddress = signerAddress
    }
}

// ============================================================================
// MARK: - WalletConnectorError
// ============================================================================

/// Errors thrown by ``WalletConnector`` implementations.
public enum WalletConnectorError: Error, Sendable {

    /// The platform does not support external wallet connections.
    ///
    /// On macOS, external wallet connections via WalletConnect are not available
    /// because the Reown SDK requires UIKit deep-link handling. See
    /// ``NoOpWalletConnector`` for the macOS multi-signer approach (keypair delegation only).
    case notSupportedOnPlatform(reason: String)

    /// The connector is running in a simulator environment where WalletConnect pairing
    /// is not functional. Use a physical device for wallet-pairing flows.
    case notSupportedInSimulator

    /// The connection attempt timed out before the wallet confirmed the pairing.
    case connectionTimeout

    /// The signing request timed out before the wallet returned a response.
    case signingTimeout

    /// No active session exists. Call `connect()` before requesting a signature.
    case noActiveSession

    /// The wallet returned a response that could not be parsed.
    case malformedWalletResponse(detail: String)

    /// The wallet rejected the signing request.
    case signingRejected(reason: String)

    /// A generic underlying error from the Reown stack.
    case reownError(underlying: Error)
}

extension WalletConnectorError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notSupportedOnPlatform(let reason):
            return "External wallet not supported on this platform: \(reason)"
        case .notSupportedInSimulator:
            return "External wallet pairing is not available in the iOS Simulator. " +
                   "Run on a physical device to test wallet connections."
        case .connectionTimeout:
            return "Wallet connection timed out. Make sure your wallet app is open and try again."
        case .signingTimeout:
            return "The wallet did not respond to the signing request in time. Try again."
        case .noActiveSession:
            return "No wallet connected. Connect a wallet before requesting a signature."
        case .malformedWalletResponse(let detail):
            return "Wallet returned an unexpected response: \(detail)"
        case .signingRejected(let reason):
            return "Signing rejected by wallet: \(reason)"
        case .reownError(let error):
            return "Wallet connection error: \(error.localizedDescription)"
        }
    }
}

// ============================================================================
// MARK: - WalletConnector
// ============================================================================

/// Protocol for an external wallet connection that can sign OZ smart-account auth entries.
///
/// This protocol is intentionally separate from the SDK's `OZExternalWalletAdapter`:
/// - `WalletConnector` speaks the demo-layer language (OZ auth entries with context rule IDs,
///   rich metadata, platform-aware errors).
/// - `OZExternalWalletAdapter` speaks the SDK's language (raw `HashIDPreimage` XDR,
///   generic `OZSignAuthEntryResult`).
///
/// `ExternalSignerManagerAdapter` bridges the two: it conforms to `OZExternalWalletAdapter`
/// and holds a reference to the active `WalletConnector`, routing signing requests to it
/// for wallet addresses while handling keypair addresses locally.
///
/// On platforms where external wallets are not supported (macOS), a `NoOpWalletConnector`
/// conforms to this protocol and returns `notSupportedOnPlatform` from all methods.
/// This keeps the shared `Sources/` code compiling on both targets without `#if os` in
/// the business layer.
///
/// Implementations must be safe to call from concurrent contexts.
public protocol WalletConnector: AnyObject, Sendable {

    /// Connects to an external wallet via WalletConnect pairing.
    ///
    /// Generates a WalletConnect URI, presents it (via QR or deep-link), and waits for
    /// the wallet to confirm the session. The session is scoped to `stellar:testnet` and
    /// the `stellar_signAuthEntry` method only.
    ///
    /// Failure modes:
    /// - `notSupportedOnPlatform` — running on macOS where Reown is not linked.
    /// - `notSupportedInSimulator` — running in the iOS Simulator.
    /// - `connectionTimeout` — wallet did not confirm within the timeout window.
    /// - `reownError` — the Reown stack raised an underlying error.
    func connect() async throws

    /// Disconnects the active wallet session and purges any persisted session state.
    ///
    /// After this call, `connectedAddress` returns `nil` and subsequent signing requests
    /// fail with `noActiveSession`. Session keys are removed from the App Group storage
    /// (not merely cleared from memory) to prevent ghost reconnections.
    func disconnect() async

    /// Requests the wallet to sign an OZ smart-account authorization entry.
    ///
    /// The adapter passes the raw `HashIDPreimage::SorobanAuthorization` XDR (base64) to
    /// the wallet as `authEntryXdr`. For Ed25519 wallets the expected response is an
    /// Ed25519 signature over `SHA-256(preimage)` encoded as a 64-byte raw signature in
    /// base64. The SDK's `OZExternalSignerManager.verifyExternalWalletSignature` performs
    /// the cryptographic recheck after the adapter returns — callers must not add a second
    /// verify layer on this path.
    ///
    /// `contextRuleIds` are forwarded to the wallet for display or audit purposes; they do
    /// not alter what the Ed25519 wallet signs. The OZ auth-digest recipe
    /// `SHA-256(signature_payload || context_rule_ids.to_xdr())` is used by the WebAuthn
    /// signer path only (inside the SDK) and does NOT flow through `WalletConnector`.
    ///
    /// Failure modes:
    /// - `noActiveSession` — no wallet is connected; call `connect()` first.
    /// - `signingTimeout` — wallet did not respond within the timeout window.
    /// - `signingRejected` — the wallet explicitly rejected the request.
    /// - `malformedWalletResponse` — the wallet returned an unparseable response.
    ///
    /// - Parameters:
    ///   - authEntryXdr: Base64-encoded `HashIDPreimage::SorobanAuthorization` XDR.
    ///   - contextRuleIds: Context rule IDs forwarded to the wallet for display/audit.
    /// - Returns: The signed auth entry and the address that produced the signature.
    func signAuthEntry(authEntryXdr: String, contextRuleIds: [UInt32]) async throws -> SignedAuthEntry

    /// The Stellar G-address of the currently connected wallet, or `nil` if not connected.
    var connectedAddress: String? { get }

    /// Metadata for the connected wallet (name, URL, icon), or `nil` if not connected.
    var walletMetadata: WalletMetadata? { get }
}
