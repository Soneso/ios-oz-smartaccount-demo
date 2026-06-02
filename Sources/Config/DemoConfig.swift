// DemoConfig.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - DemoConfig
// ============================================================================

/// All compile-time constants for the Smart Account Demo.
///
/// Values reference the shared testnet infrastructure. The network is testnet
/// only; no mainnet support is provided or intended by this demo. Any field
/// whose value must change (e.g. after a testnet reset) is annotated with the
/// expected update procedure.
///
/// SECURITY: This file is committed to a private repository. The Reown project
/// ID and on-chain addresses are not secrets — they are testnet-only values
/// with no monetary risk. Demo token admin keys are publicly derivable by
/// design (see DemoTokenService).
public enum DemoConfig {

    // -------------------------------------------------------------------------
    // MARK: Network
    // -------------------------------------------------------------------------

    /// Soroban RPC endpoint for testnet. All SDK operations target this endpoint.
    public static let rpcURL = "https://soroban-testnet.stellar.org"

    /// Stellar testnet network passphrase.
    ///
    /// Used for transaction signing, XDR encoding, and contract address derivation.
    /// Never use the mainnet passphrase with this demo.
    public static let networkPassphrase = "Test SDF Network ; September 2015"

    // -------------------------------------------------------------------------
    // MARK: Smart Account Contract
    // -------------------------------------------------------------------------

    /// WASM hash of the multisig smart account contract (OZ stellar-contracts).
    ///
    /// Passed to OZSmartAccountConfig.accountWasmHash for wallet deployment.
    /// Update after a testnet reset or contract upgrade. The hash is a 64-character
    /// lowercase hex string representing the SHA-256 digest of the on-chain WASM binary.
    public static let accountWasmHash = "86b49fe03f7df0ad1c2a28bd8361b923ab57096e09f397f92f0c00ae3bd06d28"

    // -------------------------------------------------------------------------
    // MARK: Verifier Contracts
    // -------------------------------------------------------------------------

    /// WebAuthn (secp256r1) signature verifier contract address.
    ///
    /// Validates passkey (WebAuthn / FIDO2) signatures on-chain. Registered as
    /// the verifier for ExternalSigner entries that carry a COSE P-256 public key.
    public static let webauthnVerifierAddress = "CB26VN37RCVNTHJZDEPK6IRO2MMTS3Z2IEO5JD5BINY2OOJ5KKJG7NKY"

    /// Ed25519 signature verifier contract address.
    ///
    /// Validates Ed25519 keypair signatures on-chain. Registered as the verifier
    /// for ExternalSigner entries backed by a raw 32-byte Ed25519 public key.
    public static let ed25519VerifierAddress = "CAW2Z46INPO5VIJEILMYSSEOLBVJIIII5GOE3TN5EUURSRM2FJCF7AJ6"

    // -------------------------------------------------------------------------
    // MARK: Token Contracts
    // -------------------------------------------------------------------------

    /// XLM native token Stellar Asset Contract (SAC) address on testnet.
    ///
    /// Used for XLM balance reads and transfer invocations via the SAC token interface.
    /// This address is stable for the lifetime of the current testnet network epoch.
    public static let nativeTokenContract = "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"

    // -------------------------------------------------------------------------
    // MARK: Demo Token
    // -------------------------------------------------------------------------
    // DemoTokenService deploys a custom Soroban token for testing transfers.
    // The contract address is derived deterministically from the seeds below,
    // the admin public key, and the network passphrase — the same address is
    // produced on every platform, enabling cross-demo interoperability on testnet.
    //
    // SECURITY: The admin keypair is publicly derivable (seed is in source).
    // This is intentional — the demo is testnet-only and the admin key has no
    // monetary value. README documents this explicitly.

    /// Seed string for deriving the DEMO token admin keypair via SHA-256.
    ///
    /// The admin account deploys the token contract and holds permanent mint authority.
    /// This value deliberately differs from other demo apps to avoid contract collisions.
    public static let demoTokenAdminSeed = "soneso smart account demo token admin v1"

    /// Seed string for deriving the deployment salt via SHA-256.
    ///
    /// Combined with the admin public key, network passphrase, and this salt,
    /// the token contract address is deterministic and collision-free across runs.
    public static let demoTokenSaltSeed = "soneso smart account demo token v1"

    /// Display name passed to the token contract constructor.
    public static let demoTokenName = "Demo Token"

    /// Ticker symbol passed to the token contract constructor.
    public static let demoTokenSymbol = "DEMO"

    /// Decimal places for the demo token (7 = same as XLM; 10_000_000 units = 1 token).
    public static let demoTokenDecimals: Int32 = 7

    /// Amount minted per wallet: 10_000 DEMO expressed in the token's smallest unit.
    ///
    /// With 7 decimals: 100_000_000_000 / 10^7 = 10_000 DEMO.
    public static let demoTokenMintAmount: Int64 = 100_000_000_000

    // -------------------------------------------------------------------------
    // MARK: Relayer
    // -------------------------------------------------------------------------

