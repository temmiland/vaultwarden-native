# Observable app session owner

Status: live app-shell migration, 2026-09-27. Local regression tests and unsigned macOS/iOS
Simulator builds pass. S-303/S-306 and real-server/device/process release checks remain partial.
See [executed checks](../Verification.md).

## Ownership and composition

`AppFeature.AppModel` is the sole observable owner of the app-visible session state. Both app
entry points retain it with SwiftUI `@State`. The main window, macOS Settings scene and menu bar
read the same instance. RootView switches on a typed state: credential entry/locked, preparation,
unlocked content, or security recovery. The former `AppSessionStore` class is removed.

The entry points now retain a typed AppStartup result, which owns that same AppModel and one
instance-based AppComposition. Storage configuration/container resolution must succeed before
creating the repository/model. An unavailable result shows configuration recovery in main and
Settings scenes without starting auth, timeout or credential cleanup. AppStartupRootView forwards
scene phase and timeout ticks only to a configured model. There are no static live auth services.

The target imports Domain, Foundation and Observation, not SDK or platform UI types.
`AppComposition` supplies the Domain AuthRepository, sensitive-file setup/cleanup and timeout
driver. AppSessionResource aliases Domain.AuthenticatedSessionCapability. The generic model
retains the app-owned LegacySessionAdapter, which wraps Data.AuthenticatedSession. The app model sees only
account metadata, runtime ID, access checks and revocation. Vault/Send/Settings presentation uses
Domain ports. Auth UI handoff passes only a Domain runtime capability; the sole concrete Data
conversion lives in AppComposition. No raw Client or token closure crosses the UI boundary.
See [AuthPresentation handoff](013-auth-presentation-and-handoff.md).

Timeout ownership stays in the model. Scene phase is mapped to an AppFeature enum; the app shell
only forwards lifecycle changes and timer ticks. The injected timeout policy is persisted in
Data and exposed to SettingsPresentation through a Domain port.

## Repository events and handoff

`AuthSessionSnapshot` contains the repository state, accepted runtime ID, monotone in-memory
revision and transition kind. These revisions identify auth actor transitions, not token/vault
generations or persistent sign-in lineage. Observation is registered on the repository actor and
immediately yields its current snapshot; model teardown cancels its observation task.

The model ignores older/equal revisions and handles an expiry only for its accepted or preparing
runtime ID. Expiry can trigger logout through the stream, independently of the legacy callback;
the same callback remains idempotent and cannot expire a later unlock. Restore and failed-unlock
events are distinguished from explicit lock/logout so initial queued snapshots cannot abort a
new handoff. Account metadata alone never opens authenticated content.

Handoff establishes a preparation gate before suspension. After preparation it asks the
repository to accept the runtime and reads its current snapshot. Before publishing it checks
the runtime/account, current repository state and the app's authentication epoch again. There is
no suspension between the final checks and presentation. Lock/logout advance the epoch and
revoke the runtime, preventing a late successful completion from reopening the UI.

## Secure cleanup

Lock/logout immediately replace main content with recovery and reject additional handoffs.
Runtime revocation cancels secret operations before persistent AutoFill/token cleanup. Cleanup
then waits for any in-flight temporary-storage preparation before closing temporary-file access:
a noncooperative late setup cannot reopen storage after cleanup has returned.

Only one cleanup operation runs at once. A logout requested during lock is retained and upgrades
that operation after its current pass. Logout revocation and persistence still run even if the
first lock pass failed. Persistence and temporary-file cleanup are attempted independently.
An error retains the requested action and displays retry outside the authenticated tree;
new session capabilities are rejected and revoked until retry succeeds.

## Verification and remaining work

Source fixtures cover repository approval completing after lock, noncooperative preparation,
cleanup failure/retry, logout during lock, stream-driven expiry, stale expiry callbacks and
timeout ownership. Repository fixtures also cover snapshot revision/runtime identity. They have
been built and pass, also in five repeated runs of the critical 27-test block. These gated task
interleavings do not prove real multi-scene, Keychain or cross-process behavior.

Credential entry before AppModel handoff lives in AppModules.AuthPresentation; password/2FA,
returning unlock, enrollment persistence, restore and runtime preparation live in Data behind
Domain commands. App composition injects the same repository into AppModel and DefaultAuthFlowService.
Route-owned models and restore/handoff guards are described in [Auth route lifetime](006-auth-route-lifetime.md).
Full operation-owned commit/cancellation and the final repository-observation-only workflow
remain open before S-303 can close; the app-model epoch covers handoff that has already started. Durable cleanup
recovery across relaunch, real Keychain/cross-process failures and signed multi-scene/device
lifecycle checks remain open. No release gate is satisfied by this migration alone.

The app model now additionally validates persistent session authorization before/after repository
acceptance. The live adapter delegates to the provider's fixed pre-crypto revocation epoch and
sign-in scope, covering an old capability that arrives only after model lock has finished. This
complements the model's local handoff epoch; it does not replace the remaining credential-operation
ownership or signed lifecycle checks. See the persistent-authorization section of ADR 006.

See [auth lifecycle](004-auth-repository-lifecycle.md),
[AutoFill lifecycle checks](../AutoFillLifecycleChecks.md) and
[the implementation plan](../Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).
