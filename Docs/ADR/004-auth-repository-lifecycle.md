# Auth repository lifecycle

Status: Data state machine and Domain-only AuthPresentation are live; operation/recovery remains partial,
2026-09-28. Local state-transition and lifecycle fixtures pass; real-device verification remains open.
See [executed checks](../Verification.md).

## State owner

`Domain.AuthRepository` is the auth state boundary. `Data.DefaultAuthRepository` owns the
`signedOut`, `locked(account)`, `unlocking(account)`, `unlocked(account)` and `expiring(account)`
state and publishes revisioned `AuthSessionSnapshot` values through `AsyncStream`. Snapshots carry
the transition kind and accepted runtime ID; no secrets or SDK values. Restore reads only the combined, private
session record through `AuthSessionLifecycleStore`; legacy split account metadata never restores
an authenticated state.

Return-user unlock checks the complete `AccountSession`, including account ID and configured
server routes. A failed/cancelled attempt returns `unlocking` to `locked`; cancelling either the
LocalAuthentication or Keychain biometric prompt is quiet and does not clear enrollment. Handoff
checks the persisted account again. Expiry requires the accepted runtime UUID, so a delayed event
cannot move a later unlock to `expiring`. Lock changes observable state before it starts synchronous
persistent revocation; a cleanup error leaves the repository locked. Logout changes it to signed
out before cleanup; the app's existing recovery screen blocks new unlock until retry succeeds.

Login, TOTP, unlock and biometric-enrollment Observation models reject duplicate in-flight submissions;
return-user unlock keeps its own gate active across handoff preparation even when an inner operation
updates presentation loading state. TOTP cancellation/server switching and mutable inputs are
disabled while the request is active. Biometric enrollment completes its route handoff at most once.
Auth and Settings surfaces map SDK/Keychain/transport failures to stable text instead of displaying
raw `localizedDescription` values; explicit auth errors and safe HTTP status codes remain useful.

The app composes and injects one repository instance and one Data.AuthCredentialStore. Data owns
private/shared credential persistence, app token bootstrap/commit authority and fresh login/TOTP
sequencing. Pending capabilities own scoped AutoFill publication and biometric enrollment.
Data also owns returning password/PIN/biometric sequencing behind Domain.ReturningUnlockCommands.
Data.DefaultAuthFlowService restores typed routes and prepares a Domain-only runtime capability.
Displaying the unlock screen no longer starts unlocking; submission does. `AppFeature.AppModel`
owns the typed app-visible state and registers its accepted session after preparation and a final
repository/runtime/epoch check. Main window, Settings and menu bar share this observable model.
It reacts directly to runtime-bound repository expiry and ignores queued older revisions. Lock,
logout and returning-user attempts feed the same repository actor. SessionRuntime still owns the
revocable SDK resource and its tasks. The app composition root supplies a legacy session adapter
for unmigrated feature consumers. See [AppModel ownership](005-app-model-ownership.md).

Auth routing now retains a typed Observation model per route instead of recreating it during body
evaluation. Route IDs reject retired callbacks and delayed restore/handoff; pending providers are
revoked when their context is abandoned. Unlock logout delegates to the model's complete cleanup
path. This guards local routing, not every credential-operation persistence race. See
[Auth route lifetime](006-auth-route-lifetime.md).

App composition creates the credential store from explicitly supplied private/shared Keychain
and container, then injects that store into DefaultAuthFlowService and DefaultAuthRepository directly.
Data.SessionPinUnlockSettings implements the Domain port against the same store and authenticated
runtime; the flow service creates no storage or repository. AuthServices is deleted. AuthDependencies.live/liveKeychainStore,
PinEnrollment (including its former live factory) and the static
AuthSession factory are removed. The route controller has no SwiftUI rendering or Store wrapper;
AuthFlowView renders its typed screen. Navigation/UI exit retires the old model, cancels its owned
operation and clears password/PIN/code fields. Accepted handoff transfers provider ownership to
SessionRuntime; UI teardown does not revoke it. A retired/noncooperative PIN crypto failure is
not counted as a wrong PIN. These are source-tested lifetime guarantees, not durable rollback or
secure zeroization of SDK/Swift memory. AppArchitecture and the AuthFeature package are removed;
all Auth UI/tests belong to AppModules.AuthPresentation.

