// SignerManagementSection.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import SwiftUI

// ============================================================================
// MARK: - SignerAddMode
// ============================================================================

/// Options exposed in the "Signer Type" dropdown of the add-signer form.
public enum SignerAddMode: String, CaseIterable, Sendable {

    /// Delegated Stellar account (G-address) using native `require_auth`.
    case delegated

    /// Raw Ed25519 public key authorized via the configured Ed25519 verifier.
    case ed25519

    /// Passkey (WebAuthn / secp256r1) authorized via the configured WebAuthn
    /// verifier.
    case passkey

    /// Short label used in the segmented picker.
    public var shortLabel: String {
        switch self {
        case .delegated: return "Delegated"
        case .ed25519:   return "Ed25519"
        case .passkey:   return "Passkey"
        }
    }

    /// Human-readable label shown in the dropdown header.
    public var displayName: String {
        switch self {
        case .delegated: return "Delegated (G-address)"
        case .ed25519:   return "Ed25519 Public Key"
        case .passkey:   return "Passkey (WebAuthn)"
        }
    }

    /// One-sentence sub-label shown below the option in the dropdown menu.
    public var description: String {
        switch self {
        case .delegated: return "Stellar account using native require_auth verification"
        case .ed25519:   return "Ed25519 key verified by an external verifier contract"
        case .passkey:   return "Passkey verified by the WebAuthn verifier contract"
        }
    }
}

// ============================================================================
// MARK: - SignerManagementSection
// ============================================================================

/// Form sub-section that owns the "Signers" portion of the context rule
/// builder. Produces grouped `Section` blocks suitable to be placed inside a
/// parent `Form`. All staged state is owned by the parent
/// (`ContextRuleBuilderCore`) and passed in as bindings so a single
/// authoritative state machine drives both this section and the policy
/// section's per-signer weight rows.
///
/// Edit mode (`isEditing == true`) renders an extra footer line, the
/// `(on-chain)` badges on original entries, the `You` label on the connected
/// wallet's passkey, and an immediate "Available signers" list (no `Reuse
/// Signer` button — the parent supplies the list directly via
/// `existingSigners`).
public struct SignerManagementSection: View {

    // -------------------------------------------------------------------------
    // MARK: - Environment
    // -------------------------------------------------------------------------

    @EnvironmentObject internal var activityLog: ActivityLogState

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    internal let connectedCredentialId: String?
    internal let ed25519VerifierAddress: String
    internal let flow: ContextRuleFlow
    internal let isSubmitting: Bool
    internal let isEditing: Bool
    internal let existingSigners: [any SmartAccountSignerProtocol]
    internal let signerEntries: [EditSignerEntry]
    internal let onAddEntry: ((EditSignerEntry) -> Void)?
    internal let onRemoveEntry: ((Int) -> Void)?
    /// Active wallet connector, used by the delegated-signer form to offer an
    /// "Import from Wallet" affordance that auto-fills the G-address from a
    /// freshly paired wallet. `nil` on simulator (`#if !targetEnvironment(simulator)`
    /// excludes Reown) and on macOS (`NoOpWalletConnector` is supplied by the
    /// macOS app shell); the import button is hidden in both cases.
    internal let walletConnector: (any WalletConnector)?

    @Binding internal var fieldErrors: [String: String]
    @Binding internal var signers: [any SmartAccountSignerProtocol]
    @Binding internal var signerWeights: [String: String]

    // -------------------------------------------------------------------------
    // MARK: - Local state
    // -------------------------------------------------------------------------

    @State internal var addMode: SignerAddMode = .delegated
    @State internal var delegatedAddress: String = ""
    @State internal var ed25519PubKeyHex: String = ""
    @State internal var availablePasskeys: [any SmartAccountSignerProtocol] = []
    @State internal var passkeysLoaded: Bool = false
    @State internal var isLoadingPasskeys: Bool = false
    @State internal var newPasskeyName: String = ""
    @State internal var isRegistering: Bool = false
    @State internal var isImportingFromWallet: Bool = false

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    public init(
        signers: Binding<[any SmartAccountSignerProtocol]>,
        signerWeights: Binding<[String: String]>,
        fieldErrors: Binding<[String: String]>,
        isSubmitting: Bool,
        flow: ContextRuleFlow,
        connectedCredentialId: String?,
        ed25519VerifierAddress: String,
        isEditing: Bool = false,
        existingSigners: [any SmartAccountSignerProtocol] = [],
        signerEntries: [EditSignerEntry] = [],
        onAddEntry: ((EditSignerEntry) -> Void)? = nil,
        onRemoveEntry: ((Int) -> Void)? = nil,
        walletConnector: (any WalletConnector)? = nil
    ) {
        self._signers = signers
        self._signerWeights = signerWeights
        self._fieldErrors = fieldErrors
        self.isSubmitting = isSubmitting
        self.flow = flow
        self.connectedCredentialId = connectedCredentialId
        self.ed25519VerifierAddress = ed25519VerifierAddress
        self.isEditing = isEditing
        self.existingSigners = existingSigners
        self.signerEntries = signerEntries
        self.onAddEntry = onAddEntry
        self.onRemoveEntry = onRemoveEntry
        self.walletConnector = walletConnector
    }

    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------

    public var body: some View {
        Group {
            currentSignersSection
            if !isSubmitting {
                addSignerSection
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Add signer section
    // -------------------------------------------------------------------------

    private var addSignerSection: some View {
        Section {
            modePicker
            switch addMode {
            case .delegated: delegatedForm
            case .ed25519:   ed25519Form
            case .passkey:   passkeyContent
            }
        } header: {
            Text("Add Signer")
                .font(Typography.sectionHeader)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var modePicker: some View {
        Picker("Signer Type", selection: $addMode) {
            Text("Delegated").tag(SignerAddMode.delegated)
            Text("Ed25519").tag(SignerAddMode.ed25519)
            Text("Passkey").tag(SignerAddMode.passkey)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Signer Type")
    }

    // -------------------------------------------------------------------------
    // MARK: - Validation helpers
    // -------------------------------------------------------------------------

    /// Returns a user-facing error string when `candidate` cannot be added to
    /// the staged signer list (limit reached or duplicate); otherwise `nil`.
    internal func validateAdd(_ candidate: any SmartAccountSignerProtocol) -> String? {
        if signers.count >= OZSmartAccountConstants.maxSigners {
            return "Maximum \(OZSmartAccountConstants.maxSigners) signers allowed"
        }
        if signers.contains(where: { SmartAccountBuilders.signersEqual($0, candidate) }) {
            return "This signer is already added"
        }
        return nil
    }

    /// Writes `message` to `fieldErrors[key]`. Centralised so call sites stay
    /// uniform with the parent's clear-on-change pattern.
    internal func setError(_ key: String, _ message: String) {
        fieldErrors[key] = message
    }
}
