# AutoFill lifecycle release checks

> Szenario-Runbook, keine eigenständige aktuelle Arbeitscheckliste.
> Abschlussstatus und offene Aufgaben ausschließlich in [RemainingReleaseWork.md](RemainingReleaseWork.md), insbesondere F-02/F-10–F-12/F-23.

These checks are **not executed**. Unsigned macOS/iOS Simulator builds cannot verify shared
Keychain entitlements, OS invocation lifetime, device authentication or credential completion.
Use disposable accounts and synthetic credentials on a signed macOS, iPhone and iPad build.
Never log keys, passwords, TOTP seeds/codes, credential IDs, user handles or client-data hashes.

## Current implementation boundary

Each invocation owns one revocable SDK resource. Key, account metadata and a fresh unlock ID
are published in one Keychain record. A separate nonsecret revocation epoch is rotated before
key removal; both are compared under the existing app-group process lock. Late pre-lock grant
publication and extension token refresh cannot target a later unlock, even if token generations
coincide. An invocation never switches to another account or unlock after showing its picker.

The private account/token authority is now one Data-owned Keychain record. Tokens bind account,
server and sign-in lineage; shared tokens also bind the fresh unlock ID. Only a matching grant
can authorize them. Login/unlock async boundaries revalidate that lineage. Production locking
requires the App Group container; process-only serialization is explicitly injected for fixtures.
Data now owns private/shared merge/commit and both token-persistence policies through a synchronous
transaction port. SecurityStorage owns the process/file lock; the existing physical filename is
unchanged. Data supplies envelope/grant encoding; shared Composition supplies App Group configuration.
`Data.DefaultAuthRepository` owns restored and live auth state transitions. The Auth route checks a
returning account's configured server before unlock; accepted handoff is checked against the
persisted session, and expiry events must match the accepted runtime ID.

App and extension use the same Data token coordinator and typed refresh transport. Each fixed
scope owns its local single-flight job; the extension persistence adapter additionally checks its
fixed unlock proof. 429/5xx remain retryable even with a misleading OAuth body. Explicit 400/401
`invalid_grant` without a challenge closes that coordinator; the app expiry callback is not an
extension-wide cleanup mechanism. No cross-process network deduplication is claimed.

Shared token/grant encoding and synchronous transaction leases now live in Data. Their Keychain
and App Group container are explicitly injected; production operations without a container fail
before touching Keychain. The existing storage names, schema and lock filename are unchanged.
Shared account metadata is SDK-free in AutoFillContract; its numeric KDF bounds are checked in
the SDK adapter before conversion. `Composition/SharedAppGroup.swift` is compiled into all four
app/extension targets. VaultCore is removed; signed entitlement/configuration checks remain open.

All four targets now expand the same xcconfig storage values into runtime Info.plists and
entitlement templates. Composition rejects invalid/missing signing prefixes and containers before
constructing shared stores; no personal-team fallback remains. The main app shows configuration
recovery before auth is created. Local settings/template checks do not prove signed App Group or
Keychain authorization; the device matrix below is unchanged.

KDF mapping now shares one validated adapter with main-app prelogin/unlock. AutoFill publication
uses the same parameters as the private account; a legacy Argon2 record with omitted iterations
uses Argon2's existing default of 3, not PBKDF2's 600,000. Invalid/unknown numeric metadata fails
without guessed publication. New local fixtures verify conversion and metadata agreement, not
real SDK cryptographic round-trips or signed extension behavior.

Data.AuthCredentialStore now checks that same canonical mapping inside the actual grant/token
publication transaction. This closes a leftover raw-default comparison that could reject legacy
Argon2 publication even after the producer mapped it correctly. Local storage-path fixtures cover
omitted defaults, unchanged private metadata, foreign/changed fields and stale publication epochs.
App token bootstrap/commit authority also lives in Data; the SDK callback is an adapter, not a
second token owner. These results still do not execute the signed-process matrix below.

The legacy encrypted cache now carries an account/server owner and a UUID revision. Cache reads
reject missing ownership/revisions, a wrong account and a revision change during an invocation.
Password/TOTP fulfilment rereads the selected item and checks access immediately before the OS
completion call. Passkey callbacks check access around device authentication and before writes.
Registration deliberately does not reject its **own** successful cache update after server commit.
Cache reading and fenced mutation now live in `AutoFillData.LegacyAutoFillCacheStore`. Its injected
authorization port holds the shared process lock while validating the original unlock and tokens,
reading the cache revision and replacing the encrypted file. The pure URI matcher and pinned PSL
also live in AutoFillData; SDK mode conversion and cipher HTTP/wire mapping live in the SDK adapter.
The Xcode app/extension target graph no longer depends on VaultFeature.

