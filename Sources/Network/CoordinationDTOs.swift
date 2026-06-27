// CoordinationDTOs.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - CoordinationRequest
// ============================================================================

/// A coordination-server request record (agent-signer flow, steps 4 + 5).
///
/// Mirrors the canonical request object served by the coordination server. All
/// fields are present in a server response; the nullable fields are `nil` until
/// the request is resolved. The ``args`` entries are base64-encoded `XdrSCVal`
/// strings, opaque to the server and stored verbatim so the inbox can rebuild
/// the original call exactly. The server-supplied ``amount`` is display-only and
/// untrusted — the authoritative amount is decoded from ``args``.
public struct CoordinationRequest: Sendable, Equatable, Identifiable, Codable {

    /// Server-assigned UUID v4.
    public let id: String

    /// C-address of the smart account the call targets.
    public let smartAccount: String

    /// C-address the agent tried to call.
    public let target: String

    /// Function name invoked on ``target`` (for example `transfer`).
    public let targetFn: String

    /// Base64-encoded `XdrSCVal` call arguments, verbatim.
    public let args: [String]

    /// Display-only amount string; the empty string when not supplied.
    public let amount: String

    /// Integer contract error code that triggered the escalation.
    public let reason: Int

    /// One of `pending`, `approved`, or `rejected`.
    public let status: String

    /// Creation timestamp (epoch milliseconds).
    public let createdAt: Int

    /// Resolution timestamp (epoch milliseconds), or `nil` while pending.
    public let resolvedAt: Int?

    /// Transaction/result hash set on approval, or `nil`.
    public let resultHash: String?

    /// Optional note set on rejection, or `nil`.
    public let note: String?

    /// Pending status literal.
    public static let statusPending = "pending"

    /// Approved status literal.
    public static let statusApproved = "approved"

    /// Rejected status literal.
    public static let statusRejected = "rejected"

    /// Whether the request has reached a terminal state.
    public var isResolved: Bool {
        status == Self.statusApproved || status == Self.statusRejected
    }

    public init(
        id: String,
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String,
        reason: Int,
        status: String,
        createdAt: Int,
        resolvedAt: Int? = nil,
        resultHash: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.smartAccount = smartAccount
        self.target = target
        self.targetFn = targetFn
        self.args = args
        self.amount = amount
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resultHash = resultHash
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, smartAccount, target, targetFn, args, amount, reason, status
        case createdAt, resolvedAt, resultHash, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        smartAccount = try container.decode(String.self, forKey: .smartAccount)
        target = try container.decode(String.self, forKey: .target)
        targetFn = try container.decode(String.self, forKey: .targetFn)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        // `amount` is display-only and may be omitted by some producers; default
        // to the empty string rather than failing the whole decode.
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        reason = try container.decode(Int.self, forKey: .reason)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        resolvedAt = try container.decodeIfPresent(Int.self, forKey: .resolvedAt)
        resultHash = try container.decodeIfPresent(String.self, forKey: .resultHash)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

// ============================================================================
// MARK: - Wire envelopes
// ============================================================================

/// Envelope for the list endpoint: `GET /requests` wraps its array in a
/// `requests` key.
struct CoordinationRequestList: Decodable {
    let requests: [CoordinationRequest]
}

/// Server error body shape: `{ "error": "..." }`.
struct CoordinationErrorBody: Decodable {
    let error: String
}

/// Approve request body: `{ "resultHash": "..." }`.
struct CoordinationApproveBody: Encodable {
    let resultHash: String
}

/// Reject request body: `{ "note": "..." }` (omitted when no note is supplied).
struct CoordinationRejectBody: Encodable {
    let note: String?
}

// ============================================================================
// MARK: - CoordinationError
// ============================================================================

/// Thrown when a coordination-server call fails or returns a non-2xx response.
///
/// On an error response the server returns `{ "error": "..." }`; ``message``
/// carries that string (or a transport-level description) and ``statusCode``
/// the HTTP status when one was received.
public struct CoordinationError: Error, Sendable, Equatable {

    /// Human-readable description of the failure.
    public let message: String

    /// HTTP status code when the failure carried one, otherwise `nil`.
    public let statusCode: Int?

    public init(message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }
}

extension CoordinationError: LocalizedError {
    public var errorDescription: String? {
        guard let statusCode else { return message }
        return "\(message) (HTTP \(statusCode))"
    }
}
