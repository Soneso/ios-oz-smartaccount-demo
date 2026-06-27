// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation
import Testing

@testable import ReferenceAgentCore

private func requestJson(
    id: String = "req-1",
    status: String = "pending",
    args: [String] = ["AAAA", "BBBB"],
    resultHash: String? = nil,
    note: String? = nil,
    resolvedAt: Int? = nil
) -> [String: Any] {
    var json: [String: Any] = [
        "id": id,
        "smartAccount": "CSMART",
        "target": "CTARGET",
        "targetFn": "transfer",
        "args": args,
        "amount": "10.5",
        "reason": 3016,
        "status": status,
        "createdAt": 1_782_485_036_185,
    ]
    if let resolvedAt { json["resolvedAt"] = resolvedAt }
    if let resultHash { json["resultHash"] = resultHash }
    if let note { json["note"] = note }
    return json
}

@Suite("CoordinationRequest decoding")
struct CoordinationRequestDecodeTests {

    private func decode(_ json: [String: Any]) throws -> CoordinationRequest {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(CoordinationRequest.self, from: data)
    }

    @Test("parses a full record, including absent optionals")
    func parsesFull() throws {
        let request = try decode(requestJson())
        #expect(request.id == "req-1")
        #expect(request.smartAccount == "CSMART")
        #expect(request.targetFn == "transfer")
        #expect(request.args == ["AAAA", "BBBB"])
        #expect(request.amount == "10.5")
        #expect(request.reason == 3016)
        #expect(request.status == "pending")
        #expect(request.resolvedAt == nil)
        #expect(request.resultHash == nil)
        #expect(request.note == nil)
        #expect(request.isResolved == false)
    }

    @Test("isResolved is true for approved and rejected")
    func isResolved() throws {
        #expect(try decode(requestJson(status: "approved")).isResolved)
        #expect(try decode(requestJson(status: "rejected")).isResolved)
    }

    @Test("a missing amount decodes as the empty string")
    func missingAmount() throws {
        var json = requestJson()
        json.removeValue(forKey: "amount")
        #expect(try decode(json).amount == "")
    }
}

@Suite("HttpCoordinationClient", .serialized)
struct HttpCoordinationClientTests {

    @Test("createRequest POSTs to /requests with the bearer token and exact body")
    func createPostsBody() async throws {
        StubURLProtocol.configure { _ in
            StubResponse(statusCode: 201, json: requestJson(args: ["AAAA"]))
        }
        defer { StubURLProtocol.reset() }

        let client = HttpCoordinationClient(
            baseUrl: "http://localhost:8787",
            token: "dev-token-change-me",
            session: StubURLProtocol.makeSession()
        )

        let created = try await client.createRequest(
            smartAccount: "CSMART",
            target: "CTARGET",
            targetFn: "transfer",
            args: ["AAAA"],
            amount: "10.5",
            reason: 3016
        )

        #expect(created.id == "req-1")
        #expect(created.status == "pending")

        let captured = try #require(StubURLProtocol.captured.first)
        #expect(captured.method == "POST")
        #expect(captured.url == "http://localhost:8787/requests")
        #expect(captured.headers["Authorization"] == "Bearer dev-token-change-me")
        #expect((captured.headers["Content-Type"] ?? "").contains("application/json"))

        let body = try #require(
            try JSONSerialization.jsonObject(with: captured.body) as? [String: Any]
        )
        #expect(body["smartAccount"] as? String == "CSMART")
        #expect(body["target"] as? String == "CTARGET")
        #expect(body["targetFn"] as? String == "transfer")
        #expect(body["args"] as? [String] == ["AAAA"])
        #expect(body["amount"] as? String == "10.5")
        #expect(body["reason"] as? Int == 3016)
    }

    @Test("createRequest omits amount from the body when nil")
    func createOmitsNilAmount() async throws {
        StubURLProtocol.configure { _ in
            StubResponse(statusCode: 201, json: requestJson())
        }
        defer { StubURLProtocol.reset() }

        let client = HttpCoordinationClient(
            baseUrl: "http://localhost:8787",
            token: "t",
            session: StubURLProtocol.makeSession()
        )

        _ = try await client.createRequest(
            smartAccount: "CSMART",
            target: "CTARGET",
            targetFn: "transfer",
            args: ["AAAA"],
            amount: nil,
            reason: 3016
        )

        let captured = try #require(StubURLProtocol.captured.first)
        let body = try #require(
            try JSONSerialization.jsonObject(with: captured.body) as? [String: Any]
        )
        #expect(body["amount"] == nil)
    }

    @Test("createRequest maps a non-201 error response to CoordinationError")
    func createMapsError() async throws {
        StubURLProtocol.configure { _ in
            StubResponse(statusCode: 400, json: ["error": "bad body"])
        }
        defer { StubURLProtocol.reset() }

        let client = HttpCoordinationClient(
            baseUrl: "http://localhost:8787",
            token: "t",
            session: StubURLProtocol.makeSession()
        )

        await #expect {
            try await client.createRequest(
                smartAccount: "CSMART",
                target: "CTARGET",
                targetFn: "transfer",
                args: [],
                amount: nil,
                reason: 3016
            )
        } throws: { error in
            guard let coordination = error as? CoordinationError else { return false }
            return coordination.statusCode == 400 && coordination.message.contains("bad body")
        }
    }

    @Test("getRequest GETs /requests/{id} with the bearer token and trims trailing slash")
    func getRequestSucceeds() async throws {
        StubURLProtocol.configure { _ in
            StubResponse(
                statusCode: 200,
                json: requestJson(status: "approved", resultHash: "RESULTHASH", resolvedAt: 1_782_485_040_000)
            )
        }
        defer { StubURLProtocol.reset() }

        // Trailing slash on the base URL must be trimmed.
        let client = HttpCoordinationClient(
            baseUrl: "http://localhost:8787/",
            token: "tok",
            session: StubURLProtocol.makeSession()
        )

        let request = try await client.getRequest("req-1")
        #expect(request.status == "approved")
        #expect(request.resultHash == "RESULTHASH")

        let captured = try #require(StubURLProtocol.captured.first)
        #expect(captured.method == "GET")
        #expect(captured.url == "http://localhost:8787/requests/req-1")
        #expect(captured.headers["Authorization"] == "Bearer tok")
    }

    @Test("getRequest maps a 404 to CoordinationError")
    func getMaps404() async throws {
        StubURLProtocol.configure { _ in
            StubResponse(statusCode: 404, json: ["error": "not found"])
        }
        defer { StubURLProtocol.reset() }

        let client = HttpCoordinationClient(
            baseUrl: "http://localhost:8787",
            token: "t",
            session: StubURLProtocol.makeSession()
        )

        await #expect {
            try await client.getRequest("missing")
        } throws: { error in
            (error as? CoordinationError)?.statusCode == 404
        }
    }
}
