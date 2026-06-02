// SignerPickerSheet.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - SignerKind
// ============================================================================

/// Classification of a signer for the purposes of picker grouping and chip
/// labelling.
///
/// - `passkey`: `ExternalSigner` carrying a WebAuthn credential ID (key
///   buffer larger than a bare secp256r1 SEC1 public key).
/// - `delegated`: `DelegatedSigner` — a Stellar account that authorizes via
///   an Ed25519 secret key entered by the user, or via a connected external
///   wallet.
/// - `ed25519`: `ExternalSigner` with a bare 32-byte Ed25519 public key
///   (no embedded credential ID).
enum SignerKind {
    case passkey
    case delegated
    case ed25519

    /// Classifies a signer using `SmartAccountBuilders.getCredentialIdStringFromSigner`
    /// for passkey detection and a type check for delegated signers.
    static func of(_ signer: any SmartAccountSignerProtocol) -> SignerKind {
        if signer is DelegatedSigner { return .delegated }
        if let external = signer as? ExternalSigner {
            let credId = SmartAccountBuilders.getCredentialIdStringFromSigner(signer: external)
            return credId != nil ? .passkey : .ed25519
        }
        return .ed25519
    }
}

// ============================================================================
// MARK: - DelegatedAuthState
// ============================================================================

/// Per-row authorization state for a delegated Stellar account signer.
///
/// Tracks the row's progress through the secret-key entry flow and the
/// external-wallet pairing flow. Drives toggle-enable gating and chip / button
/// rendering inside the picker.
enum DelegatedAuthState: Equatable {

    /// No authorization has been provided yet. Toggle is disabled. Both
    /// "Enter Key" and "Connect Wallet" buttons are shown (Connect Wallet only
    /// when the platform exposes a connector).
    case none

    /// The user entered and verified an Ed25519 secret key. The secret is held
    /// in `verifiedSecrets` keyed by the signer's G-address. Toggle is enabled.
    case keypairVerified

    /// A wallet pairing attempt is in flight. Toggle is disabled and all other
    /// rows' "Connect Wallet" buttons are disabled (single-wallet invariant).
    case walletConnecting

    /// An external wallet is connected for this signer's G-address. Toggle is
    /// enabled. A "Disconnect" affordance is shown.
    case walletConnected

    /// The most recent wallet pairing attempt failed. The error caption is
    /// shown beneath the row buttons. Toggle is disabled.
    case walletError(String)
}

// ============================================================================
// MARK: - Ed25519AuthState
// ============================================================================

/// Per-row authorization state for an Ed25519 external signer.
///
/// Tracks whether the user has verified a secret key for this signer. The
/// verified secret bytes are held in the picker-local `verifiedEd25519Secrets`
/// cache. Drives toggle-enable gating and chip / button rendering inside the
/// picker.
enum Ed25519AuthState: Equatable {

    /// No secret key has been verified. Toggle is disabled. The "Enter Key"
    /// button is shown.
    case none

    /// The user entered and verified a secret key. The 32 raw secret bytes
    /// are held in the picker-local cache keyed by the signer's identity.
    /// Toggle is enabled.
    case keypairVerified
}

// ============================================================================
// MARK: - SignerPickerRow
// ============================================================================

/// View state for a single signer row inside `SignerPickerSheet`.
struct SignerPickerRow: Identifiable {

    /// Stable identity from `signer.uniqueKey`.
    var id: String { signer.uniqueKey }

    /// The smart account signer this row represents.
    let signer: any SmartAccountSignerProtocol

    /// `true` when the current user is the passkey credential connected to this signer.
    let isConnected: Bool

    /// Whether the signer is selected for inclusion in the action.
    var isSelected: Bool

    /// Per-row authorization state for delegated Stellar account signers.
    /// Always `.none` for non-delegated rows; the state machine is only meaningful
    /// for delegated rows.
    var auth: DelegatedAuthState = .none

    /// Per-row authorization state for Ed25519 external signers.
    /// Always `.none` for non-Ed25519 rows; the state machine is only meaningful
    /// for Ed25519 rows.
    var ed25519Auth: Ed25519AuthState = .none

    /// Category used for section bucketing and chip rendering.
    var kind: SignerKind { SignerKind.of(signer) }

    /// Whether the signer is a delegated Stellar account.
    var isDelegated: Bool { kind == .delegated }

    /// Whether the signer is an Ed25519 external signer (not a passkey).
    var isEd25519: Bool { kind == .ed25519 }

    /// Display name shown in the picker row.
    var displayName: String {
        switch kind {
        case .passkey:
            return "Passkey"
        case .delegated:
            if let delegated = signer as? DelegatedSigner {
                return truncateContractAddress(delegated.address)
            }
            return truncateAddress(signer.uniqueKey)
        case .ed25519:
            return signerDisplayIdentifier(for: signer)
        }
    }

    /// G-address for delegated rows; nil otherwise.
    var delegatedAddress: String? {
        (signer as? DelegatedSigner)?.address
    }

    /// Verifier address and 32-byte public key for Ed25519 rows; nil otherwise.
    var ed25519SignerIdentity: (verifierAddress: String, publicKey: Data)? {
        guard let external = signer as? ExternalSigner,
              kind == .ed25519,
              external.keyData.count == SmartAccountConstants.ed25519PublicKeySize else {
            return nil
        }
        return (verifierAddress: external.verifierAddress, publicKey: external.keyData)
    }
}

