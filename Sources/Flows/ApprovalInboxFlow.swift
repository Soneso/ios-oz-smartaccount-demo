// ApprovalInboxFlow.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
import stellarsdk

// ============================================================================
// MARK: - Rejection-reason mapping
// ============================================================================

/// Maps an on-chain contract error `reason` code to a human-readable name.
///
/// The numbers come from the OpenZeppelin smart-account contract's `Error`
/// enum and are surfaced by the SDK via `OZContractErrorCodes`. Unknown codes
/// fall back to a generic `Contract error #<n>` label so the inbox never hides
/// a rejection it cannot name.
public func describeRejectionReason(_ reason: Int) -> String {
    switch reason {
    case OZContractErrorCodes.mathOverflow:
        return "Math overflow"
    case OZContractErrorCodes.keyDataTooLarge:
        return "Key data too large"
    case OZContractErrorCodes.contextRuleIdsLengthMismatch:
        return "Context rule IDs length mismatch"
    case OZContractErrorCodes.nameTooLong:
        return "Name too long"
    case OZContractErrorCodes.unauthorizedSigner:
        return "Unauthorized signer"
    default:
        return "Contract error #\(reason)"
    }
}

// ============================================================================
// MARK: - DecodedCall
// ============================================================================

/// The call shape the inbox recognised in a request's decoded arguments.
public enum DecodedCallKind: Sendable, Equatable {

    /// `transfer(from, to, amount)` — the recipient is the `to` argument.
    case transfer

    /// `approve(from, spender, amount, expiration)` — the recipient is the
    /// `spender` argument.
    case approve

    /// A shape the inbox does not special-case; the full argument list is shown.
    case unknown

    /// The stored arguments could not be decoded at all.
    case undecodable
}

/// A single decoded argument rendered for an unrecognised call shape.
public struct DecodedArgument: Sendable, Equatable, Identifiable {

    /// Position + type label, for example `Arg 1 (address)`.
    public let label: String

    /// Human-readable value (a decoded address, integer, symbol, or — for
    /// exotic types — the verbatim base64 that re-submits).
    public let value: String

    public var id: String { label }

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Authoritative consent data derived from a request's stored `args`.
///
/// These values come from decoding the opaque base64 `XdrSCVal` arguments that
/// are actually re-submitted on-chain, NOT from the server-supplied,
/// display-only `amount` string. The card the user approves renders THESE
/// values so the displayed call matches the executed call exactly.
public struct DecodedCall: Sendable, Equatable {

    /// The recognised call shape.
    public let kind: DecodedCallKind

    /// Decoded recipient address (`to`/`spender`), or `nil` when the shape is
    /// unknown/undecodable.
    public let recipient: String?

    /// Label for ``recipient``: `Recipient` for transfer, `Spender` for approve.
    public let recipientLabel: String?

    /// ``amountBaseUnits`` formatted at the token's decimal scale, or `nil`.
    public let amount: String?

    /// Raw decoded on-chain amount in base units (the i128), or `nil`.
    public let amountBaseUnits: Int128?

    /// Full decoded argument list, populated when ``kind`` is
    /// ``DecodedCallKind/unknown``.
    public let arguments: [DecodedArgument]

    /// User-facing message when ``kind`` is ``DecodedCallKind/undecodable``.
    public let error: String?

    init(
        kind: DecodedCallKind,
        recipient: String? = nil,
        recipientLabel: String? = nil,
        amount: String? = nil,
        amountBaseUnits: Int128? = nil,
        arguments: [DecodedArgument] = [],
        error: String? = nil
    ) {
        self.kind = kind
        self.recipient = recipient
        self.recipientLabel = recipientLabel
        self.amount = amount
        self.amountBaseUnits = amountBaseUnits
        self.arguments = arguments
        self.error = error
    }
}

// ============================================================================
// MARK: - ApprovalResult / RejectionResult
// ============================================================================

/// Outcome of an ``ApprovalInboxFlow/approveRequest(_:)`` or
/// ``ApprovalInboxFlow/retryReport(_:)`` call.
///
/// ``success`` is true when the rebuilt call confirmed on-chain AND the result
/// was reported back. ``confirmedOnChain`` is true whenever the transaction
/// confirmed on-chain — even when reporting it back failed — so the inbox can
/// switch the card from a re-submittable "Approve" to an idempotent
/// "Retry report" and NEVER submit the same call twice.
public struct ApprovalResult: Sendable, Equatable {

