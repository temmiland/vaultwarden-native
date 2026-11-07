import Darwin
import Foundation

public enum CrossProcessFileLockPolicy: Sendable {
    case requiredContainer
    /// Explicit in-memory fixture injection only; never a fallback after a live lock failure.
    case processOnly
}

public enum CrossProcessFileLockError: Error, Sendable, Equatable {
    case unavailable(Int32)
    case missingContainer
    case invalidFilename
}

/// Synchronous persistence critical section, NOT a network/server transaction. Composition supplies
/// the entitled container and a stable leaf filename; no credential material belongs in that file.
/// Non-reentrant, including across instances: never acquire another storage lock inside a callback.
public struct CrossProcessFileLock: Sendable {
    private static let processLock = NSLock()
    private let containerURL: URL?
    private let filename: String
    private let policy: CrossProcessFileLockPolicy

    public init(containerURL: URL?, filename: String, policy: CrossProcessFileLockPolicy = .requiredContainer) {
        self.containerURL = containerURL
        self.filename = filename
        self.policy = policy
    }

    public func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        guard !filename.isEmpty, filename != ".", filename != "..",
              !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0")
        else { throw CrossProcessFileLockError.invalidFilename }
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        if case .processOnly = policy { return try operation() }
        guard let containerURL else { throw CrossProcessFileLockError.missingContainer }

        let lockURL = containerURL.appendingPathComponent(filename, isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CrossProcessFileLockError.unavailable(errno) }
        defer { close(descriptor) }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw CrossProcessFileLockError.unavailable(errno)
        }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CrossProcessFileLockError.unavailable(errno) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
