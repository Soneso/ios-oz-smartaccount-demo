// MockSmartAccountExecutor.swift
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

// ============================================================================
// MARK: - MockSmartAccountExecutor
// ============================================================================

/// Configurable mock for ``SmartAccountExecutorType``. Captures the supplied
/// `target`, `targetFn`, `targetArgs`, and optional signer list so the edit-
/// flow tests can assert the correct execute payload.
final class MockSmartAccountExecutor: SmartAccountExecutorType, @unchecked Sendable {

    /// Sequential per-call recorder used by tests to assert dispatch order.
    /// `SCValXDR` is not `Equatable`, so callers compare via case extraction
    /// (see ``ExecuteCall/functionName``) rather than direct equality.
    enum ExecuteCall {
        case execute(target: String, targetFn: String, targetArgs: [SCValXDR])
        case multiSignerExecute(
            target: String,
            targetFn: String,
            targetArgs: [SCValXDR],
            selectedSigners: [OZSelectedSigner]
        )

        /// The invoked function name across both single- and multi-signer
        /// cases. Returns `nil` for any future case that does not carry a
        /// function name.
        var functionName: String? {
            switch self {
            case .execute(_, let targetFn, _):
                return targetFn
            case .multiSignerExecute(_, let targetFn, _, _):
                return targetFn
            }
        }
    }

    /// Recorded call ledger in execution order. Tests assert against this.
    private(set) var executeCalls: [ExecuteCall] = []

    var executeResult: OZTransactionResult?
    var executeError: Error?
    var multiSignerExecuteResult: OZTransactionResult?
    var multiSignerExecuteError: Error?

    private static func defaultSuccess(_ tag: String) -> OZTransactionResult {
        OZTransactionResult(success: true, hash: "executor-\(tag)-hash", error: nil)
    }

    func executeAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR]
    ) async throws -> OZTransactionResult {
        executeCalls.append(
            .execute(target: target, targetFn: targetFn, targetArgs: targetArgs)
        )
        if let error = executeError { throw error }
        return executeResult ?? Self.defaultSuccess("execute")
    }

    func multiSignerExecuteAndSubmit(
        target: String,
        targetFn: String,
        targetArgs: [SCValXDR],
        selectedSigners: [OZSelectedSigner]
    ) async throws -> OZTransactionResult {
        executeCalls.append(
            .multiSignerExecute(
                target: target,
                targetFn: targetFn,
                targetArgs: targetArgs,
                selectedSigners: selectedSigners
            )
        )
        if let error = multiSignerExecuteError { throw error }
        return multiSignerExecuteResult ?? Self.defaultSuccess("multi")
    }
}