    /// True when the call confirmed on-chain and the outcome was reported back.
    public let success: Bool

    /// On-chain transaction hash when known; `nil` otherwise.
    public let hash: String?

    /// Sanitised user-facing error message on failure; `nil` on success.
    public let error: String?

    /// True when the transaction confirmed on-chain regardless of whether the
    /// report-back succeeded. Once true, the request must never be re-submitted.
    public let confirmedOnChain: Bool

    public init(success: Bool, hash: String? = nil, error: String? = nil, confirmedOnChain: Bool = false) {
        self.success = success
        self.hash = hash
        self.error = error
        self.confirmedOnChain = confirmedOnChain
    }
}

/// Outcome of an ``ApprovalInboxFlow/rejectRequest(_:note:)`` call.
public struct RejectionResult: Sendable, Equatable {

    /// True when the rejection was recorded on the coordination server.
    public let success: Bool

    /// Sanitised user-facing error message on failure; `nil` on success.
    public let error: String?

    public init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
    }
}

// ============================================================================
// MARK: - ApprovalInboxFlow
// ============================================================================

/// Business logic for the approval inbox (steps 4 + 5 of the agent-signer flow).
///
/// The single entry point the approval inbox screen uses to talk to the
/// coordination server and the smart-account SDK. Screens must not call into
/// the SDK or the HTTP client directly.
///
/// - ``loadPending()`` / ``pendingCount()`` — read the pending escalations the
///   agent posted, scoped client-side to the connected smart account.
/// - ``decodeCall(_:)`` — derive the authoritative consent data (recipient +
///   on-chain amount) from the stored base64 `XdrSCVal` arguments that are
///   actually re-submitted, NOT from the server-supplied display-only `amount`.
/// - ``approveRequest(_:)`` — rebuild the agent's EXACT call from the stored
///   arguments and re-submit it under the user's Default rule (single-signer
///   passkey path), then report the resulting transaction hash back.
/// - ``retryReport(_:)`` — re-report a previously confirmed on-chain approval
///   whose report-back POST failed, WITHOUT re-submitting on-chain.
/// - ``rejectRequest(_:note:)`` — decline the escalation with an optional note.
///
/// The coordination client and the contract-call submission are both injected,
/// so every path is unit-testable without a network or a live testnet.
@MainActor
public final class ApprovalInboxFlow {

    // -------------------------------------------------------------------------
    // MARK: - Dependencies
    // -------------------------------------------------------------------------

    private let coordination: any CoordinationClientType
    private let activityLog: ActivityLogState
    private let demoState: DemoState
    private let contractCallProvider: @MainActor () -> (any ContractCallOperationsType)?
    private let tokenDecimals: Int

    // -------------------------------------------------------------------------
    // MARK: - State
    // -------------------------------------------------------------------------

    /// True while an approve call is executing, guarding concurrent in-flight
    /// submissions.
    private var isApproving = false

    /// Marks a request that confirmed on-chain but produced no reportable hash.
    ///
    /// Stored in ``DemoState/confirmedApprovalHashes`` like a real hash so the
    /// "never re-submit" guard still trips for an approval that confirmed but
    /// returned no hash; ``isAwaitingReport(_:)`` excludes it because there is
    /// nothing to report.
    private static let confirmedNoHashSentinel = "<confirmed-without-hash>"