    /// Fee-sponsoring relayer URL.
    ///
    /// The relayer wraps transactions in a fee-bump envelope so wallets without
    /// XLM can pay operation fees. This endpoint is the Soneso-operated proxy.
    ///
    /// Empty string disables the relayer: the kit is constructed with
    /// `relayerUrl: nil` and the SDK submits transactions directly via the
    /// Soroban RPC endpoint, so the connected wallet pays its own fees. Set to
    /// `""` to test the RPC-only submission path.
    public static let defaultRelayerURL = "https://smart-account-relayer-proxy.soneso.workers.dev"

    // -------------------------------------------------------------------------
    // MARK: Indexer
    // -------------------------------------------------------------------------

    /// Credential-to-contract address indexer URL.
    ///
    /// Maps a passkey credential ID to its deployed smart account contract address.
    /// Used by WalletConnectionFlow to resolve a credential to a contract without
    /// requiring the user to paste a C-address manually.
    ///
    /// Empty string disables the indexer: the kit is constructed with
    /// `indexerUrl: nil` and credential-to-contract lookup falls back to the
    /// on-chain scan path.
    public static let defaultIndexerURL = "https://smart-account-indexer.sdf-ecosystem.workers.dev"

    // -------------------------------------------------------------------------
    // MARK: WebAuthn / Passkey
    // -------------------------------------------------------------------------

    /// Relying Party identifier for passkey registration and authentication.
    ///
    /// Must match the domain in the app's Associated Domains entitlement and the
    /// domain serving .well-known/apple-app-site-association. The `?mode=developer`
    /// suffix is present in the entitlements files for debug builds only; the
    /// build-time gate (post-build script) prevents Release builds from shipping
    /// that suffix.
    public static let defaultRpId = "soneso.com"

    /// Display name shown to users during passkey registration prompts.
    ///
    /// Appears in the system passkey sheet alongside the RP identifier.
    public static let rpName = "Smart Account Kit Demo"

    // -------------------------------------------------------------------------
    // MARK: Reown (WalletConnect)
    // -------------------------------------------------------------------------

    /// Reown (WalletConnect) project ID for external wallet pairing.
    ///
    /// A project ID is required for external-wallet connect. Register a free one
    /// at https://cloud.reown.com and set it here. When this value is empty, the
    /// external-wallet connector is not installed and the "Connect Wallet" UI is
    /// hidden — the demo's passkey and keypair signer flows are unaffected.
    public static let reownProjectId = ""

    // -------------------------------------------------------------------------
    // MARK: Context Rule Discovery
    // -------------------------------------------------------------------------

    /// Maximum context rule ID to scan when iterating on-chain rules.
    ///
    /// The smart account contract assigns monotonically increasing IDs and
    /// leaves gaps when rules are removed. This cap prevents unbounded iteration
    /// if the on-chain active-rule count diverges from the enumerated IDs.
    public static let maxContextRuleScanId: UInt32 = 25
}

// ============================================================================
// MARK: - PolicyInfo
// ============================================================================

/// Descriptor for a known policy contract deployed on testnet.
///
/// Used to populate the policy picker in the Context Rule Builder screen.
/// The `type` field is the policy's canonical machine identifier as defined
/// by the OZ smart account contract interface.
public struct PolicyInfo: Sendable {

    /// Machine-readable policy type identifier (e.g. `"threshold"`).
    public let type: String

    /// Human-readable policy name shown in the UI.
    public let name: String

    /// One-sentence description of what the policy enforces.
    public let description: String

    /// On-chain contract address (C-address) of the deployed policy contract.
    public let address: String

    public init(type: String, name: String, description: String, address: String) {
        self.type = type
        self.name = name
        self.description = description
        self.address = address
    }
}

// ============================================================================
// MARK: - Known Policies
// ============================================================================

/// Policy contracts deployed on testnet and usable in the demo.
///
/// Each entry describes a different enforcement model. The addresses below are
/// stable for the current testnet network epoch; update after a network reset.
public let knownPolicies: [PolicyInfo] = [
    PolicyInfo(
        type: "threshold",
        name: "Threshold (M-of-N)",
        description: "Requires M signatures out of N total signers",
        address: "CAZJ3UVRY3R3S5C5BH32GMYBRSN23N75ZEEXEOLXOUUAHDFIMVP4AXUC"
    ),
    PolicyInfo(
        type: "spending_limit",
        name: "Spending Limit",
        description: "Limits spending to a maximum amount per time period",
        address: "CBQE7L3UNP5IR4I7IBKLS7NV256WHR5TTH26HTMUIK7WXJC6J64RSE2L"
    ),
    PolicyInfo(
        type: "weighted_threshold",
        name: "Weighted Threshold",
        description: "Requires minimum total weight from signers with different voting weights",
        address: "CAF4OCRIB73T5777UWAQS7KGOG6WVIZ3EFXNNUYSPFSBKW2Q5XEIOSPW"
    )
]
