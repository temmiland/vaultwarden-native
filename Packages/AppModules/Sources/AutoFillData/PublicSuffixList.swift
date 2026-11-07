import Foundation

/// Offline parser for the Mozilla Public Suffix List bundled with this target. The list defines
/// registry boundaries; it is not a DNS validator. A missing or malformed resource intentionally
/// yields no registrable domain, which suppresses AutoFill rather than widening a suggestion.
struct PublicSuffixList: Sendable {
    static let bundled = PublicSuffixList.loadBundled()

    private let exactRules: Set<String>
    private let wildcardRules: Set<String>
    private let exceptionRules: Set<String>
    private let hasRules: Bool

    init(source: String) {
        var exactRules: Set<String> = []
        var wildcardRules: Set<String> = []
        var exceptionRules: Set<String> = []
        var malformed = false
        let allowedLabelCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters).union(
            CharacterSet(charactersIn: "-")
        )

        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }
            let rule = line.hasPrefix("!") ? String(line.dropFirst()) :
                line.hasPrefix("*.") ? String(line.dropFirst(2)) : line
            let labels = rule.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.allSatisfy({ label in
                !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                    label.unicodeScalars.allSatisfy { allowedLabelCharacters.contains($0) }
            }) else { malformed = true; continue }
            if line.hasPrefix("!") {
                exceptionRules.insert(String(line.dropFirst()))
            } else if line.hasPrefix("*.") {
                wildcardRules.insert(String(line.dropFirst(2)))
            } else {
                exactRules.insert(line)
            }
        }

        self.exactRules = exactRules
        self.wildcardRules = wildcardRules
        self.exceptionRules = exceptionRules
        hasRules = !malformed && (!exactRules.isEmpty || !wildcardRules.isEmpty || !exceptionRules.isEmpty)
    }

    /// The eTLD+1 for a normalized DNS host, or `nil` for a public suffix itself. Implements the
    /// PSL prevailing-rule algorithm including wildcard and exception rules.
    func registrableDomain(of host: String) -> String? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard hasRules, labels.count >= 2, !labels.contains(where: \.isEmpty) else { return nil }

        let publicSuffixLabelCount: Int
        if let exception = longestMatchingRule(in: labels, rules: exceptionRules) {
            // An exception rule (`!www.ck`) means its parent (`ck`) is the public suffix.
            publicSuffixLabelCount = exception.count - 1
        } else {
            let exactCount = longestMatchingRule(in: labels, rules: exactRules)?.count ?? 0
            let wildcardCount = longestWildcardMatch(in: labels)
            // The implicit `*` rule makes the final label a suffix when the PSL has no explicit
            // matching rule. This is required by the PSL algorithm for newly delegated TLDs.
            publicSuffixLabelCount = max(1, exactCount, wildcardCount)
        }

        guard labels.count > publicSuffixLabelCount else { return nil }
        return labels.suffix(publicSuffixLabelCount + 1).joined(separator: ".")
    }

    private func longestMatchingRule(in labels: [String], rules: Set<String>) -> [String]? {
        var result: [String]?
        for start in labels.indices {
            let candidate = labels[start...].joined(separator: ".")
            guard rules.contains(candidate) else { continue }
            let candidateLabels = Array(labels[start...])
            if candidateLabels.count > (result?.count ?? 0) {
                result = candidateLabels
            }
        }
        return result
    }

    private func longestWildcardMatch(in labels: [String]) -> Int {
        // A `*.foo` rule needs one additional concrete label before `foo`.
        guard labels.count >= 2 else { return 0 }
        var result = 0
        for start in labels.indices.dropFirst() {
            let suffix = labels[start...].joined(separator: ".")
            guard wildcardRules.contains(suffix) else { continue }
            result = max(result, labels.count - start + 1)
        }
        return result
    }

    private static func loadBundled() -> PublicSuffixList {
        guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              source.contains("// ===BEGIN ICANN DOMAINS==="),
              source.contains("// ===END ICANN DOMAINS==="),
              source.contains("// ===BEGIN PRIVATE DOMAINS==="),
              source.contains("// ===END PRIVATE DOMAINS===")
        else {
            return PublicSuffixList(source: "")
        }
        return PublicSuffixList(source: source)
    }
}