    private static let noWalletError = "No wallet connected. Connect a wallet to approve."
    private static let accountMismatchError =
        "This escalation targets a different smart account than the one you are connected to."

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    /// Creates a flow with injected dependencies.
    ///
    /// - Parameters:
    ///   - coordination: Client for the coordination server.
    ///   - activityLog: Receives progress messages.
    ///   - demoState: Source of the connected smart account address.
    ///   - contractCallProvider: Returns the single-signer submission adapter
    ///     for the connected kit (or `nil` when no wallet is connected).
    ///     Resolved lazily on each call so a kit that becomes available after
    ///     the flow is created is picked up without rebuilding the flow.
    ///   - tokenDecimals: Decimal scale used to format decoded amounts. Defaults
    ///     to the demo token's configured scale: the agent flow scopes the
    ///     delegation to the 7-decimal demo token, and the inbox does not make a
    ///     network call to resolve a per-request token's `decimals()`.
    public init(
        coordination: any CoordinationClientType,
        activityLog: ActivityLogState,
        demoState: DemoState,
        contractCallProvider: @escaping @MainActor () -> (any ContractCallOperationsType)?,
        tokenDecimals: Int = Int(DemoConfig.demoTokenDecimals)
    ) {
        self.coordination = coordination
        self.activityLog = activityLog
        self.demoState = demoState
        self.contractCallProvider = contractCallProvider
        self.tokenDecimals = tokenDecimals
    }

    // -------------------------------------------------------------------------
    // MARK: - Reads
    // -------------------------------------------------------------------------

    /// Loads the pending escalations for the connected smart account,
    /// newest-first.
    ///
    /// The server filters only by status, so the listing is scoped client-side
    /// to `request.smartAccount == ` the connected account. Returns an empty
    /// list when no wallet is connected. Propagates ``CoordinationError`` so the
    /// screen can render an error state when the server is unreachable.
    public func loadPending() async throws -> [CoordinationRequest] {
        let pending = try await coordination.listPending()
        return scopeToConnectedAccount(pending)
    }

    /// Returns the number of pending escalations for the connected account.
    ///
    /// Used by the bell badge on the main screen. Scoped exactly like
    /// ``loadPending()``; zero when no wallet is connected.
    public func pendingCount() async throws -> Int {
        let pending = try await coordination.listPending()
        return scopeToConnectedAccount(pending).count
    }

    private func scopeToConnectedAccount(_ all: [CoordinationRequest]) -> [CoordinationRequest] {
        guard let account = demoState.contractId else { return [] }
        return all.filter { $0.smartAccount == account }
    }

    // -------------------------------------------------------------------------
    // MARK: - Decode (authoritative consent data)
    // -------------------------------------------------------------------------

    /// Decodes the authoritative consent data the user is actually authorising.
    ///
    /// Decodes each base64 `XdrSCVal` entry in `request.args` and, for the known
    /// `transfer(from, to, amount)` and `approve(from, spender, amount, expiry)`
    /// shapes, derives the on-chain recipient and amount. For any other shape the
    /// full decoded argument list is returned. The server-supplied
    /// `request.amount` is deliberately ignored: it is display-only and
    /// untrusted.
    public func decodeCall(_ request: CoordinationRequest) -> DecodedCall {
        let args: [SCValXDR]
        do {
            args = try decodeArgs(request.args)
        } catch {
            return DecodedCall(
                kind: .undecodable,
                error: "Cannot decode the stored call arguments. Do not approve."
            )
        }

        switch request.targetFn {
        case "transfer" where args.count == 3:
            if let decoded = decodeTransferLike(args, recipientIndex: 1, amountIndex: 2, recipientLabel: "Recipient") {
                return decoded
            }
        case "approve" where args.count == 4:
            if let decoded = decodeTransferLike(args, recipientIndex: 1, amountIndex: 2, recipientLabel: "Spender") {
                return decoded
            }
        default:
            break
        }

        // Unknown shape (or a known function with an unexpected argument count):
        // surface the full decoded argument list so nothing is hidden.
        return DecodedCall(kind: .unknown, arguments: summariseArgs(args, encoded: request.args))
    }

