import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing

@testable import CoordinationServerCore

private let token = "test-token-123"

private func authHeaders() -> HTTPFields {
    var headers = HTTPFields()
    headers[.authorization] = "Bearer \(token)"
    headers[.contentType] = "application/json"
    return headers
}

private func jsonBody(_ object: [String: Any]) -> ByteBuffer {
    let data = try! JSONSerialization.data(withJSONObject: object)
    var buffer = ByteBuffer()
    buffer.writeBytes(data)
    return buffer
}

private func rawBody(_ string: String) -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeBytes(Array(string.utf8))
    return buffer
}

private func decode(_ response: TestResponse) -> [String: Any] {
    let data = Data(response.body.readableBytesView)
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

private func createBody(
    smartAccount: String = "CSMART",
    target: String = "CTARGET",
    targetFn: String = "transfer",
    args: [String] = ["AAAA", "BBBB"],
    amount: Any? = "10.5",
    reason: Any = 3016
) -> [String: Any] {
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
    return body
}

private func makeApp(store: RequestStore = RequestStore()) -> some ApplicationProtocol {
    buildApplication(store: store, token: token, port: 0)
}

private func createRequest(_ client: some TestClientProtocol) async throws -> String {
    try await client.execute(
        uri: "/requests",
        method: .post,
        headers: authHeaders(),
        body: jsonBody(createBody())
    ) { response in
        decode(response)["id"] as! String
    }
}

@Suite("health")
struct HealthTests {
    @Test("returns ok without auth")
    func healthOk() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(decode(response)["status"] as? String == "ok")
            }
        }
    }
}

@Suite("auth")
struct AuthTests {
    @Test("rejects a missing Authorization header with 401")
    func missingHeader() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/requests", method: .get) { response in
                #expect(response.status == .unauthorized)
                #expect(decode(response)["error"] is String)
            }
        }
    }

    @Test("rejects a wrong bearer token with 401")
    func wrongToken() async throws {
        try await makeApp().test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Bearer wrong"
            try await client.execute(uri: "/requests", method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("rejects a non-Bearer scheme with 401")
    func nonBearerScheme() async throws {
        try await makeApp().test(.router) { client in
            var headers = HTTPFields()
            headers[.authorization] = "Basic \(token)"
            try await client.execute(uri: "/requests", method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("accepts the configured bearer token")
    func acceptsToken() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/requests", method: .get, headers: authHeaders()) { response in
                #expect(response.status == .ok)
            }
        }
    }
}

@Suite("POST /requests")
struct CreateRequestTests {
    @Test("creates a pending request and returns 201 with the full object")
    func createsPending() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(createBody())
            ) { response in
                #expect(response.status == .created)
                let body = decode(response)
                #expect(body["id"] is String)
                #expect((body["id"] as? String)?.isEmpty == false)
                #expect(body["status"] as? String == "pending")
                #expect(body["createdAt"] is Int || body["createdAt"] is NSNumber)
                #expect(body["resolvedAt"] is NSNull)
                #expect(body["resultHash"] is NSNull)
                #expect(body["note"] is NSNull)
                #expect(body["smartAccount"] as? String == "CSMART")
                #expect(body["targetFn"] as? String == "transfer")
                #expect(body["args"] as? [String] == ["AAAA", "BBBB"])
                #expect((body["reason"] as? NSNumber)?.intValue == 3016)
            }
        }
    }

    @Test("assigns a uuid v4 id")
    func assignsUUIDv4() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(createBody())
            ) { response in
                let id = decode(response)["id"] as! String
                let pattern =
                    "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
                #expect(id.range(of: pattern, options: .regularExpression) != nil, "id was \(id)")
            }
        }
    }

    @Test("defaults amount to an empty string when omitted")
    func defaultsAmount() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(createBody(amount: nil))
            ) { response in
                #expect(decode(response)["amount"] as? String == "")
            }
        }
    }

    @Test("ignores client-supplied id/status/createdAt")
    func ignoresServerAssignedFields() async throws {
        try await makeApp().test(.router) { client in
            var body = createBody()
            body["id"] = "client-id"
            body["status"] = "approved"
            body["createdAt"] = 1
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(body)
            ) { response in
                let created = decode(response)
                #expect(created["id"] as? String != "client-id")
                #expect(created["status"] as? String == "pending")
                #expect((created["createdAt"] as? NSNumber)?.intValue != 1)
            }
        }
    }

    @Test("400 on a malformed JSON body")
    func malformedJSON() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: rawBody("{not json")
            ) { response in
                #expect(response.status == .badRequest)
                #expect(decode(response)["error"] is String)
            }
        }
    }

    @Test("400 when a required field is missing")
    func missingRequiredField() async throws {
        try await makeApp().test(.router) { client in
            var body = createBody()
            body.removeValue(forKey: "targetFn")
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(body)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("400 when reason is not an integer")
    func reasonNotInteger() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(createBody(reason: "oops"))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("400 when args contains a non-string element")
    func argsNonStringElement() async throws {
        try await makeApp().test(.router) { client in
            var body = createBody()
            body["args"] = ["ok", 5]
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(body)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("400 when a required string field is empty")
    func emptyRequiredString() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(createBody(smartAccount: ""))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }
}

@Suite("GET /requests")
struct ListRequestsTests {
    @Test("lists newest first")
    func listsNewestFirst() async throws {
        try await makeApp().test(.router) { client in
            let first = try await createRequest(client)
            let second = try await createRequest(client)
            try await client.execute(uri: "/requests", method: .get, headers: authHeaders()) { response in
                let list = decode(response)["requests"] as! [[String: Any]]
                #expect(list.count == 2)
                #expect(list.first?["id"] as? String == second)
                #expect(list.last?["id"] as? String == first)
            }
        }
    }

    @Test("filters by status")
    func filtersByStatus() async throws {
        try await makeApp().test(.router) { client in
            let pendingId = try await createRequest(client)
            let toApprove = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(toApprove)/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["resultHash": "h"])
            ) { _ in }

            try await client.execute(
                uri: "/requests?status=pending",
                method: .get,
                headers: authHeaders()
            ) { response in
                let list = decode(response)["requests"] as! [[String: Any]]
                #expect(list.count == 1)
                #expect(list.first?["id"] as? String == pendingId)
            }

            try await client.execute(
                uri: "/requests?status=approved",
                method: .get,
                headers: authHeaders()
            ) { response in
                let list = decode(response)["requests"] as! [[String: Any]]
                #expect(list.count == 1)
                #expect(list.first?["id"] as? String == toApprove)
            }
        }
    }

    @Test("400 on an unknown status filter")
    func unknownStatusFilter() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests?status=bogus",
                method: .get,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }
}

