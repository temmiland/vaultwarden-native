# Explicit abandonment of unresolved passkey tracking

Status: live X-604 recovery follow-up, 2026-09-28. This is a local acknowledgment of an
unresolved outcome, not proof of rejection, rollback or a release gate. Automatic observed-write
reconciliation and immediate identity publication remain governed by [ADR 015](015-passkey-registration-write-recovery.md)
and [ADR 016](016-passkey-registration-incremental-identities.md).

## Decision and user workflow

A sync without the exact recorded credential still never automatically clears a marker. The vault
warning now offers **Review Unresolved Write**. Review itself has no mutation side effect.
For new records, the user may explicitly abandon local tracking only after:

1. Locking/unlocking the app so the originating unlock is no longer authorized.
2. Completing a fresh full authoritative sync with current encrypted cache and OS suggestions,
   no stale snapshot and no unavailable-item warning. Ordinary CRUD or a failed/partial sync
   invalidates this readiness; a fabricated initial snapshot does not establish it.
3. Inspecting the vault and relying party in an official client and checking the acknowledgment
   that the outcome remains unresolved and another registration may duplicate a late write.
4. Choosing **Abandon Local Tracking** in the metadata-only review sheet. Close/dismiss keeps it.

The prompt shows RP and whether the server acknowledged the write. It carries no credential key,
user handle, proof, token or SDK backing. Same-unlock reviews are informational with lock/unlock
guidance; older records with no originating unlock remain blocked. There is no automatic retry,
server deletion, expiry, account-wide journal reset or false success claim.

## Boundaries and authorization

`Domain.PasskeyRegistrationRecoveryReview` contains an ephemeral nonce, vault revision, RP,
confirmation flag and readiness, with redacted diagnostics. VaultPresentation uses only Domain
ports, models and SwiftUI. Its destructive action requires a current ready review and explicit
checkbox; busy guards prevent duplicate taps. Sheet identity is keyed by the review nonce so
checkbox consent cannot carry into another review; content scrolls for small screens/large text.
Snapshot changes, sync, session revocation and
failures close the old prompt. An acknowledged local mutation closes that same prompt before
checking UI cancellation, just like a confirmed create draft.

The session repository serializes review/acknowledgment with sync and CRUD. A successful full
sync revision is tracked separately from merely having a snapshot. Once explicit consent submits
the local mutation, a repository-owned Task finishes the acknowledgment independently of UI
cancellation; already-cancelled submissions do nothing. Runtime lock still rejects late publication.
There is no server-write call in this path. The pending warning is removed only according to the
local transaction result, without changing the vault revision or hiding unrelated warnings.

`Data.PasskeyRegistrationRecoveryReconciler` is now an actor and keeps one ephemeral review plus
the exact journal record. A new review or reconciliation invalidates previous consent. Forged,
stale, changed or reused reviews fail. A submitted eligible attempt consumes its service consent;
the repository invalidates sync-readiness on success or failure, requiring sync/read/review again.
Concrete async methods explicitly match the protocol signatures;
the negative default adapter cannot shadow a concrete actor call.

New reservations bind `originatingUnlockID` to the proof actually authorized by the journal
store, under the existing shared grant/token process lock. Caller-supplied foreign origins are
denied. This is additive optional v1 metadata, not a new storage filename or a guessed migration.
Existing records without the field still decode and can reconcile through exact credential proof,
but cannot be manually abandoned. No key, revocation epoch or credential secret is added.

`abandonReviewedRecord` rereads and compares the entire record in the same authorization
transaction that removes it. It checks exact account/server, current proof, a known different
originating unlock and unchanged mutation ID/phase/cipher/credential/RP metadata. It removes only
that record, preserves foreign-account records and reports remaining same-account tracking.
Missing/changed records, unknown schema, stale proof and storage errors do not claim success or
reset the file. The normal atomic-write/synchronize/0600 protections remain.

## Executed verification

Twenty-two new methods: three journal-store, seven live recovery-service, six repository pipeline
and six presentation-model methods. Real temporary journal files and explicit continuation gates
cover fresh/same/legacy unlocks, binding/forged origins, exact compare, changed phase, foreign
servers, schema/proof/runtime failures, one-shot consent, sync/projection/partial-vault guards,
zero server writes, canceled submissions, cancellation after local commit, lock, duplicate taps,
late prompts, redacted errors and legacy automatic reconciliation. Existing assertions remain.

Complete AppModules targets passed: 684 Swift-Testing methods in 85 suites plus two XCTest tests,
686 total. Both unsigned macOS-arm64 and generic iOS-Simulator app/extension builds passed.
No graph/extension file-list change; new package sources are auto-discovered. Official SDK/subrepos
are unchanged. Commands and limitations: [verification report](../Verification.md).

## Limits

A fresh unlock revokes old local capabilities; it cannot recall an HTTP request already sent.
That request may commit after inspection/sync/abandonment. User acknowledgment explicitly accepts
this uncertainty and duplicate risk, not a recommendation to register again. Only the local marker
is removed, never server data or a relying-party credential. A new manual OS registration is a
separate user action and must still satisfy the existing write guards.

Atomic replacement may succeed before a later synchronization/permission error. In that case
the UI reports failure and asks for sync; it does not assert the marker is still on disk or issue
another server write. Process death between removal and acknowledgment likewise requires sync.
There is no durable user-consent audit ledger or server idempotency/rollback contract.

Legacy-origin recovery remains intentionally limited. The actual signed review sheet, accessibility/
OS-context interactions, late real server commits, process termination, power-loss and concurrent
app/extension ordering need the signed/server matrix. No real crypto/FFI smoke, server, UI launch,
signed device/entitlement or Release build was executed here. SDK-shaped FIDO/writer boundaries
are now separated by [ADR 018](018-autofill-sdk-callback-and-registration-ports.md); controller/
OS-context remains open. Shared OS-mutation ordering is implemented locally by
[ADR 019](019-shared-credential-identity-mutation-ordering.md), not verified for signed processes/
termination or atomic with review/recovery. No compatibility functionality added.
