// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

@Suite("AgentEd25519SignerAdapter")
struct AgentEd25519SignerAdapterTests {

    @Test("kit constructs headlessly with in-memory storage and the Ed25519 adapter")
    func kitConstructsHeadlessly() async throws {
        let adapter = AgentEd25519SignerAdapter()
        let config = try OZSmartAccountConfig(
            rpcUrl: AgentDefaults.rpcUrl,
            networkPassphrase: AgentDefaults.networkPassphrase,
            accountWasmHash: AgentDefaults.accountWasmHash,
            webauthnVerifierAddress: AgentDefaults.webauthnVerifierAddress,
            relayerUrl: AgentDefaults.relayerUrl,
            storage: OZInMemoryStorageAdapter(),
            externalEd25519Adapter: adapter
        )

        let kit = OZSmartAccountKit.create(config: config)

        // The kit is constructed but not connected (no passkey, no session).
        #expect(kit.isConnected == false)
        #expect(kit.contractId == nil)

        // The adapter is wired in and registers/clears the agent keypair.
        let keypair = try KeyPair.generateRandomKeyPair()
        try adapter.add(verifierAddress: AgentDefaults.ed25519VerifierAddress, keypair: keypair)
        #expect(adapter.canSignFor(
            verifierAddress: AgentDefaults.ed25519VerifierAddress,
            publicKey: Data(keypair.publicKey.bytes)
        ))
        adapter.clearAll()
        #expect(adapter.canSignFor(
            verifierAddress: AgentDefaults.ed25519VerifierAddress,
            publicKey: Data(keypair.publicKey.bytes)
        ) == false)

        await kit.close()
    }

    @Test("signs the auth digest with the registered key")
    func signsAuthDigest() async throws {
        let adapter = AgentEd25519SignerAdapter()
        let keypair = try KeyPair.generateRandomKeyPair()
        try adapter.add(verifierAddress: AgentDefaults.ed25519VerifierAddress, keypair: keypair)

        let digest = Data((0..<32).map { UInt8($0) })
        let signature = try await adapter.signAuthDigest(
            authDigest: digest,
            publicKey: Data(keypair.publicKey.bytes)
        )

        #expect(signature.count == 64)
        // The signature verifies against the registered public key.
        #expect(try keypair.verify(signature: [UInt8](signature), message: [UInt8](digest)))
    }

    @Test("rejects a public-only keypair")
    func rejectsPublicOnlyKeypair() throws {
        let adapter = AgentEd25519SignerAdapter()
        let publicOnly = try KeyPair(accountId: try KeyPair.generateRandomKeyPair().accountId)
        #expect(throws: AgentSignerKeyError.self) {
            try adapter.add(verifierAddress: AgentDefaults.ed25519VerifierAddress, keypair: publicOnly)
        }
    }

    @Test("signAuthDigest throws when no keypair is registered for the public key")
    func signThrowsForUnknownKey() async throws {
        let adapter = AgentEd25519SignerAdapter()
        let registered = try KeyPair.generateRandomKeyPair()
        try adapter.add(verifierAddress: AgentDefaults.ed25519VerifierAddress, keypair: registered)

        let unknown = try KeyPair.generateRandomKeyPair()
        await #expect(throws: AgentSignerError.self) {
            try await adapter.signAuthDigest(
                authDigest: Data(repeating: 0, count: 32),
                publicKey: Data(unknown.publicKey.bytes)
            )
        }
    }
}
