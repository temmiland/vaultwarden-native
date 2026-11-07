# Auth and token persistence ownership

Status: implemented storage boundary and common refresh core, incomplete repository migration; 2026-09-26.
Verification update 2026-09-27: local package tests and unsigned app builds pass. Not a security audit;
signed-device and cross-process checks remain open. See [results](../Verification.md).

## Decision

`Data.PrivateAuthSessionStore` persists account metadata, wrapped keys, token pair and a
`TokenScope` in **one** replace-in-place, when-unlocked private Keychain value (`auth.session.v1`).
`StoredAuthAccount` and `TokenPair` are persistence values, not Domain/UI state. Legacy AuthFeature
names are aliases; the final presentation-safe auth repository is still missing.

`Data.AppTokenPersistence` now owns private/shared reconciliation and refresh commit; the extension
uses `Data.ExtensionTokenPersistence` with a fixed proof. `SharedTokenTransacting` supplies one
scoped, synchronous transaction lease. `SecurityStorage.CrossProcessFileLock` owns the lock
implementation. Data owns the shared token envelope, unlock grant and transaction adapter;
`Composition/SharedAppGroup.swift` supplies app/extension App Group configuration; VaultCore is removed.
See [the persistence-port decision](003-token-persistence-ports.md).

A token scope contains the exact account ID, configured server base URL and a random
`authenticationID`. Successful password/2FA sign-in creates a new ID and starts generation 1,
including re-login to the same account. Lock/unlock and refresh preserve that sign-in ID.
Identity comparison is exact; URL normalization remains the configured environment's job.

The extension grant schema is now 2. Its proof contains the sign-in ID as well as a fresh
`unlockID` and revocation epoch. Shared token records carry the same scope and unlock ID. The
extension token provider requires a fixed proof, checks it against the current grant and checks
token ownership; possession of the nonsecret proof alone does not authorize token access.
The refresh endpoint must belong to that proof's configured server.

## One merge rule

Only a token record that matches **account, server, sign-in lineage and current unlock grant** is
eligible for reconciliation. Inside that scope, a strictly higher generation wins. Equal
generations keep the private record; an attempted shared publication with conflicting equal
payloads is rejected. `updatedAt`, token string comparisons and JWT decoding do not decide which
generation wins. Missing ownership is never inferred from whichever account happens to be open.

| Transition | Durable authority | Extension capability |
| --- | --- | --- |
| Password/2FA login | Commit account + tokens together, new sign-in ID, generation 1 | Revoke old grant/tokens first; do not publish tokens yet |
| Unlock | Retain sign-in ID and adopt an eligible newer shared generation | Publish fresh grant and matching tokens under one process lock |
| App refresh | Compare original scope and generation, adopt a winner or increment safely | Publish only under the matching current grant |
| Extension refresh | Main app adopts its matching newer generation before use/lock | Compare-and-write checks scope, generation and fixed unlock proof |
| Lock | Preserve eligible newest shared rotation before revocation | Rotate epoch, delete grant and tokens; attempt each independently |
| Logout | Delete private session and legacy records after successful shared revocation | Revoke grant and tokens; no token reconciliation needed for deletion |

App reconciliation, private writes, grant/token publication and lock/logout transitions share a
synchronous App Group file-lock transaction. No SDK, network, biometric prompt or suspension runs
under that lock. The transaction lease expires when the callback returns; escaped handles reject
subsequent operations. Missing production App Group containers throw. `.processOnly` is an
explicitly injected in-memory-fixture policy, never live composition's fallback.

The app provider binds once: a login provider cannot read an older stored login before success,
and an existing provider cannot adopt another lineage. Async grant publication, biometric
enrollment and final handoff validate the provider's lineage again. Biometric enrollment checks
that scope inside the persistence transaction before writing the key/account flag.

## Failures and migration

- Failed fresh-login replacement preserves the previous combined account/token record. Old
  extension access has already been revoked; biometric/PIN material may already have been removed
  and must be re-enrolled. This is not a transaction over all independent Keychain items.
- A shared refresh publication followed by a failed private write leaves the eligible shared
  rotation recoverable on the next app lookup.
- Failed shared publication still attempts to retain the issued pair privately, then independently
  revokes the obsolete shared capability. That lookup fails; a later app lookup can use the durable
  private pair. Revocation failure is propagated, not reported as successful cleanup.
- If reading the shared authority fails, no guessed merge/overwrite is performed. If both durable
  writes fail, a server-issued rotation may be lost. `TokenCommitRecoveryError` reports whether
  capability revocation also failed, without retaining raw diagnostics. Recovery journaling and
  presentation of this typed failure remain open.
- Issued pairs are validated before either publication/write. A refresh based on a generation
  ahead of current storage cannot claim that lower stored generation as a winning commit.
- Generation overflow is rejected, never incremented with a trapping arithmetic operation.
- Malformed/future private sessions fail closed without falling back to older split token records.
  Explicit logout can discard a malformed record after shared revocation succeeds.
- `auth.account` may still be read as legacy display/recovery metadata. `auth.tokens` never grants
  authentication. Existing split sessions require **one fresh password/2FA sign-in**, followed by
  unlock and sync. The UI explains this migration; it does not silently erase the old records.
- Grants/tokens use new `.v2` Keychain names; legacy items are independently removed during
  revocation, never imported. Older readers cannot consume newly issued pairs under the old names.
- Raw/schema-1 shared grants and unbound token/cache records cannot be used. An already-running
  older binary cannot be fixed by this code; close/restart old extension requests after upgrading.
- Token/account/session descriptions are redacted. No secrets or ownership IDs should be logged.

## Remaining work

S-302 is still partial. App and extension now use `Data.TokenCoordinator` and the same typed
refresh transport; see [refresh coordination](002-token-refresh-coordination.md). Merge/commit and
app/extension persistence policy are in Data; the lock implementation is in SecurityStorage.
Shared envelope/grant encoding now lives in Data with SDK-free metadata in AutoFillContract.
App Group configuration is shared by the app/extension composition targets; login and
biometric/PIN/account-setting transitions remain in AuthFeature. Each coordinator deduplicates
locally, not across app and extension network requests. The lock covers persistence,
**not** server refresh-token consumption or server/OS
commits. Real concurrent rotating refreshes, process death, persistence/revocation failures and
recovery journaling require verification. There is no durable refresh-intent or cleanup-retry
marker across process restart yet.

`Data.DefaultAuthRepository` now owns restore/locked/unlocking/unlocked/expiring/signed-out
transitions and typed state events. It validates the full account/server at unlock and requires the
accepted private record at handoff. The Auth route and app lock/logout use this lifecycle; it does
not yet own credential entry, password/2FA transport, or the in-memory SDK runtime. Legacy SDK
contexts remain inside AuthFeature. Auth handoff still passes a Data session assembly, but that
assembly exports neither a raw SDK Client nor a token closure. PIN enrollment/removal and biometric-key operations
now check the authentication lineage per operation. The wider account-settings projection and
atomicity across independent Keychain items remain open.
Vault/cache/OS identity consistency and signed-device checks remain separate release blockers.

New and updated source fixtures cover ownership mismatch, atomic login write failure, unbound
legacy records, app/extension late refreshes, lock/re-unlock, both single-write failure directions,
generation overflow and explicit production-versus-fixture lock policy. The local fixtures now
**pass**; they do not verify real concurrent processes. See [AutoFill lifecycle checks](../AutoFillLifecycleChecks.md) and
[Feature status](../FeatureStatus.md).
