import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// Maximum request body the coordination API will buffer. The payloads are
/// small JSON objects; this guards against unbounded reads.
private let maxBodySize = 1 << 20

/// Builds the fully wired router: CORS, request logging, error mapping, and
/// bearer auth around the routed endpoints.
///
/// Middleware order (outermost first): CORS so every response — including
/// `401` and `500` — carries CORS headers and preflight is answered before
/// auth; logging; error mapping; then auth guarding the routes.
public func buildRouter(store: RequestStore, token: String) -> Router<BasicRequestContext> {
    let router = Router()
    router.add(middleware: CORSMiddleware())
    router.add(middleware: RequestLogMiddleware())
    router.add(middleware: ErrorMappingMiddleware())
    router.add(middleware: BearerAuthMiddleware(token: token))

    router.get("/health") { _, _ in
        HTTPResponses.json(status: .ok, object: ["status": "ok"])
    }

    router.post("/requests") { request, context in
        let body = try await readJSONObject(request, allowEmpty: false)
        let input = try CreateRequestInput.fromJSON(body)
        let created = try await store.create(input)
        return HTTPResponses.json(status: .created, object: created.jsonObject())
    }

    router.get("/requests") { request, _ in
        let status: RequestStatus?
        if let raw = request.uri.queryParameters["status"] {
            status = try RequestStatus.fromWire(String(raw))
        } else {
            status = nil
        }
        let requests = await store.list(status: status)
        return HTTPResponses.json(
            status: .ok,
            object: ["requests": requests.map { $0.jsonObject() }]
        )
    }

    router.get("/requests/:id") { _, context in
        let id = try requireParameter(context, "id")
        guard let found = await store.getById(id) else {
            throw NotFoundError("request '\(id)' not found")
        }
        return HTTPResponses.json(status: .ok, object: found.jsonObject())
    }

    router.post("/requests/:id/approve") { request, context in
        let id = try requireParameter(context, "id")
        let body = try await readJSONObject(request, allowEmpty: false)
        guard let resultHash = body["resultHash"] as? String, !resultHash.isEmpty else {
            throw ValidationError("field 'resultHash' must be a non-empty string")
        }
        let updated = try await store.approve(id, resultHash: resultHash)
        return HTTPResponses.json(status: .ok, object: updated.jsonObject())
    }

    router.post("/requests/:id/reject") { request, context in
        let id = try requireParameter(context, "id")
        let body = try await readJSONObject(request, allowEmpty: true)
        let note = try JSONField.optionalString(body, "note")
        let updated = try await store.reject(id, note: note)
        return HTTPResponses.json(status: .ok, object: updated.jsonObject())
    }

    return router
}

/// Builds a Hummingbird application bound to `0.0.0.0:<port>` serving the
/// coordination router.
public func buildApplication(
    store: RequestStore,
    token: String,
    port: Int
) -> some ApplicationProtocol {
    let router = buildRouter(store: store, token: token)
    return Application(
        router: router,
        configuration: ApplicationConfiguration(
            address: .hostname("0.0.0.0", port: port),
            serverName: "coordination-server"
        )
    )
}

/// Extracts a required path parameter, throwing ``NotFoundError`` when absent.
private func requireParameter(_ context: BasicRequestContext, _ name: String) throws -> String {
    guard let value = context.parameters.get(name), !value.isEmpty else {
        throw NotFoundError("request '' not found")
    }
    return value
}

/// Reads and decodes a JSON object body.
///
/// When `allowEmpty` is true an empty body yields an empty object (used by
/// reject, whose `note` is optional). Throws ``ValidationError`` on a
/// non-object or malformed JSON body.
private func readJSONObject(_ request: Request, allowEmpty: Bool) async throws -> [String: Any] {
    let buffer = try await request.body.collect(upTo: maxBodySize)
    let data = Data(buffer.readableBytesView)
    let text = String(decoding: data, as: UTF8.self)
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if allowEmpty {
            return [:]
        }
        throw ValidationError("request body must be a JSON object")
    }
    let decoded: Any
    do {
        decoded = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ValidationError("request body is not valid JSON")
    }
    guard let object = decoded as? [String: Any] else {
        throw ValidationError("request body must be a JSON object")
    }
    return object
}
