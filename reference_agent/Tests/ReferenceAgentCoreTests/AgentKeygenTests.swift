// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

/// Matches a raw 32-byte value rendered as 64-character lowercase hex.
private func isHex64(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
}

/// Derives the raw 32-byte public key hex for a 64-hex seed, independently of
/// the keygen under test, to confirm the keygen reports the right public key.
private func derivePublicKeyHex(seedHex: String) throws -> String {
    let bytes = try #require(Hex.decode(seedHex.lowercased()))
    let keypair = KeyPair(seed: try Seed(bytes: bytes))
    return Hex.encode(keypair.publicKey.bytes)
}

@Suite("resolveAgentKey")
struct ResolveAgentKeyTests {

    @Test("generates a fresh keypair as 64-hex public key + 64-hex seed")
    func generatesFresh() throws {
        let result = try resolveAgentKey()
        #expect(result.generated)
        let seedHex = try #require(result.secretSeedHex)
        #expect(isHex64(seedHex))
        #expect(isHex64(result.publicKeyHex))
        // The reported public key is the one derived from the generated seed.
        #expect(try derivePublicKeyHex(seedHex: seedHex) == result.publicKeyHex)
    }

    @Test("derives the hex public key from a supplied seed and does not echo it")
    func derivesFromSeed() throws {
        let seedHex = try #require(try resolveAgentKey().secretSeedHex)
        let result = try resolveAgentKey(seed: seedHex)
        #expect(result.generated == false)
        #expect(result.secretSeedHex == nil)
        #expect(isHex64(result.publicKeyHex))
        #expect(try derivePublicKeyHex(seedHex: seedHex) == result.publicKeyHex)
    }

    @Test("accepts an upper-case hex seed and derives the same public key")
    func acceptsUpperCase() throws {
        let seedHex = try #require(try resolveAgentKey().secretSeedHex)
        let lower = try resolveAgentKey(seed: seedHex)
        let upper = try resolveAgentKey(seed: seedHex.uppercased())
        #expect(upper.publicKeyHex == lower.publicKeyHex)
    }

    @Test("treats an empty seed as generate-a-fresh-key")
    func emptySeedGenerates() throws {
        let result = try resolveAgentKey(seed: "")
        #expect(result.generated)
        let seedHex = try #require(result.secretSeedHex)
        #expect(isHex64(seedHex))
    }

    @Test("rejects a non-hex seed")
    func rejectsNonHex() {
        #expect(throws: AgentConfigError.self) {
            try resolveAgentKey(seed: "not-a-seed")
        }
    }

    @Test("rejects a wrong-length hex seed")
    func rejectsWrongLength() {
        #expect(throws: AgentConfigError.self) {
            try resolveAgentKey(seed: "abcd")
        }
        #expect(throws: AgentConfigError.self) {
            try resolveAgentKey(seed: String(repeating: "a", count: 62))
        }
    }

    @Test("two generated seeds differ")
    func generatedSeedsDiffer() throws {
        let a = try #require(try resolveAgentKey().secretSeedHex)
        let b = try #require(try resolveAgentKey().secretSeedHex)
        #expect(a != b)
    }
}

@Suite("formatAgentKeyOutput")
struct FormatAgentKeyOutputTests {

    @Test("a generated key prints the hex seed and the hex public key")
    func generatedOutput() throws {
        let result = try resolveAgentKey()
        let seedHex = try #require(result.secretSeedHex)
        let out = formatAgentKeyOutput(result).joined(separator: "\n")
        #expect(out.contains(seedHex))
        #expect(out.contains(result.publicKeyHex))
        #expect(out.contains("Delegate-to-agent"))
    }

    @Test("a supplied seed prints only the hex public key, never the secret")
    func suppliedSeedOutput() throws {
        let seedHex = try #require(try resolveAgentKey().secretSeedHex)
        let result = try resolveAgentKey(seed: seedHex)
        let out = formatAgentKeyOutput(result).joined(separator: "\n")
        #expect(out.contains(result.publicKeyHex))
        #expect(!out.contains(seedHex))
    }
}

@Suite("shouldPrintAgentKey")
struct ShouldPrintAgentKeyTests {

    @Test("honors AGENT_PRINT_KEY=true case-insensitively")
    func honorsEnv() {
        #expect(shouldPrintAgentKey(env: ["AGENT_PRINT_KEY": "true"]))
        #expect(shouldPrintAgentKey(env: ["AGENT_PRINT_KEY": "TRUE"]))
    }

    @Test("honors the --print-key argument")
    func honorsArg() {
        #expect(shouldPrintAgentKey(args: ["--print-key"]))
    }

    @Test("is false without either trigger")
    func falseWithoutTrigger() {
        #expect(shouldPrintAgentKey() == false)
        #expect(shouldPrintAgentKey(env: ["AGENT_PRINT_KEY": "false"]) == false)
    }
}
