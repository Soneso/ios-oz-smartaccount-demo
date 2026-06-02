// FlowTypeAliases.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import stellarsdk

// ============================================================================
// MARK: - FlowTypeAliases
// ============================================================================
//
// Typedef re-exports for SDK types that pass through the flow layer unchanged.
// Components that only need to name these types use these aliases and can omit
// a per-file `import stellarsdk`, because both the alias definitions and the
// component files compile into the same module (SmartAccountDemoLib /
// SmartAccountDemoMacLib). The module links stellarsdk transitively.
//
// These aliases are exact type synonyms — they preserve Sendable / Hashable /
// Equatable conformances of the underlying type and are fully compatible with
// code that uses the SDK type names directly.

/// On-chain context rule as parsed from Soroban storage.
///
/// Re-exported so read-only consumers (`ContextRuleCard`, `KnownSignersScreenCore`)
/// can reference the type without a per-file `import stellarsdk`.
public typealias ParsedContextRuleInfo = ParsedContextRule

/// Static builder helpers for signer identity, key derivation, and equality.
///
/// Components use `SmartAccountBuilders` in place of `OZSmartAccountBuilders`
/// to avoid a direct `import stellarsdk`. All existing static call sites compile
/// unchanged via the alias.
public typealias SmartAccountBuilders = OZSmartAccountBuilders

/// OZ smart-account operational constants (max signers, max policies, etc.).
///
/// Re-exported so components referencing `OZConstants.maxSigners` or
/// `OZConstants.maxPolicies` can use `OZSmartAccountConstants` without a
/// per-file SDK import. Named with the `OZ` prefix to avoid shadowing the
/// SDK's own `SmartAccountConstants` type (which holds different fields).
public typealias OZSmartAccountConstants = OZConstants

/// Delegated signer type (a Stellar `G…` account address).
///
/// Re-exported so components that only inspect a delegated signer's `address`
/// field but do not construct one can reference the type without importing the SDK.
public typealias DelegatedSigner = OZDelegatedSigner

/// The signer protocol common to all OZ smart-account signer variants.
///
/// Re-exported as a protocol alias so components that work with `[any OZSmartAccountSigner]`
/// lists — but do not construct signer instances — can use
/// `[any SmartAccountSignerProtocol]` without a per-file `import stellarsdk`.
public typealias SmartAccountSignerProtocol = OZSmartAccountSigner

/// Stellar protocol constants (ledgers per hour/day, stroops per XLM, etc.).
///
/// Re-exported so components that reference ledger-duration math can use
/// `StellarProtocol` without a per-file `import stellarsdk`.
public typealias StellarProtocol = StellarProtocolConstants

/// A resolved signer entry passed to multi-signer submission pipelines.
///
/// Re-exported so submission pipeline helpers in the component layer can
/// reference `[SelectedSigner]` return types without a per-file SDK import.
public typealias SelectedSignerEntry = SelectedSigner

/// Context rule type discriminant (default, call-contract, create-contract).
///
/// Re-exported so the builder submission pipeline can reference `ContextRuleType`
/// without a per-file SDK import.
public typealias ContextRuleType = stellarsdk.ContextRuleType

/// OZ smart-account byte-size constants (Ed25519 seed/pubkey, secp256r1 pubkey).
///
/// Re-exported as an exact type synonym so components that size-check `keyData`
/// or validate secret-key byte lengths can use `SmartAccountConstants` without
/// a per-file SDK import. Note: the OZ operational-limit constants (max signers,
/// max policies) live on the separate `OZConstants` type, aliased as
/// `OZSmartAccountConstants`.
public typealias SmartAccountConstants = stellarsdk.SmartAccountConstants

/// External signer type (passkey, Ed25519 key, or any OZ verifier-contract signer).
///
/// Re-exported so components that classify or read external signers — the picker,
/// the registration row UI — can reference the type without a per-file SDK import.
public typealias ExternalSigner = OZExternalSigner

/// Stellar keypair type wrapping an Ed25519 seed and its derived account ID.
///
/// Re-exported so components that derive a G-address from a Stellar secret seed
/// (e.g., delegated-signer secret verification) can use `StellarKeyPair` without
/// a per-file SDK import.
public typealias StellarKeyPair = KeyPair

/// Encoded Soroban value (`SCVal`) used for policy install parameters and
/// weighted-threshold signer encoding.
///
/// Re-exported so policy form components can reference `SCValXDR` in staged-
/// policy storage and builder call sites without a per-file SDK import.
public typealias ScVal = SCValXDR

/// SDK wallet-layer exception base class.
///
/// Re-exported so components that throw `WalletException.NotConnected` can do
/// so without a per-file SDK import.
public typealias WalletError = WalletException
