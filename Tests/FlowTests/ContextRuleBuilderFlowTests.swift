// ContextRuleBuilderFlowTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import stellarsdk
import Testing

// ============================================================================
// MARK: - resolveAbsoluteLedger tests
// ============================================================================

@Suite("ContextRuleFlow: resolveAbsoluteLedger")
struct ResolveAbsoluteLedgerTests {

    @Test("Adds offset to current ledger when source is bound")
    @MainActor
    func resolveAbsoluteLedger_returnsCurrentPlusOffset() async throws {
        let made = BuilderFixtures.makeFlow()
        made.ledger.nextSequence = 1_000_000
        let result = try await made.flow.resolveAbsoluteLedger(offset: 720)
        #expect(result == 1_000_720)
        #expect(made.ledger.callCount == 1)
    }

    @Test("Returns nil when no ledger source is bound")
    @MainActor
    func resolveAbsoluteLedger_noSource_returnsNil() async throws {
        let st = ContextRuleFixtures.connectedState()
        DemoExternalSignersTestSupport.install(into: st)
        let flow = ContextRuleFlow(
            demoState: st,
            activityLog: ActivityLogState(),
            contextRuleManager: MockContextRuleManagerWithAdd(),
            ledgerSource: nil
        )
        let result = try await flow.resolveAbsoluteLedger(offset: 720)
        #expect(result == nil)
    }

    @Test("Propagates RPC failure as latestLedgerFetchFailed")
    @MainActor
    func resolveAbsoluteLedger_rpcFails_throws() async throws {
        let made = BuilderFixtures.makeFlow()
        made.ledger.error = MockContextRuleNetworkError(detail: "rpc down")
        await #expect(throws: (any Error).self) {
            _ = try await made.flow.resolveAbsoluteLedger(offset: 100)
        }
    }
}

// ============================================================================
// MARK: - registerPasskeySigner tests
// ============================================================================

@Suite("ContextRuleFlow: registerPasskeySigner")
struct RegisterPasskeySignerTests {

    @Test("Returns webAuthn external signer with configured verifier")
    @MainActor
    func registerPasskey_success_returnsExternalSigner() async throws {
        let made = BuilderFixtures.makeFlow()
        let signer = try await made.flow.registerPasskeySigner(name: "Recovery Key")
        let external = try #require(signer as? OZExternalSigner)
        #expect(external.verifierAddress == BuilderFixtures.webauthnVerifier)
        #expect(made.provider.registerCallCount == 1)
        #expect(made.provider.lastUserName == "Recovery Key")
    }

    @Test("Throws WebAuthnException.Cancelled when provider cancels")
    @MainActor
    func registerPasskey_cancel_throwsCancelled() async throws {
        let made = BuilderFixtures.makeFlow()
        made.provider.registrationError = WebAuthnException.Cancelled()
        await #expect(throws: WebAuthnException.Cancelled.self) {
            _ = try await made.flow.registerPasskeySigner(name: "X")
        }
    }

    @Test("Throws webAuthnProviderUnavailable when provider is nil")
    @MainActor
    func registerPasskey_noProvider_throws() async throws {
        let st = ContextRuleFixtures.connectedState()
        DemoExternalSignersTestSupport.install(into: st)
        let flow = ContextRuleFlow(
            demoState: st,
            activityLog: ActivityLogState(),
            contextRuleManager: MockContextRuleManagerWithAdd(),
            webAuthnProvider: nil,
            webAuthnVerifierAddress: nil
        )
        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await flow.registerPasskeySigner(name: "X")
        }
    }
}

// ============================================================================
// MARK: - loadAvailablePasskeySigners tests
// ============================================================================

@Suite("ContextRuleFlow: loadAvailablePasskeySigners")
struct LoadAvailablePasskeySignersTests {

