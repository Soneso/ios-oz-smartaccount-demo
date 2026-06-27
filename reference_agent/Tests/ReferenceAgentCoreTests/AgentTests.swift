// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

/// Exercises the live-assembly path `Agent.fromConfig`: it validates the
/// config, decodes the agent seed, wires an `OZSmartAccountKit` headlessly, and
/// builds the `AgentRunner`. Construction touches no network (the kit is built
/// but not connected), so a stub coordination `URLSession` is injected and the
/// resulting wiring is asserted directly.
@Suite("Agent.fromConfig")
struct AgentTests {

    /// Builds a config that satisfies `validateForLiveRun`: a valid contract id
    /// for the smart account, a valid 64-hex Ed25519 seed, and a valid G-address
    /// destination. Network values fall back to the testnet defaults.
    private func completeConfig() throws -> AgentConfig {
        let destination = try KeyPair.generateRandomKeyPair().accountId
        return AgentConfig(
            tokenContractId: AgentDefaults.nativeTokenContract,
            amount: "5",
            smartAccountContractId: AgentDefaults.nativeTokenContract,
            agentSecretSeed: String(repeating: "01", count: 32),
            destinationAddress: destination
        )
    }

    @Test("wires a runner whose config matches the validated input")
    func wiresRunner() async throws {
        let config = try completeConfig()
        // Precondition: the config is genuinely complete, so any throw below is
        // an assembly failure rather than a validation rejection.
        #expect(config.isCompleteForLiveRun)

        let agent = try Agent.fromConfig(config, session: StubURLProtocol.makeSession())

        // The runner consumes the exact config that was validated.
        #expect(agent.runner.config == config)
        #expect(agent.runner.config.smartAccountContractId == AgentDefaults.nativeTokenContract)
        #expect(agent.runner.config.agentSecretSeed == String(repeating: "01", count: 32))

        await agent.dispose()
    }

    @Test("throws AgentConfigError for a seed that passes validation but is not ASCII hex")
    func rejectsNonAsciiHexSeed() throws {
        // 64 fullwidth-digit characters: `isHexDigit` is true for each and the
        // length is 64, so `validateForLiveRun`'s surface checks pass, but the
        // bytes are not ASCII-parseable, so `Agent.fromConfig`'s `Hex.decode`
        // guard rejects them.
        let nonAsciiSeed = String(repeating: "\u{FF11}", count: 64)
        let base = try completeConfig()
        let config = base.with(agentSecretSeed: nonAsciiSeed)

        // The surface validation that `fromConfig` runs first does accept it.
        #expect(throws: Never.self) { try config.validateForLiveRun() }

        // Assembly still rejects it when decoding the seed to bytes.
        #expect(throws: AgentConfigError.self) {
            _ = try Agent.fromConfig(config, session: StubURLProtocol.makeSession())
        }
    }

    @Test("propagates the validation failure for an incomplete config")
    func rejectsIncompleteConfig() throws {
        // No smart account contract id: `validateForLiveRun` fails, and
        // `fromConfig` surfaces that as an `AgentConfigError` before any kit
        // assembly happens.
        let config = AgentConfig(
            agentSecretSeed: String(repeating: "01", count: 32),
            destinationAddress: try KeyPair.generateRandomKeyPair().accountId
        )
        #expect(config.smartAccountContractId == nil)

        #expect(throws: AgentConfigError.self) {
            _ = try Agent.fromConfig(config, session: StubURLProtocol.makeSession())
        }
    }
}
