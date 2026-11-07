# Contributing

Scope is frozen: fix existing behavior, preserve encrypted payloads and polish architecture/UI.
Do not add Vaultwarden/Bitwarden compatibility features or silently normalize unsupported data.
Use synthetic fixtures/accounts only. Project-owned source, documentation and assets are licensed
under GPL-3.0-only. Do not change or remove third-party license notices; upstream SDK sources and
other third-party materials retain their existing license terms (see THIRD_PARTY_NOTICES.md).

## Setup and source ownership

Follow README and Docs/ContributorConfiguration.md. Recorded local verification uses Xcode 27,
Swift 6.4 compiler in Swift 5 language mode, macOS arm64 and generic iOS Simulator; deployment
floors remain macOS 14 / iOS 17. Older supported toolchains must be verified, not inferred.
Do not commit Configuration/Local.xcconfig, signing credentials, generated .xcodeproj, caches,
sdk-internal clones or XCFramework binaries. Never hand-edit Packages/VaultwardenSDK generated
sources or official Bitwarden/Vaultwarden checkouts. project.yml/xcconfig are the Xcode authority.

## Changes and verification

Keep UI dependent on Domain/SharedUI, crypto on BitwardenSDKAdapter, persistence/repositories in
Data and system effects in PlatformServices/SecurityStorage. Composition constructs live adapters;
tests inject ports. Avoid broad unchecked Sendable, generic error text or secret logging. A
confirmed mutation must not become a retryable create merely because its UI consumer cancelled.

Run the package test targets, not merely builds. Run both unsigned app/extension schemes after
production/composition changes; regenerate the project after graph changes. Add explicit gates
for races instead of correctness assertions based on sleeps. Document actual counts/results and
remaining OS/server limitations in the single current checklist, Docs/RemainingReleaseWork.md.
Docs/Verification.md preserves dated evidence; the original plan preserves the frozen scope and
acceptance specifications. Do not create competing current task/status lists.
No signed device, SDK FFI, HTTP server or Release gate is passed by a fake callback.

Use Scripts/test-packages.sh and Scripts/build-unsigned.sh (optional argument Release).
Scripts/test-integration.sh runs both packages plus the hostless macOS/iOS-Simulator bundles in
Tests/PlatformIntegration; Scripts/test-integration-preflight.sh checks its refusals offline.
Integration tests use in-memory Keychains, isolated preferences and synthetic HTTP only; the
opt-in server contract needs explicit owner consent (Docs/IntegratedAcceptance.md).
Run bash Scripts/swiftformat.sh --lint, swift Scripts/check-architecture.swift,
bash Scripts/test-architecture-rules.sh, swift Scripts/check-source-secrets.swift and
bash Scripts/test-source-secrets.sh (synthetic positive/negative fixture).
Run swift Scripts/check-source-materials.swift for the third-party byte inventory and to reject
private/build/signing material in tracked source. Project generation uses the same pinned,
hash-verified Scripts/xcodegen.sh in local builds and CI; no moving Homebrew tool version is used.
After project generation, bash Scripts/test-configuration.sh checks public synthetic settings
and negative cases without signing. Bare verify-configuration.swift intentionally fails if your
local signing prefix is unconfigured; run it against your configured settings before device work.
For formatting use bash Scripts/swiftformat.sh: SwiftFormat 0.63.0 and its archive SHA-256 are
pinned, with one .swiftformat configuration excluding generated/upstream code. Own targets use
complete strict concurrency and warnings as errors; generated SDK targets keep upstream settings.
Prepared GitHub CI has not been run remotely; consult the release checklist for verified state.

## Releases

Do not push tags, upload artifacts, change server data or select distribution policies as a side
effect of a local refactor. The first publication is source-only as a learning project. Project-
owned source/documentation/assets use GPL-3.0-only; upstream SDK sources and other third-party
materials retain their own terms. The owner approves publication and final license-scope review.
See Docs/RemainingReleaseWork.md. A release must identify its exact source, SDK provenance, tested
server/device versions and known limitations. Screenshots must contain synthetic values only.
