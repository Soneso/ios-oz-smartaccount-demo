// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation

/// A coordination-server request record.
///
/// Mirrors the canonical request object documented in the coordination server
/// README. All fields are always present in a server response; optional fields
/// are `nil` until the request is resolved.
public struct CoordinationRequest: Sendable, Equatable {

    /// Pending status literal.
    public static let statusPending = "pending"

    /// Approved status literal.
    public static let statusApproved = "approved"

    /// Rejected status literal.
    public static let statusRejected = "rejected"

    /// Server-assigned UUID v4.
    public let id: String

    /// C-address of the smart account.
    public let smartAccount: String

    /// C-address the agent tried to call.
    public let target: String

    /// Function name invoked on [target] (e.g. `transfer`).
    public let targetFn: String

    /// Base64-encoded `SCValXDR` call arguments, verbatim, so the inbox can
    /// rebuild the original call.
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

    /// Whether the request has reached a terminal state.
    public var isResolved: Bool {
        status == CoordinationRequest.statusApproved || status == CoordinationRequest.statusRejected
    }
}

extension CoordinationRequest: Decodable {
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
        args = try container.decode([String].self, forKey: .args)
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        reason = try container.decode(Int.self, forKey: .reason)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        resolvedAt = try container.decodeIfPresent(Int.self, forKey: .resolvedAt)
        resultHash = try container.decodeIfPresent(String.self, forKey: .resultHash)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// Thrown when a coordination-server call fails or returns an error response.
public struct CoordinationError: Error, CustomStringConvertible, Sendable {

    /// Human-readable description of the failure.
    public let message: String

    /// HTTP status code when the failure carried one, otherwise `nil`.
    public let statusCode: Int?

    public init(_ message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    public var description: String {
        statusCode == nil
            ? "CoordinationError: \(message)"
            : "CoordinationError(\(statusCode!)): \(message)"
    }
}

/// Abstraction over the coordination server's REST contract.
///
/// Behind a protocol so the agent runner can be unit-tested with a fake that
/// returns canned responses, without a live server or network access.
public protocol CoordinationClient: Sendable {

    /// Posts a rejected call to `POST /requests`.
    ///
    /// [args] is the list of base64-encoded `SCValXDR` strings — the exact call
    /// arguments, so the inbox can rebuild the call verbatim. [reason] is the
    /// integer contract error code. Returns the created record with a
    /// server-assigned `id` and `pending` status.
    func createRequest(
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String?,
        reason: Int
    ) async throws -> CoordinationRequest

    /// Fetches one request from `GET /requests/{id}` to poll its status.
    func getRequest(_ id: String) async throws -> CoordinationRequest
}

/// `CoordinationClient` backed by the coordination server's HTTP API.
///
/// Sends `Authorization: Bearer <token>` on every `/requests*` call and maps
/// non-2xx responses (JSON `{ "error": "..." }`) to `CoordinationError`.
public final class HttpCoordinationClient: CoordinationClient {

    private let baseUrl: String
    private let token: String
    private let session: URLSession

    /// Constructs a client for [baseUrl] authenticating with [token].
    ///
    /// A trailing slash on [baseUrl] is trimmed. Supply [session] to inject a
    /// test double (for example a `URLProtocol`-backed session); when omitted
    /// the shared session is used.
    public init(baseUrl: String, token: String, session: URLSession = .shared) {
        self.baseUrl = HttpCoordinationClient.trimTrailingSlash(baseUrl)
        self.token = token
        self.session = session
    }

    public func createRequest(
        smartAccount: String,
        target: String,
        targetFn: String,
        args: [String],
        amount: String?,
        reason: Int
    ) async throws -> CoordinationRequest {
        var body: [String: Any] = [
            "smartAccount": smartAccount,
            "target": target,
            "targetFn": targetFn,
            "args": args,
            "reason": reason,
        ]
        if let amount {
            body["amount"] = amount
        }

        guard let url = URL(string: "\(baseUrl)/requests") else {
            throw CoordinationError("Invalid coordination base URL: \(baseUrl)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw CoordinationError("Failed to encode POST /requests body: \(error)")
        }

        return try await send(request, expectedStatus: 201, context: "create")
    }

    public func getRequest(_ id: String) async throws -> CoordinationRequest {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(baseUrl)/requests/\(encodedId)") else {
            throw CoordinationError("Invalid coordination base URL: \(baseUrl)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)

        return try await send(request, expectedStatus: 200, context: "poll")
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func send(
        _ request: URLRequest,
        expectedStatus: Int,
        context: String
    ) async throws -> CoordinationRequest {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let method = request.httpMethod ?? "?"
            let path = request.url?.path ?? "?"
            throw CoordinationError("\(method) \(path) failed: \(error)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw CoordinationError("\(context) returned a non-HTTP response")
        }
        guard http.statusCode == expectedStatus else {
            throw CoordinationError(
                "\(context) returned \(http.statusCode): \(HttpCoordinationClient.errorBody(data))",
                statusCode: http.statusCode
            )
        }

        do {
            return try JSONDecoder().decode(CoordinationRequest.self, from: data)
        } catch {
            throw CoordinationError("\(context) returned malformed JSON: \(error)")
        }
    }

    /// Extracts the `error` field from a JSON error body, falling back to the
    /// raw body when it is not the expected shape.
    private static func errorBody(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String {
            return error
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? "(empty body)" : raw
    }

    private static func trimTrailingSlash(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}
