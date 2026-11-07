import Darwin
import Foundation

/// A privacy-hardened URLSession transport. Its default session is ephemeral, does not persist
/// cookies or responses, and applies a credential-safe redirect policy per request.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }

    init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = makeURLRequest(request)
        let (body, response) = try await boundedResponseData(for: urlRequest, request: request)
        return try makeResponse(body: body, response: response)
    }

    public func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        try Task.checkCancellation()
        var urlRequest = makeURLRequest(request)
        urlRequest.httpBody = nil
        let collector = LimitedUploadResponseCollector(request: request)
        let uploadSession = URLSession(configuration: session.configuration, delegate: collector, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }
        let (body, response) = try await collector.upload(
            using: uploadSession,
            request: urlRequest,
            from: fileURL
        )
        return try makeResponse(body: body, response: response)
    }

    /// Downloads to a sibling staging file, applies user-only permissions, and then replaces the
    /// destination. The final path is never partially written. Callers should pass a path reserved
    /// by `SecurityStorage.SensitiveTemporaryFileStore` for sensitive transfers.
    public func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        try Task.checkCancellation()
        guard destinationURL.isFileURL else { throw HTTPFileTransferError.invalidDestination }
        var urlRequest = makeURLRequest(request)
        urlRequest.httpBody = nil
        // Cancel the actual transfer on every early exit, including rejected Content-Length and
        // oversized chunked bodies. No unbounded URLSession temporary download file is created.
        let (bytes, response) = try await session.bytes(
            for: urlRequest,
            delegate: redirectDelegate(for: request)
        )
        defer { bytes.task.cancel() }
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let headers = normalizedHeaders(httpResponse)
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw HTTPStatusError(
                response: HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, body: Data())
            )
        }
        guard response.expectedContentLength <= Int64(request.maximumResponseBytes) else {
            throw HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)
        }
        let (stagingURL, handle) = try HTTPDownloadedFileInstaller.openStagingFile(nextTo: destinationURL)
        var isOpen = true
        do {
            var count = 0
            var chunk = Data()
            chunk.reserveCapacity(64 * 1024)
            try Task.checkCancellation()
            for try await byte in bytes {
                guard count < request.maximumResponseBytes else {
                    throw HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)
                }
                count += 1
                chunk.append(byte)
                if chunk.count == 64 * 1024 {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            try Task.checkCancellation()
            if !chunk.isEmpty { try handle.write(contentsOf: chunk) }
            try handle.close()
            isOpen = false
            try HTTPDownloadedFileInstaller.install(stagingURL, at: destinationURL)
            try FileManager.default.removeItem(at: stagingURL)
        } catch {
            var cleanupFailed = false
            if isOpen {
                do { try handle.close() } catch { cleanupFailed = true }
            }
            do { try FileManager.default.removeItem(at: stagingURL) } catch { cleanupFailed = true }
            if cleanupFailed { throw HTTPFileTransferError.cleanupFailed }
            throw error
        }
        return HTTPFileResponse(statusCode: httpResponse.statusCode, headers: headers)
    }

    private func makeURLRequest(_ request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }

    private func boundedResponseData(for requestValue: URLRequest, request: HTTPRequest) async throws -> (
        Data,
        URLResponse
    ) {
        let (bytes, response) = try await session.bytes(for: requestValue, delegate: redirectDelegate(for: request))
        defer { bytes.task.cancel() }
        if response.expectedContentLength > Int64(request.maximumResponseBytes) {
            throw HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)
        }
        var body = Data()
        if response.expectedContentLength > 0 {
            body.reserveCapacity(min(Int(response.expectedContentLength), request.maximumResponseBytes))
        }
        for try await byte in bytes {
            guard body.count < request.maximumResponseBytes else {
                throw HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)
            }
            body.append(byte)
        }
        return (body, response)
    }

    private func makeResponse(body: Data, response: URLResponse) throws -> HTTPResponse {
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(statusCode: response.statusCode, headers: normalizedHeaders(response), body: body)
    }

    private func normalizedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { headers, pair in
            guard let key = pair.key as? String else { return }
            headers[key.lowercased()] = String(describing: pair.value)
        }
    }

    private func redirectDelegate(for request: HTTPRequest) -> URLSessionTaskDelegate {
        CredentialSafeRedirectDelegate(request: request)
    }
}

/// Internal seam exercises the actual filesystem publication path without a real HTTP server.
enum HTTPDownloadedFileInstaller {
    static func openStagingFile(nextTo destination: URL) throws -> (URL, FileHandle) {
        let url = destination.deletingLastPathComponent().appendingPathComponent(
            ".download-transfer-\(UUID().uuidString)"
        )
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        #if os(iOS)
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: url.path
                )
            } catch {
                do {
                    try handle.close()
                    try FileManager.default.removeItem(at: url)
                } catch { throw HTTPFileTransferError.cleanupFailed }
                throw error
            }
        #endif
        return (url, handle)
    }

    static func install(
        _ downloadURL: URL,
        at destinationURL: URL,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws {
        try checkCancellation()
        guard destinationURL.isFileURL else { throw HTTPFileTransferError.invalidDestination }
        let manager = FileManager.default
        // Inspect the link itself, including broken links. Do not follow a replaced destination.
        do {
            let attributes = try manager.attributesOfItem(atPath: destinationURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw HTTPFileTransferError.invalidDestination
            }
        } catch {
            let underlying = error as NSError
            guard underlying.domain == NSCocoaErrorDomain,
                  [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(underlying.code) else { throw error }
        }
        let directory = destinationURL.deletingLastPathComponent()
        let stagingURL = directory.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: false)
        do {
            try manager.copyItem(at: downloadURL, to: stagingURL)
            try manager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: stagingURL.path
            )
            #if os(iOS)
                try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: stagingURL.path)
            #endif
            try checkCancellation()
            if manager.fileExists(atPath: destinationURL.path) {
                _ = try manager.replaceItemAt(
                    destinationURL,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try manager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            if manager.fileExists(atPath: stagingURL.path) {
                do { try manager.removeItem(at: stagingURL) }
                catch { throw HTTPFileTransferError.cleanupFailed }
            }
            throw error
        }
    }
}