    @Test("Returns passkeys from all rules, deduped, excluding the connected credential")
    @MainActor
    func loadPasskeys_filtersAndDedupes() async throws {
        let made = BuilderFixtures.makeFlow()
        let connected = BuilderFixtures.passkeySigner(credId: "passkeyConnected")
        let other = BuilderFixtures.passkeySigner(credId: "passkeyOther")
        let otherDuplicate = BuilderFixtures.passkeySigner(credId: "passkeyOther")
        made.manager.listResult = [
            OZParsedContextRule(
                id: 1,
                contextType: .defaultRule,
                name: "r1",
                signers: [connected, other],
                signerIds: [0, 1],
                policies: [],
                policyIds: [],
                validUntil: nil
            ),
            OZParsedContextRule(
                id: 2,
                contextType: .defaultRule,
                name: "r2",
                signers: [otherDuplicate],
                signerIds: [0],
                policies: [],
                policyIds: [],
                validUntil: nil
            )
        ]
        let connectedCredString = OZSmartAccountBuilders
            .getCredentialIdStringFromSigner(signer: connected)
        let result = await made.flow.loadAvailablePasskeySigners(
            excludeCredentialId: connectedCredString
        )
        #expect(result.count == 1)
        let credString = OZSmartAccountBuilders
            .getCredentialIdStringFromSigner(signer: result[0])
        #expect(credString != connectedCredString)
    }

    @Test("Returns empty list on list failure")
    @MainActor
    func loadPasskeys_listFails_returnsEmpty() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.listError = MockContextRuleNetworkError(detail: "RPC down")
        let result = await made.flow.loadAvailablePasskeySigners(excludeCredentialId: nil)
        #expect(result.isEmpty)
    }

    @Test("Returns empty list when not connected")
    @MainActor
    func loadPasskeys_notConnected_returnsEmpty() async throws {
        let st = ContextRuleFixtures.disconnectedState()
        let made = BuilderFixtures.makeFlow(state: st)
        let result = await made.flow.loadAvailablePasskeySigners(excludeCredentialId: nil)
        #expect(result.isEmpty)
    }

    @Test("Filters out non-WebAuthn external signers")
    @MainActor
    func loadPasskeys_excludesNonWebAuthn() async throws {
        let made = BuilderFixtures.makeFlow()
        let passkey = BuilderFixtures.passkeySigner(credId: "pkey")
        let ed25519 = try OZExternalSigner.ed25519(
            verifierAddress: ContextRuleFixtures.verifier,
            publicKey: Data(repeating: 1, count: 32)
        )
        made.manager.listResult = [
            OZParsedContextRule(
                id: 1,
                contextType: .defaultRule,
                name: "r",
                signers: [passkey, ed25519],
                signerIds: [0, 1],
                policies: [],
                policyIds: [],
                validUntil: nil
            )
        ]
        let result = await made.flow.loadAvailablePasskeySigners(excludeCredentialId: nil)
        #expect(result.count == 1)
        let external = try #require(result[0] as? OZExternalSigner)
        #expect(external.verifierAddress == BuilderFixtures.webauthnVerifier)
    }
}

// ============================================================================
// MARK: - addContextRule tests
// ============================================================================

@Suite("ContextRuleFlow: addContextRule")
struct AddContextRuleTests {

