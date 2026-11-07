import Darwin
import Foundation

public enum AsyncCrossProcessFileLockError: Error, Sendable, Equatable {
    case invalidContainer, timedOut
}

/// FD-owned flock can span async OS callbacks without holding an NSLock on a Swift executor.
/// Contended acquisition is nonblocking and cancellation-aware. Timeout bounds WAITING only:
/// an acquired lock is never expired while its operation can still mutate external state.
/// Use a dedicated stable file, never the shared token lock; never unlink it or nest acquisition.
public struct AsyncCrossProcessFileLock: Sendable {
    private let containerURL: URL?
    private let filename: String
    private let waitingLimit: Duration
    private let onContention: @Sendable () -> Void

    public init(containerURL: URL?, filename: String, waitingLimit: Duration = .seconds(10)) {
        self.init(containerURL: containerURL, filename: filename, waitingLimit: waitingLimit, onContention: {})
    }

    init(containerURL: URL?, filename: String, waitingLimit: Duration, onContention: @escaping @Sendable () -> Void) {
        self.containerURL = containerURL; self.filename = filename; self.waitingLimit = waitingLimit; self.onContention = onContention
    }

    public func withExclusiveLock<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/"),
              !filename.contains("\\"), !filename.contains("\0") else { throw CrossProcessFileLockError.invalidFilename }
        guard let containerURL else { throw CrossProcessFileLockError.missingContainer }
        guard containerURL.isFileURL, waitingLimit > .zero else { throw AsyncCrossProcessFileLockError.invalidContainer }
        let descriptor = open(
            containerURL.appendingPathComponent(filename, isDirectory: false).path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw CrossProcessFileLockError.unavailable(errno) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw AsyncCrossProcessFileLockError.invalidContainer
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw CrossProcessFileLockError.unavailable(errno) }
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: waitingLimit)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let failure = errno
            guard failure == EWOULDBLOCK || failure == EAGAIN || failure == EINTR else {
                throw CrossProcessFileLockError.unavailable(failure)
            }
            onContention()
            try Task.checkCancellation()
            guard clock.now < deadline else { throw AsyncCrossProcessFileLockError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        // No post-operation cancellation check: the batch must finish its own confirmation/
        // compensation even if its UI consumer was cancelled during an external write.
        return try await operation()
    }
}
