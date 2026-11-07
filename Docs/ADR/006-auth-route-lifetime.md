# Auth route lifetime and injected authority

Status: partial S-303/U-504 migration, 2026-09-28. macOS and iOS Simulator app/extension builds pass.
Local regression tests also pass. This does not close credential-entry security or
release verification.
See [executed checks](../Verification.md).

## Stable route-owned screens

`AuthCoordinator` is a typed Observation flow controller, without a generic
Coordinator/AnyObject navigation base. It creates one typed screen and its Observation model only
when entering a route. SwiftUI body evaluation reads that retained screen instead of constructing
new models. Unrelated redraws no longer discard input, duplicate the screen's submit gate or
replace the owner of in-flight work.

Each route receives an opaque in-memory UUID. Navigation invalidates the previous identity and
cancels retained restore/handoff tasks. Callbacks from a retired screen cannot navigate or finish
the current flow. Rejected pending contexts revoke their token provider. A provider retained for
2FA/enrollment is also revoked when navigation leaves that context, but retained when the same
provider moves forward to the next stage.

Navigation first retires the previous model. AuthOperationLifetime owns one task per screen,
deduplicates operations and forwards cancellation from the UI caller. Retirement permanently
cancels it and rejects later input/submits, even if another caller still retains the old model.
Password/PIN/code fields are cleared synchronously; completion after noncooperative suspension
cannot restore an error or hand off that retired screen. Two-factor credentials are not part of
observable state: the model's optional private context is dropped on cancel/retirement. Back
callbacks capture only the environment, not the context's password/hash/Client.

AuthFlowView owns rendering. AuthRootView retains the controller in State and stops it when the
auth tree disappears; reappearance starts a fresh route. A successful handoff explicitly transfers
provider ownership: that UI teardown must not revoke the accepted SessionRuntime's provider.

Restore checks its route identity after Domain command awaits and revokes a stale returned
command. Data captures the persistent epoch before repository suspension and checks account/scope
and state again. Only submission begins unlocking. Handoff checks identity and provider scope
before constructing the session and again after installing the expiry handler. It also checks
runtime access immediately before the final callback. Failed/stale handoff revokes any constructed
runtime and the pending provider. Expiry captures the injected repository, not a global lookup,
so it remains tied to the same authority after the coordinator disappears.

## Composition and cleanup

`AppComposition` retains one repository and injects it into AppModel and Data.DefaultAuthFlowService.
App composition constructs Data.AuthCredentialStore once from injected private/shared Keychain
and container, then passes it to the flow with HTTP, biometric/device-name clients and app version.
DefaultAuthRepository receives that same store directly; Data.SessionPinUnlockSettings binds the
Domain settings port to it and the runtime. The old lifecycle/PIN composition adapters and
PinEnrollment are removed. AuthSession and AuthDependencies.live/liveKeychainStore are removed.
Neither views nor the coordinator create live dependencies.
AuthServices is deleted; AuthDependencies now exists only in integration-test fixtures.
AuthRootView and AuthCoordinator use Domain.AuthFlowCommands and the biometric platform port.
The complete AuthPresentation target depends only on Domain/SharedUI; the AuthFeature package is removed.

Default prelogin/password/TOTP transports have moved to Data and use injected Networking HTTP.
The Domain prelogin port and KDF values replace SDK.Kdf in route contexts. The SDK adapter alone
converts numeric parameters; Data maps stored/token metadata and AutoFill publication. Direct
credential transport calls reject unsafe servers before HTTP and check cancellation after a
noncooperative response. Fresh login/TOTP sequencing subsequently moved to Data behind Domain
commands/capabilities; returning UnlockModel subsequently moved behind Domain commands as well.

App token bootstrap and persistent commit authority now live in Data.AppAuthTokenProvider and
AuthCredentialStore. The provider's SDK conformance is replaced with a narrow SDKManagedTokenAdapter;
Data needs no SDK import. Settings PIN writes compare a captured epoch inside the storage lock.
Fresh login/TOTP, private retry credentials and scoped pending key operations now also run in Data.
All five screen models receive only Domain ports, and route contexts contain no client/provider/password/hash.
Challenge and pending stages retain the same attempt ID; completed challenge revocation does not
revoke its successor. The Data handoff bridge uses the same resource and is single-use; it installs
expiry before returning. Data now also owns restore and the final UI callback carries only a
Domain runtime capability. PIN counter/reset and enrollment cleanup additionally compare the
captured epoch inside their write transaction. See [returning commands](012-returning-unlock-commands.md).
See [credential authority](010-auth-credential-authority.md) and
[command capabilities](011-auth-command-capabilities.md).