// ============================================================================
// MARK: - Ed25519SecretKey (picker-local cache key)
// ============================================================================

/// Hashable key used to store a per-row verified Ed25519 secret in the
/// picker-local `verifiedEd25519Secrets` map and to pass secrets from the
/// picker's `onConfirm` callback to the flow layer for registration.
///
/// Carries the verifier contract address and the 32-byte public key that
/// together uniquely identify an Ed25519 signer slot. Matches the two fields
/// exposed by `SignerPickerRow.ed25519SignerIdentity`.
public struct Ed25519SecretKey: Hashable, Sendable {

    /// Contract address (`C…` strkey) of the Ed25519 verifier.
    public let verifierAddress: String

    /// 32-byte Ed25519 public key identifying the signer slot.
    public let publicKey: Data

    /// Creates an `Ed25519SecretKey` for the given verifier address and public key.
    public init(verifierAddress: String, publicKey: Data) {
        self.verifierAddress = verifierAddress
        self.publicKey = publicKey
    }
}

// ============================================================================
// MARK: - SignerPickerModel
// ============================================================================

/// Observable state model that drives `SignerPickerSheet`.
///
/// Owns the row-by-row state machine for delegated signers (secret-key entry
/// and external-wallet pairing), the Ed25519 signer verification state,
/// the verified-secrets maps, and the dismissal cleanup contract. Exists as a
/// separate type so the state transitions are testable without rendering
/// SwiftUI views.
///
/// All mutating methods are `@MainActor` because consumers observe
/// `@Published` state from the main thread.
@MainActor
final class SignerPickerModel: ObservableObject {

    // -------------------------------------------------------------------------
    // MARK: - Published state
    // -------------------------------------------------------------------------

    @Published var rows: [SignerPickerRow] = []
    @Published var openSecretKeyAddress: String?
    @Published var openEd25519SignerKey: String?
    @Published var validationError: String?

    /// G-address → verified secret-key map. Populated when a delegated row
    /// transitions to `.keypairVerified`; cleared by `performDismissCleanup()`.
    private(set) var verifiedSecrets: [String: String] = [:]

    /// Per-signer cache of verified Ed25519 secret bytes (32 bytes each).
    ///
    /// Populated when an Ed25519 row transitions to `.keypairVerified`.
    /// Cleared by `performDismissCleanup()`. Registration of the secret is
    /// deferred to the flow's submission-time cleanup wrapper, so cancel cleanup
    /// requires no adapter or manager interaction here.
    private(set) var verifiedEd25519Secrets: [Ed25519SecretKey: Data] = [:]

    // -------------------------------------------------------------------------
    // MARK: - Configuration (immutable per instance)
    // -------------------------------------------------------------------------

    let availableSigners: [TransferSignerInfo]
    let connectedCredentialId: String?
    let walletConnector: (any WalletConnector)?
    let walletAvailable: Bool

    /// Whether Ed25519 signer rows are interactive.
    ///
    /// When `true`, Ed25519 rows display the "Enter Key" button and may
    /// transition to `.keypairVerified` after a valid secret is submitted.
    /// When `false` (no kit available), Ed25519 rows are non-interactive.
    let ed25519Available: Bool

    /// Set to `true` by `markConfirmed()` so `performDismissCleanup()` knows
    /// not to disconnect the wallet (the kit needs the session to sign).
    private(set) var didConfirm: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    init(
        availableSigners: [TransferSignerInfo],
        connectedCredentialId: String?,
        walletConnector: (any WalletConnector)?,
        ed25519Available: Bool = false
    ) {
        self.availableSigners = availableSigners
        self.connectedCredentialId = connectedCredentialId
        self.walletConnector = walletConnector
        self.ed25519Available = ed25519Available
        if let connector = walletConnector {
            self.walletAvailable = !(connector is NoOpWalletConnectorMarker)
        } else {
            self.walletAvailable = false
        }
        buildRows()
    }

    // -------------------------------------------------------------------------
    // MARK: - Public derived state
    // -------------------------------------------------------------------------

    /// Number of currently selected signers.
    var selectedCount: Int {
        rows.reduce(0) { $0 + ($1.isSelected ? 1 : 0) }
    }

    /// Whether any delegated row currently holds an active wallet session.
    /// Drives the single-wallet invariant: while one row is `.walletConnecting`
    /// or `.walletConnected`, other rows' Connect buttons are disabled.
    var anyWalletActive: Bool {
        rows.contains { row in
            switch row.auth {
            case .walletConnecting, .walletConnected: return true
            default: return false
            }
        }
    }

    /// Whether the toggle for the row at `index` should be enabled.
    func toggleEnabled(at index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        let row = rows[index]
        if row.isEd25519 {
            return row.ed25519Auth == .keypairVerified
        }
        if !row.isDelegated { return true }
        switch row.auth {
        case .keypairVerified, .walletConnected: return true
        default: return false
        }
    }

