// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing
import stellarsdk

@testable import ReferenceAgentCore

@Suite("ContractErrorClassifier")
struct ContractErrorClassifierTests {

    @Test("parses the contract error code from a HostError message")
    func parsesCode() {
        #expect(
            ContractErrorClassifier.parseContractErrorCode("HostError: Error(Contract, #3016)") == 3016
        )
    }

    @Test("returns nil when no contract code is present")
    func noCode() {
        #expect(ContractErrorClassifier.parseContractErrorCode("network unreachable") == nil)
    }

    @Test("maps known OZContractErrorCodes constants to names")
    func mapsKnownCodes() {
        #expect(ContractErrorClassifier.nameForCode(OZContractErrorCodes.unauthorizedSigner) == "unauthorizedSigner")
        #expect(ContractErrorClassifier.nameForCode(3013) == "keyDataTooLarge")
        #expect(ContractErrorClassifier.nameForCode(9999) == nil)
    }
}

@Suite("classifyResult")
struct ClassifyResultTests {

    @Test("success yields succeeded with the hash")
    func successHash() {
        let outcome = classifyResult(OZTransactionResult(success: true, hash: "HASH"))
        #expect(outcome == .succeeded(hash: "HASH"))
    }

    @Test("contract-code failure yields rejected")
    func contractCodeRejected() {
        let outcome = classifyResult(
            OZTransactionResult(success: false, error: "Error(Contract, #3016)")
        )
        guard case let .rejected(errorCode, errorName, _) = outcome else {
            Issue.record("expected .rejected, got \(outcome)")
            return
        }
        #expect(errorCode == 3016)
        #expect(errorName == "unauthorizedSigner")
    }

    @Test("non-contract failure yields failed")
    func nonContractFailed() {
        let outcome = classifyResult(OZTransactionResult(success: false, error: "timeout"))
        #expect(outcome == .failed(message: "timeout"))
    }

    @Test("unknown contract code yields rejected with a nil name")
    func unknownCode() {
        let outcome = classifyResult(
            OZTransactionResult(success: false, error: "Error(Contract, #4242)")
        )
        guard case let .rejected(errorCode, errorName, _) = outcome else {
            Issue.record("expected .rejected, got \(outcome)")
            return
        }
        #expect(errorCode == 4242)
        #expect(errorName == nil)
    }
}

@Suite("classifyError")
struct ClassifyErrorTests {

    @Test("SmartAccountException with a contract code yields rejected")
    func smartAccountRejected() {
        let outcome = classifyError(
            SmartAccountTransactionException.simulationFailed(reason: "Error(Contract, #3016)")
        )
        guard case let .rejected(errorCode, _, _) = outcome else {
            Issue.record("expected .rejected, got \(outcome)")
            return
        }
        #expect(errorCode == 3016)
    }

    @Test("generic error without a code yields failed")
    func genericFailed() {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }
        let outcome = classifyError(Boom())
        guard case let .failed(message) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("boom"))
    }
}