VaultCore is removed. All routes use Domain.ServerEnvironment and its credential-server policy.
Handoff passes the validated token scope into Data.AuthenticatedSession, which accepts a Domain
account and opaque SDKSessionClient rather than a raw Client/token closure. Its storage owner
retains the exact persisted server spelling, including a legacy trailing slash; normalized
transport routes must not change grant/cache ownership. Only AppComposition consumes the
concrete session; UI has a Domain-only boundary. Full operation/recovery ownership remains open.
See [AuthPresentation handoff](013-auth-presentation-and-handoff.md).

Logout from the unlock screen delegates to AppModel's injected cleanup callback. It does not call
the repository directly or navigate to a fresh login while cleanup may have failed. The app owner
controls recovery, persistence and sensitive temporary files together.

The unavailable-Keychain route also offers explicit confirmed logout through that same app
cleanup path. A corrupt private record otherwise correctly denies fresh-login commit but could
leave recovery with no way to clear it. This action removes only device-local sign-in/AutoFill
access, not the server vault. A failed final handoff revokes its provider and rebuilds the
saved-sign-in route, instead of leaving a finished-once enrollment screen with a dead provider.

## Explicit limits and verification

### Persistent auth authorization

Fresh password/2FA login now captures the existing revocation epoch and prior sign-in scope
before prelogin/network/SDK suspension. Commit compares both under the same cross-process storage
transaction before revoking any capability or replacing the private record. Lock/logout, including
lock while signed out, or another fresh sign-in deny the old attempt. A same-lineage token refresh
does not invalidate it. Candidates are validated before old grant removal. The committed record
and its newly rotated epoch return from that transaction together; no post-commit read can adopt
a later lock's epoch. Production has no unchecked two-argument session-save entrypoint.

Returning unlock captures its epoch before `beginUnlock` and biometric/crypto suspension. Provider
construction compares that captured epoch; subsequent scope/token access validates the same fixed
epoch rather than just the sign-in scope (which intentionally survives lock). AutoFill sharing
uses the provider's epoch captured before derivation. Biometric enrollment compares it inside the
actual Keychain write transaction. AppModel validates the persistent authorization before and
after repository handoff, including a capability whose callback arrived only after lock ended.
An authorization failure for an accepted expiring runtime performs logout, not just lock.

Login clears observable passwords on success, 2FA detour, server switch and cancellation/retirement;
TOTP success/cancellation/retirement clears the code. PIN cancellation, including a noncooperative
crypto operation that throws another error after route retirement, consumes no wrong-PIN attempt. A failed post-crypto
authorization check is not classified as incorrect PIN. These are partial secret-clearing and
operation-cancellation improvements, not secure zeroization of Swift strings.

Route IDs guard local routing/handoff, not cross-process sign-in lineage or transactional commit.
Cancelling an owned task does **not** erase every retained credential buffer, stop noncooperative
SDK work or roll back an already committed session before its callback.
The epoch/scope guard above specifically denies commit after successful persistent revocation or
lineage replacement; a route-only cancellation is not itself that persistent revocation.
Prelogin/KDF/password/2FA work needs an operation-scoped cancellation/commit authority at the
repository/persistence boundary. Provider revocation alone is not a durable rollback of an already
committed account. UI dismissal alone must not be treated as proof of secure cleanup.

Source fixtures cover direct Observation/synchronous state, retained login input across view construction, retired-screen
navigation, delayed restore after route change and unlock logout delegation. They use fake
persistence/platform/network dependencies and explicit continuation gates, without executing SDK
crypto or sleeping. They have been built and pass. Real multi-window, Keychain/biometric,
credential-commit and app/extension lifecycle verification remains outstanding.

Additional source fixtures cover stale fresh commit after lock/logout/replacement, competing
signed-out attempts, same-lineage refresh, epoch-read failure, invalid candidate/grant preservation,
missing provider authority, returning unlock across lock, stale biometric enrollment, delayed
AppModel authorization and expiry failure, and PIN cancellation. Unlock fixtures use fake crypto
services but retain legacy SDK client bootstrap; the PIN suite is serialized for its process-wide
attempt gate. These local fixtures and both unsigned app builds pass; real-device, server and
concurrent-process checks remain open.

The latest block adds caller/route cancellation gates for prelogin, TOTP, biometric evaluation and
returning unlock; it checks duplicate suppression, secret clearing and ignored late errors without
SDK crypto or sleeps. Additional fixtures verify the one injected store across repository/PIN
settings, clean controller restart, accepted provider ownership and the noncooperative PIN-error
budget regression. The removed generic Store tests have no live subject; retained-model/direct-state
invariants are exercised against the production auth models instead. See the latest executed
checks for exact suite counts and both unsigned build results.

See [auth lifecycle](004-auth-repository-lifecycle.md),
[AppModel ownership](005-app-model-ownership.md) and
[the implementation plan](../Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).
