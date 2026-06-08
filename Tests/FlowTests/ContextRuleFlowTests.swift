// ContextRuleFlowTests.swift
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
// MARK: - List happy path
// ============================================================================

@Suite("ContextRuleFlow: List Rules")
struct ContextRuleFlowListTests {

    @Test("List returns rules sorted by ID ascending")
    @MainActor
    func listContextRules_sortedByID() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listResult = [
            ContextRuleFixtures.defaultRule(id: 3, name: "c"),
            ContextRuleFixtures.defaultRule(id: 1, name: "a"),
            ContextRuleFixtures.callContractRule(id: 2, name: "b")
        ]

        let result = try await made.flow.listContextRules()

        #expect(result.count == 3)
        #expect(result[0].id == 1)
        #expect(result[1].id == 2)
        #expect(result[2].id == 3)
        #expect(made.manager.listCallCount == 1)
    }

    @Test("List logs rule count on success")
    @MainActor
    func listContextRules_logsCount() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listResult = [
            ContextRuleFixtures.defaultRule(id: 1),
            ContextRuleFixtures.callContractRule(id: 2)
        ]

        _ = try await made.flow.listContextRules()

        #expect(made.log.entries.contains { $0.message.contains("2 context rules") })
    }

    @Test("List propagates SDK error")
    @MainActor
    func listContextRules_sdkThrows_propagates() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listError = MockContextRuleNetworkError(detail: "RPC timeout")

        await #expect(throws: MockContextRuleNetworkError.self) {
            _ = try await made.flow.listContextRules()
        }
    }

    @Test("List when not connected throws NotConnected")
    @MainActor
    func listContextRules_notConnected_throws() async throws {
        let made = ContextRuleFixtures.makeFlow(state: ContextRuleFixtures.disconnectedState())

        await #expect(throws: (any Error).self) {
            _ = try await made.flow.listContextRules()
        }
        #expect(made.manager.listCallCount == 0)
    }
}

// ============================================================================
// MARK: - Remove happy path
// ============================================================================

@Suite("ContextRuleFlow: Remove Rule")
struct ContextRuleFlowRemoveTests {

    @Test("Remove succeeds with multiple rules, returns hash")
    @MainActor
    func removeContextRule_multipleRules_succeeds() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeResult = ContextRuleFixtures.successResult()

        let hash = try await made.flow.removeContextRule(
            ruleId: 1,
            ruleName: "default",
            totalRuleCount: 2,
            selectedSigners: [],
            delegatedSecrets: [:]
        )

        #expect(hash == ContextRuleFixtures.txHash)
        #expect(made.manager.removeCallCount == 1)
        #expect(made.manager.lastRemovedRuleId == 1)
    }

    @Test("Remove logs transaction hash on success")
    @MainActor
    func removeContextRule_successLogsHash() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeResult = ContextRuleFixtures.successResult(hash: "abcd1234efgh5678")

        _ = try await made.flow.removeContextRule(
            ruleId: 2,
            ruleName: "rule-2",
            totalRuleCount: 3,
            selectedSigners: [],
            delegatedSecrets: [:]
        )

        #expect(made.log.entries.contains { $0.message.contains("Rule #2 removed") })
    }

    @Test("Remove last rule throws cannotRemoveLastRule without calling SDK")
    @MainActor
    func removeContextRule_lastRule_throws() async throws {
        let made = ContextRuleFixtures.makeFlow()

        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "only-rule",
                totalRuleCount: 1,
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        }
        #expect(made.manager.removeCallCount == 0)
    }

    @Test("Remove propagates SDK error")
    @MainActor
    func removeContextRule_sdkThrows_propagates() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeError = MockContextRuleNetworkError(detail: "submission failed")

        await #expect(throws: MockContextRuleNetworkError.self) {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "r",
                totalRuleCount: 2,
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        }
    }

    @Test("Remove SDK non-success throws removeFailed")
    @MainActor
    func removeContextRule_sdkNonSuccess_throwsRemoveFailed() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeResult = ContextRuleFixtures.failedResult(error: "out of fee")

        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "r",
                totalRuleCount: 2,
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        }
    }

    @Test("Remove empty name uses Unnamed Rule in log")
    @MainActor
    func removeContextRule_emptyName_logsUnnamed() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeResult = ContextRuleFixtures.successResult()

        _ = try await made.flow.removeContextRule(
            ruleId: 5,
            ruleName: "",
            totalRuleCount: 2,
            selectedSigners: [],
            delegatedSecrets: [:]
        )

        #expect(made.log.entries.contains { $0.message.contains("Unnamed Rule") })
    }

    @Test("Remove after previous error resets guard and allows retry")
    @MainActor
    func removeContextRule_guardResetsAfterError() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeError = MockContextRuleNetworkError(detail: "simulated")

        // First call throws
        do {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "rule",
                totalRuleCount: 2,
                selectedSigners: [],
                delegatedSecrets: [:]
            )
        } catch { /* expected */ }

        // Guard resets — second call succeeds
        made.manager.removeError = nil
        made.manager.removeResult = ContextRuleFixtures.successResult()
        let hash = try await made.flow.removeContextRule(
            ruleId: 2,
            ruleName: "rule-2",
            totalRuleCount: 2,
            selectedSigners: [],
            delegatedSecrets: [:]
        )
        #expect(hash == ContextRuleFixtures.txHash)
    }

    @Test("Remove with unsupported signer kind throws unsupportedSignerKind")
    @MainActor
    func removeContextRule_unsupportedSignerKind_throws() async throws {
        let made = ContextRuleFixtures.makeFlow()
        let unsupported = UnsupportedTestSigner()

        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "rule",
                totalRuleCount: 2,
                selectedSigners: [unsupported],
                delegatedSecrets: [:]
            )
        }
        // SDK must not be called when the flow rejects the signer kind.
        #expect(made.manager.removeCallCount == 0)
    }
}

