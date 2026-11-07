# Returning unlock behind Domain commands

Status: password/PIN/biometric returning orchestration migrated, 2026-09-28.
S-303/U-504 remain partial until restore/root handoff and live AuthPresentation composition move.

Current follow-up: [AuthPresentation and Domain handoff](013-auth-presentation-and-handoff.md)
completes restore/root UI migration and removes the AuthFeature package and AuthServices.
The boundaries and counts below record this ADR's introducing block; operation/recovery and
real-server/device/process gates remain open.

## Decision

Domain.ReturningUnlockCommands owns an explicit route lifetime, exposes only a nonsecret
ReturningUnlockAccount, availability and typed results/failures. Wrapped keys, sign-in scope,
device ID, token provider and SDK clients are not presentation state or route properties.
UnlockModel now only collects inputs, renders Domain state, gates its UI task and hands off an
opaque PendingAuthentication. Together with the previous block, all five auth screens/models
use Domain/platform ports rather than Data/SDK/storage operations.

Data.ReturningUnlockService owns KDF validation, captured authorization, repository begin/failure,
OS biometric evaluation, key reads, crypto initialization, PIN counter/fallback policy, best-effort
AutoFill publication and pending handoff. The existing device-local PIN single-flight gate is
preserved across overlapping command instances. The service is MainActor-isolated for platform
prompts and that gate; SDK operations cross the async SDKAuthCredentialCryptography adapter.
No storage lock is held over these async crypto/repository awaits. This is not a performance or
signed-device prompt guarantee; the existing synchronous Keychain access policy remains unchanged.

The command closes after success and transfers resource/provider ownership to the pending
capability. Retirement of the old route cannot revoke that successor. Failure/cancellation revokes
active resources before reporting repository unlock failure. A cancellation reported by beginUnlock
also reconciles the requested transition, even if the caller task itself was not cancelled.
The model rejects/revokes a late successful capability from a noncooperative implementation and
clears password/PIN before either handoff callback.

## Defects tightened, not new features

Sign-in scope intentionally survives lock. Returning mutations previously checked that scope
alone, so a noncooperative PIN error or stale unavailable-biometry result could target the same
lineage after lock. Data validates its original epoch after repository/platform/crypto suspension
and before final publication/handoff. PIN increment/reset and PIN/biometric cleanup additionally
require the captured epoch inside the same storage write transaction. Old scope-only production
mutation entrypoints are removed; setup conveniences exist only in test targets.

PIN eligibility/key/budget is read from persistence for every submission, not trusted from an
earlier UI availability copy. Reaching the limit denies crypto even without first rendering
availability. Accepted PIN with failed counter reset never publishes or hands off; persistent
fallback and unconfirmed cleanup remain distinct typed failures with explicit no-retry guidance.
OS/Keychain cancellation stays quiet and preserves enrollment. Late unavailable-biometry after
lock cannot clear enrollment. A leftover biometric key does not authorize a disabled enrollment:
that path is denied before OS evaluation/crypto. Successful password/PIN/biometric paths all publish AutoFill before
handoff using the existing best-effort policy. No endpoint/provider/compatibility behavior is added.

The product raw SDK client factory and StoredAccount/StoredTokens/VaultUnlockService aliases are
deleted. AuthFeature no longer directly depends on BitwardenSdk, AutoFillContract or SecurityStorage
as a product target; its test target explicitly retains those no-handle/storage fixtures. Transitional
AuthServices composition still imports Data/Networking/SDKAdapter, not the screens/routes.

## Verification and remaining limits

14 new Data methods use in-memory stores, no-handle resources and controlled continuation gates;
three new model methods use only Domain fakes. Existing auth assertions stay intact, without being
counted as new coverage. Full targets pass 510 AppModules Swift-Testing tests plus two XCTest
tests and 65 AuthFeature tests (577 total). Both unsigned macOS-arm64 and generic iOS Simulator
app/extension builds pass after the manifest cleanup. See [executed checks](../Verification.md).

Restore/controller composition still reads Data persistence, and the root still receives
Data.AuthenticatedSession through the single-use preparation bridge. AuthFeature therefore remains
a third package; the live auth UI is not yet consolidated into AuthPresentation. Complete
repository-owned command/commit semantics, durable cleanup/process-crash recovery, concurrent
settings/key-replacement and full multi-scene/server/device/cross-process coverage remain open.
Keychain items remain separate writes; no rollback of confirmed writes or Swift/SDK zeroization is
promised. No real-server/SDK-crypto smoke, signed OS/device/entitlement, UI launch or Release product
build in this block. No release gate is closed; official SDK/subrepos are unchanged.
