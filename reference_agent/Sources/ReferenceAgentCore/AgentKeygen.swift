// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.
//
// AGENT BOOTSTRAP (print-key / keygen mode).
//
// Lets an operator obtain the agent's Ed25519 public key — and a fresh secret
// seed when none exists yet — before a full live configuration is available.
// The public key is rendered as raw 64-character hex and pasted into the demo's
// "Delegate to agent" screen, which registers it as the Ed25519 external signer
// the agent then signs with. The seed is copied into the agent config
// (AGENT_SECRET_SEED).

import Foundation
import stellarsdk

/// Number of hex characters in a raw 32-byte Ed25519 value (public key or seed).
public let agentHexKeyLength = 64

/// Outcome of resolving the agent's signing identity for the print-key mode.
public struct AgentKeyResult: Sendable, Equatable {

    /// The agent's raw 32-byte Ed25519 public key as 64-character lowercase hex.
    public let publicKeyHex: String

    /// Whether the key was newly generated (`true`) or derived from a supplied
    /// seed (`false`).
    public let generated: Bool

    /// The raw 32-byte secret seed as 64-character lowercase hex, to copy into
    /// the agent config (`AGENT_SECRET_SEED`). Non-nil only when [generated] is
    /// `true`: a seed supplied by the operator is never echoed back, since they
    /// already hold it.
    public let secretSeedHex: String?

    public init(publicKeyHex: String, generated: Bool, secretSeedHex: String? = nil) {
        self.publicKeyHex = publicKeyHex
        self.generated = generated
        self.secretSeedHex = secretSeedHex
    }
}

/// Resolves the agent's identity for the print-key bootstrap mode.
///
/// When [seed] is a non-empty, valid 64-character hex seed, derives and returns
/// its public key hex; `AgentKeyResult.generated` is `false` and
/// `AgentKeyResult.secretSeedHex` is `nil` (the operator already holds the seed,
/// so it is not echoed). Otherwise generates a fresh Ed25519 keypair from a
/// cryptographically secure 32-byte seed and returns both the new seed hex and
/// its public key hex.
///
/// Throws `AgentConfigError` when [seed] is non-empty but malformed.
public func resolveAgentKey(seed: String? = nil) throws -> AgentKeyResult {
    if let seed, !seed.isEmpty {
        let normalized = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidHexSeed(normalized), let bytes = Hex.decode(normalized.lowercased()) else {
            throw AgentConfigError(
                "AGENT_SECRET_SEED is set but is not a valid 64-character hex Ed25519 seed."
            )
        }
        let keypair = KeyPair(seed: try Seed(bytes: bytes))
        return AgentKeyResult(publicKeyHex: publicKeyHex(keypair), generated: false)
    }
    let seedBytes = generateSeedBytes()
    let keypair = KeyPair(seed: try Seed(bytes: seedBytes))
    return AgentKeyResult(
        publicKeyHex: publicKeyHex(keypair),
        generated: true,
        secretSeedHex: Hex.encode(seedBytes)
    )
}

/// Formats [result] into operator-facing console lines.
///
/// For a generated key both the seed (to copy into `AGENT_SECRET_SEED`) and the
/// public key hex (to paste into the demo's Delegate-to-agent screen) are shown.
/// For a supplied seed only the derived public key hex is shown — the secret is
/// never printed.
public func formatAgentKeyOutput(_ result: AgentKeyResult) -> [String] {
    if result.generated {
        return [
            "Generated a new agent Ed25519 keypair.",
            "AGENT_SECRET_SEED (copy into the agent config, keep secret): "
                + "\(result.secretSeedHex ?? "")",
            "Agent public key (paste into Delegate-to-agent): \(result.publicKeyHex)",
        ]
    }
    return [
        "Derived the agent public key from AGENT_SECRET_SEED.",
        "Agent public key (paste into Delegate-to-agent): \(result.publicKeyHex)",
    ]
}

/// Whether the print-key bootstrap mode is requested, via [env]
/// (`AGENT_PRINT_KEY=true`, case-insensitive) or [args] (`--print-key`).
public func shouldPrintAgentKey(
    env: [String: String] = [:],
    args: [String] = []
) -> Bool {
    let fromEnv = (env["AGENT_PRINT_KEY"] ?? "").lowercased() == "true"
    let fromArgs = args.contains("--print-key")
    return fromEnv || fromArgs
}

/// The keypair's raw 32-byte public key as 64-character lowercase hex.
private func publicKeyHex(_ keypair: KeyPair) -> String {
    Hex.encode(keypair.publicKey.bytes)
}

/// Whether [value] is exactly 64 hex characters (a raw 32-byte seed).
private func isValidHexSeed(_ value: String) -> Bool {
    value.count == agentHexKeyLength && Hex.isHexString(value)
}

/// Generates a cryptographically secure raw 32-byte Ed25519 seed.
private func generateSeedBytes() -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    var seed = [UInt8]()
    seed.reserveCapacity(32)
    for _ in 0..<32 {
        seed.append(UInt8.random(in: UInt8.min...UInt8.max, using: &generator))
    }
    return seed
}
