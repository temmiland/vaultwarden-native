import Data
import Domain
import Foundation
@testable import Networking
import Testing

@Suite(.timeLimit(.minutes(1)))
struct HTTPUploadCancellationTests {
    @Test
    func cancelledCallerDoesNotStartAnUpload() async throws {
        let fixture = PausedUpload()
        defer { PausedUploadProtocol.registry.remove(fixture.id) }
        let transport = makeTransport()
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.upload(fixture.request, fromFile: file)
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(fixture.startCount == 0)
    }

    @Test
    func cancellationStopsTheUnderlyingUploadWithoutWaitingForAServerResponse() async throws {
        let fixture = PausedUpload()
        defer { PausedUploadProtocol.registry.remove(fixture.id) }
        let transport = makeTransport()
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let operation = Task { try await transport.upload(fixture.request, fromFile: file) }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        var stopped = fixture.stopped.makeAsyncIterator()
        _ = await stopped.next()
        #expect(fixture.startCount == 1)
    }

    @Test
    func cancelledDownloadStopsTransportAndLeavesTheDestinationUnchanged() async throws {
        let fixture = PausedUpload()
        defer { PausedUploadProtocol.registry.remove(fixture.id) }
        let transport = makeTransport()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result")
        let old = Foundation.Data("old".utf8)
        try old.write(to: destination)
        var request = fixture.request
        request.method = .get
        let downloadRequest = request
        let operation = Task { try await transport.download(downloadRequest, to: destination) }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        operation.cancel()
        do {
            _ = try await operation.value
            Issue.record("Cancelled download returned a file")
        } catch is CancellationError {} catch let error as URLError {
            #expect(error.code == .cancelled)
        }
        var stopped = fixture.stopped.makeAsyncIterator()
        _ = await stopped.next()
        #expect(try Foundation.Data(contentsOf: destination) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["result"])
    }

    @Test
    func lockCancelsTheActualUploadTransport() async throws {
        let fixture = PausedUpload()
        defer { PausedUploadProtocol.registry.remove(fixture.id) }
        let account = AccountSession(
            accountID: AccountID(rawValue: "synthetic"), email: "synthetic@example.invalid",
            environment: try ServerEnvironment(baseURL: URL(string: "https://fixture.example.com")!)
        )
        let runtime = SessionRuntime(account: account, resource: AuthResourceFixture(), tokens: UploadTokens())
        let client = SessionHTTPClient(runtime: runtime, base: makeTransport())
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let operation = Task { try await client.upload(fixture.request, fromFile: file) }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        await runtime.revoke(.lock)
        await #expect(throws: CancellationError.self) { try await operation.value }
        var stopped = fixture.stopped.makeAsyncIterator()
        _ = await stopped.next()
        #expect(throws: CancellationError.self) { try runtime.checkAccess() }
    }

    private func makeTransport() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PausedUploadProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Foundation.Data("synthetic upload".utf8).write(to: url)
        return url
    }
}

private actor UploadTokens: SessionTokenProviding {
    func getAccessToken() async -> String? { nil }
    func revoke() async {}
}

/// Only registry and count are shared mutable state, both protected by their own locks. Streams
/// are buffered signals, so correctness never depends on sleeps or on which task reaches next first.
private final class PausedUpload: @unchecked Sendable {
    let id = UUID().uuidString
    let started: AsyncStream<Void>
    let stopped: AsyncStream<Void>
    private let startSignal: AsyncStream<Void>.Continuation
    private let stopSignal: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var starts = 0
    var startCount: Int { lock.withLock { starts } }
    var request: HTTPRequest {
        HTTPRequest(url: URL(string: "https://paused-upload.example.invalid/\(id)")!, method: .post)
    }

    init() {
        (started, startSignal) = AsyncStream.makeStream()
        (stopped, stopSignal) = AsyncStream.makeStream()
        PausedUploadProtocol.registry.add(self)
    }

    func didStart() { lock.withLock { starts += 1 }; startSignal.yield(()) }
    func didStop() { stopSignal.yield(()) }
}

private final class UploadFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: PausedUpload] = [:]
    func add(_ fixture: PausedUpload) { lock.withLock { fixtures[fixture.id] = fixture } }
    func remove(_ id: String) { lock.withLock { _ = fixtures.removeValue(forKey: id) } }
    func lookup(_ id: String) -> PausedUpload? { lock.withLock { fixtures[id] } }
}

private final class PausedUploadProtocol: URLProtocol, @unchecked Sendable {
    static let registry = UploadFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "paused-upload.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.registry.lookup(request.url!.lastPathComponent)?.didStart() }
    override func stopLoading() { Self.registry.lookup(request.url!.lastPathComponent)?.didStop() }
}