`AutoFillData.ExtensionVaultSession` now assembles that one invocation resource and the
`CredentialQuery`/`PasskeyService` actors against injected proof/cache readers. AutoFillVaultStore
only composes it. SDK conversion/configuration and backing values live in the adapter; AutoFillData
does not import BitwardenSdk. Queries retain no decrypted cache and picker summaries carry no
passwords or TOTP seeds. Fulfilment resolves the selected secret afresh. Partial item failures
produce a visible list warning; duplicate cipher/credential identities are denied. Assertions
revalidate the current exact RP and selected credential bytes before the callback and reject
late revoked/cancelled results or a different returned credential ID. The synchronous revocable
lease remains necessary for existing FIDO callbacks. Local gated fixtures pass; they do not
execute the OS context or actual SDK cryptography. See [the split](ADR/014-autofill-query-and-passkey-orchestration.md).

Direct OS passkey identities now resolve only their selected cipher and exact credential, without
querying the whole vault. Failed identified password/TOTP requests cancel instead of falling
back to an identifier-free picker. Only explicit list entry points can authorize manual browsing.
Three gated direct-passkey methods pass. The subsequently added terminal boundary is used by the
controller and executed against injected synthetic contexts; the actual Apple controller/context
and signed UI invocation remain unexecuted.

Visible invocation sessions also reread the shared grant on a scheduled one-second monitor.
This is not a real-time deadline or an interprocess notification; fulfilment guards do not depend
on that monitor. Revocation clears the picker and closes its local SDK resource. No zeroization
of SDK memory or already-issued values is claimed.

Completion/cancellation use one invocation gate and a synchronous terminal context port. The live
controller delegates every output/cancel to AutoFillRequestCompletion; only the Apple adapter
starts OS terminal calls. Fake-context tests verify exact-once, lease/cancellation checks,
superseded requests, capability/output validation and reentrant dispatch without successor
teardown. Query/context compositions cover selected-only decryption, lock before output, late
query results and generation after TOTP selection. Explicit biometric user cancellation is sticky
through callback-error wrapping; confirmed writes retain recovery priority. Unknown registration
errors disable Save rather than encourage another write. The full block passed 751 package tests
and both unsigned builds. See [ADR 020](ADR/020-autofill-terminal-context-and-error-policy.md).
This is not a real AuthenticationServices controller/UI/OS test, and generation-at-selection
does not verify a TOTP period/expiry boundary.

Update 2026-09-29: the actual `CredentialProviderViewController` now runs in hostless macOS and
iOS-Simulator integration bundles with injected synthetic session loaders: hosted content is
replaced with full UIKit containment and edge constraints, a new invocation revokes the previous
session synchronously, and a gated late loader from a retired invocation is revoked without
publishing content. The real `ASCredentialProviderExtensionContext` completion, PluginKit,
QuickType and signed invocation remain unexecuted. See [integrated acceptance](IntegratedAcceptance.md).

## Typed SDK callbacks and registration (2026-09-28)

FIDO callback implementations and WebAuthn encoding now belong to BitwardenSDKAdapter, not the
extension. AutoFillData owns typed registration persistence and whole-operation single-flight;
PlatformServices supplies device-owner verification via a Domain port. Synthetic SDK callback
fixtures cover exact decoded userHandle/ID/RP matching, fail-closed selection, metadata errors,
late verification and owner/edit policy. Persistence/coordinator gates cover stale crypto,
reserve-before-HTTP, post-submit UI cancellation, receipt binding and FFI-wrapped error state.
The verifier uses fresh contexts and rejects late cancelled results; fake-context tests do not
show a real LocalAuthentication prompt. No real SDK crypto/FFI callback or OS completion executed.
See [typed ports and limits](ADR/018-autofill-sdk-callback-and-registration-ports.md).

## Shared OS-mutation batches (2026-09-28)

App replace/clear and extension add/recheck/targeted compensation now share an FD-owned async
App Group lock, separate from the short grant/token lock. An invalid extension removes its
identity before a queued newer app publish; queued publication rechecks current cache/proof.
Old app cleanup cannot clear a successor unlock's suggestions. Contended acquisition is cancellable
and bounded; timeout never expires an acquired OS batch or enables uncoordinated fallback.
Real-file/independent-descriptor and gated fake-OS tests pass in one process, not signed concurrent
processes. Missing container/coordination may retain stale suggestions; revoked grants still deny
fulfilment. A process death cannot recall a submitted OS-daemon request. See
[ordering and remaining limits](ADR/019-shared-credential-identity-mutation-ordering.md).

## Required matrix

