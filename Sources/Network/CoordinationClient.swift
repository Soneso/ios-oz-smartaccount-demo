// CoordinationClient.swift
// SmartAccountDemo
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation

// ============================================================================
// MARK: - CoordinationClientType
// ============================================================================

/// Inbox-facing subset of the coordination server's REST contract.
///
/// The coordination server brokers policy-rejected smart-account calls between
/// the autonomous reference agent and this demo's approval inbox. The agent
/// posts a rejected call (`POST /requests`); this client implements only the
/// inbox side: listing pending requests, fetching one, approving (reporting a
/// transaction hash), and rejecting.
///
/// Behind a protocol so the approval-inbox flow and the pending-count poller can
/// be unit-tested against a fake, without a live server or network access.
public protocol CoordinationClientType: Sendable {

    /// Lists every pending request via `GET /requests?status=pending`,
    /// newest-first.
    func listPending() async throws -> [CoordinationRequest]

    /// Fetches one request via `GET /requests/{id}`.
    func getRequest(_ id: String) async throws -> CoordinationRequest

    /// Approves a pending request via `POST /requests/{id}/approve` with
    /// `{ "resultHash": <hash> }`. Returns the updated record.
    func approve(_ id: String, resultHash: String) async throws -> CoordinationRequest

    /// Rejects a pending request via `POST /requests/{id}/reject` with an
    /// optional `{ "note": <text> }` body. Returns the updated record.
    func reject(_ id: String, note: String?) async throws -> CoordinationRequest
}

// ============================================================================
// MARK: - URLSessionCoordinationClient
// ============================================================================

/// ``CoordinationClientType`` backed by the coordination server's HTTP API.
///
/// Sends `Authorization: Bearer <token>` on every `/requests*` call and maps
/// non-2xx responses (JSON `{ "error": "..." }`) to ``CoordinationError``. The
/// `URLSession` is injectable so tests can install a `URLProtocol` stub.
public struct URLSessionCoordinationClient: CoordinationClientType {

    private let baseURL: String
    private let token: String
    private let session: URLSession

    /// Creates a client for `baseURL` authenticating with `token`.
    ///
    /// A trailing slash on `baseURL` is trimmed. Supply `session` to inject a
    /// test double; when omitted `URLSession.shared` is used.
    public init(baseURL: String, token: String, session: URLSession = .shared) {
        self.baseURL = Self.trimTrailingSlash(baseURL)
        self.token = token
        self.session = session
    }

    // -------------------------------------------------------------------------
    // MARK: - Endpoints
    // -------------------------------------------------------------------------

    public func listPending() async throws -> [CoordinationRequest] {
        let url = try makeURL(
            path: "/requests",
            query: [URLQueryItem(name: "status", value: CoordinationRequest.statusPending)]
        )
        let data = try await send(
            makeRequest(url: url, method: "GET"),
            context: "list"
        )
        do {
            return try JSONDecoder().decode(CoordinationRequestList.self, from: data).requests
        } catch {
            throw CoordinationError(message: "list returned malformed JSON: \(error)")
        }
    }

    public func getRequest(_ id: String) async throws -> CoordinationRequest {
        let url = try makeURL(path: "/requests/\(encodePathSegment(id))")
        let data = try await send(makeRequest(url: url, method: "GET"), context: "get")
        return try decodeRequest(data, context: "get")
    }

    public func approve(_ id: String, resultHash: String) async throws -> CoordinationRequest {
        let url = try makeURL(path: "/requests/\(encodePathSegment(id))/approve")
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try encodeBody(CoordinationApproveBody(resultHash: resultHash))
        let data = try await send(request, context: "approve")
        return try decodeRequest(data, context: "approve")
    }

    public func reject(_ id: String, note: String?) async throws -> CoordinationRequest {
        let url = try makeURL(path: "/requests/\(encodePathSegment(id))/reject")
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try encodeBody(CoordinationRejectBody(note: note))
        let data = try await send(request, context: "reject")
        return try decodeRequest(data, context: "reject")
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: request construction
    // -------------------------------------------------------------------------

    private func makeURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw CoordinationError(message: "Invalid coordination URL: \(baseURL + path)")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw CoordinationError(message: "Invalid coordination URL components for \(path)")
        }
        return url
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func encodeBody<T: Encodable>(_ body: T) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw CoordinationError(message: "Failed to encode request body: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: transport
    // -------------------------------------------------------------------------

    /// Sends `request`, validating the HTTP status is 2xx and mapping any error
    /// body (`{ "error": "..." }`) to a ``CoordinationError``.
    private func send(_ request: URLRequest, context: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CoordinationError(message: "\(context) request failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CoordinationError(message: "\(context) returned a non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw CoordinationError(
                message: "\(context) returned \(http.statusCode): \(Self.errorBody(data))",
                statusCode: http.statusCode
            )
        }
        return data
    }

    private func decodeRequest(_ data: Data, context: String) throws -> CoordinationRequest {
        do {
            return try JSONDecoder().decode(CoordinationRequest.self, from: data)
        } catch {
            throw CoordinationError(message: "\(context) returned malformed JSON: \(error)")
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Private: helpers
    // -------------------------------------------------------------------------

    /// Extracts the `error` field from a JSON error body, falling back to the
    /// raw body when it is not the expected shape.
    private static func errorBody(_ data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(CoordinationErrorBody.self, from: data) {
            return decoded.error
        }
        if data.isEmpty { return "(empty body)" }
        return String(decoding: data, as: UTF8.self)
    }

    private func encodePathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func trimTrailingSlash(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}
