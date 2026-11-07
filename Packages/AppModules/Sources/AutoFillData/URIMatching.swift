import AutoFillContract
import Foundation

/// One synchronous URI scan's shared CPU budget and compiled-expression cache. The context never
/// survives the query, so patterns are reused only inside that query and are discarded afterward.
final class URIQueryMatchingContext {
    private let deadline: ContinuousClock.Instant
    private let now: () -> ContinuousClock.Instant
    private let cancellationCheck: () -> Bool
    private var expressions: [String: NSRegularExpression] = [:]
    private(set) var didExhaustBudget = false
    private(set) var didInterruptExpression = false
    var isIncomplete: Bool { didExhaustBudget || didInterruptExpression }
    var compiledExpressionCount: Int { expressions.count }

    init(
        budget: Duration = .milliseconds(100),
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
        cancellationCheck: @escaping () -> Bool = { withUnsafeCurrentTask { $0?.isCancelled ?? false } }
    ) {
        deadline = now() + budget
        self.now = now
        self.cancellationCheck = cancellationCheck
    }

    var isCancelled: Bool { cancellationCheck() }

    func canContinue() -> Bool {
        guard !isCancelled, !didExhaustBudget else { return false }
        guard now() < deadline else {
            didExhaustBudget = true
            return false
        }
        return true
    }

    func matchesRegularExpression(pattern: String, input: String) -> Bool {
        guard canContinue() else { return false }
        let expressionDeadline = now() + .milliseconds(25)
        func canEvaluateExpression() -> Bool {
            guard canContinue() else { return false }
            guard now() < expressionDeadline else {
                didInterruptExpression = true
                return false
            }
            return true
        }
        let expression: NSRegularExpression
        if let cached = expressions[pattern] {
            expression = cached
        } else {
            do {
                expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                expressions[pattern] = expression
            } catch {
                return false
            }
        }

        guard canEvaluateExpression() else { return false }
        let range = NSRange(input.startIndex..., in: input)
        var matched = false
        expression.enumerateMatches(in: input, options: [.reportProgress], range: range) { result, _, stop in
            guard canEvaluateExpression() else {
                stop.pointee = true
                return
            }
            if result != nil {
                matched = true
                stop.pointee = true
            }
        }
        return matched
    }
}

/// Decides whether a stored login's URI should be offered for the site the system is asking about.
///
/// Uses only Foundation and the shared URI mode contract; SDK mapping happens in its adapter.
public enum URIMatching {
    /// Applies Bitwarden's per-URI detection mode. A missing mode uses the product default,
    /// Base Domain. The account-wide override is not implemented by this client, so there is no
    /// second hidden fallback that could widen suggestions unexpectedly.
    public static func matches(
        storedURI: String,
        matchType: AutoFillURIMatchMode?,
        requestURI: String
    ) -> Bool {
        matches(
            storedURI: storedURI,
            matchType: matchType,
            requestURI: requestURI,
            using: URIQueryMatchingContext()
        )
    }

    static func matches(
        storedURI: String,
        matchType: AutoFillURIMatchMode?,
        requestURI: String,
        using context: URIQueryMatchingContext
    ) -> Bool {
        guard context.canContinue() else { return false }
        guard storedURI.utf8.count <= 2_048, requestURI.utf8.count <= 2_048 else { return false }

        switch matchType ?? .domain {
        case .domain:
            guard let storedHost = host(from: storedURI),
                  let requestHost = host(from: requestURI)
            else { return false }
            // IP literals have no registrable domain. Treating their final dot-separated labels as
            // one would make unrelated addresses such as 127.0.0.1 and 192.168.0.1 look related.
            if isIPAddress(storedHost) || isIPAddress(requestHost) {
                return storedHost == requestHost
            }
            guard let storedDomain = registrableDomain(of: storedHost),
                  let requestDomain = registrableDomain(of: requestHost)
            else { return false }
            return storedDomain == requestDomain

        case .host:
            guard let stored = components(from: storedURI),
                  let request = components(from: requestURI),
                  normalizedHost(stored.host) == normalizedHost(request.host)
            else { return false }
            return normalizedPort(stored) == normalizedPort(request)

        case .startsWith:
            guard let stored = normalizedAbsoluteURI(from: storedURI),
                  let request = normalizedAbsoluteURI(from: requestURI)
            else { return false }
            return request.hasPrefix(stored)

        case .exact:
            guard let stored = normalizedAbsoluteURI(from: storedURI),
                  let request = normalizedAbsoluteURI(from: requestURI)
            else { return false }
            return stored == request

        case .regularExpression:
            guard storedURI.utf8.count <= 1_024 else { return false }
            return context.matchesRegularExpression(pattern: storedURI, input: requestURI)

        case .never:
            return false
        }
    }

