import Darwin
import Foundation

public enum SystemBootSessionError: Error, Sendable, Equatable { case unavailable }

/// Shared across app/extension processes, changes at every system boot, independent of wall time.
/// Failure denies persisted grants; never substitute a process UUID or a timestamp.
public enum SystemBootSession {
    public static func currentID() throws -> UUID {
        var bytes = [CChar](repeating: 0, count: 37)
        var size = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0,
              size == bytes.count, bytes[36] == 0,
              let id = UUID(uuidString: String(cString: bytes)) else {
            throw SystemBootSessionError.unavailable
        }
        return id
    }
}