final class CredentialSafeRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let request: HTTPRequest

    init(request: HTTPRequest) {
        self.request = request
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let oldURL = task.currentRequest?.url ?? request.url
        guard let safeRequest = CredentialSafeRedirectPolicy.request(
            from: oldURL,
            redirecting: newRequest,
            original: request
        ) else {
            completionHandler(nil)
            return
        }
        completionHandler(safeRequest)
    }
}

enum CredentialSafeRedirectPolicy {
    static func request(
        from oldURL: URL, redirecting newRequest: URLRequest, original: HTTPRequest, hasFileBody: Bool = false
    ) -> URLRequest? {
        guard !hasFileBody, original.redirectPolicy == .follow, original.method == .get, original.body == nil,
              let newURL = newRequest.url,
              newRequest.httpMethod?.uppercased() == "GET",
              newRequest.httpBody == nil, newRequest.httpBodyStream == nil else { return nil }
        guard let oldScheme = URLComponents(url: oldURL, resolvingAgainstBaseURL: false)?.scheme?.lowercased(),
              let newScheme = URLComponents(url: newURL, resolvingAgainstBaseURL: false)?.scheme?.lowercased() else {
            return nil
        }
        guard ["http", "https"].contains(oldScheme), ["http", "https"].contains(newScheme),
              oldScheme != "https" || newScheme == "https" else { return nil }
        guard !Origin(url: oldURL).isEqual(to: Origin(url: newURL)) else { return newRequest }

        var safeRequest = newRequest
        for header in ["Authorization", "Proxy-Authorization", "Cookie"] {
            safeRequest.setValue(nil, forHTTPHeaderField: header)
        }
        return safeRequest
    }
}

private struct Origin: Equatable {
    let scheme: String?
    let host: String?
    let port: Int?

    init(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        scheme = components?.scheme?.lowercased()
        host = components?.host?.lowercased()
        if let port = components?.port {
            self.port = port
        } else {
            switch components?.scheme?.lowercased() {
            case "https": port = 443
            case "http": port = 80
            default: port = nil
            }
        }
    }

    func isEqual(to other: Origin) -> Bool {
        self == other
    }
}

private final class LimitedUploadResponseCollector: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate,
    @unchecked Sendable {
    private let request: HTTPRequest
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var response: URLResponse?
    private var body = Data()
    private var task: URLSessionUploadTask?
    private var isCancelled = false
    private var isFinished = false

    init(request: HTTPRequest) { self.request = request }

    func upload(
        using session: URLSession,
        request: URLRequest,
        from fileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, fromFile: fileURL)
                let canStart = lock.withLock {
                    guard !isCancelled else { return false }
                    self.continuation = continuation
                    self.task = task
                    return true
                }
                if canStart { task.resume() }
                else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let pending = lock.withLock {
            isCancelled = true
            let pending = (task, continuation)
            task = nil
            continuation = nil
            isFinished = true
            body = Data()
            response = nil
            return pending
        }
        pending.0?.cancel()
        pending.1?.resume(throwing: CancellationError())
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let oldURL = task.currentRequest?.url ?? request.url
        completionHandler(CredentialSafeRedirectPolicy.request(
            from: oldURL, redirecting: newRequest, original: request, hasFileBody: true
        ))
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard response.expectedContentLength <= Int64(request.maximumResponseBytes) else {
            finish(.failure(HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)))
            completionHandler(.cancel)
            return
        }
        let acceptsResponse = lock.withLock {
            guard !isFinished else { return false }
            self.response = response
            return true
        }
        completionHandler(acceptsResponse ? .allow : .cancel)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = lock.withLock { () -> Bool in
            guard !isFinished else { return false }
            guard data.count <= request.maximumResponseBytes - body.count else { return true }
            body.append(data)
            return false
        }
        if exceeded {
            finish(.failure(HTTPResponseBodyError.exceedsLimit(maximumBytes: request.maximumResponseBytes)))
            dataTask.cancel()
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let result = lock.withLock { () -> Result<(Data, URLResponse), any Error> in
            if let error { return .failure(error) }
            guard let response else { return .failure(URLError(.badServerResponse)) }
            return .success((body, response))
        }
        finish(result)
    }

    private func finish(_ result: Result<(Data, URLResponse), any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<(Data, URLResponse), any Error>? in
            defer {
                self.continuation = nil
                task = nil
                isFinished = true
                body = Data()
                response = nil
            }
            return self.continuation
        }
        guard let continuation else { return }
        switch result {
        case let .success(response): continuation.resume(returning: response)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }
}
