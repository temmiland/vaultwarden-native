import Foundation

/// The one auth/server transport policy. Release never permits HTTP; Debug permits literal
/// loopbacks only. URL syntax is validated independently by ServerEnvironment.
public enum ServerURLPolicy {
    public static func isPermitted(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1 ... 65_535).contains($0) }) ?? true else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http":
            #if DEBUG
                return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
            #else
                return false
            #endif
        default: return false
        }
    }
}
