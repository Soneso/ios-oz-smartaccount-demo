// CoordinationClientWireTests.swift
// SmartAccountDemoTests
//
// Copyright (c) 2026 Soneso. All rights reserved.

import Foundation
#if canImport(UIKit)
@testable import SmartAccountDemoLib
#else
@testable import SmartAccountDemoMacLib
#endif
import Testing

// ============================================================================
// MARK: - StubURLProtocol
// ============================================================================

/// `URLProtocol` stub that answers requests from an injected handler, so the
/// coordination client's wire format is exercised without a live server.
final class StubURLProtocol: URLProtocol {

    /// Handler producing a canned response. Serial test execution makes the
    /// static mutable storage safe.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Records the requests the client issued, for path / method / header
    /// assertions.
    nonisolated(unsafe) static var recorded: [URLRequest] = []

    static func reset() {
        handler = nil
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorded.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CoordinationError(message: "no stub handler"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Reads the request body whether it was set directly or moved to a stream
    /// by `URLProtocol`.
    static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// ============================================================================
// MARK: - Test helpers
// ============================================================================

private enum WireFixtures {

    static let baseURL = "https://coord.example/"
    static let token = "wire-token"

    static func makeClient() -> URLSessionCoordinationClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return URLSessionCoordinationClient(baseURL: baseURL, token: token, session: session)
    }

    static func ok(_ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://coord.example")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }

    static func error(_ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://coord.example")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    static let sampleRequest = """
    {"id":"req-1","smartAccount":"CACC","target":"CTOK","targetFn":"transfer",
     "args":["AAAA"],"amount":"10.0","reason":3016,"status":"pending","createdAt":1700000000000}
    """
}

// ============================================================================
// MARK: - Wire format
// ============================================================================

@Suite("URLSessionCoordinationClient: Wire Format", .serialized)
struct CoordinationClientWireTests {

    @Test("listPending sends a Bearer GET to /requests?status=pending and unwraps the array")
    func listPending() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            WireFixtures.ok("{\"requests\":[\(WireFixtures.sampleRequest)]}")
        }
        let client = WireFixtures.makeClient()

        let pending = try await client.listPending()

        #expect(pending.count == 1)
        #expect(pending.first?.id == "req-1")
        #expect(pending.first?.reason == 3016)
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/requests")
        #expect(request.url?.query?.contains("status=pending") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(WireFixtures.token)")
    }

    @Test("getRequest GETs /requests/{id} and decodes the bare object")
    func getRequest() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in WireFixtures.ok(WireFixtures.sampleRequest) }
        let client = WireFixtures.makeClient()

        let result = try await client.getRequest("req-1")

        #expect(result.id == "req-1")
        #expect(StubURLProtocol.recorded.first?.url?.path == "/requests/req-1")
    }

    @Test("approve POSTs the resultHash body")
    func approve() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in
            WireFixtures.ok(WireFixtures.sampleRequest.replacingOccurrences(of: "pending", with: "approved"))
        }
        let client = WireFixtures.makeClient()

        let result = try await client.approve("req-1", resultHash: "hash-xyz")

        #expect(result.status == "approved")
        let request = try #require(StubURLProtocol.recorded.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/requests/req-1/approve")
        let body = try #require(StubURLProtocol.body(of: request))
        let decoded = try #require(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(decoded["resultHash"] as? String == "hash-xyz")
    }

    @Test("non-2xx responses map to CoordinationError carrying the server error and status")
    func errorMapping() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in WireFixtures.error(409, "{\"error\":\"already resolved\"}") }
        let client = WireFixtures.makeClient()

        await #expect(throws: CoordinationError.self) {
            _ = try await client.approve("req-1", resultHash: "h")
        }
        do {
            _ = try await client.approve("req-1", resultHash: "h")
            Issue.record("expected CoordinationError")
        } catch let error as CoordinationError {
            #expect(error.statusCode == 409)
            #expect(error.message.contains("already resolved"))
        }
    }
}
