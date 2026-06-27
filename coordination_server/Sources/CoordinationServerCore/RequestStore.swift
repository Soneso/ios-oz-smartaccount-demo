import Foundation

/// In-memory store of ``SmartAccountRequest``s with optional JSON-file
/// persistence.
///
/// The store is an actor, so every mutation and read is serialized: in-memory
/// state never races. When a store path is configured, each mutation writes
/// the full snapshot to the backing file before returning. The write goes to a
/// temporary file that is atomically renamed over the target, so the store
/// file is never observed in a partially written state.
public actor RequestStore {
    private let storePath: String?
    private let idGenerator: @Sendable () -> String
    private let clock: @Sendable () -> Int

    /// Records keyed by id for O(1) lookup.
    private var byId: [String: SmartAccountRequest] = [:]

    /// Insertion order of ids. Reversed when listing so newest appears first.
    private var order: [String] = []

    public init(
        storePath: String? = nil,
        idGenerator: (@Sendable () -> String)? = nil,
        clock: (@Sendable () -> Int)? = nil
    ) {
        self.storePath = storePath
        self.idGenerator = idGenerator ?? { UUID().uuidString.lowercased() }
        self.clock = clock ?? { Int(Date().timeIntervalSince1970 * 1000) }
    }

    /// Path of the backing JSON file, or `nil` when persistence is disabled.
    public var backingStorePath: String? { storePath }

    /// Loads persisted records when a store path is configured and the file
    /// exists. Safe to call once during startup.
    ///
    /// Throws ``StoreFormatError`` when the file is not a JSON array of request
    /// objects and ``ValidationError`` when a record is structurally invalid,
    /// so a corrupt store fails loudly instead of dropping data.
    public func load() throws {
        guard let path = storePath else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let text = String(decoding: data, as: UTF8.self)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let entries = decoded as? [Any] else {
            throw StoreFormatError("store file must contain a JSON array")
        }
        byId.removeAll()
        order.removeAll()
        for entry in entries {
            guard let object = entry as? [String: Any] else {
                throw StoreFormatError("store file entries must be JSON objects")
            }
            let request = try SmartAccountRequest.fromJSON(object)
            byId[request.id] = request
            order.append(request.id)
        }
    }

    /// Creates a new pending request from validated `input`, assigning the id,
    /// `createdAt`, and `pending` status. Persists before returning.
    public func create(_ input: CreateRequestInput) throws -> SmartAccountRequest {
        let request = SmartAccountRequest(
            id: idGenerator(),
            smartAccount: input.smartAccount,
            target: input.target,
            targetFn: input.targetFn,
            args: input.args,
            amount: input.amount,
            reason: input.reason,
            status: .pending,
            createdAt: clock()
        )
        byId[request.id] = request
        order.append(request.id)
        try flush()
        return request
    }

    /// Returns the request with `id`, or `nil` when absent.
    public func getById(_ id: String) -> SmartAccountRequest? {
        byId[id]
    }

    /// Returns stored requests newest-first, optionally filtered by `status`.
    public func list(status: RequestStatus? = nil) -> [SmartAccountRequest] {
        var result: [SmartAccountRequest] = []
        for id in order.reversed() {
            guard let request = byId[id] else { continue }
            if status == nil || request.status == status {
                result.append(request)
            }
        }
        return result
    }

    /// Transitions a pending request to approved, recording `resultHash` and
    /// the resolution time. Persists before returning.
    ///
    /// Throws ``NotFoundError`` when `id` is unknown and ``ConflictError``
    /// when the request is already resolved.
    public func approve(_ id: String, resultHash: String) throws -> SmartAccountRequest {
        try resolve(id, status: .approved, resultHash: resultHash, note: nil)
    }

    /// Transitions a pending request to rejected, recording the optional `note`
    /// and the resolution time. Persists before returning.
    ///
    /// Throws ``NotFoundError`` when `id` is unknown and ``ConflictError``
    /// when the request is already resolved.
    public func reject(_ id: String, note: String?) throws -> SmartAccountRequest {
        try resolve(id, status: .rejected, resultHash: nil, note: note)
    }

    private func resolve(
        _ id: String,
        status: RequestStatus,
        resultHash: String?,
        note: String?
    ) throws -> SmartAccountRequest {
        guard let existing = byId[id] else {
            throw NotFoundError("request '\(id)' not found")
        }
        if existing.isResolved {
            throw ConflictError("request '\(id)' is already \(existing.status.wireName)")
        }
        let updated = existing.resolving(
            status: status,
            resolvedAt: clock(),
            resultHash: resultHash,
            note: note
        )
        byId[id] = updated
        try flush()
        return updated
    }

    /// Writes the current snapshot to the backing file atomically.
    ///
    /// No-op when persistence is disabled. The snapshot preserves insertion
    /// order so newest-first listing survives a reload.
    private func flush() throws {
        guard let path = storePath else { return }
        let snapshot = order.compactMap { byId[$0]?.jsonObject() }
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty, !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }
}