    @Test("Happy path with single passkey signer, default rule, no expiry, no policies")
    @MainActor
    func addContextRule_happyPath() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        let result = try await made.flow.addContextRule(
            contextType: .defaultRule,
            name: "DefaultRule",
            validUntil: nil,
            signers: [passkey],
            policies: [],
            selectedSigners: [],
            delegatedSecrets: [:]
        )
        #expect(result.success)
        #expect(result.hash == ContextRuleFixtures.txHash)
        #expect(made.manager.addCallCount == 1)
        #expect(made.manager.lastAddName == "DefaultRule")
        #expect(made.manager.lastAddValidUntil == nil)
        #expect(made.manager.lastAddSigners.count == 1)
        #expect(made.manager.lastAddPolicies.isEmpty)
        #expect(made.manager.lastAddSelectedSigners.isEmpty)
    }

    @Test("Forwards validUntil")
    @MainActor
    func addContextRule_validUntilForwarded() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        _ = try await made.flow.addContextRule(
            contextType: .defaultRule,
            name: "Expires",
            validUntil: 12_345,
            signers: [passkey],
            policies: [],
            selectedSigners: [],
            delegatedSecrets: [:]
        )
        #expect(made.manager.lastAddValidUntil == 12_345)
    }

    @Test("Skips policy entries without SCVal params")
    @MainActor
    func addContextRule_skipsPoliciesWithoutScVal() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        let threshold = try #require(knownPolicies.first { $0.type == "threshold" })
        let stagedEmpty = FlowPolicyEntry(address: threshold.address, scVal: nil)
        let stagedReal = FlowPolicyEntry(
            address: threshold.address,
            scVal: PolicyScValBuilders.buildSimpleThresholdScVal(threshold: 1)
        )
        _ = try await made.flow.addContextRule(
            contextType: .defaultRule,
            name: "Mixed",
            validUntil: nil,
            signers: [passkey],
            policies: [stagedEmpty, stagedReal],
            selectedSigners: [],
            delegatedSecrets: [:]
        )
        #expect(made.manager.lastAddPolicies.count == 1)
        #expect(made.manager.lastAddPolicies[threshold.address] != nil)
    }

    @Test("Multi-signer path registers delegated keypairs and forwards OZSelectedSigner list")
    @MainActor
    func addContextRule_multiSigner_registersKeypairs() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        let delegated = ContextRuleFixtures.makeDelegatedSigner()
        let kp = try KeyPair.generateRandomKeyPair()
        let secret = try #require(kp.secretSeed)
        let delegatedKp = try OZDelegatedSigner(address: kp.accountId)

        // The delegated keypair must be registered on the real manager while the
        // SDK add call runs; capture that live state from the manager hook.
        let signers = made.signers
        made.manager.onAddContextRule = {
            await signers.canSignFor(address: kp.accountId)
        }

        _ = try await made.flow.addContextRule(
            contextType: .defaultRule,
            name: "Multi",
            validUntil: nil,
            signers: [passkey, delegated],
            policies: [],
            selectedSigners: [passkey, delegatedKp],
            delegatedSecrets: [kp.accountId: secret]
        )
        #expect(made.manager.lastCanSignDuringAdd == true)
        #expect(made.manager.lastAddSelectedSigners.count == 2)
        // Cleared after success — nothing retained across screens.
        #expect(await made.signers.getAll().isEmpty)
    }

    @Test("Throws SmartAccountWalletException.NotConnected when not connected")
    @MainActor
    func addContextRule_notConnected_throws() async throws {
        let st = ContextRuleFixtures.disconnectedState()
        let made = BuilderFixtures.makeFlow(state: st)
        let passkey = BuilderFixtures.passkeySigner()
        await #expect(throws: SmartAccountWalletException.NotConnected.self) {
            _ = try await made.flow.addContextRule(
                contextType: .defaultRule,
                name: "X",
                validUntil: nil,
                signers: [passkey],
                policies: [],
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        }
    }

    @Test("SDK non-success returns failure ContextRuleResult with redacted error")
    @MainActor
    func addContextRule_sdkNonSuccess_returnsFailure() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.failedTx(error: "Insufficient fee")
        let passkey = BuilderFixtures.passkeySigner()
        let result = try await made.flow.addContextRule(
            contextType: .defaultRule,
            name: "Boom",
            validUntil: nil,
            signers: [passkey],
            policies: [],
            selectedSigners: [],
            delegatedSecrets: [:]
        )
        #expect(!result.success)
        #expect(result.hash == nil)
        #expect(result.error == "Insufficient fee")
    }

    @Test("Atomic-commit-or-abort: delegated registration failure clears prior state")
    @MainActor
    func addContextRule_atomicAbortOnRegistrationFailure() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        let kp = try KeyPair.generateRandomKeyPair()
        let delegated = try OZDelegatedSigner(address: kp.accountId)
        // An invalid secret key makes the real manager's addFromSecret throw, so
        // registration aborts before the SDK add call.
        let invalidSecret = "SNOTAVALIDSECRETKEYATALL000000000000000000000000000000000"
        do {
            _ = try await made.flow.addContextRule(
                contextType: .defaultRule,
                name: "Bad",
                validUntil: nil,
                signers: [passkey, delegated],
                policies: [],
                selectedSigners: [passkey, delegated],
                delegatedSecrets: [kp.accountId: invalidSecret]
            )
            Issue.record("expected addContextRule to throw")
        } catch {
            // The SDK add call was never reached and nothing leaked.
            #expect(made.manager.addCallCount == 0)
            #expect(await made.signers.getAll().isEmpty)
        }
    }

    @Test("Rejects unsupported signer kinds via selected list")
    @MainActor
    func addContextRule_unsupportedSelectedSigner_throws() async throws {
        let made = BuilderFixtures.makeFlow()
        made.manager.addResult = BuilderFixtures.successTx()
        let passkey = BuilderFixtures.passkeySigner()
        let unsupported = UnsupportedTestSigner()
        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.addContextRule(
                contextType: .defaultRule,
                name: "X",
                validUntil: nil,
                signers: [passkey],
                policies: [],
                selectedSigners: [unsupported],
                delegatedSecrets: [:]
            )
        }
    }
}
