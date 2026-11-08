# Vaultwarden – native Apple client learning project

Shared SwiftUI code for macOS, iOS and iPadOS, with a credential provider extension and the
Bitwarden Rust/UniFFI crypto core. Independent project; not an official Bitwarden/Vaultwarden client.

> **Unaudited learning project. Do not use irreplaceable production credentials.**
> First publication: **source code only**, not signed installable apps.
> Status: `0.1.0-prealpha`, not a stable security release.

Project-owned source, documentation and assets use [GPL-3.0-only](LICENSE). Generated Bitwarden
SDK sources, datasets and other third-party materials retain their upstream license terms; see
[third-party notices](THIRD_PARTY_NOTICES.md). No combined SDK binary is approved for release.
See [feature status and known limits](Docs/FeatureStatus.md),
[release checklist](Docs/RemainingReleaseWork.md), [security policy](SECURITY.md) and
[changelog](CHANGELOG.md).

## Requirements and setup

- macOS with Xcode and command-line tools. Recorded local checks: Xcode 27 / Swift 6.4 compiler
  in Swift 5 language mode. Deployment floors: macOS 14 / iOS 17; older toolchains are not proven here.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): the shared `Scripts/xcodegen.sh` downloads
  and verifies the pinned 2.46.0 release automatically during project generation.
