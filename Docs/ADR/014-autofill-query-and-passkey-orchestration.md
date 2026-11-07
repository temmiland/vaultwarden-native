# AutoFill invocation assembly, credential queries and passkey assertions

Status: live partial migration, 2026-09-28. Full AppModules targets and both unsigned app/extension
builds pass. X-601/X-602/X-603 and release gates remain partial for the boundaries below.

## Decision

`AutoFillVaultStore` is now a 40-line extension composition root, not the owner of decryption,
matching, TOTP generation or assertion orchestration. It injects shared account/unlock metadata,
the original cache revision, current-proof and cache readers into `AutoFillData.ExtensionVaultSession`.
That invocation assembly creates one revocable SDK resource, one shared credential source and
the `CredentialQuery` and `PasskeyService` actors. It does not create a token authority or expose
an unlocked SDK Client. SDK configuration, KDF conversion, crypto and WebAuthn JSON stay in
BitwardenSDKAdapter. AutoFillData neither imports nor directly depends on BitwardenSdk.

The existing synchronous `ExtensionSession` lease remains the authorization boundary for SDK
callbacks. Turning that lease into an actor would not fit those synchronous callbacks. Actors
own query/assertion sequencing, not a lock held across crypto/network suspension. The immutable
live source rechecks the same proof/resource around operations; cache reads also validate the
account/server and fixed UUID revision. A changed/missing proof, cache or revision permanently
revokes the invocation. Dropping the assembly revokes it even if a query actor was retained.

Picker state now contains `AutoFillLoginSummary`: name, username, URI matching metadata, TOTP
availability and passkey selection metadata. It contains no password, TOTP seed or passkey
private key. Passwords are decrypted again on selection; TOTP is generated from the freshly
resolved item immediately before output. Neither actor caches decrypted results. Secret-bearing
adapter values and fulfilment results have redacted descriptions. This is not memory zeroization.

Lists return an `AutoFillCredentialList`, including the number of eligible items that could not
be read safely. The password, TOTP, passkey and registration pickers show a stable partial-list
warning. Policy-excluded items do not count as decryption failures. Cancellation and source-wide
authorization/cache failures terminate the query rather than becoming a partial-success warning.
Duplicate cipher IDs are denied, not mapped to the first record.

Passkey rows use cipher ID plus credential bytes as identity, so two passkeys in one cipher do
not collide in SwiftUI. Direct OS identities match both fields. Assertion decrypts only the
selected cipher and checks the current unique credential ID and exact RP before invoking the
SDK callback. It rechecks cancellation/cache access after the callback and denies a response for
a different credential. A busy flag prevents parallel assertions across actor reentrancy.
Missing picker user-handle metadata is not required: the SDK assertion supplies its result.
AuthenticationServices output mapping stays in `AutoFillPasskeyAssertion`, an extension adapter.

## Verification

23 new methods: nine CredentialQuery, nine PasskeyService and five ExtensionVaultSession methods.
They cover metadata-only/redacted values, manual/concrete matching, partial failures, duplicate
IDs, fresh password/seed resolution, invalid/deleted/replaced credential metadata, exact RP and
request bytes, late cancellation/revocation/policy changes, parallel assertion exclusion and
retained-query resource lifetime. Parameterized gated fixtures use explicit continuations,
not timing-dependent sleeps. They use synthetic SDK models/no-handle resources, not real crypto.

The initial complete AppModules run passed 612 Swift-Testing methods in 78 suites plus two
XCTest tests (614 total). The identified-request follow-up adds three PasskeyService methods and
passes 615 Swift-Testing methods plus two XCTest tests (617 total). Existing assertions remain.
Both unsigned macOS-arm64 and generic iOS-Simulator app/
extension schemes pass after project regeneration. No official SDK/subrepo is modified.
See [executed commands and limits](../Verification.md).

The direct OS passkey path now calls `PasskeyService.match`, resolving only the identified cipher
and exact credential rather than decrypting the whole vault before selection. It shares the
same current-credential validation with assertion. New tests cover unrelated damaged items,
exact selection among multiple credentials, unknown/duplicate/foreign identities, wrong RP,
missing passkeys, decryption failure and late cancellation/lock/policy changes.

An identified password/TOTP fulfilment error now cancels the request. It cannot substitute an
identifier-free vault picker: that OS entry point supplies no service-list scope, unlike an
explicit manual-list invocation. The controller change is reviewed and compiled in both platform
builds, not claimed as an executed OS-context test. The identified-request debug log no longer
prints the record identifier.

## Remaining boundaries

The original SDK-shaped callback/registration split is implemented by
[ADR 018](018-autofill-sdk-callback-and-registration-ports.md): legacyView is internal,
ExtensionVaultSession.perform exposes typed adapter operations, SDK callbacks/JSON belong to
the SDK adapter, registration persistence/coordinator to AutoFillData and device-owner verification
to PlatformServices. The extension retains Apple mapping and scoped composition, not raw SDK models.
The operation-owned writer/journal and exact app-sync reconciliation are covered by
[ADR 015](015-passkey-registration-write-recovery.md), incremental publication by
[ADR 016](016-passkey-registration-incremental-identities.md) and explicit reviewed abandonment
by [ADR 017](017-passkey-registration-reviewed-abandonment.md). Their remaining cross-process/
legacy-origin/signed-server gates remain open. No new compatibility flow is introduced.

Silent SDK-internal per-field decryption degradation is not fully classified by aggregate
thrown-error counting. The legacy cache still lacks collection policy. Controller/OS-context
integration, full error/user-verification matrix, server
round-trips, signed-device/entitlement checks, Release product builds and concurrent processes
remain separate work. A cache/proof check and OS completion are not an atomic transaction, and
already-issued values cannot be recalled.
