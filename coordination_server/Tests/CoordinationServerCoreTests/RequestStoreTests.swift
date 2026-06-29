import Foundation
import Testing

@testable import CoordinationServerCore

private func makeInput(
    smartAccount: String = "CSMART",
    target: String = "CTARGET",
    targetFn: String = "transfer",
    args: [String] = ["AAAA", "BBBB"],
    amount: String = "10.5",
    reason: Int = 3016
) -> CreateRequestInput {
    CreateRequestInput(
        smartAccount: smartAccount,
        target: target,
        targetFn: targetFn,
        args: args,
        amount: amount,
        reason: reason
    )
}

@Suite("RequestStore CRUD")
struct RequestStoreCRUDTests {
    @Test("create assigns id, pending status, and createdAt")
    func createAssignsFields() async throws {
        let counter = Counter()
        let store = RequestStore(
            idGenerator: { "id-\(counter.next())" },
            clock: { 1_700_000_000_000 }
        )
        let created = try await store.create(makeInput())

        #expect(created.id == "id-0")
        #expect(created.status == .pending)
        #expect(created.createdAt == 1_700_000_000_000)
        #expect(created.resolvedAt == nil)
        #expect(created.resultHash == nil)
        #expect(created.note == nil)
        #expect(created.amount == "10.5")
        #expect(created.reason == 3016)
        #expect(created.args == ["AAAA", "BBBB"])
    }

    @Test("args are stored verbatim")
    func argsStoredVerbatim() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput(args: ["Zm9v", "YmFy"]))
        #expect(created.args == ["Zm9v", "YmFy"])
    }

    @Test("getById returns the request or nil")
    func getByIdReturnsOrNil() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput())
        let fetched = await store.getById(created.id)
        #expect(fetched == created)
        let missing = await store.getById("missing")
        #expect(missing == nil)
    }

    @Test("list returns newest first")
    func listNewestFirst() async throws {
        let counter = Counter()
        let store = RequestStore(idGenerator: { "id-\(counter.next())" })
        let a = try await store.create(makeInput())
        let b = try await store.create(makeInput())
        let c = try await store.create(makeInput())

        let ids = await store.list().map(\.id)
        #expect(ids == [c.id, b.id, a.id])
    }

    @Test("list filters by status")
    func listFiltersByStatus() async throws {
        let counter = Counter()
        let store = RequestStore(idGenerator: { "id-\(counter.next())" })
        let a = try await store.create(makeInput())
        let b = try await store.create(makeInput())
        _ = try await store.create(makeInput())

        _ = try await store.approve(a.id, resultHash: "hashA")
        _ = try await store.reject(b.id, note: "nope")

        let pending = await store.list(status: .pending)
        #expect(pending.count == 1)
        let approved = await store.list(status: .approved)
        #expect(approved.count == 1)
        #expect(approved[0].id == a.id)
        let rejected = await store.list(status: .rejected)
        #expect(rejected.count == 1)
        #expect(rejected[0].id == b.id)
    }
}

@Suite("RequestStore transitions")
struct RequestStoreTransitionTests {
    @Test("approve sets status, resolvedAt, and resultHash")
    func approveSetsFields() async throws {
        let store = RequestStore(clock: { 42 })
        let created = try await store.create(makeInput())
        let approved = try await store.approve(created.id, resultHash: "abc123")

        #expect(approved.status == .approved)
        #expect(approved.resolvedAt == 42)
        #expect(approved.resultHash == "abc123")
        #expect(approved.note == nil)
        let stored = await store.getById(created.id)
        #expect(stored == approved)
    }

    @Test("reject sets status, resolvedAt, and optional note")
    func rejectSetsFields() async throws {
        let store = RequestStore(clock: { 99 })
        let created = try await store.create(makeInput())
        let rejected = try await store.reject(created.id, note: "policy violation")

        #expect(rejected.status == .rejected)
        #expect(rejected.resolvedAt == 99)
        #expect(rejected.note == "policy violation")
        #expect(rejected.resultHash == nil)
    }

