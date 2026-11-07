# Password sign-in and opaque auth capabilities

Status: fresh password/TOTP flow and three Domain-only models implemented, 2026-09-28.
Returning unlock, final root handoff and release verification remain partial S-303/U-504 work.

Current follow-up: [AuthPresentation and Domain handoff](013-auth-presentation-and-handoff.md)
completes restore/root UI migration and removes the AuthFeature package and AuthServices.
The boundaries and counts below record this ADR's introducing block; operation/recovery and
real-server/device/process gates remain open.

## Decision

Domain defines PasswordSignInCommands, typed results/rejections, AuthSecondFactorChallenge and
PendingAuthentication. Screens receive commands/capabilities, not Data wire responses, token
providers, wrapped keys or SDK clients. LoginModel, TwoFactorModel and EnableBiometricsModel
depend only on Domain ports plus Foundation/Observation. The biometric OS prompt remains a
Domain platform client; Data owns the subsequent scoped key derivation/storage operation.

Data.PasswordSignInService owns device/bootstrap authority, prelogin, password hash, token grant,
crypto initialization, validated account construction and private commit. SDKAuthCredentialCryptography
implements the narrow adapter port over one opaque SDKSessionClient; no raw Client crosses its
API. SDKManagedTokenAdapter still delegates to the one Data token authority. No new protocol,
endpoint, provider, or Vaultwarden compatibility feature is introduced; only authenticator/TOTP
(provider 0) can be submitted. Other offered providers remain deliberately unsupported.

Data.PasswordSecondFactorChallenge privately retains retry credentials. Its Domain surface exposes
only attempt ID, environment, provider IDs and submit/revoke. Duplicate submissions are rejected.
Successful completion clears password/hash references and transfers the same attempt/resource
to PendingAuthSession. A late challenge revoke, including forward-navigation retirement, is a
no-op after transfer; it cannot revoke the successor. Descriptions are explicitly redacted.
Clearing Swift references does not promise secure memory zeroization.

## Authorization and ownership

Fresh login captures storage epoch/prior scope before the first device-name/prelogin suspension.
Data validates that fixed proof after each suspended stage and again under the commit transaction.
Lock, even without an account, and a replacement sign-in invalidate it. Cancelled/noncooperative
prelogin/hash/token/unlock completions cannot advance to the next stage or commit. Invalid token
KDF metadata, empty subject/refresh/wrapped-key data and invalid expiry fail before SDK unlock.
Known safe transport failures map to a Domain enum; unknown diagnostics are never UI text.

PendingAuthSession keeps crypto/provider/store private. AutoFill publication remains best effort,
while biometric enrollment throws a stable UI-mapped failure. Both capture scope/epoch before
derivation, validate afterward and use the existing scoped storage write guards. No extra token
authority or keychain schema is added. Revocation drops the resource before awaiting provider cleanup.

The transitional Data prepareHandoff bridge consumes a candidate once, constructs a runtime using
the same SDK resource, and installs its runtime-bound expiry handler before returning. Repeated
preparation cannot replace that handler or create another runtime. The route then rechecks its
identity/authorization and runtime immediately before callback; failed/stale preparation revokes
the runtime/candidate. Accepted UI teardown leaves runtime-owned authority active.

## Verification and explicit limits

Four existing methods move to AppModules (JWT bookkeeping and invalid token KDF), rather than being
counted as new coverage. Eighteen new methods cover production Data orchestration, per-stage
noncooperative cancellation/lock/account replacement, TOTP retry/duplicates/revoke/transfer,
malformed token data, late key derivation, single-use handoff/expiry and Domain-only screen callbacks.
Controlled continuation gates use synthetic credentials and no-handle resources, not real SDK crypto.
Final complete targets pass 496 AppModules Swift-Testing tests + two XCTest tests and 62 AuthFeature
tests (560 total). Both unsigned macOS-arm64 and generic iOS-Simulator app/extension builds pass.
See [executed commands and remaining gates](../Verification.md).

Follow-up: [returning unlock](012-returning-unlock-commands.md) moves password/PIN/biometric
sequencing into Data and makes UnlockModel Domain-only too. AuthDependencies/restore composition
and root callback remain Data-shaped;
AuthFeature is not yet removable and AuthPresentation is not yet the complete live auth feature.
Private commit followed by UI cancellation is not rolled back; a subsequent fresh unlock/sign-in
may be required. There is no durable multi-item cleanup/recovery transaction, fully repository-owned
credential operation, or verified process-crash semantics. Separate keychain items remain separate.
No real-server/FFI smoke, UI launch, signed-device/entitlement, Release product or cross-process test
was run in this block. Existing KDF-cost and release gates remain open. Official SDK/subrepos are untouched.