@Suite("GET /requests/{id}")
struct GetRequestTests {
    @Test("returns the request")
    func returnsRequest() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(uri: "/requests/\(id)", method: .get, headers: authHeaders()) { response in
                #expect(response.status == .ok)
                #expect(decode(response)["id"] as? String == id)
            }
        }
    }

    @Test("404 for an unknown id")
    func unknownId() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests/does-not-exist",
                method: .get,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .notFound)
                #expect(decode(response)["error"] is String)
            }
        }
    }
}

@Suite("POST /requests/{id}/approve")
struct ApproveRequestTests {
    @Test("approves a pending request and returns the updated object")
    func approvesPending() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["resultHash": "tx-hash-xyz"])
            ) { response in
                #expect(response.status == .ok)
                let body = decode(response)
                #expect(body["status"] as? String == "approved")
                #expect(body["resultHash"] as? String == "tx-hash-xyz")
                #expect((body["resolvedAt"] as? NSNumber) != nil)
            }
        }
    }

    @Test("404 for an unknown id")
    func unknownId() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests/missing/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["resultHash": "h"])
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("409 when already resolved")
    func doubleResolve() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["resultHash": "h1"])
            ) { _ in }
            try await client.execute(
                uri: "/requests/\(id)/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["resultHash": "h2"])
            ) { response in
                #expect(response.status == .conflict)
            }
        }
    }

    @Test("400 when resultHash is missing")
    func missingResultHash() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/approve",
                method: .post,
                headers: authHeaders(),
                body: jsonBody([:])
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }
}

@Suite("POST /requests/{id}/reject")
struct RejectRequestTests {
    @Test("rejects a pending request with a note")
    func rejectsWithNote() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/reject",
                method: .post,
                headers: authHeaders(),
                body: jsonBody(["note": "looks malicious"])
            ) { response in
                #expect(response.status == .ok)
                let body = decode(response)
                #expect(body["status"] as? String == "rejected")
                #expect(body["note"] as? String == "looks malicious")
                #expect((body["resolvedAt"] as? NSNumber) != nil)
            }
        }
    }

    @Test("rejects with an empty body (note optional)")
    func rejectsEmptyBody() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/reject",
                method: .post,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .ok)
                #expect(decode(response)["note"] is NSNull)
            }
        }
    }

    @Test("404 for an unknown id")
    func unknownId() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/requests/missing/reject",
                method: .post,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("409 when already resolved")
    func doubleResolve() async throws {
        try await makeApp().test(.router) { client in
            let id = try await createRequest(client)
            try await client.execute(
                uri: "/requests/\(id)/reject",
                method: .post,
                headers: authHeaders()
            ) { _ in }
            try await client.execute(
                uri: "/requests/\(id)/reject",
                method: .post,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .conflict)
            }
        }
    }
}

@Suite("CORS")
struct CORSTests {
    @Test("preflight returns 204 with CORS headers and no auth")
    func preflight() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/requests", method: .options) { response in
                #expect(response.status == .noContent)
                #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
                let methods = response.headers[HTTPField.Name("Access-Control-Allow-Methods")!] ?? ""
                #expect(methods.contains("POST"))
                let allowedHeaders = response.headers[HTTPField.Name("Access-Control-Allow-Headers")!] ?? ""
                #expect(allowedHeaders.contains("Authorization"))
            }
        }
    }

    @Test("CORS headers are present on normal responses")
    func normalResponse() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
            }
        }
    }

    @Test("CORS headers are present on 401 responses")
    func unauthorizedResponse() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(uri: "/requests", method: .get) { response in
                #expect(response.status == .unauthorized)
                #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
            }
        }
    }

    @Test("an unmatched route returns 404 with CORS headers and a JSON error body")
    func unknownRoute() async throws {
        try await makeApp().test(.router) { client in
            // Authenticate so the request passes the bearer guard and reaches the
            // router, where an unmatched path raises Hummingbird's framework 404.
            // That framework error must still be mapped to the JSON error shape
            // and carry CORS headers, like every other response.
            try await client.execute(
                uri: "/no-such-route",
                method: .get,
                headers: authHeaders()
            ) { response in
                #expect(response.status == .notFound)
                #expect(response.headers[HTTPField.Name("Access-Control-Allow-Origin")!] == "*")
                #expect(decode(response)["error"] is String)
                #expect((decode(response)["error"] as? String)?.isEmpty == false)
            }
        }
    }
}
