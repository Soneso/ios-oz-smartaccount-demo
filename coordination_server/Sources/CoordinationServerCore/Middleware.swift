import Foundation
import HTTPTypes
import Hummingbird

/// Adds permissive CORS headers to every response and answers `OPTIONS`
/// preflight directly with `204`, short-circuiting before auth.
///
/// The web demo polls this service from a browser, so cross-origin reads and
/// the bearer header must be allowed.
struct CORSMiddleware<Context: RequestContext>: RouterMiddleware {
    private static var headerFields: [(HTTPField.Name, String)] {
        [
            (HTTPField.Name("Access-Control-Allow-Origin")!, "*"),
            (HTTPField.Name("Access-Control-Allow-Methods")!, "GET, POST, OPTIONS"),
            (HTTPField.Name("Access-Control-Allow-Headers")!, "Authorization, Content-Type"),
            (HTTPField.Name("Access-Control-Max-Age")!, "86400"),
        ]
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if request.method == .options {
            var response = Response(status: .noContent)
            apply(to: &response)
            return response
        }
        var response = try await next(request, context)
        apply(to: &response)
        return response
    }

    private func apply(to response: inout Response) {
        for (name, value) in Self.headerFields {
            response.headers[name] = value
        }
    }
}

/// Requires `Authorization: Bearer <token>` on every route except `/health`.
///
/// `OPTIONS` preflight never reaches this layer because ``CORSMiddleware`` runs
/// outermost and answers it first. Token comparison is constant-time to avoid
/// leaking the token through response timing.
struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    private let expected: [UInt8]

    init(token: String) {
        self.expected = Array(token.utf8)
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if request.uri.path == "/health" {
            return try await next(request, context)
        }
        let prefix = "Bearer "
        guard let header = request.headers[.authorization], header.hasPrefix(prefix) else {
            return HTTPResponses.error(status: .unauthorized, message: "missing or malformed Authorization header")
        }
        let presented = Array(header.dropFirst(prefix.count).utf8)
        guard constantTimeEquals(expected, presented) else {
            return HTTPResponses.error(status: .unauthorized, message: "invalid bearer token")
        }
        return try await next(request, context)
    }
}

/// Translates thrown domain errors into JSON HTTP responses with the right
/// status code, and turns any unexpected error into a `500` without leaking
/// internals to the client.
///
/// Framework HTTP errors (e.g. an unmatched route, or a wrong method on a known
/// path, both of which Hummingbird's router resolves through its not-found
/// responder to a `404` raised as ``HTTPError``) are converted to the same JSON
/// `{ "error": ... }` shape and returned rather than rethrown, so they keep
/// flowing back out through the outer CORS and request-log middleware.
/// Rethrowing them would let the framework synthesise the response above those
/// layers, stripping the CORS headers the web demo needs and skipping the log.
struct ErrorMappingMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as ValidationError {
            return HTTPResponses.error(status: .badRequest, message: error.message)
        } catch let error as NotFoundError {
            return HTTPResponses.error(status: .notFound, message: error.message)
        } catch let error as ConflictError {
            return HTTPResponses.error(status: .conflict, message: error.message)
        } catch let error as HTTPError {
            return HTTPResponses.error(
                status: error.status,
                message: error.body ?? error.status.reasonPhrase
            )
        } catch {
            context.logger.error("Unhandled error: \(error)")
            return HTTPResponses.error(status: .internalServerError, message: "internal server error")
        }
    }
}

/// Logs one line per request to stdout (excluding CORS preflight, which
/// ``CORSMiddleware`` answers before this layer runs): timestamp, method, path,
/// status, and duration in milliseconds.
/// Shared formatter reused across requests instead of allocated per call.
/// `ISO8601DateFormatter` formatting is thread-safe on Apple platforms, so a
/// single instance is safe to read from concurrent request handlers. Held at
/// file scope because a generic type cannot declare a static stored property.
nonisolated(unsafe) private let requestLogTimestampFormatter = ISO8601DateFormatter()

struct RequestLogMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let start = ContinuousClock.now
        let response = try await next(request, context)
        let elapsed = ContinuousClock.now - start
        let millis = elapsed.components.seconds * 1000
            + Int64(Double(elapsed.components.attoseconds) / 1e15)
        let timestamp = requestLogTimestampFormatter.string(from: Date())
        print("\(timestamp) \(request.method.rawValue) \(request.uri.path) \(response.status.code) \(millis)ms")
        return response
    }
}

/// Length-aware constant-time byte comparison.
func constantTimeEquals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    var diff = UInt8(lhs.count == rhs.count ? 0 : 1)
    let maxCount = max(lhs.count, rhs.count)
    var index = 0
    while index < maxCount {
        let byteA = index < lhs.count ? lhs[index] : 0
        let byteB = index < rhs.count ? rhs[index] : 0
        diff |= byteA ^ byteB
        index += 1
    }
    return diff == 0
}
