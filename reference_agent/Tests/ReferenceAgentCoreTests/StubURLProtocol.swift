// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation

/// A request captured by `StubURLProtocol`, including the materialized HTTP body.
struct CapturedRequest: Sendable {
    let method: String
    let url: String
    let headers: [String: String]
    let body: Data
}

/// A canned HTTP response returned by the stub.
struct StubResponse: Sendable {
    let statusCode: Int
    let body: Data

    init(statusCode: Int, json: Any) {
        self.statusCode = statusCode
        self.body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

/// In-process `URLProtocol` stub for exercising `HttpCoordinationClient` wire
/// format without a network. Configure a responder and inspect the captured
/// requests after the client call.
///
/// Process-global state is guarded by a lock; the coordination suite is
/// serialized so configured responders never overlap.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) private static var responder: (@Sendable (CapturedRequest) -> StubResponse)?
    nonisolated(unsafe) private static var capturedRequests: [CapturedRequest] = []
    private static let lock = NSLock()

    /// Installs [responder] and clears any previously captured requests.
    static func configure(_ responder: @escaping @Sendable (CapturedRequest) -> StubResponse) {
        lock.withLock {
            self.responder = responder
            self.capturedRequests = []
        }
    }

    /// Removes the responder and clears captured requests.
    static func reset() {
        lock.withLock {
            responder = nil
            capturedRequests = []
        }
    }

    /// The requests observed since the last `configure`.
    static var captured: [CapturedRequest] {
        lock.withLock { capturedRequests }
    }

    /// Builds a `URLSession` routed exclusively through this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let captured = CapturedRequest(
            method: request.httpMethod ?? "",
            url: request.url?.absoluteString ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: StubURLProtocol.bodyData(from: request)
        )

        let responder = StubURLProtocol.lock.withLock {
            StubURLProtocol.capturedRequests.append(captured)
            return StubURLProtocol.responder
        }

        guard let responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let stub = responder(captured)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Materializes the request body, reading from the body stream when the
    /// session has converted `httpBody` into a stream.
    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