Registration now uses an operation-owned write actor and a versioned App Group mutation journal
reserved before HTTP. Exact account/server and the fixed grant authorize its transactions. A
confirmed cache failure retains server success and a repair receipt; unknown/confirmed outcomes
cannot become retryable creates. App sync resolves only an exact unique credential after matching
cache and OS publication. Pending/storage-failed repair is visible; absence does not prove that a
write was rejected. Local gated/file/transport fixtures pass, not the signed matrix below. See
[registration recovery](ADR/015-passkey-registration-write-recovery.md).

Confirmed registration now commits encrypted cache first and incrementally adds only the selected
new passkey. Exact proof/UUID/monotonic-revision/encrypted-record receipts are checked around
metadata and OS awaits. Late invalidation or uncertain OS failure removes only the attempted
identity; cleanup failure remains durable repair, not another upload. Disabled/non-incremental
stores never trigger replace-all. The journal still requires full app-sync reconciliation.
Gated local fixtures pass; actual cross-process OS ordering remains unverified. See
[incremental publication and its limits](ADR/016-passkey-registration-incremental-identities.md).

All rows are pending on every supported signed platform.

| Scenario | Expected behavior |
| --- | --- |
| Fresh unlock followed by sync | Password, TOTP and existing passkey requests use the matching account cache. Registration into an existing/new login works through the existing flow. |
| App locks/logout while picker is open | The scheduled monitor cancels the invocation and clears its content. A selection racing that monitor fails its independent grant check; no newly authorized fill is produced. |
| Lock during user verification | Passkey assertion/registration denies the obsolete grant after authentication. No old assertion reaches completion; a write already sent to the server may need recovery. |
| Same account/key locked and unlocked again | The old picker cannot recover by loading the new grant. A new OS invocation is required. |
| Account changes, including the same user ID on another server | Old session and old cache are rejected; metadata/key/cache from different accounts are never combined. |
| Sync updates organization keys/cache while picker is open | The old invocation rejects that revision at selection/output. A new invocation initializes crypto from the new cache. |
| Extension refresh returns after lock + re-unlock | It cannot overwrite the new shared tokens or return an access token under the old proof, even with the same starting token generation. |
| Concurrent token requests in one invocation; cancel one waiter | One refresh per generation in that coordinator. Cancellation denies that waiter's output without cancelling other waiters. Noncooperative work may delay return. |
| 429/5xx with an `invalid_grant` body and Retry-After | Do not expire the session. Suppress same-generation refresh until the finite delay ends; no background retry loop. |
| Stale rejection after another process commits a higher matching generation | Adopt the eligible newer tokens without expiring that newer rotation. Never overwrite a newer winner. |
| Simultaneous rotating refresh in app and extension; process killed after server response | Check server-token consumption, durable adoption and recovery. Actor-local single-flight and the persistence lock do not resolve this race; recovery remains open. |
| Lock during an in-flight registration write | The old invocation cannot publish a late result or project into another account. Already committed/ambiguous server writes are not undone; inspect/sync the vault before retrying. |
| Rapid selection/double tap, cancel while working, new OS entry point | At most one terminal call per invocation; no old callback completes/cancels the new request and no parallel duplicate save starts. Verify eventual completion/cancellation too. |
| Keychain read/entitlement error or device locked after boot | No fallback to a retained client. If epoch rotation or key removal fails, attempt the other independently and report cleanup failure in the app. |
| Upgrade from split account/tokens, raw/schema-1 shared grant or unbound cache | Open the app, sign in once with password/2FA to migrate split sessions, unlock and sync. No legacy fallback authorization/decryption. Restart/close requests from an older extension binary; this cannot patch an already-running older binary. |
| Higher token generation for another account/server/sign-in, or stale unlock ID | Neither app reconciliation nor extension token access adopts it. A generation is comparable only inside the exact ownership scope. |
| Shared-token write fails after server refresh | Attempt to retain the issued pair privately and revoke the obsolete grant; report failure. Verify retry without losing the private rotation and independent revocation failures. |
| Shared refresh succeeds but private write fails | Preserve the matching shared rotation and adopt it after private storage becomes available. Check lock/error recovery before allowing another unlock. |
| Both rotation writes fail, with/without revocation failure | Deny the refresh result and expose the redacted Data classification. The issued rotation may be lost; typed UI propagation and durable recovery remain open. Verify independent cleanup, not only the first error. |
| Missing App Group container/entitlement | Production does not silently substitute a process-only lock or publish a shared capability. Explicit fixture policy is not reachable from live composition. |
| Corrupt/future unlock schema, invalid KDF or missing cache owner/revision | Deny safely without trapping, silently creating a new account, clearing re-prompt flags or treating device authentication as master-password verification. |
| Registration process dies before/during/after HTTP or local projection | The reserved marker survives; no blind second registration. Full sync resolves only the exact persisted credential after cache/OS repair. Unobserved outcomes remain blocked. |
| App full replacement/clear overlaps incremental registration publication | Verify shared batch ordering: add/recheck/targeted compensation finish before queued app replace/clear; queued work revalidates cache/unlock. Characterize old binaries, process death and late OS-daemon requests; full sync must repair, no global atomicity claim. |
| Identity store disabled/non-incremental or add/targeted removal fails | No replace-all fallback or second HTTP write. Preserve the journal/repair receipt; verify app-sync repair and unchanged unrelated password/TOTP/passkey suggestions. |
| Journal read/write/synchronize/remove fails or has an unknown future schema | Do not reset it or send an unjournaled registration. Preserve existing data and surface recovery; verify restart and storage availability. |
| Review during originating unlock, after fresh unlock or using an old record with no origin | Same-unlock/legacy reviews cannot abandon tracking. A fresh-unlock, full-sync review requires explicit inspection/risk acknowledgment and removes only its exact unchanged local marker; no rollback or HTTP retry. |
| Review is dismissed, duplicated, changed by sync/CRUD/phase update, cancelled or locked | Dismissal does nothing; changed/reused consent fails. Submitted local acknowledgment finishes independently of UI cancellation, but lock prevents late output. Sync repairs ambiguous local acknowledgment; never claim server rejection. |
| Old HTTP request commits after manual local abandonment | Fresh unlock cannot recall HTTP. The prompt explicitly warns of late-write/duplicate risk. Characterize the real server/relying-party outcome; no automatic registration follows acknowledgment. |
| Registration cache/OS repair fails, locks mid-sync or finds duplicate/wrong RP/credential/cipher | Keep the marker and warning. A later valid full sync may repair local projection without repeating the server mutation. |