// ============================================================================
// MARK: - Parser fallback
// ============================================================================

@Suite("ContextRuleFlow: Parser Fallback")
struct ContextRuleFlowFallbackTests {

    @Test("List returns malformed/unknown rule shape without throwing")
    @MainActor
    func listContextRules_fallbackRule_returnedWithoutThrowing() async throws {
        // Scenario #6: the SDK has parsed a rule into a structurally unusual
        // `OZParsedContextRule` (createContract context, empty name, no signers,
        // no policies). The flow must surface it untouched — neither the sort
        // step nor the success log path is allowed to mutate or drop the shape.
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listResult = [
            ContextRuleFixtures.defaultRule(id: 1, name: "ok"),
            ContextRuleFixtures.fallbackRule(id: 99)
        ]

        let result = try await made.flow.listContextRules()

        #expect(result.count == 2)
        #expect(result[0].id == 1)
        #expect(result[1].id == 99)
        let fallback = result[1]
        #expect(fallback.name.isEmpty)
        #expect(fallback.signers.isEmpty)
        #expect(fallback.policies.isEmpty)
        guard case .createContract(let hash) = fallback.contextType else {
            Issue.record("Expected createContract fallback context type")
            return
        }
        #expect(hash.count == 32)
        #expect(made.log.entries.contains { $0.message.contains("2 context rules") })
    }
}

// ============================================================================
// MARK: - Available signers
// ============================================================================

@Suite("ContextRuleFlow: Available Signers")
struct ContextRuleFlowSignersTests {

    @Test("loadAvailableSigners returns signers from rules")
    @MainActor
    func loadAvailableSigners_returnsFromRules() async {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listResult = [ContextRuleFixtures.defaultRule(id: 1)]

        let signers = await made.flow.loadAvailableSigners()

        #expect(!signers.isEmpty)
    }

    @Test("loadAvailableSigners when not connected returns empty")
    @MainActor
    func loadAvailableSigners_notConnected_empty() async {
        let made = ContextRuleFixtures.makeFlow(state: ContextRuleFixtures.disconnectedState())

        let signers = await made.flow.loadAvailableSigners()

        #expect(signers.isEmpty)
    }

    @Test("loadAvailableSigners on SDK error returns empty")
    @MainActor
    func loadAvailableSigners_sdkError_empty() async {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.listError = MockContextRuleNetworkError(detail: "error")

        let signers = await made.flow.loadAvailableSigners()

        #expect(signers.isEmpty)
    }

    @Test("isSinglePasskeyRemoval — single connected passkey returns true")
    @MainActor
    func isSinglePasskey_connectedPasskey_true() {
        let made = ContextRuleFixtures.makeFlow()
        let signer = ContextRuleFixtures.makePasskeySigner()

        #expect(made.flow.isSinglePasskeyRemoval([signer]))
    }

