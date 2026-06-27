import Foundation

/// Lifecycle state of a coordination request.
///
/// A request is created as ``pending`` and transitions exactly once to either
/// ``approved`` or ``rejected``. No other transition is permitted.
public enum RequestStatus: String, Sendable, CaseIterable {
    case pending
    case approved
    case rejected

    /// The string used on the wire and in persisted JSON.
    public var wireName: String { rawValue }

    /// Parses a wire value into a ``RequestStatus``.
    ///
    /// Throws ``ValidationError`` when `value` is not a known status.
    public static func fromWire(_ value: String) throws -> RequestStatus {
        guard let status = RequestStatus(rawValue: value) else {
            throw ValidationError("status must be one of 'pending', 'approved', 'rejected'")
        }
        return status
    }
}

/// A policy-rejected smart-account call awaiting human approval.
///
/// Values are immutable; mutations produce a new value via ``resolving(...)``.
/// The `args` list holds base64-encoded `XdrSCVal` entries that are opaque to
/// the server and are stored and returned verbatim so the inbox can rebuild
/// the original call exactly.
public struct SmartAccountRequest: Sendable, Equatable {
    /// Server-assigned UUID v4 identifier.
    public let id: String

    /// C-address of the smart account the call targets.
    public let smartAccount: String

    /// C-address the agent attempted to call.
    public let target: String

    /// Contract function name, e.g. `transfer`.
    public let targetFn: String

    /// Base64-encoded `XdrSCVal` arguments, opaque to the server.
    public let args: [String]

    /// Display-only amount string. Empty when the agent supplied none.
    public let amount: String

    /// On-chain rejection contract error code, e.g. `3016`.
    public let reason: Int

    /// Current lifecycle state.
    public let status: RequestStatus

    /// Creation time in unix milliseconds.
    public let createdAt: Int

    /// Resolution time in unix milliseconds, or `nil` while pending.
    public let resolvedAt: Int?

    /// Transaction/result hash recorded on approval, or `nil`.
    public let resultHash: String?

    /// Optional free-text note recorded on rejection, or `nil`.
    public let note: String?

    public init(
        id: String,
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String,
        reason: Int,
        status: RequestStatus,
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

    /// Whether this request has already transitioned out of ``RequestStatus/pending``.
    public var isResolved: Bool { status != .pending }

    /// Returns a resolved copy carrying the new terminal `status`, the
    /// `resolvedAt` timestamp, and any approval `resultHash` or rejection `note`.
    public func resolving(
        status: RequestStatus,
        resolvedAt: Int,
        resultHash: String? = nil,
        note: String? = nil
    ) -> SmartAccountRequest {
        SmartAccountRequest(
            id: id,
            smartAccount: smartAccount,
            target: target,
            targetFn: targetFn,
            args: args,
            amount: amount,
            reason: reason,
            status: status,
            createdAt: createdAt,
            resolvedAt: resolvedAt,
            resultHash: resultHash,
            note: note
        )
    }

    /// Builds a request from its persisted/transported JSON representation.
    ///
    /// Throws ``ValidationError`` when a field is missing or has the wrong
    /// type, keeping a persisted store file from loading silently corrupted
    /// records.
    public static func fromJSON(_ json: [String: Any]) throws -> SmartAccountRequest {
        SmartAccountRequest(
            id: try JSONField.requireNonEmptyString(json, "id"),
            smartAccount: try JSONField.requireNonEmptyString(json, "smartAccount"),
            target: try JSONField.requireNonEmptyString(json, "target"),
            targetFn: try JSONField.requireNonEmptyString(json, "targetFn"),
            args: try JSONField.requireStringList(json, "args"),
            amount: try JSONField.requireString(json, "amount"),
            reason: try JSONField.requireInt(json, "reason"),
            status: try RequestStatus.fromWire(JSONField.requireNonEmptyString(json, "status")),
            createdAt: try JSONField.requireInt(json, "createdAt"),
            resolvedAt: try JSONField.optionalInt(json, "resolvedAt"),
            resultHash: try JSONField.optionalString(json, "resultHash"),
            note: try JSONField.optionalString(json, "note")
        )
    }

    /// Serializes to the canonical wire/persistence JSON shape.
    ///
    /// Nullable fields are always present, carrying `NSNull` when unset, so the
    /// emitted object matches the locked wire contract field-for-field.
    public func jsonObject() -> [String: Any] {
        [
            "id": id,
            "smartAccount": smartAccount,
            "target": target,
            "targetFn": targetFn,
            "args": args,
            "amount": amount,
            "reason": reason,
            "status": status.wireName,
            "createdAt": createdAt,
            "resolvedAt": resolvedAt ?? NSNull(),
            "resultHash": resultHash ?? NSNull(),
            "note": note ?? NSNull(),
        ]
    }
}

/// Validated input for `POST /requests`.
///
/// The client supplies only the agent-controlled fields; the server assigns
/// `id`, `status`, and `createdAt`.
public struct CreateRequestInput: Sendable, Equatable {
    public let smartAccount: String
    public let target: String
    public let targetFn: String
    public let args: [String]
    public let amount: String
    public let reason: Int

    public init(
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String,
        reason: Int
    ) {
        self.smartAccount = smartAccount
        self.target = target
        self.targetFn = targetFn
        self.args = args
        self.amount = amount
        self.reason = reason
    }

    /// Validates a decoded JSON object into a ``CreateRequestInput``.
    ///
    /// Throws ``ValidationError`` with a field-specific message on any missing
    /// or wrongly typed field. Server-assigned fields present in the body are
    /// ignored. `amount` is optional and defaults to the empty string.
    public static func fromJSON(_ json: [String: Any]) throws -> CreateRequestInput {
        CreateRequestInput(
            smartAccount: try JSONField.requireNonEmptyString(json, "smartAccount"),
            target: try JSONField.requireNonEmptyString(json, "target"),
            targetFn: try JSONField.requireNonEmptyString(json, "targetFn"),
            args: try JSONField.requireStringList(json, "args"),
            amount: try JSONField.optionalString(json, "amount") ?? "",
            reason: try JSONField.requireInt(json, "reason")
        )
    }
}