## Still open

- The UUID cache revision is local invalidation metadata, **not** a server revision or an atomic
  repository/cache/OS-identity transaction. Main-app mutations now use a repository-owned projection
  pipeline; real cross-process/file/OS failure recovery remains unverified (`V-401`/`V-402`/`V-403`).
- Registration now journals submitted/confirmed mutations and gates retry across writer/store
  recreation. Immediate incremental identity projection and explicit review/abandonment for new
  unlock-bound markers are implemented; legacy-origin and real server/process/power-loss/signed
  workflow verification remain pending (`X-604`). See [reviewed abandonment](ADR/017-passkey-registration-reviewed-abandonment.md).
  A full app sync plus exact credential/cache/OS verification repairs observed writes; a sync
  without that credential never automatically removes its marker.
- A cross-process lock cannot make Keychain access and the OS completion API one transaction.
  A credential already handed to the OS cannot be recalled; real lock/completion races need
  signed-device verification. Noncooperative SDK/network work may finish internally, but its
  revoked result is rejected at the implemented boundaries.
- Legacy cache permissions do not carry collection policy; silent SDK-internal per-field
  decryption failures remain incompletely classified. Thrown eligible-item failures now show a
  partial-list warning. Reader/matcher/query/assertion/registration orchestration lives in AutoFillData;
  SDK-shaped FIDO callbacks live in BitwardenSDKAdapter and platform verification in PlatformServices.
  The unscoped identified-request fallback is removed; the live terminal boundary has injected
  context/query tests. Actual Apple controller/UI/OS completion, real verification/FFI errors and
  real SDK/OS expiry acceptance remain open. Local epoch-aligned TOTP rollover, bounded
  regeneration and query-to-dispatch expiry are now covered with an injected clock; SDK period
  and exact generation date reach the terminal check. See [ADR 021](ADR/021-autofill-totp-expiry-boundary.md).
- Password/TOTP/returning execution and presentation now use Data implementations and Domain
  ports. Full operation-owned commit/cancellation, the final app-shell adapter/workflow and
  durable cleanup retry state across app relaunch remain unfinished. PIN/biometric operations
  check exact sign-in scope under the shared Keychain lock, but their multiple items are not one
  atomic record. The typed Data auth state machine now covers restore, unlock start/failure, handoff, expiry,
  lock and logout. Token adapters/merge are live in Data and locking
  is in SecurityStorage; atomic private account/token storage and shared scope/grant
  checks are implemented, not a transaction over all keys, network requests or server commits.
  Simultaneous app/extension network refreshes, process death and failure of both durable writes
  can still need recovery. The signed cross-process/storage-error matrix is unexecuted. See
  [the ownership decision](ADR/001-auth-token-ownership.md), [persistence ports](ADR/003-token-persistence-ports.md)
  and [auth lifecycle](ADR/004-auth-repository-lifecycle.md); S-302/S-303 remain partial.
  The app now shares an observable AppFeature.AppModel with revisioned repository events and
  runtime-bound expiry. Credential commit/recovery semantics and signed lifecycle verification
  remain open; see [app ownership](ADR/005-app-model-ownership.md).

See [FeatureStatus](FeatureStatus.md) and the [implementation plan](Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).