## Boundaries and remaining work

This is deliberately not completion of S-303. Prelogin/password/TOTP HTTP services now live in
Data, and Domain.PreloginService returns SDK-free KeyDerivationParameters. SDK conversion and
numeric validation are shared by app/extension adapters. Fresh hashing, OAuth/TOTP, password crypto
initialization and commit now run in Data behind Domain commands/capabilities; old raw SDK/credential
route contexts are removed. Returning unlock now also uses Domain commands and a nonsecret
account snapshot; Data owns SDK/key/counter/fallback operations. Auth handoff now passes
Domain.AuthenticatedSessionCapability, implemented by Data.AuthenticatedSession against the
validated persistent scope. Only app composition consumes that concrete assembly; no raw
Client or token closure is exposed to presentation. Credential commit/recovery
ownership across repository handoff remains incomplete. The repository does
not store passwords, PINs, SDK clients, tokens or wrapped keys in its state values.

Returning unlock rejects invalid KDF metadata before repository beginUnlock, crypto or biometric
evaluation; it clears inputs but consumes no PIN attempt and removes no enrollment. Fresh login
validates token KDF metadata before crypto/persistence and stores the exact parameters used by
prelogin. Omitted metadata does not switch a saved Argon2/custom-PBKDF2 account to defaults.
The same validated parameters feed AutoFill publication. Login/TOTP/enrollment models now consume
Domain-only commands/results, as does returning UnlockModel. The controller/root UI now consumes
Domain.AuthFlowCommands and the runtime capability. See [AuthPresentation](013-auth-presentation-and-handoff.md).
See [command capability ownership and remaining limits](011-auth-command-capabilities.md).
See [returning unlock and mutation epoch checks](012-returning-unlock-commands.md).
See [transports and KDF](009-auth-transports-and-kdf.md).

PIN enrollment/removal, PIN attempt reads/writes, and biometric-key reads/disable now require the
exact sign-in scope while holding the existing shared Keychain transaction lock. Settings enrollment
validates authorization before crypto and again afterward; enrollment/removal additionally compare
the captured revocation epoch inside the storage write transaction. App-wide PIN
submission gating also covers overlapping model instances. If a successful
PIN cannot reset its attempt budget, the flow persistently disables/removes PIN enrollment or keeps
the current unlock route blocked with an explicit warning. Unlock routing captures that scope and
refuses to construct a returning-user token provider from a replaced lineage. Fresh sign-in
already rotates the scope and clears old convenience keys. The Keychain items are still separate
writes rather than one atomic multi-item record; cleanup failures can leave recovery work, and
setting mutations racing a real lock need execution on signed devices. Credential entry and the
wider account-settings migration remain open.

AppAuthTokenProvider and its bootstrap factory are Data-owned and SDK-free. Fresh-login commit
proofs and unscoped raw-key/token persistence helpers are Data-internal. SDKManagedTokenAdapter
only forwards a Sendable token capability and denies cancelled/late outputs. Legacy Argon2
publication validates against the same canonical mapping as the producer; previous raw-default
comparison could incorrectly refuse the normalized metadata. Real storage-path fixtures now
cover this case and ensure the original private record remains unchanged.
See [credential authority](010-auth-credential-authority.md).

Cleanup and transition behavior has pure source fixtures for restore, account mismatch, failure,
stale expiry, state stream, lock/logout failure and retry, stale PIN/biometric scope denial, and
parallel unlock submission. New model fixtures cover caller/route cancellation, ignored late errors,
direct Observation, secret clearing, retry, shared injected stores and provider ownership after
handoff. New AppModel fixtures cover late completion after lock, preparation/
cleanup ordering, cleanup retry, logout during lock, repository expiry, timeout and stale callbacks.
The local fixtures have been built and **pass**, including gated actor interleavings. A failed
lock/logout now prevents restore and unlock handoff until explicit cleanup succeeds; pending logout
cannot be downgraded to lock. That marker is not durable across relaunch. Neither fixtures nor
unsigned builds validate real Keychain failures. See [token ownership](001-auth-token-ownership.md),
[AutoFill lifecycle checks](../AutoFillLifecycleChecks.md) and the
[implementation plan](../Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).
