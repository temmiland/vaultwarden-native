import AutoFillContract
import Foundation

/// OS suggestions identify a saved service, not the requesting URL. Only Base Domain rules can
/// be represented by a domain identity; host/port, path, regex and never rules stay in the picker.
public enum QuickTypeIdentityPolicy {
    public static func domain(for uri: String, matchType: AutoFillURIMatchMode?) -> String? {
        guard matchType == nil || matchType == .domain, uri.utf8.count <= 2048,
              let url = URL(string: uri.contains("://") ? uri : "https://" + uri),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.hasSuffix("."),
              host.split(separator: ".").contains(where: { $0.contains(where: { !$0.isNumber }) })
        else { return nil }
        return PublicSuffixList.bundled.registrableDomain(of: host)
    }
}