- [rustup](https://rustup.rs) and Cargo for the first SDK build (pinned Rust 1.99.0).

The ignored `BitwardenFFI.xcframework` is not included in git. A fresh clone builds it:

```sh
bash Scripts/build-sdk.sh --install
bash Scripts/generate-xcodeproj.sh
open Vaultwarden.xcodeproj
```

For an existing checkout after an SDK pin/dependency update, `bash Scripts/build-sdk.sh --upgrade`
rebuilds the pinned SDK, refreshes its generated bindings and replaces the local framework. It
retains the previous sources and framework in the ignored isolated build directory for rollback.
Ordinary `--build`/`--install` runs continue to verify the committed bindings without rewriting them.

Ordinary SDK builds verify revision, both patch hashes, toolchain and the reviewed Cargo.lock.
They use their own `.build/sdk-isolated` scratch clone, compare regenerated bindings, and never
patch an existing official checkout or rewrite committed generated sources. `--install` refuses an
existing artifact; `--build` builds for comparison without installing; `--check` inventories
local bytes read-only. `--verify-build PATH` rechecks an explicit previous scratch build;
`bash Scripts/test-rebuilt-sdk.sh PATH` runs the real FFI smoke against it. Scratch outputs remain
ignored for provenance review.

Pins and the [historical local byte inventory](Docs/SDKLocalArtifactInventory.json) are not proof
of binary origin or byte-identical rebuilds. An isolated five-slice rebuild and real smoke against
the new binary [passed locally](Docs/SDKRebuildVerification.md); remote CI and a fully fresh
contributor machine are not yet proven. Review SDK licenses before
redistributing its source or any combined binary.

`project.yml` and `Configuration/*.xcconfig` are the Xcode authority; the generated project is
ignored. Do not hand-edit it or the SDK bindings.

For runtime development, copy `Configuration/Local.example.xcconfig` to the ignored
`Configuration/Local.xcconfig` and configure your own team/IDs, App Group and Keychain services.
Regenerate the project and run `swift Scripts/verify-configuration.swift`. Unconfigured unsigned
apps compile but show configuration recovery, not sign-in. No personal Team ID/fallback is
committed. See [contributor configuration](Docs/ContributorConfiguration.md).

## Verification

Run from the repository root after building the SDK:

```sh
bash Scripts/swiftformat.sh --lint
swift Scripts/check-architecture.swift
bash Scripts/test-architecture-rules.sh
swift Scripts/check-source-secrets.swift
swift Scripts/check-source-secrets.swift --history
bash Scripts/test-source-secrets.sh
bash Scripts/test-configuration.sh
bash Scripts/test-integration-preflight.sh
bash Scripts/test-integration.sh
bash Scripts/build-unsigned.sh
bash Scripts/build-unsigned.sh Release
```

`test-integration.sh` runs both package test targets (`Scripts/test-packages.sh`) and then the
hostless macOS and iOS-Simulator integration bundles; it needs an installed iOS Simulator runtime.
For the disposable local server contract, run `bash Scripts/test-disposable-server.sh` with Docker
available. It creates and removes a loopback-only container and synthetic account.

The [integrated acceptance process](Docs/IntegratedAcceptance.md) exercises actual shared app/
extension composition and native hosting/controllers on macOS and iOS. An isolated server account
can be tested with explicit opt-in; an unrun server or signed OS flow is never counted as passed.

Tests execute both packages, including the real SDK FFI smoke. Builds include both apps and
extensions without signing. Own targets use complete strict concurrency and warnings as errors;
generated SDK targets retain upstream policy. SwiftFormat is version/hash-pinned and excludes
upstream files. Secret scanning checks selected credential patterns across unignored UTF-8 source
and reachable Git history; it remains heuristic and cannot detect every secret or personal-data leak.

The latest dated results, including test counts and limitations, are in
[verification](Docs/Verification.md) and the [remaining work](Docs/RemainingReleaseWork.md).
A local synthetic server contract against Vaultwarden 1.37.5 ran on 2026-11-03; it did not
exercise every supported flow. A separate disposable local run on 2026-11-06 passed a login TOTP
challenge and a long encrypted file-Send filename. Individual device revocation returned 404 and
was not performed. Package tests on 2026-11-06 passed with opt-in live-server tests skipped.
Previous unsigned builds and simulator integration
results apply only to their recorded builds and environment; prepared GitHub CI is not a passed
remote run.

## Architecture

```text
App/                       macOS/iOS shells and composition roots
AutoFillExtension/         Apple request/controller/context adapters
Composition/               shared contributor/App Group/Keychain configuration
Configuration/             Debug/Release settings and ignored local overrides
Packages/
  AppModules/Sources/
    Domain                 SDK-/OS-free values, commands and repository/platform ports
    Data                   auth/session/vault/send/settings authorities and persistence
    Networking             HTTP and protected file transport
    SecurityStorage        Keychain, process locks and sensitive temporary files
    BitwardenSDKAdapter    raw SDK/Crypto/Wire mapping (only raw SDK importer)
    PlatformServices       Apple system effects behind Domain ports
    AutoFillContract       versioned encrypted cross-process records/proofs
    AutoFillData            query/matching, assertion/registration/recovery/completion
    AutoFillFeature        shared picker/registration views through Contract + callbacks
    SharedUI               shared UI/environment ports
    AuthPresentation       Observation auth models/routes/views
    VaultPresentation      Observation vault model/state/views
    SendPresentation       Observation send model/views
    SettingsPresentation   settings UI through Domain ports
    AppFeature             app lifecycle/session/timeout state
  VaultwardenSDK/           generated upstream bindings + ignored FFI binary
Scripts/                   verified build, generation, format and source-policy checks
Tests/PlatformIntegration/ hostless macOS/iOS composition, hosting and controller tests
Docs/                      architecture, ADRs, limits, verification and third-party texts
  Planning/                frozen restructure specification and dated implementation history
```

Feature UI depends on Domain/SharedUI, not tokens, SDK clients or live storage factories.
Composition injects HTTP/storage/system adapters; repositories own authoritative snapshots and
confirmed mutations. App/extension share account/server/lineage/unlock-bound proofs, not UI state.
See [architecture and data flows](Docs/Architecture.md),
[threat model](Docs/ThreatModel.md) and [architecture decisions](Docs/ADR).

## Scope and important limits

This refactor polishes existing login/TOTP-2FA, unlock, vault CRUD, attachments, Sends, settings,
AutoFill/passkeys and macOS conveniences; no new Vaultwarden compatibility features are added. Unsupported
editors/data remain read-only or fail-closed. Full supported/unsupported matrix:
[FeatureStatus](Docs/FeatureStatus.md).

- The limited Vaultwarden 1.37.5 synthetic-server run does not establish a general Bitwarden/Vaultwarden version guarantee.
- Password and TOTP QuickType suggestions use Base Domain rules only and revalidate the current URI policy, user and unlock proof. Stricter URI rules remain in the scoped interactive picker.
- iOS/iPadOS 26.2+ supports explicitly confirmed password saves and existing-login updates. Unknown server outcomes require sync/recovery before another save. On macOS, save passwords through the app editor; Apple does not expose this save request to macOS credential-provider extensions. Signed-device acceptance remains pending.
- No signed device/entitlement, real Apple-controller/UI, parallel-process/crash or security audit.
- The pinned SDK lockfile has open RustSec findings; target membership is not proof that every
  advisory is exploitable here. See the [advisory inventory](Docs/ThirdParty/SDKAdvisoryInventory.json)
  and F-16 in the [work checklist](Docs/RemainingReleaseWork.md). No binary distribution is approved.
- Lock/logout has persistent Keychain cleanup replay; refresh has a network lease, durable intent
  and recovery fences. Real crash/upgrade/process failure combinations remain unverified; total
  persistence failure cannot guarantee durable denial after restart.
- Attachment and File-Send transport uses protected files and shared 64-KiB multipart assembly;
  SDK file crypto still reads whole files. **Total peak memory is not constant.**
- Encrypted attachment downloads have a local 64-MiB byte cap; JSON responses are separately
  capped at 4 MiB (full sync: 64 MiB). These caps do not bound all SDK allocations.
- Shared AutoFill unlocks are bound to the system boot, including the “never” timeout preference.
  Previous unlock schemas require fresh app authentication; old records are refused without deletion.
- Unclear passkey writes retain recovery tracking and are not blindly retried. Reviewed abandonment
  acknowledges local uncertainty, not server rejection or rollback. Older origin-less markers stay blocked.
- Master-password re-prompt items cannot expose secrets/mutate/AutoFill without a proven grant;
  device biometrics do not substitute for that proof. No new re-prompt feature is added.
- Unknown cipher fields now make the item read-only to prevent lossy replacement. Known contents
  remain readable; unknown values are not copied into the local projection or echoed back.
  Older caches require a fresh sync. [Write-safety boundary](Docs/ADR/026-unsupported-cipher-write-fence.md).
  Real lifecycle/storage/OS recovery and future payload semantics remain unverified.
- Private security reports: [welcome@temmi.land](mailto:welcome@temmi.land). The owner confirmed
  mailbox reachability on 2026-11-02; never include real secrets in public reports or an initial email.

The frozen scope and acceptance specifications are in
[RESTRUCTURE_IMPLEMENTATION_PLAN.md](Docs/Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md), with current review and task status in
[RemainingReleaseWork.md](Docs/RemainingReleaseWork.md). Source publication does not mark those plan phases complete.

## Contributing

Use disposable accounts and synthetic fixtures; keep SDK/upstream checkouts and generated code
unchanged. Do not commit binaries, build caches, local signing settings or real vault exports.
Read [CONTRIBUTING](CONTRIBUTING.md) and [SECURITY](SECURITY.md) before submitting changes.