    private func decodeTransferLike(
        _ args: [SCValXDR],
        recipientIndex: Int,
        amountIndex: Int,
        recipientLabel: String
    ) -> DecodedCall? {
        guard let recipient = decodeAddress(args[recipientIndex]),
              let amountBaseUnits = decodeInt128(args[amountIndex]) else {
            return nil
        }
        return DecodedCall(
            kind: recipientLabel == "Spender" ? .approve : .transfer,
            recipient: recipient,
            recipientLabel: recipientLabel,
            amount: formatBaseUnitsAsDecimal(amountBaseUnits, decimals: tokenDecimals),
            amountBaseUnits: amountBaseUnits
        )
    }

    // -------------------------------------------------------------------------
    // MARK: - Approve (steps 4 + 5)
    // -------------------------------------------------------------------------

    /// Rebuilds and re-submits the agent's exact call, then reports the outcome.
    ///
    /// Before submitting, guards in order: a wallet must be connected; the
    /// escalation must target the connected smart account (BEFORE any passkey
    /// ceremony); the stored arguments must decode; and a fresh
    /// `GET /requests/{id}` must still report `pending` (a stale inbox /
    /// cross-device resolution aborts the submission). Once a hash is confirmed,
    /// that request is recorded and can never be re-submitted — a failed
    /// report-back returns ``ApprovalResult/confirmedOnChain`` true so the inbox
    /// offers ``retryReport(_:)`` instead of a second submit.
    public func approveRequest(_ request: CoordinationRequest) async -> ApprovalResult {
        guard !isApproving else {
            return ApprovalResult(success: false, error: "An approval is already in progress.")
        }
        isApproving = true
        defer { isApproving = false }

        // If this request already confirmed on-chain, never re-submit: route to
        // the idempotent report-back path instead. The dedup map lives on
        // `DemoState`, so this guard trips even for a flow instance rebuilt after
        // navigation (a fresh inbox view) that never saw the original submission.
        if demoState.confirmedApprovalHash(requestId: request.id) != nil {
            return await retryReport(request)
        }

        guard let contractCall = contractCallProvider() else {
            return ApprovalResult(success: false, error: Self.noWalletError)
        }

        // Account-scope guard: refuse before any ceremony when the escalation
        // targets a different smart account than the connected one.
        guard let connectedAccount = demoState.contractId else {
            return ApprovalResult(success: false, error: Self.noWalletError)
        }
        guard connectedAccount == request.smartAccount else {
            activityLog.error(Self.accountMismatchError)
            return ApprovalResult(success: false, error: Self.accountMismatchError)
        }

        let targetArgs: [SCValXDR]
        do {
            targetArgs = try decodeArgs(request.args)
        } catch {
            let message = "Cannot decode the stored call arguments. Do not approve."
            activityLog.error(message)
            return ApprovalResult(success: false, error: message)
        }

        // Re-check the request is still pending immediately before submitting so
        // a stale inbox / cross-device resolution does not trigger a duplicate
        // on-chain transfer.
        do {
            let latest = try await coordination.getRequest(request.id)
            if latest.status != CoordinationRequest.statusPending {
                let message = "This escalation is no longer pending (status: \(latest.status)); " +
                    "it was resolved elsewhere. Refresh the inbox."
                activityLog.info(message)
                return ApprovalResult(success: false, error: message)
            }
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Could not re-check the escalation before submitting: \(message)")
            return ApprovalResult(success: false, error: message)
        }

        activityLog.info(
            "Approving agent call \(request.targetFn) on \(truncateAddress(request.target))"
        )

        let result: OZTransactionResult
        do {
            result = try await contractCall.contractCall(
                target: request.target,
                targetFn: request.targetFn,
                targetArgs: targetArgs
            )
        } catch {
            if isUserCancellation(error) {
                activityLog.info("Passkey authentication cancelled")
                return ApprovalResult(success: false, error: "Passkey authentication cancelled")
            }
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Approval failed: \(message)")
            return ApprovalResult(success: false, error: message)
        }

        guard result.success else {
            let message = "Approval failed: \(ActivityLogState.redact(result.error ?? "Unknown error"))"
            activityLog.error(message)
            return ApprovalResult(success: false, error: message)
        }

        let hash = result.hash ?? ""
        // The transaction confirmed on-chain. From here on this request must
        // NEVER be re-submitted, even when the hash is empty or report-back
        // fails. Record it on `DemoState` before attempting the report so the
        // guard survives navigation and is shared with every other flow instance.
        demoState.recordConfirmedApprovalHash(
            requestId: request.id,
            hash: hash.isEmpty ? Self.confirmedNoHashSentinel : hash
        )

        if hash.isEmpty {
            let message = "Approval confirmed on-chain but no transaction hash was returned; " +
                "the agent could not be notified automatically."
            activityLog.error(message)
            return ApprovalResult(success: false, error: message, confirmedOnChain: true)
        }

        // Step 5: report the confirmed hash back so the agent learns the outcome.
        return await reportApproval(id: request.id, hash: hash)
    }

