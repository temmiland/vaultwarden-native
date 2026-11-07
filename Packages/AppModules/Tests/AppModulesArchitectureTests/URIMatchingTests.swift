import AutoFillContract
@testable import AutoFillData
import Foundation
import Testing

@Suite
struct URIMatchingTests {
    @Test
    func missingOrEmptySuffixListNeverWidensAcrossPrivateTenants() {
        for source in ["", "// empty resource\n", "com\nio\ngithub.io\ninvalid?rule\n"] {
            let list = PublicSuffixList(source: source)
            #expect(list.registrableDomain(of: "alice.github.io") == nil)
            #expect(list.registrableDomain(of: "bob.github.io") == nil)
        }
        let list = PublicSuffixList(source: "com\nio\ngithub.io\n")
        #expect(list.registrableDomain(of: "alice.github.io") == "alice.github.io")
        #expect(list.registrableDomain(of: "bob.github.io") == "bob.github.io")
    }

    @Test
    func perURIMatchModesFollowTheirDocumentedBoundaries() {
        #expect(URIMatching.matches(
            storedURI: "https://google.com", matchType: .domain,
            requestURI: "https://accounts.google.com/login"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://sub.domain.com:4000", matchType: .host,
            requestURI: "https://sub.domain.com"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://sub.domain.com:4000", matchType: .host,
            requestURI: "http://sub.domain.com:4000/path"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://sub.domain.com/path/", matchType: .startsWith,
            requestURI: "https://sub.domain.com/path/page.html"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://sub.domain.com/path/", matchType: .startsWith,
            requestURI: "https://sub.domain.com/path"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://www.google.com/page.html", matchType: .exact,
            requestURI: "https://www.google.com/page.html"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://www.google.com/page.html", matchType: .exact,
            requestURI: "https://www.google.com/page.html?query=1"
        ))
        #expect(URIMatching.matches(
            storedURI: "^https://[a-z]+\\.wikipedia\\.org/w/index\\.php", matchType: .regularExpression,
            requestURI: "https://en.wikipedia.org/w/index.php?title=Login"
        ))
        #expect(!URIMatching.matches(
            storedURI: "[", matchType: .regularExpression, requestURI: "https://example.com"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://example.com", matchType: .never, requestURI: "https://example.com"
        ))
    }

    @Test
    func pathologicalRegularExpressionStopsWithinBoundedTime() {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(!URIMatching.matches(
            storedURI: "^(a+)+$", matchType: .regularExpression,
            requestURI: String(repeating: "a", count: 40) + "!"
        ))
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test
    func oneContextReusesCompiledExpressionsAndSharesItsDeadline() {
        var now = ContinuousClock.Instant.now
        let context = URIQueryMatchingContext(budget: .seconds(1), now: { now }, cancellationCheck: { false })

        #expect(URIMatching.matches(
            storedURI: "example\\.com", matchType: .regularExpression,
            requestURI: "https://example.com", using: context
        ))
        #expect(URIMatching.matches(
            storedURI: "example\\.com", matchType: .regularExpression,
            requestURI: "https://accounts.example.com", using: context
        ))
        #expect(context.compiledExpressionCount == 1)

        now += .seconds(1)
        #expect(!URIMatching.matches(
            storedURI: "other", matchType: .regularExpression,
            requestURI: "https://example.com", using: context
        ))
        #expect(context.didExhaustBudget)
    }

    @Test
    func singleExpressionHasItsOwnDeadlineWithoutSpendingTheEntireQueryBudget() {
        let start = ContinuousClock.now
        var reads = 0
        let context = URIQueryMatchingContext(now: {
            reads += 1
            return reads < 5 ? start : start + .milliseconds(25)
        }, cancellationCheck: { false })
        #expect(!URIMatching.matches(
            storedURI: "example", matchType: .regularExpression,
            requestURI: "https://example.com", using: context
        ))
        #expect(context.didInterruptExpression)
        #expect(!context.didExhaustBudget)
        #expect(context.isIncomplete)
        #expect(URIMatching.matches(
            storedURI: "https://example.com", matchType: .exact,
            requestURI: "https://example.com", using: context
        ))
        #expect(context.canContinue())
    }

    @Test
    func singleExpressionTimeoutKeepsLaterMatchesAndMarksTheListIncomplete() {
        let start = ContinuousClock.now
        var reads = 0
        let context = URIQueryMatchingContext(now: {
            reads += 1
            return reads < 8 ? start : start + .milliseconds(25)
        }, cancellationCheck: { false })
        let expensive = AutoFillLoginSummary(
            cipherId: "regex", name: "Regex", username: "synthetic",
            uris: [.init(value: "example", matchType: .regularExpression)]
        )
        let ordinary = AutoFillLoginSummary(
            cipherId: "exact", name: "Exact", username: "synthetic",
            uris: [.init(value: "https://example.com", matchType: .exact)]
        )
        let result = CredentialQuery.filterForQuery(
            [expensive, ordinary], matching: ["https://example.com"], context: context
        )
        #expect(context.didInterruptExpression)
        #expect(!context.didExhaustBudget)
        #expect(result.items.map(\.cipherId) == ["exact"])
        #expect(result.isIncomplete)
    }

    @Test
    func credentialFilteringReportsWhenTheSharedBudgetStopsEvaluation() {
        let item = AutoFillLoginSummary(
            cipherId: "synthetic",
            name: "Synthetic login",
            username: "synthetic-user",
            uris: [.init(value: "example\\.com", matchType: .regularExpression)]
        )
        let context = URIQueryMatchingContext(budget: .zero, cancellationCheck: { false })
        let result = CredentialQuery.filterForQuery([item], matching: ["https://example.com"], context: context)
        let list = AutoFillCredentialList(
            items: result.items,
            unavailableItemCount: 0,
            matchingEvaluationIncomplete: result.isIncomplete
        )

        #expect(result.items.isEmpty)
        #expect(result.isIncomplete)
        #expect(list.warningMessage?.contains("Some matching logins may be missing") == true)
    }

    @Test
    func missingPerURIModeUsesBaseDomain() {
        #expect(URIMatching.matches(
            storedURI: "https://example.co.uk", matchType: nil,
            requestURI: "https://accounts.example.co.uk"
        ))
    }

    @Test
    func ipLiteralsOnlyMatchTheExactAddressInDomainMode() {
        #expect(URIMatching.matches(
            storedURI: "https://127.0.0.1", matchType: .domain,
            requestURI: "https://127.0.0.1/login"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://127.0.0.1", matchType: .domain,
            requestURI: "https://192.168.0.1/login"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://[::1]", matchType: .domain,
            requestURI: "https://[::1]/login"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://[::1]", matchType: .domain,
            requestURI: "https://[::2]/login"
        ))
    }

    @Test
    func normalizesIDNATrailingDotsAndDefaultPortsWithoutWideningTheHost() {
        #expect(URIMatching.matches(
            storedURI: "https://xn--bcher-kva.example./login", matchType: .host,
            requestURI: "https://bücher.example:443/other"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://example.com:443/login", matchType: .exact,
            requestURI: "https://example.com/login"
        ))
        #expect(URIMatching.matches(
            storedURI: "https://example.com:443/login", matchType: .startsWith,
            requestURI: "https://example.com/login/next"
        ))
        #expect(!URIMatching.matches(
            storedURI: "https://example.com:443/login", matchType: .exact,
            requestURI: "http://example.com/login"
        ))
    }

    @Test
    func rejectsProtocolRelativeAndNonHierarchicalIdentifiers() {
        #expect(URIMatching.host(from: "//example.com/login") == nil)
        #expect(URIMatching.host(from: "mailto:user@example.com") == nil)
        #expect(!URIMatching.matches(
            storedURI: "https://example.com", matchType: .exact,
            requestURI: "//example.com"
        ))
    }

    @Test
    func exactHostMatches() {
        #expect(URIMatching.hostMatches("example.com", requestHost: "example.com"))
        #expect(URIMatching.hostMatches("EXAMPLE.com", requestHost: "example.COM"))
    }

    @Test
    func storedSubdomainMatchesTheParentDomainBeingRequested() {
        #expect(URIMatching.hostMatches("accounts.example.com", requestHost: "example.com"))
        #expect(URIMatching.hostMatches("a.b.example.com", requestHost: "example.com"))
    }

    /// The direction that matters: an attacker who can register `evil.example.com` must not be
    /// offered the credentials the user stored for `example.com` itself.
    @Test
    func requestedSubdomainDoesNotMatchAStoredParentDomain() {
        #expect(URIMatching.hostMatches("example.com", requestHost: "evil.example.com") == false)
    }

    @Test
    func unrelatedHostsDoNotMatch() {
        #expect(URIMatching.hostMatches("example.com", requestHost: "example.org") == false)
        #expect(URIMatching.hostMatches("notexample.com", requestHost: "example.com") == false)
        // Suffix matching must respect label boundaries, not raw string suffixes.
        #expect(URIMatching.hostMatches("evilexample.com", requestHost: "example.com") == false)
    }

    /// Without public-suffix awareness, a request for "co.uk" would match every `*.co.uk` login in
    /// the vault at once.
    @Test
    func aBarePublicSuffixMatchesNothing() {
        #expect(URIMatching.hostMatches("example.co.uk", requestHost: "co.uk") == false)
        #expect(URIMatching.hostMatches("bank.com.au", requestHost: "com.au") == false)
        #expect(URIMatching.hostMatches("example.com", requestHost: "com") == false)
    }

    @Test
    func subdomainsStillMatchUnderAMultiLabelPublicSuffix() {
        #expect(URIMatching.hostMatches("accounts.example.co.uk", requestHost: "example.co.uk"))
        #expect(URIMatching.hostMatches("example.co.uk", requestHost: "example.co.uk"))
    }

    @Test
    func registrableDomainHandlesBothSuffixShapes() {
        #expect(URIMatching.registrableDomain(of: "accounts.example.com") == "example.com")
        #expect(URIMatching.registrableDomain(of: "example.com") == "example.com")
        #expect(URIMatching.registrableDomain(of: "accounts.example.co.uk") == "example.co.uk")
        #expect(URIMatching.registrableDomain(of: "example.co.uk") == "example.co.uk")
    }

    @Test
    func bundledPSLSeparatesUnrelatedPrivateSuffixTenants() {
        #expect(URIMatching.registrableDomain(of: "login.alice.github.io") == "alice.github.io")
        #expect(URIMatching.registrableDomain(of: "login.bob.github.io") == "bob.github.io")
        #expect(!URIMatching.matches(
            storedURI: "https://login.alice.github.io", matchType: .domain,
            requestURI: "https://login.bob.github.io"
        ))
    }

    @Test
    func bundledPSLHonorsWildcardAndExceptionRules() {
        // The PSL's `*.ck` rule normally makes `b.ck` a public suffix, while `!www.ck` is an
        // exception: `www.ck` itself is registrable under the parent suffix `ck`.
        #expect(URIMatching.registrableDomain(of: "a.b.ck") == "a.b.ck")
        #expect(URIMatching.registrableDomain(of: "www.ck") == "www.ck")
        #expect(URIMatching.registrableDomain(of: "login.www.ck") == "www.ck")
    }

    @Test
    func aPublicSuffixHasNoRegistrableDomain() {
        #expect(URIMatching.registrableDomain(of: "co.uk") == nil)
        #expect(URIMatching.registrableDomain(of: "com.au") == nil)
        #expect(URIMatching.registrableDomain(of: "com") == nil)
    }

    /// `ASCredentialServiceIdentifier` supplies full URLs from browsers and bare domains from
    /// native apps; both have to resolve.
    @Test
    func hostIsExtractedFromBothURLsAndBareDomains() {
        #expect(URIMatching.host(from: "https://example.com/login?next=/x") == "example.com")
        #expect(URIMatching.host(from: "example.com") == "example.com")
        #expect(URIMatching.host(from: "http://sub.example.com:8080") == "sub.example.com")
    }
}
