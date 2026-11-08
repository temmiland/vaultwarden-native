import Darwin
import Foundation

public enum SharedClockSessionError: Error, Sendable, Equatable {
    case unavailable
    case invalidState
    case systemFailure(Int32)
}

/// A live comparison domain for persisted monotonic deadlines, NOT an operating-system boot ID.
/// A kernel-held shared file lock proves that at least one participating process stayed alive.
/// Losing every participant (including any reboot) rotates the identifier before old grants can
/// be read. No wall clock, uptime estimate, private sysctl, or recreation of an old lease is used.
public enum SharedClockSession {
    private static let registry = SharedClockSessionRegistry()

    public static func currentID(containerURL: URL) throws -> UUID {
        try registry.currentID(containerURL: containerURL)
    }
}

/// Separate instances model independent processes in tests; descriptors are retained for the
/// instance lifetime. The live singleton retains one anchor per entitled App Group.
final class SharedClockSessionRegistry: @unchecked Sendable {
    private struct Lease {
        let id: UUID
        let descriptor: Int32
    }

    private let mutex = NSLock()
    private var leases: [String: Lease] = [:]

    deinit { for lease in leases.values { close(lease.descriptor) } }

    func currentID(containerURL: URL) throws -> UUID {
        mutex.lock()
        defer { mutex.unlock() }
        guard containerURL.isFileURL else { throw SharedClockSessionError.unavailable }
        // Lock order: token-store lock -> this registry -> clock bootstrap lock. Nothing under
        // this lock acquires a token-store lock. It deliberately does not recurse into the
        // global process mutex used by CrossProcessFileLock.
        let bootstrap = containerURL.appendingPathComponent(".vaultwarden-clock-session.lock")
        let lockFD = open(bootstrap.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw SharedClockSessionError.systemFailure(errno) }
        defer { close(lockFD) }
        try validate(lockFD)
        guard flock(lockFD, LOCK_EX) == 0 else { throw SharedClockSessionError.systemFailure(errno) }
        defer { flock(lockFD, LOCK_UN) }

        let key = containerURL.standardizedFileURL.path
        let record = containerURL.appendingPathComponent(".vaultwarden-clock-session.id")
        let previousID = try readID(record)
        if let previousID, let joined = try join(previousID, in: containerURL) {
            if let old = leases.updateValue(Lease(id: previousID, descriptor: joined), forKey: key) {
                close(old.descriptor)
            }
            return previousID
        }

        let id = UUID()
        let file = leaseURL(id, in: containerURL)
        let fd = open(file.path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SharedClockSessionError.systemFailure(errno) }
        var retained = false
        defer {
            if !retained { close(fd); unlink(file.path) }
        }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { throw SharedClockSessionError.systemFailure(errno) }
        try Data(id.uuidString.utf8).write(to: record, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: record.path)
        let old = leases.updateValue(Lease(id: id, descriptor: fd), forKey: key)
        retained = true
        if let old { close(old.descriptor) }
        if let previousID { unlink(leaseURL(previousID, in: containerURL).path) }
        return id
    }

    private func join(_ id: UUID, in container: URL) throws -> Int32? {
        let fd = open(leaseURL(id, in: container).path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw SharedClockSessionError.systemFailure(errno)
        }
        var retained = false
        defer { if !retained { close(fd) } }
        try validate(fd)
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // No live anchor remains. NEVER turn this persisted identifier into a new anchor.
            flock(fd, LOCK_UN)
            return nil
        }
        let failure = errno
        guard failure == EWOULDBLOCK else { throw SharedClockSessionError.systemFailure(failure) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { throw SharedClockSessionError.systemFailure(errno) }
        retained = true
        return fd
    }

    private func readID(_ file: URL) throws -> UUID? {
        let fd = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw SharedClockSessionError.systemFailure(errno)
        }
        defer { close(fd) }
        try validate(fd)
        var bytes = [UInt8](repeating: 0, count: 37)
        let count = read(fd, &bytes, bytes.count)
        guard count >= 0 else { throw SharedClockSessionError.systemFailure(errno) }
        guard count == 36 else { return nil }
        return UUID(uuidString: String(decoding: bytes.prefix(count), as: UTF8.self))
    }

    private func validate(_ fd: Int32) throws {
        var metadata = stat()
        guard fstat(fd, &metadata) == 0 else { throw SharedClockSessionError.systemFailure(errno) }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == geteuid(), metadata.st_nlink == 1 else {
            throw SharedClockSessionError.invalidState
        }
    }

    private func leaseURL(_ id: UUID, in container: URL) -> URL {
        container.appendingPathComponent(".vaultwarden-clock-\(id.uuidString).lease")
    }
}