    /// Re-reports a previously confirmed on-chain approval WITHOUT re-submitting.
    ///
    /// Used by the inbox's "Retry report" affordance after ``approveRequest(_:)``
    /// confirmed the transaction on-chain but the report-back POST failed. Looks
    /// up the recorded hash and POSTs only `/requests/{id}/approve`. Never calls
    /// `contractCall`. A `409` (already resolved) is treated as success.
    public func retryReport(_ request: CoordinationRequest) async -> ApprovalResult {
        guard let recordedHash = demoState.confirmedApprovalHash(requestId: request.id),
              recordedHash != Self.confirmedNoHashSentinel else {
            let message = "No confirmed transaction hash is available to report for this escalation."
            activityLog.error(message)
            return ApprovalResult(success: false, error: message)
        }

        do {
            _ = try await coordination.approve(request.id, resultHash: recordedHash)
        } catch let error as CoordinationError {
            if error.statusCode == 409 {
                // Already resolved server-side: the report is effectively complete.
                demoState.clearConfirmedApprovalHash(requestId: request.id)
                activityLog.info("Escalation already resolved on the coordination server. Hash: \(recordedHash)")
                return ApprovalResult(success: true, hash: recordedHash)
            }
            let message = "Reporting the approval failed: \(error.message) " +
                "(transaction confirmed on-chain: \(recordedHash))"
            activityLog.error(message)
            return ApprovalResult(success: false, hash: recordedHash, error: message, confirmedOnChain: true)
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Reporting the approval failed: \(message)")
            return ApprovalResult(
                success: false,
                hash: recordedHash,
                error: "\(message) (transaction confirmed on-chain: \(recordedHash))",
                confirmedOnChain: true
            )
        }

        demoState.clearConfirmedApprovalHash(requestId: request.id)
        activityLog.success("Agent call approved. Hash: \(recordedHash)")
        return ApprovalResult(success: true, hash: recordedHash)
    }

    /// Reports a confirmed `hash` back to the coordination server for `id`.
    private func reportApproval(id: String, hash: String) async -> ApprovalResult {
        do {
            _ = try await coordination.approve(id, resultHash: hash)
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Reporting the approval failed: \(message)")
            return ApprovalResult(
                success: false,
                hash: hash,
                error: "\(message) (transaction confirmed on-chain: \(hash))",
                confirmedOnChain: true
            )
        }
        demoState.clearConfirmedApprovalHash(requestId: id)
        activityLog.success("Agent call approved. Hash: \(hash)")
        return ApprovalResult(success: true, hash: hash)
    }

    /// Whether `id` has a confirmed on-chain transaction whose report-back is
    /// still outstanding. The no-hash sentinel does not count: there is nothing
    /// to report.
    public func isAwaitingReport(_ id: String) -> Bool {
        guard let hash = demoState.confirmedApprovalHash(requestId: id) else { return false }
        return hash != Self.confirmedNoHashSentinel
    }

