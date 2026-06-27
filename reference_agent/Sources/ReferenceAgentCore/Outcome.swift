// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import stellarsdk

/// Classification of a single scoped contract-call attempt.
///
/// A call either confirmed on-chain (`succeeded`), was rejected by the
/// smart-account contract with a parseable error code (`rejected`), or failed
/// for a non-contract reason such as a network error (`failed`). Only a
/// `rejected` outcome is a policy decision that the agent escalates.
public enum CallOutcome: Sendable, Equatable {

    /// The scoped call confirmed on-chain, carrying the transaction hash.
    case succeeded(hash: String)

    /// The smart-account contract rejected the call with an on-chain error code.
    ///
    /// `errorCode` is the integer extracted from the contract error in the
    /// failure message (e.g. `Error(Contract, #3016)` yields `3016`).
    /// `errorName` is the symbolic name when `errorCode` matches a known
    /// `OZContractErrorCodes` constant, otherwise `nil`. `rawMessage` is the
    /// failure text the code was parsed from.
    case rejected(errorCode: Int, errorName: String?, rawMessage: String)

    /// The call failed for a reason other than a contract rejection (for example
    /// a network or simulation error). The agent does not escalate these.
    case failed(message: String)
}

/// Maps and parses OpenZeppelin smart-account contract error codes.
public enum ContractErrorClassifier {

    /// Symbolic names for the `OZContractErrorCodes` constants the SDK documents.
    public static let knownCodes: [Int: String] = [
        OZContractErrorCodes.mathOverflow: "mathOverflow",
        OZContractErrorCodes.keyDataTooLarge: "keyDataTooLarge",
        OZContractErrorCodes.contextRuleIdsLengthMismatch: "contextRuleIdsLengthMismatch",
        OZContractErrorCodes.nameTooLong: "nameTooLong",
        OZContractErrorCodes.unauthorizedSigner: "unauthorizedSigner",
    ]

    /// Matches `#<digits>` as it appears in `Error(Contract, #3016)`.
    private static let codePattern = try! NSRegularExpression(pattern: "#(\\d+)")

    /// Returns the integer contract error code embedded in [message], or `nil`
    /// when no `#<digits>` token is present.
    public static func parseContractErrorCode(_ message: String) -> Int? {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = codePattern.firstMatch(in: message, range: range),
              match.numberOfRanges >= 2,
              let digitsRange = Range(match.range(at: 1), in: message)
        else {
            return nil
        }
        return Int(message[digitsRange])
    }

    /// Returns the symbolic name for [code], or `nil` when it is not a known
    /// `OZContractErrorCodes` constant.
    public static func nameForCode(_ code: Int) -> String? {
        knownCodes[code]
    }

    /// Returns the message text of [error], preferring the SDK exception's own
    /// `message` over its string description.
    public static func messageOf(_ error: Error) -> String {
        if let smartAccountError = error as? SmartAccountException {
            return smartAccountError.message
        }
        return String(describing: error)
    }
}

/// Classifies an `OZTransactionResult` returned by the multi-signer pipeline.
public func classifyResult(_ result: OZTransactionResult) -> CallOutcome {
    if result.success {
        return .succeeded(hash: result.hash ?? "")
    }
    let message = result.error ?? "Unknown submission error"
    return classifyFailureMessage(message)
}

/// Classifies an error thrown by the multi-signer pipeline.
public func classifyError(_ error: Error) -> CallOutcome {
    classifyFailureMessage(ContractErrorClassifier.messageOf(error))
}

private func classifyFailureMessage(_ message: String) -> CallOutcome {
    if let code = ContractErrorClassifier.parseContractErrorCode(message) {
        return .rejected(
            errorCode: code,
            errorName: ContractErrorClassifier.nameForCode(code),
            rawMessage: message
        )
    }
    return .failed(message: message)
}