    @Test("reject without a note leaves note nil")
    func rejectWithoutNote() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput())
        let rejected = try await store.reject(created.id, note: nil)
        #expect(rejected.note == nil)
    }

    @Test("approve on unknown id throws NotFoundError")
    func approveUnknownThrows() async throws {
        let store = RequestStore()
        await #expect(throws: NotFoundError.self) {
            _ = try await store.approve("nope", resultHash: "h")
        }
    }

    @Test("reject on unknown id throws NotFoundError")
    func rejectUnknownThrows() async throws {
        let store = RequestStore()
        await #expect(throws: NotFoundError.self) {
            _ = try await store.reject("nope", note: nil)
        }
    }

    @Test("double approve throws ConflictError")
    func doubleApproveThrows() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput())
        _ = try await store.approve(created.id, resultHash: "h1")
        await #expect(throws: ConflictError.self) {
            _ = try await store.approve(created.id, resultHash: "h2")
        }
    }

    @Test("approving an already rejected request throws ConflictError")
    func approveAfterRejectThrows() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput())
        _ = try await store.reject(created.id, note: nil)
        await #expect(throws: ConflictError.self) {
            _ = try await store.approve(created.id, resultHash: "h")
        }
    }

    @Test("rejecting an already approved request throws ConflictError")
    func rejectAfterApproveThrows() async throws {
        let store = RequestStore()
        let created = try await store.create(makeInput())
        _ = try await store.approve(created.id, resultHash: "h")
        await #expect(throws: ConflictError.self) {
            _ = try await store.reject(created.id, note: nil)
        }
    }
}

@Suite("RequestStore persistence")
struct RequestStorePersistenceTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coord_store_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("round-trips state through the store file")
    func roundTrip() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("store.json").path

        let counter = Counter()
        let writer = RequestStore(
            storePath: path,
            idGenerator: { "id-\(counter.next())" },
            clock: { 1000 }
        )
        let a = try await writer.create(makeInput(amount: "one"))
        let b = try await writer.create(makeInput(amount: "two"))
        _ = try await writer.approve(a.id, resultHash: "tx-hash")
        _ = try await writer.reject(b.id, note: "too risky")

        #expect(FileManager.default.fileExists(atPath: path))

        let reader = RequestStore(storePath: path)
        try await reader.load()

        let loaded = await reader.list()
        #expect(loaded.count == 2)
        // Newest-first preserved across reload.
        #expect(loaded[0].id == b.id)
        #expect(loaded[1].id == a.id)

        let loadedA = try #require(await reader.getById(a.id))
        #expect(loadedA.status == .approved)
        #expect(loadedA.resultHash == "tx-hash")
        #expect(loadedA.amount == "one")

        let loadedB = try #require(await reader.getById(b.id))
        #expect(loadedB.status == .rejected)
        #expect(loadedB.note == "too risky")
    }

    @Test("writes a well-formed JSON array")
    func writesJSONArray() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("store.json").path

        let store = RequestStore(storePath: path)
        _ = try await store.create(makeInput())

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let array = try #require(decoded as? [Any])
        #expect(array.count == 1)
        #expect(array[0] is [String: Any])
    }

    @Test("load on a missing file leaves an empty store")
    func loadMissingFile() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("absent.json").path

        let store = RequestStore(storePath: path)
        try await store.load()
        let listed = await store.list()
        #expect(listed.isEmpty)
    }

    @Test("load rejects a non-array store file")
    func loadRejectsNonArray() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("bad.json").path
        try Data(#"{"not":"an array"}"#.utf8).write(to: URL(fileURLWithPath: path))

        let store = RequestStore(storePath: path)
        await #expect(throws: StoreFormatError.self) {
            try await store.load()
        }
    }
}

/// Deterministic, thread-safe counter for id generation in tests.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