    @Test("isSinglePasskeyRemoval — multiple signers returns false")
    @MainActor
    func isSinglePasskey_multipleSigners_false() {
        let made = ContextRuleFixtures.makeFlow()
        let passkey = ContextRuleFixtures.makePasskeySigner()
        let delegated = ContextRuleFixtures.makeDelegatedSigner()

        #expect(!made.flow.isSinglePasskeyRemoval([passkey, delegated]))
    }

    @Test("isSinglePasskeyRemoval — delegated signer returns false")
    @MainActor
    func isSinglePasskey_delegatedSigner_false() {
        let made = ContextRuleFixtures.makeFlow()
        let delegated = ContextRuleFixtures.makeDelegatedSigner()

        #expect(!made.flow.isSinglePasskeyRemoval([delegated]))
    }
}

// ============================================================================
// MARK: - Passkey cancellation
// ============================================================================

@Suite("ContextRuleFlow: Passkey Cancellation")
struct ContextRuleFlowCancellationTests {

    @Test("Passkey cancellation propagates as user cancellation")
    @MainActor
    func remove_passkeyCancelled_propagates() async throws {
        let made = ContextRuleFixtures.makeFlow()
        made.manager.removeError = MockWebAuthnCancelledError()

        do {
            _ = try await made.flow.removeContextRule(
                ruleId: 1,
                ruleName: "rule",
                totalRuleCount: 2,
                selectedSigners: [],
                delegatedSecrets: [:]
            )
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(isUserCancellation(error) || error is MockWebAuthnCancelledError)
        }
    }
}

// ============================================================================
// MARK: - Spending-limit decimals resolution
// ============================================================================

@Suite("ContextRuleFlow: Spending-Limit Decimals")
struct ContextRuleFlowSpendingDecimalsTests {

    /// A valid non-native token contract (the spending-limit policy address from
    /// the demo's known policies), used to exercise the fetch path.
    static let customToken = "CBQE7L3UNP5IR4I7IBKLS7NV256WHR5TTH26HTMUIK7WXJC6J64RSE2L"

    @Test("Native XLM guarded token returns 7 without fetching")
    @MainActor
    func nativeReturnsSevenNoFetch() async throws {
        let resolver = MockTokenDecimalsResolver()
        let made = ContextRuleFixtures.makeFlow(tokenDecimalsResolver: resolver)

        let decimals = try await made.flow.resolveSpendingLimitDecimals(
            forGuardedToken: DemoConfig.nativeTokenContract
        )

        #expect(decimals == nativeTokenDecimals)
        #expect(resolver.callCount == 0)
    }

    @Test("Nil guarded token returns 7 without fetching")
    @MainActor
    func nilReturnsSevenNoFetch() async throws {
        let resolver = MockTokenDecimalsResolver()
        let made = ContextRuleFixtures.makeFlow(tokenDecimalsResolver: resolver)

        let decimals = try await made.flow.resolveSpendingLimitDecimals(forGuardedToken: nil)

        #expect(decimals == nativeTokenDecimals)
        #expect(resolver.callCount == 0)
    }

    @Test("Custom guarded token fetches the token's decimals")
    @MainActor
    func customTokenFetchesDecimals() async throws {
        let resolver = MockTokenDecimalsResolver()
        resolver.result = 2
        let made = ContextRuleFixtures.makeFlow(tokenDecimalsResolver: resolver)

        let decimals = try await made.flow.resolveSpendingLimitDecimals(
            forGuardedToken: Self.customToken
        )

        #expect(decimals == 2)
        #expect(resolver.callCount == 1)
        #expect(resolver.lastTokenContract == Self.customToken)
    }

    @Test("Custom token decimals fetch failure propagates")
    @MainActor
    func customTokenFetchFailurePropagates() async throws {
        let resolver = MockTokenDecimalsResolver()
        resolver.error = MockContextRuleNetworkError(detail: "decimals read failed")
        let made = ContextRuleFixtures.makeFlow(tokenDecimalsResolver: resolver)

        await #expect(throws: MockContextRuleNetworkError.self) {
            _ = try await made.flow.resolveSpendingLimitDecimals(
                forGuardedToken: Self.customToken
            )
        }
    }

    @Test("Missing resolver throws tokenDecimalsUnavailable for a custom token")
    @MainActor
    func missingResolverThrows() async throws {
        let made = ContextRuleFixtures.makeFlow(tokenDecimalsResolver: nil)

        await #expect(throws: ContextRuleFlowError.self) {
            _ = try await made.flow.resolveSpendingLimitDecimals(
                forGuardedToken: Self.customToken
            )
        }
    }
}
