# Passkey registration mutation ownership and durable recovery

Status: live partial X-604 implementation, 2026-09-28. Complete AppModules test targets and
both unsigned app/extension builds pass. Immediate extension-side identity publication is now
implemented in [ADR 016](016-passkey-registration-incremental-identities.md); explicit reviewed
abandonment is implemented in [ADR 017](017-passkey-registration-reviewed-abandonment.md).
Legacy-origin recovery and the signed/server/process matrix remain open; no release gate is closed.

## Decision and fixed defects

The extension previously swallowed a cache-upsert error after a confirmed server write, and a
registration failure could leave the same Save actions enabled despite an unknown outcome.
`AutoFillData.PasskeyRegistrationWriter` now owns the submitted mutation in its own Task. UI
consumer cancellation cannot skip an acknowledged write's projection. Shared-grant/runtime
revocation still denies projection/output. Actor reentrancy cannot submit two simultaneous writes;
a confirmed or unknown mutation cannot reopen that writer as a retryable create.

Before HTTP, the writer reserves a UUID mutation ID and public credential-selection metadata in
`autofill-passkey-recovery-v1.json`. `PasskeyRegistrationRecoveryStore` takes the injected shared
grant/token process lock around read/compare/write, uses atomic replacement, file synchronization
and 0600 permissions, and has no fallback container. The journal is versioned and contains only
account/server, RP, credential ID, target/server cipher ID, phase and mutation ID. ADR 017 adds
the actual originating unlock ID to new reservations. It stores no
password, key, TOTP seed, user handle, client-data hash, attestation or HTTP body. Descriptions
are redacted. Corrupt/future/duplicate records are not overwritten or silently reset.

Only one pending mutation per exact account/server may be reserved. This deliberately blocks
other registrations for that account until recovery: creating a new writer, OS invocation or
unlock cannot turn an unknown write into an automatic retry. Foreign-account records are retained
and cannot be removed using this account's proof. Ordinary password/TOTP/assertion requests do
not depend on the registration journal.

The existing SDK callback still supplies the encrypted cipher. Before reservation, the adapter
bridge uses SDK-decoded credential bytes to verify that exactly one credential was added for
the requested RP and that existing passkeys were not dropped. It checks the EncryptionContext's
owner, original item/edit policy and cache fence. It never guesses the SDK's UUID/b64 encoding.
Cipher payload construction remains the existing lossless SDK/wire mapper; no endpoint, request
field or compatibility provider is added.

`SDKCipherService.savePasskeyResponse` classifies pre-submit mapping/token/cancellation failures,
explicit 400/401/403/404/405/413/422/429 rejection, ambiguous transport/timeout/conflict/5xx and
successful HTTP status with unusable response separately. Omitted update IDs retain the existing
target-ID behavior; missing create IDs, foreign update IDs and ineligible responses cannot be
projected as successful credentials. Definite rejection releases only its own reservation;
failed cleanup retains the marker and blocks retry. A successful server write followed by local
journal/cache failure is not undone: it returns a receipt indicating repair, with the marker
retained. Lost proof prevents OS success even when the server may already have committed.

The SDK FFI may wrap a Swift callback failure. Registration consults this writer's redacted
failure/terminal state, rather than making a wrapped SDK error retryable. The UI disables Save
actions for unknown/confirmed-repair/pending mutations and leaves Cancel available. A completed
registration is still never reported before server confirmation. A returned SDK attestation
alone is not enough: the writer must supply a confirmed receipt and its credential bytes must
match the SDK result before OS success. Cache projection is no longer
an ignored `try?`; immediate system-suggestion projection was not completed in this original
block and is implemented by the subsequent ADR 016 follow-up.

## App-side reconciliation

App composition injects `Data.PasskeyRegistrationRecoveryReconciler` into the same live
DefaultVaultRepository. Only a full successful authoritative sync is allowed to resolve a marker,
and only after encrypted cache and system identities have both published the same revision.
Exactly one descriptor must match the recorded credential bytes and RP, plus the target/server
cipher ID when known. An ambiguous create without a server ID can resolve only when that exact
credential appears uniquely in the synchronized account. Merely receiving a successful sync,
not finding the passkey, a normal app mutation or repairing only the cache does not clear it.

Journal read/remove failure, missing match, failed OS/cache projection or absent projection port
keeps `VaultLoadWarning.passkeyRegistrationRecoveryPending` visible. This warning is separate
from unavailable-item counts and does not hide vault rows. Later successful sync retries local
repair, not the registration HTTP write. Lock during reconciliation prevents late snapshots.
The journal is not erased on lock/logout: unresolved ownership metadata must survive restart.

## Executed checks

30 new methods: ten mutation-writer, seven journal-store, four reconciler, four SDK transport,
four repository pipeline and one presentation-state method. Parameterized continuation fixtures
cover confirmed/ambiguous/rejected responses, parallel submissions/reservations, cancellation,
runtime revocation, cache/confirmation/cleanup/storage errors, recreation, foreign servers,
future/corrupt journals, identity mismatch/ambiguity, revision ordering, missing projection and
lock during repair. Real temporary-file fixtures check persisted records and 0600 permissions;
SDK/HTTP fixtures are synthetic, not real cryptographic/server/device runs.

Final complete run: 645 Swift-Testing methods in 81 suites plus two XCTest tests (647 total).
Existing assertions remain; unsigned macOS-arm64 and generic iOS-Simulator app/extension builds
pass. Official SDK/subrepos are unchanged. Commands and limits:
[verification report](../Verification.md).

## Remaining limits and next work

Immediate registration-side OS identity publication and local revision coupling are implemented
by ADR 016. Cross-process OS ordering remains unverified, not an atomic transaction.
The server write, journal, Keychain, cache and OS completion are not one atomic transaction.
The process lock covers local journal/cache transactions, not network deduplication across
processes or a server idempotency contract. File synchronization is not proof of power-loss
durability; process termination at every stage and signed cross-process races are unexecuted.

A crash immediately before HTTP, an ambiguous rejection, deletion of the recorded passkey or
SDK degradation may leave no observable matching credential. Such a marker stays blocked even
after sync. ADR 017 implements an explicit reviewed abandonment workflow for new lineage-bound
records, requiring a fresh unlock, complete sync and acknowledgment of the unresolved/late-write
risk. Legacy records without known origin remain blocked unless exact credential reconciliation
succeeds. Do not implement “sync returned 200, therefore forget the marker”, expiry or automatic
resubmission. Abandonment is not rejection/rollback evidence or a finished signed UX matrix.

SDK FIDO callbacks/request JSON and typed target/persistence/coordinator boundaries are now
separated by [ADR 018](018-autofill-sdk-callback-and-registration-ports.md), with platform
verification behind a Domain port. Error/verification/cancellation/controller-context and
real create/update/response-preservation matrices remain open. No new Vaultwarden compatibility,
multi-account UI, rollback, zeroization or independent security-audit claim is introduced.