    // -------------------------------------------------------------------------
    // MARK: - Reject
    // -------------------------------------------------------------------------

    /// Declines `request`, recording an optional `note`.
    ///
    /// An empty or whitespace-only note is sent as no note. Returns a
    /// ``RejectionResult``; on failure ``RejectionResult/error`` is sanitised.
    public func rejectRequest(_ request: CoordinationRequest, note: String?) async -> RejectionResult {
        let trimmed = note?.trimmingCharacters(in: .whitespaces)
        let effectiveNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
        do {
            _ = try await coordination.reject(request.id, note: effectiveNote)
            activityLog.info(
                "Rejected agent call \(request.targetFn) on \(truncateAddress(request.target))"
            )
            return RejectionResult(success: true)
        } catch {
            let message = ActivityLogState.redact(actionableMessage(for: error))
            activityLog.error("Rejection failed: \(message)")
            return RejectionResult(success: false, error: message)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: SCVal decoding
    // -------------------------------------------------------------------------

    /// Decodes the base64-encoded `XdrSCVal` argument list verbatim.
    private func decodeArgs(_ encoded: [String]) throws -> [SCValXDR] {
        try encoded.map { try SCValXDR.fromXdr(base64: $0) }
    }

    /// Decodes an address `XdrSCVal` to its StrKey form, or `nil` when `val` is
    /// not an address or cannot be decoded.
    private func decodeAddress(_ val: SCValXDR) -> String? {
        guard let address = val.address else { return nil }
        if let accountId = address.accountId { return accountId }
        if let contractIdHex = address.contractId {
            return try? contractIdHex.encodeContractIdHex()
        }
        return nil
    }

    /// Decodes a signed-integer `XdrSCVal` (i128/u128/i64/u64/i32/u32) into an
    /// `Int128`, preserving the full range. Returns `nil` for non-integer types.
    private func decodeInt128(_ val: SCValXDR) -> Int128? {
        switch val {
        case .i128(let parts):
            return (Int128(parts.hi) << 64) + Int128(parts.lo)
        case .u128:
            return val.u128String.flatMap { Int128($0) }
        case .i64(let value):
            return Int128(value)
        case .u64(let value):
            return Int128(value)
        case .i32(let value):
            return Int128(value)
        case .u32(let value):
            return Int128(value)
        default:
            return nil
        }
    }

    private func summariseArgs(_ args: [SCValXDR], encoded: [String]) -> [DecodedArgument] {
        args.enumerated().map { index, val in
            let fallback = index < encoded.count ? encoded[index] : ""
            return DecodedArgument(
                label: "Arg \(index) (\(scValTypeName(val)))",
                value: describeScVal(val, fallbackBase64: fallback)
            )
        }
    }

    private func describeScVal(_ val: SCValXDR, fallbackBase64: String) -> String {
        if let decoded = decodeAddress(val) { return decoded }
        if let amount = decodeInt128(val) { return String(amount) }
        if let bool = val.bool { return String(bool) }
        if let symbol = val.symbol { return symbol }
        if let string = val.string { return string }
        // Exotic types: show the verbatim base64 that re-submits rather than
        // hide it, so the value remains verifiable.
        return fallbackBase64
    }

    private func scValTypeName(_ val: SCValXDR) -> String {
        switch val {
        case .address: return "address"
        case .i128: return "i128"
        case .u128: return "u128"
        case .i256: return "i256"
        case .u256: return "u256"
        case .u32: return "u32"
        case .i32: return "i32"
        case .u64: return "u64"
        case .i64: return "i64"
        case .bool: return "bool"
        case .symbol: return "symbol"
        case .string: return "string"
        case .bytes: return "bytes"
        case .vec: return "vec"
        case .map: return "map"
        default: return "value"
        }
    }
}