    /// Whether a stored URI's host should be offered for a request against `requestHost`.
    ///
    /// Matches on exact host, or on the stored host being a *subdomain* of the requested one
    /// (`accounts.example.com` stored, `example.com` requested). The reverse direction is
    /// deliberately not matched: it would offer credentials stored for `evil.example.com` while
    /// the user is on `example.com`, which is exactly what an attacker who can register a
    /// subdomain wants. A bare public suffix on the requesting side never matches, so
    /// `something.co.uk` can't be reached via a request for `co.uk`.
    public static func hostMatches(_ uriHost: String, requestHost: String) -> Bool {
        guard let uriHost = normalizedHost(uriHost),
              let requestHost = normalizedHost(requestHost)
        else { return false }

        if isIPAddress(uriHost) || isIPAddress(requestHost) {
            return uriHost == requestHost
        }

        if uriHost == requestHost { return true }
        guard uriHost.hasSuffix(".\(requestHost)") else { return false }
        // The requested host has to be a registrable domain in its own right, not a public suffix -
        // otherwise a request for "co.uk" would match every British site in the vault.
        return registrableDomain(of: requestHost) == requestHost
    }

    /// The registrable domain ("eTLD+1") of `host`, e.g. `example.co.uk` for
    /// `accounts.example.co.uk`. `nil` when `host` is itself a public suffix (`co.uk`, `com`) and
    /// so isn't something anyone can own.
    ///
    /// Uses the versioned, bundled Mozilla Public Suffix List, including private suffixes. This is
    /// essential for credentials on multi-tenant hosts such as `github.io`: unrelated tenants must
    /// never share a base-domain AutoFill match just because their last two labels happen to match.
    public static func registrableDomain(of host: String) -> String? {
        guard let host = normalizedHost(host), !isIPAddress(host) else { return nil }
        return PublicSuffixList.bundled.registrableDomain(of: host)
    }

    /// Extracts a host from either a full URL or a bare domain. `ASCredentialServiceIdentifier`
    /// hands over both shapes depending on which app or browser is asking.
    public static func host(from raw: String) -> String? {
        normalizedHost(components(from: raw)?.host)
    }

    private static func components(from raw: String) -> URLComponents? {
        guard !raw.isEmpty, !raw.hasPrefix("//") else { return nil }
        if let parsed = URLComponents(string: raw) {
            if parsed.host != nil { return parsed }
            // A bare host with a numeric port (notably `localhost:8080`) is parsed by Foundation
            // as a scheme without a host. Preserve that supported service-identifier form, but do
            // not reinterpret `mailto:`, `https:example.com`, or another non-hierarchical URI.
            if parsed.scheme != nil, !isBareHostWithPort(raw) {
                return nil
            }
        }
        return URLComponents(string: "https://\(raw)")
    }

    private static func isBareHostWithPort(_ raw: String) -> Bool {
        let authority = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        guard let colon = authority.lastIndex(of: ":") else { return false }
        return Int(authority[authority.index(after: colon)...]) != nil
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    private static func normalizedPort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func normalizedAbsoluteURI(from raw: String) -> String? {
        guard var components = components(from: raw),
              let scheme = components.scheme?.lowercased(),
              let host = normalizedHost(components.host)
        else { return nil }
        components.scheme = scheme
        components.host = host
        // The port is part of Host/Exact matching, but the default spelling (`:443`/`:80`) must
        // compare equal to an omitted port for the same scheme.
        if components.port == defaultPort(for: scheme) {
            components.port = nil
        }
        return components.string
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https": 443
        case "http": 80
        default: nil
        }
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.hasPrefix("["), host.hasSuffix("]"), host.contains(":") {
            // URLComponents accepts and normalizes bracketed IPv6 literals; domains cannot contain
            // a colon, so this is sufficient here without introducing a networking dependency.
            return true
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.allSatisfy(\.isNumber), let value = UInt8(octet) else {
                return false
            }
            return String(value) == octet || (octet.count > 1 && octet.first == "0")
        }
    }
}