    /// Whether the row at `index` itself holds the active wallet (i.e. is
    /// either `.walletConnecting` or `.walletConnected`).
    func isWalletActive(at index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        switch rows[index].auth {
        case .walletConnecting, .walletConnected: return true
        default: return false
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Lifecycle
    // -------------------------------------------------------------------------

    private func buildRows() {
        rows = availableSigners.map { info in
            let isConnectedPasskey: Bool
            if let credId = connectedCredentialId {
                isConnectedPasskey = SmartAccountBuilders.signerMatchesCredentialId(
                    signer: info.signer,
                    credentialId: credId
                )
            } else {
                isConnectedPasskey = false
            }
            return SignerPickerRow(
                signer: info.signer,
                isConnected: isConnectedPasskey,
                isSelected: isConnectedPasskey
            )
        }
    }

    /// Marks the confirm path as taken so dismissal cleanup leaves the wallet
    /// session intact (the kit's adapter will sign with it).
    func markConfirmed() {
        didConfirm = true
    }

    /// Best-effort wallet disconnect + secret cleanup on dismiss-without-confirm.
    ///
    /// Clears the verified-secrets maps. Because the picker never calls
    /// `kit.externalSigners` during verification, there is
    /// nothing to undo in the adapter on a cancel path.
    func performDismissCleanup() async {
        verifiedSecrets.removeAll()
        verifiedEd25519Secrets.removeAll()
        guard !didConfirm else { return }
        await walletConnector?.disconnect()
    }

    // -------------------------------------------------------------------------
    // MARK: - Confirmation
    // -------------------------------------------------------------------------

    /// Result of `confirmSelection`: the chosen signers plus both secrets maps,
    /// or a `validationError` describing why confirmation cannot proceed.
    struct ConfirmationResult {
        let chosenSigners: [any SmartAccountSignerProtocol]
        let delegatedSecrets: [String: String]
        let ed25519Secrets: [Ed25519SecretKey: Data]
    }

    /// Validates the current selection and, when valid, builds the result that
    /// will be passed to the parent's `onConfirm` callback.
    ///
    /// Returns `nil` when validation fails; `validationError` carries the
    /// reason. On success, marks the model as confirmed so the wallet session
    /// is preserved past dismissal.
    func confirmSelection() -> ConfirmationResult? {
        let selectedRows = rows.filter { $0.isSelected }
        guard !selectedRows.isEmpty else {
            validationError = "Select at least one signer."
            return nil
        }
        for row in selectedRows where row.isDelegated {
            guard isAuthorized(row.auth) else {
                validationError = "Authorize each Stellar account signer before signing."
                return nil
            }
        }
        for row in selectedRows where row.isEd25519 {
            guard row.ed25519Auth == .keypairVerified else {
                validationError = "Verify a secret key for each Ed25519 signer before signing."
                return nil
            }
        }
        validationError = nil
        markConfirmed()
        return ConfirmationResult(
            chosenSigners: selectedRows.map { $0.signer },
            delegatedSecrets: buildDelegatedSecrets(),
            ed25519Secrets: buildEd25519Secrets()
        )
    }

    private func isAuthorized(_ state: DelegatedAuthState) -> Bool {
        switch state {
        case .keypairVerified, .walletConnected: return true
        default: return false
        }
    }

    /// Builds the keypair-verified G-address → secret map returned to callers.
    ///
    /// Wallet-backed rows are intentionally absent — the kit's wallet adapter
    /// already routes signing for those addresses through the active
    /// `WalletConnector`.
    private func buildDelegatedSecrets() -> [String: String] {
        var out: [String: String] = [:]
        for row in rows where row.isSelected && row.isDelegated && row.auth == .keypairVerified {
            if let address = row.delegatedAddress, let secret = verifiedSecrets[address] {
                out[address] = secret
            }
        }
        return out
    }

    /// Builds the verified Ed25519 secret-bytes map returned to callers.
    ///
    /// Only includes rows that are selected and in the `.keypairVerified` state.
    private func buildEd25519Secrets() -> [Ed25519SecretKey: Data] {
        var out: [Ed25519SecretKey: Data] = [:]
        for row in rows where row.isSelected && row.isEd25519 && row.ed25519Auth == .keypairVerified {
            if let identity = row.ed25519SignerIdentity {
                let key = Ed25519SecretKey(
                    verifierAddress: identity.verifierAddress,
                    publicKey: identity.publicKey
                )
                if let bytes = verifiedEd25519Secrets[key] {
                    out[key] = bytes
                }
            }
        }
        return out
    }

    // -------------------------------------------------------------------------
    // MARK: - Row transitions (secret key)
    // -------------------------------------------------------------------------

    func openSecretEntry(at index: Int) {
        guard let address = rows[index].delegatedAddress else { return }
        openSecretKeyAddress = address
    }

    func cancelSecretEntry(at index: Int) {
        guard let address = rows[index].delegatedAddress else { return }
        if openSecretKeyAddress == address {
            openSecretKeyAddress = nil
        }
    }

    func clearKey(at index: Int) {
        guard let address = rows[index].delegatedAddress else { return }
        verifiedSecrets.removeValue(forKey: address)
        rows[index].auth = .none
        rows[index].isSelected = false
    }

    /// Validates the entered secret key for the delegated row at `index`.
    ///
    /// On success transitions the row to `.keypairVerified`, stores the secret,
    /// auto-selects the row, and closes the inline form. On failure returns the
    /// human-readable error string (the row state is unchanged).
    @discardableResult
    func verifySecret(at index: Int, secret: String) -> String? {
        guard rows.indices.contains(index) else { return "Internal error." }
        guard let delegated = rows[index].signer as? DelegatedSigner else {
            return "Internal error: row is not a delegated signer."
        }
        let trimmed = secret.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Secret key is required for this signer." }
        if !trimmed.isValidEd25519SecretSeed() { return "Must be a valid Stellar secret key (S...)." }
        let derivedAddress: String
        do {
            derivedAddress = try StellarKeyPair(secretSeed: trimmed).accountId
        } catch {
            return "Invalid secret key."
        }
        guard derivedAddress == delegated.address else {
            return "Secret key does not match the signer's address."
        }
        verifiedSecrets[delegated.address] = trimmed
        rows[index].auth = .keypairVerified
        rows[index].isSelected = true
        openSecretKeyAddress = nil
        return nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Ed25519 cache key
    // -------------------------------------------------------------------------

    /// Returns the `Ed25519SecretKey` cache key for the given row, or `nil`
    /// when the row is not an Ed25519 signer or has no identity attached.
    private func ed25519CacheKey(for row: SignerPickerRow) -> Ed25519SecretKey? {
        guard let identity = row.ed25519SignerIdentity else { return nil }
        return Ed25519SecretKey(verifierAddress: identity.verifierAddress, publicKey: identity.publicKey)
    }

    // -------------------------------------------------------------------------
    // MARK: - Row transitions (Ed25519 secret key)
    // -------------------------------------------------------------------------

    /// Opens the inline secret-key form for the Ed25519 row at `index`.
    func openEd25519SecretEntry(at index: Int) {
        guard rows.indices.contains(index), rows[index].isEd25519 else { return }
        openEd25519SignerKey = rows[index].signer.uniqueKey
    }

    /// Closes the inline secret-key form for the Ed25519 row at `index`.
    func cancelEd25519SecretEntry(at index: Int) {
        guard rows.indices.contains(index), rows[index].isEd25519 else { return }
        if openEd25519SignerKey == rows[index].signer.uniqueKey {
            openEd25519SignerKey = nil
        }
    }

    /// Clears a previously verified Ed25519 secret for the row at `index`.
    ///
    /// Removes the secret bytes from the picker-local cache and returns the row
    /// to `.none`, also deselecting it. The picker never registered the keypair
    /// in the adapter, so there is nothing to undo there.
    func clearEd25519Key(at index: Int) {
        guard rows.indices.contains(index),
              let key = ed25519CacheKey(for: rows[index]) else { return }
        verifiedEd25519Secrets.removeValue(forKey: key)
        rows[index].ed25519Auth = .none
        rows[index].isSelected = false
    }

    /// Validates the entered secret key for the Ed25519 row at `index` and stores
    /// the verified secret bytes in the picker-local cache.
    ///
    /// Validation steps:
    /// 1. Must be exactly 64 hex characters (case-insensitive), representing 32 raw bytes.
    /// 2. The derived 32-byte public key must exactly match the signer's stored public key.
    ///
    /// On success, stores the 32 raw secret bytes in `verifiedEd25519Secrets`, transitions
    /// the row to `.keypairVerified`, auto-selects it, and closes the form. Registration
    /// of the secret is deferred to the flow's submission-time cleanup wrapper. On
    /// failure, returns a human-readable error string; the row state is unchanged.
    @discardableResult
    func verifyEd25519Secret(at index: Int, secret: String) async -> String? {
        guard rows.indices.contains(index) else { return "Internal error." }
        guard rows[index].isEd25519 else {
            return "Internal error: row is not an Ed25519 signer."
        }
        guard let identity = rows[index].ed25519SignerIdentity else {
            return "Internal error: could not read signer identity."
        }
        let trimmed = secret.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Secret key is required for this signer." }

        let badSecretMessage = "Secret key must be \(SmartAccountConstants.ed25519SecretSeedSize * 2) hex characters (\(SmartAccountConstants.ed25519SecretSeedSize) bytes)."
        guard let secretKeyBytes = trimmed.data(using: .hexadecimal),
              secretKeyBytes.count == SmartAccountConstants.ed25519SecretSeedSize else {
            return badSecretMessage
        }

        // Derive the public key locally for the mismatch check.
        let derivedPublicKey: Data
        do {
            derivedPublicKey = try Ed25519KeyDerivation.deriveKeypair(fromSecretBytes: secretKeyBytes).publicKey
        } catch {
            return "Invalid secret key bytes."
        }
        guard derivedPublicKey == identity.publicKey else {
            return "Secret key does not match this signer's public key."
        }

        // Store the verified secret bytes in the picker-local cache.
        guard let cacheKey = ed25519CacheKey(for: rows[index]) else {
            return "Internal error: could not build cache key."
        }
        verifiedEd25519Secrets[cacheKey] = secretKeyBytes

        rows[index].ed25519Auth = .keypairVerified
        rows[index].isSelected = true
        openEd25519SignerKey = nil
        return nil
    }

    // -------------------------------------------------------------------------
    // MARK: - Row transitions (wallet)
    // -------------------------------------------------------------------------

    /// Drives the wallet pairing flow for the row at `index`.
    ///
    /// Transitions: `.none` → `.walletConnecting` → `.walletConnected`,
    /// `.walletError`, or back to `.none` on a silent cancel.
    func connectWallet(at index: Int) async {
        guard rows.indices.contains(index) else { return }
        guard let connector = walletConnector else { return }
        guard let expectedAddress = rows[index].delegatedAddress else { return }

        rows[index].auth = .walletConnecting

        do {
            try await connector.connect()
        } catch let error as WalletConnectorError {
            rows[index].auth = .walletError(error.errorDescription ?? "Wallet connection failed.")
            return
        } catch {
            rows[index].auth = .walletError(error.localizedDescription)
            return
        }

        guard let connectedAddress = connector.connectedAddress else {
            // No session surfaced — treat as a silent cancellation.
            rows[index].auth = .none
            return
        }

        guard connectedAddress == expectedAddress else {
            await connector.disconnect()
            rows[index].auth = .walletError(
                "Connected wallet address does not match this signer. Disconnected."
            )
            return
        }

        rows[index].auth = .walletConnected
        rows[index].isSelected = true
    }

    /// Tears down the active wallet session and returns the row to `.none`.
    func disconnectWallet(at index: Int) async {
        guard rows.indices.contains(index) else { return }
        await walletConnector?.disconnect()
        rows[index].auth = .none
        rows[index].isSelected = false
    }
}

// ============================================================================
// MARK: - SignerPickerSheet
// ============================================================================

/// Modal sheet for selecting which signers co-authorize a multi-signer action.
///
/// Per-row authorization state machines are documented on `DelegatedAuthState`
/// and `Ed25519AuthState`; passkey rows are a single auto-selectable toggle.
///
/// Return contract: `onConfirm` is called with:
/// - the list of chosen signers,
/// - a `[String: String]` map of G-address → secret key for keypair-verified
///   delegated rows (wallet-backed rows are absent), and
/// - a `[Ed25519SecretKey: Data]` map of raw secret bytes for verified Ed25519 rows.
/// The flow layer registers both maps into the respective adapters before calling
/// the SDK.
///
/// Wallet lifecycle: a connected wallet is preserved across the confirm path
/// so the kit can sign with it. On dismiss-without-confirm (Cancel, drag-down,
/// or the toolbar close), any active wallet session is disconnected on a
/// best-effort basis and the verified-secrets map is cleared.
///
/// Shared between iOS and macOS. SwiftUI primitives only. On macOS or when no
/// connector is supplied, the "Connect Wallet" button is hidden entirely and
/// only the "Enter Key" path is available for delegated rows.
public struct SignerPickerSheet: View {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let description: String
    private let confirmLabel: String
    private let walletConnectLabel: String
    private let onCancel: () -> Void
    private let onConfirm: ([any SmartAccountSignerProtocol], [String: String], [Ed25519SecretKey: Data]) -> Void

    // -------------------------------------------------------------------------
    // MARK: - State model
    // -------------------------------------------------------------------------

    @StateObject private var model: SignerPickerModel

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a `SignerPickerSheet`.
    ///
    /// - Parameters:
    ///   - availableSigners: Signers to display in the list.
    ///   - connectedCredentialId: Active credential ID used to mark the matching
    ///     passkey row with the `"Active"` badge.
    ///   - walletConnector: Active platform wallet connector. Pass `nil` or a
    ///     `NoOpWalletConnector` to hide the wallet pairing affordance.
    ///   - ed25519Available: Whether Ed25519 signer rows display the "Enter Key"
    ///     button. Pass `true` when the kit is initialised (Ed25519 signing is
    ///     available via `kit.externalSigners`). Verified secrets are stored in
    ///     the picker's local cache.
    ///   - description: Instructional text shown at the top of the sheet.
    ///   - confirmLabel: Label for the confirm toolbar button. Defaults to `"Sign Transfer"`.
    ///   - walletConnectLabel: Label for the wallet pairing button. Defaults to `"Connect Wallet"`.
    ///   - onCancel: Dismiss action.
    ///   - onConfirm: Confirm action with chosen signers, keypair-verified delegated secrets map,
    ///     and verified Ed25519 secret bytes map (keyed by `Ed25519SecretKey`).
    public init(
        availableSigners: [TransferSignerInfo],
        connectedCredentialId: String?,
        walletConnector: (any WalletConnector)?,
        ed25519Available: Bool = false,
        description: String,
        confirmLabel: String = "Sign Transfer",
        walletConnectLabel: String = "Connect Wallet",
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([any SmartAccountSignerProtocol], [String: String], [Ed25519SecretKey: Data]) -> Void
    ) {
        self.description = description
        self.confirmLabel = confirmLabel
        self.walletConnectLabel = walletConnectLabel
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _model = StateObject(wrappedValue: SignerPickerModel(
            availableSigners: availableSigners,
            connectedCredentialId: connectedCredentialId,
            walletConnector: walletConnector,
            ed25519Available: ed25519Available
        ))
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        NavigationStack {
            listContainer
                .navigationTitle("Select Signers")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: handleCancel)
                            .accessibilityLabel("Cancel signer selection")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmButtonTitle) {
                            handleConfirm()
                        }
                        .fontWeight(.semibold)
                        .disabled(model.selectedCount == 0)
                        .accessibilityLabel(confirmButtonTitle)
                        .accessibilityHint("Confirms signer selection and initiates the action.")
                    }
                }
        }
        #if os(macOS)
        // macOS sheets size to their content's ideal height, and a List reports
        // a near-zero ideal height, which collapses the signer list. Give the
        // sheet a concrete size so the rows and description render.
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 640)
        #endif
        .onDisappear {
            // Runs for every dismissal path. The model itself knows whether
            // the confirm callback was taken; on the confirm path the wallet
            // session is preserved, on every other path it is disconnected.
            let snapshot = model
            Task { await snapshot.performDismissCleanup() }
        }
        .onChange(of: model.validationError) { _, newError in
            guard let error = newError else { return }
            postAccessibilityAnnouncement(error)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Subviews
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var listContainer: some View {
        #if os(iOS)
        List {
            sectionContents
        }
        .listStyle(.insetGrouped)
        #elseif os(macOS)
        List {
            sectionContents
        }
        .listStyle(.automatic)
        #else
        List {
            sectionContents
        }
        #endif
    }

    @ViewBuilder
    private var sectionContents: some View {
        descriptionSection

        if model.rows.isEmpty {
            emptySection
        } else {
            signerSection(title: "Passkey Signers", kind: .passkey)
            signerSection(title: "Stellar Account Signers", kind: .delegated)
            signerSection(title: "Ed25519 Signers", kind: .ed25519)
        }

        if let error = model.validationError {
            Section {
                InlineErrorText(error)
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            Text(description)
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private var confirmButtonTitle: String {
        "\(confirmLabel) (\(model.selectedCount) selected)"
    }

    /// Whether Ed25519 interactive key entry is available.
    ///
    /// True when Ed25519 signing is available (`kit.externalSigners` is ready);
    /// false otherwise (e.g. test paths that construct the picker without a kit).
    private var ed25519SignerAvailable: Bool {
        model.ed25519Available
    }

    /// Placeholder text for the Ed25519 secret-key input field.
    private var ed25519InputPlaceholder: String {
        "Enter secret key (\(SmartAccountConstants.ed25519SecretSeedSize * 2) hex characters)"
    }

    @ViewBuilder
    private func signerSection(title: String, kind: SignerKind) -> some View {
        let filtered = model.rows.enumerated().filter { $0.element.kind == kind }
        if !filtered.isEmpty {
            Section {
                ForEach(filtered, id: \.element.id) { index, _ in
                    SignerRowView(
                        row: $model.rows[index],
                        walletAvailable: model.walletAvailable,
                        walletConnectLabel: walletConnectLabel,
                        anyOtherWalletActive: model.anyWalletActive && !model.isWalletActive(at: index),
                        toggleEnabled: model.toggleEnabled(at: index),
                        openSecretKeyAddress: $model.openSecretKeyAddress,
                        openEd25519SignerKey: $model.openEd25519SignerKey,
                        ed25519SignerManagerAvailable: ed25519SignerAvailable,
                        ed25519KeyPlaceholder: ed25519InputPlaceholder,
                        onEnterKeyTap: { model.openSecretEntry(at: index) },
                        onVerifySecret: { secret in await runVerify(at: index, secret: secret) },
                        onCancelSecretEntry: { model.cancelSecretEntry(at: index) },
                        onConnectWallet: { await model.connectWallet(at: index) },
                        onDisconnectWallet: { await model.disconnectWallet(at: index) },
                        onClearKey: { model.clearKey(at: index) },
                        onEnterEd25519KeyTap: { model.openEd25519SecretEntry(at: index) },
                        onVerifyEd25519Secret: { secret in await runVerifyEd25519(at: index, secret: secret) },
                        onCancelEd25519SecretEntry: { model.cancelEd25519SecretEntry(at: index) },
                        onClearEd25519Key: { model.clearEd25519Key(at: index) }
                    )
                }
            } header: {
                Text(title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView(
                "No Signers Available",
                systemImage: "person.crop.circle.badge.xmark",
                description: Text("No signers are available for the selected context.")
            )
            .symbolRenderingMode(.hierarchical)
        }
        .listRowBackground(Color.clear)
    }

    // -------------------------------------------------------------------------
    // MARK: - Actions
    // -------------------------------------------------------------------------

    private func handleCancel() {
        onCancel()
    }

    private func handleConfirm() {
        guard let result = model.confirmSelection() else { return }
        onConfirm(result.chosenSigners, result.delegatedSecrets, result.ed25519Secrets)
    }

    /// Bridges the inline form's `String?`-returning verify callback to the
    /// model's synchronous delegated-signer validator. Yields once to keep the
    /// call awaitable for callers that may want to add async validation later
    /// without an API change.
    private func runVerify(at index: Int, secret: String) async -> String? {
        await Task.yield()
        return model.verifySecret(at: index, secret: secret)
    }

    /// Bridges the inline form's `String?`-returning verify callback to the
    /// model's Ed25519 validator. Yields once before invoking the model so the
    /// UI can breathe before the crypto work starts, matching `runVerify`.
    private func runVerifyEd25519(at index: Int, secret: String) async -> String? {
        await Task.yield()
        return await model.verifyEd25519Secret(at: index, secret: secret)
    }
}

// ============================================================================
// MARK: - SignerRowView
// ============================================================================

/// A single row inside `SignerPickerSheet` for one signer.
///
/// Renders the toggle, identity, type chip, and — for delegated signers — the
/// state-driven button row, error caption, and inline secret-key form.
/// Ed25519 rows render an "Enter Key" button and the shared `SecretKeyInputForm`
/// when no signing source is registered, mirroring the delegated-signer UX.
private struct SignerRowView: View {

    @Binding var row: SignerPickerRow

    let walletAvailable: Bool
    let walletConnectLabel: String
    let anyOtherWalletActive: Bool
    let toggleEnabled: Bool

    @Binding var openSecretKeyAddress: String?
    @Binding var openEd25519SignerKey: String?

    /// Whether the `ExternalSignerManager` or an adapter is wired; gates Ed25519 key entry.
    let ed25519SignerManagerAvailable: Bool

    /// Placeholder text shown in the Ed25519 secret-key input field.
    let ed25519KeyPlaceholder: String

    // Delegated signer callbacks
    let onEnterKeyTap: () -> Void
    let onVerifySecret: (String) async -> String?
    let onCancelSecretEntry: () -> Void
    let onConnectWallet: () async -> Void
    let onDisconnectWallet: () async -> Void
    let onClearKey: () -> Void

    // Ed25519 signer callbacks
    let onEnterEd25519KeyTap: () -> Void
    let onVerifyEd25519Secret: (String) async -> String?
    let onCancelEd25519SecretEntry: () -> Void
    let onClearEd25519Key: () -> Void

    private var isSecretFormOpen: Bool {
        guard let address = row.delegatedAddress else { return false }
        return openSecretKeyAddress == address
    }

    private var isEd25519FormOpen: Bool {
        guard row.isEd25519 else { return false }
        return openEd25519SignerKey == row.signer.uniqueKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $row.isSelected) {
                rowLabel
            }
            .toggleStyle(.checkmark)
            .disabled(!toggleEnabled)

            if row.isDelegated {
                delegatedAuthSection
            }

            if row.isEd25519 && ed25519SignerManagerAvailable {
                ed25519AuthSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var rowBackground: Color {
        let selectedTinted = row.isSelected && toggleEnabled
        return selectedTinted ? Color.accentColor.opacity(0.12) : Color.cardBackground
    }

    @ViewBuilder
    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.displayName)
                    .font(Typography.secondary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if row.kind == .passkey && row.isConnected {
                    chip(label: "Active", style: .success)
                        .accessibilityLabel("Active passkey")
                }

                if row.isDelegated, case .keypairVerified = row.auth {
                    chip(label: "Verified", style: .success)
                        .accessibilityLabel("Secret key verified")
                }

                if row.isDelegated, case .walletConnected = row.auth {
                    chip(label: "Wallet", style: .info)
                        .accessibilityLabel("Wallet connected")
                }

                if row.isEd25519 && row.ed25519Auth == .keypairVerified {
                    chip(label: "Verified", style: .success)
                        .accessibilityLabel("Signing key verified")
                }

                Spacer(minLength: 0)

                switch row.kind {
                case .passkey:
                    chip(label: "WebAuthn", style: .neutral)
                case .ed25519:
                    chip(label: "Ed25519", style: .neutral)
                case .delegated:
                    EmptyView()
                }
            }

            if row.isDelegated {
                Text(delegatedSubtitle)
                    .font(Typography.caption2)
                    .foregroundStyle(Color.brandOnSurfaceVariant)
            }

            if row.isEd25519 && ed25519SignerManagerAvailable {
                Text(ed25519Subtitle)
                    .font(Typography.caption2)
                    .foregroundStyle(Color.brandOnSurfaceVariant)
            }
        }
    }

    private var delegatedSubtitle: String {
        switch row.auth {
        case .none, .walletError:
            return "Enter secret key or connect wallet to enable signing"
        case .keypairVerified:
            return "Ready to sign"
        case .walletConnecting:
            return "Connecting to wallet…"
        case .walletConnected:
            return "Wallet — Ready to sign"
        }
    }

    private var ed25519Subtitle: String {
        switch row.ed25519Auth {
        case .none:
            return "Enter secret key to enable signing"
        case .keypairVerified:
            return "Ready to sign"
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Delegated auth section (buttons / form / error)
    // -------------------------------------------------------------------------

    @ViewBuilder
    private var delegatedAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch row.auth {
            case .none:
                actionButtons(isConnecting: false)
            case .keypairVerified:
                clearKeyButton
            case .walletConnecting:
                actionButtons(isConnecting: true)
            case .walletConnected:
                disconnectButton
            case .walletError(let message):
                actionButtons(isConnecting: false)
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Color.semanticError)
                    .accessibilityLabel("Wallet error: \(message)")
            }

            if isSecretFormOpen {
                SecretKeyInputForm(
                    placeholder: "S... secret key",
                    onVerify: onVerifySecret,
                    onCancel: onCancelSecretEntry
                )
            }
        }
        .padding(.leading, 32)
    }

    // -------------------------------------------------------------------------
    // MARK: - Ed25519 auth section (button / form)
    // -------------------------------------------------------------------------

    /// Auth section rendered beneath Ed25519 signer rows when the SDK's
    /// `ExternalSignerManager` is wired.
    ///
    /// Shows an "Enter Key" button when no secret has been verified, and
    /// a "Clear key" button once the keypair is verified. The inline form
    /// is the same `SecretKeyInputForm` used by the delegated-signer path.
    @ViewBuilder
    private var ed25519AuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch row.ed25519Auth {
            case .none:
                ed25519EnterKeyButton
            case .keypairVerified:
                clearEd25519KeyButton
            }

            if isEd25519FormOpen {
                SecretKeyInputForm(
                    placeholder: ed25519KeyPlaceholder,
                    onVerify: onVerifyEd25519Secret,
                    onCancel: onCancelEd25519SecretEntry
                )
            }
        }
        .padding(.leading, 32)
    }

    private var ed25519EnterKeyButton: some View {
        Button(action: onEnterEd25519KeyTap) {
            Label("Enter Key", systemImage: "key")
                .font(Typography.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isEd25519FormOpen)
        .accessibilityLabel("Enter secret key for Ed25519 signer")
    }

    private var clearEd25519KeyButton: some View {
        Button(action: onClearEd25519Key) {
            Text("Clear key")
                .font(Typography.caption)
                .foregroundStyle(Color.brandOnSurfaceVariant)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Ed25519 signing key")
    }

    // -------------------------------------------------------------------------
    // MARK: - Delegated auth action buttons
    // -------------------------------------------------------------------------

    @ViewBuilder
    private func actionButtons(isConnecting: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            enterKeyButton(disabled: isConnecting)

            if walletAvailable {
                if isConnecting {
                    connectingButton
                } else {
                    connectWalletButton
                }
            }
        }
    }

    private func enterKeyButton(disabled: Bool) -> some View {
        Button(action: onEnterKeyTap) {
            Label("Enter Key", systemImage: "key")
                .font(Typography.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled || isSecretFormOpen)
        .accessibilityLabel("Enter secret key")
    }

    private var connectWalletButton: some View {
        Button {
            Task { await onConnectWallet() }
        } label: {
            Label(walletConnectLabel, systemImage: "link.circle")
                .font(Typography.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(anyOtherWalletActive)
        .accessibilityLabel(walletConnectLabel)
    }

    private var connectingButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting…")
                    .font(Typography.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
        .accessibilityLabel("Connecting to wallet")
    }

    private var disconnectButton: some View {
        Button {
            Task { await onDisconnectWallet() }
        } label: {
            Text("Disconnect")
                .font(Typography.caption)
                .foregroundStyle(Color.semanticError)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Disconnect wallet")
    }

    private var clearKeyButton: some View {
        Button(action: onClearKey) {
            Text("Clear key")
                .font(Typography.caption)
                .foregroundStyle(Color.brandOnSurfaceVariant)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear secret key")
    }

    // -------------------------------------------------------------------------
    // MARK: - Chip
    // -------------------------------------------------------------------------

    private enum ChipStyle {
        case success
        case info
        case neutral
    }

    @ViewBuilder
    private func chip(label: String, style: ChipStyle) -> some View {
        let (foreground, background): (Color, Color) = {
            switch style {
            case .success:
                return (.white, .activityLogSuccess)
            case .info:
                return (.white, Color.blue)
            case .neutral:
                return (.secondary, Color.secondary.opacity(0.15))
            }
        }()
        Text(label)
            .font(Typography.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// ============================================================================
// MARK: - SecretKeyInputForm
// ============================================================================

/// Inline secret-key entry form shown beneath a delegated or Ed25519 row when
/// the user taps "Enter Key". Holds the entered value and inline error caption
/// in local state so it is automatically discarded when the form closes.
private struct SecretKeyInputForm: View {

    let placeholder: String
    let onVerify: (String) async -> String?
    let onCancel: () -> Void

    @State private var secret: String = ""
    @State private var showSecret: Bool = false
    @State private var error: String?
    @State private var isValidating: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Group {
                    if showSecret {
                        TextField(placeholder, text: $secret)
                    } else {
                        SecureField(placeholder, text: $secret)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .padding(8)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            error != nil ? Color.semanticError : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

                Button {
                    showSecret.toggle()
                } label: {
                    Image(systemName: showSecret ? "eye.slash" : "eye")
                        .foregroundStyle(Color.brandOnSurfaceVariant)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showSecret ? "Hide secret key" : "Show secret key")
            }

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isValidating)

                Button {
                    Task { await runVerify() }
                } label: {
                    HStack(spacing: 4) {
                        if isValidating {
                            ProgressView().controlSize(.mini)
                        }
                        Text(isValidating ? "Verifying…" : "Verify")
                    }
                    .font(Typography.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isValidating || secret.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color.semanticError)
                    .accessibilityLabel("Error: \(error)")
            }

            Text("The secret key is held in memory for this signing session only.")
                .font(Typography.caption2)
                .foregroundStyle(Color.brandOnSurfaceVariant)
        }
    }

    private func runVerify() async {
        isValidating = true
        error = nil
        let result = await onVerify(secret)
        isValidating = false
        if let result {
            error = result
        }
    }
}

// ============================================================================
// MARK: - Checkmark toggle style
// ============================================================================

private struct CheckmarkToggleStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                .font(Typography.title3)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityHidden(true)

            configuration.label
                .contentShape(Rectangle())
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

private extension ToggleStyle where Self == CheckmarkToggleStyle {
    static var checkmark: CheckmarkToggleStyle { CheckmarkToggleStyle() }
}

// ============================================================================
// MARK: - NoOpWalletConnectorMarker
// ============================================================================

/// Marker conformance used by the picker model to detect the macOS no-op
/// connector without referencing the platform-specific type from shared code.
///
/// The macOS `NoOpWalletConnector` adopts this marker so the picker can hide
/// the "Connect Wallet" button on macOS without `#if os(macOS)` in the shared
/// surface. iOS handlers do not adopt the marker.
public protocol NoOpWalletConnectorMarker: WalletConnector {}
