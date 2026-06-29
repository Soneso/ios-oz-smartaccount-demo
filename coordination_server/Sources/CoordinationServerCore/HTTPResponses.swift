import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// JSON serialization helpers that build Hummingbird responses with the exact
/// content type and body shape required by the wire contract.
enum HTTPResponses {
    private static let jsonContentType = "application/json; charset=utf-8"

    /// Builds a JSON response from a serializable object (`[String: Any]` or
    /// `[Any]`).
    static func json(status: HTTPResponse.Status, object: Any) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = jsonContentType
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
    }

    /// Builds a JSON error response of the shape `{ "error": "..." }`.
    static func error(status: HTTPResponse.Status, message: String) -> Response {
        json(status: status, object: ["error": message])
    }
}
