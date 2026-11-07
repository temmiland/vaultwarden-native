# Incremental system identities after confirmed passkey registration

Status: live partial X-604/V-403 follow-up, 2026-09-28. This implements immediate
registration-side publication, not an atomic cross-process transaction or a release gate.
The mutation journal/reconciliation decision remains [ADR 015](015-passkey-registration-write-recovery.md).

## Decision

The existing registration callback now awaits `AutoFillData.PasskeyRegistrationProjection`
inside the mutation-owned writer Task. UI cancellation cannot skip the confirmed write's
asynchronous projection or receipt. The fixed runtime/unlock proof remains authoritative.

Publication is incremental and contains exactly the new passkey. Replacing the entire index from
the extension could erase existing password, TOTP and other passkey suggestions. The Domain port
`PasskeyIdentityUpdating` therefore permits only single-identity add/remove. The sole platform
adapter, `SystemCredentialIdentityStore`, requires an enabled store with `supportsIncrementalUpdates`.
There is no replace-all fallback. Missing support or an OS error leaves durable app-sync repair.
Strict incremental mapping throws on invalid fields rather than reporting success while omitting
the identity. An empty SDK-decoded user handle is permitted; a missing handle is not.

The order is:

1. Commit the confirmed encrypted DTO using the original account/proof/cache UUID under the
   shared grant/token authorization lock. Advance UUID and monotonic projection revision.
2. Obtain a transient redacted receipt binding that proof, the new revisions and the exact
   encoded encrypted cipher. Check it against the current file under the same lock.
3. Decode the server DTO through the existing session SDK resource. The SDK adapter selects
   exactly one public credential using its decoded bytes, exact RP, cipher ID, current revision
   and secret/edit policy. Duplicate/missing/mismatched credentials are rejected.
4. Use the existing `Data.CredentialIdentityMapper` so full app sync and incremental registration
   use the same descriptor ID. The SDK source has no URI/password/TOTP identity projections.
5. Recheck proof/receipt after metadata awaits, add only that descriptor, and recheck after the
   OS await. A concurrent projection cannot start another commit in the same actor.

Receipts are not persisted, cannot be constructed by callers and redact diagnostic descriptions.
They carry an encrypted DTO, not a password, seed or private key. Validation checks account,
proof, both revisions, uniqueness, policy and exact encrypted bytes. A legacy cache without a
monotonic revision is still upserted after server confirmation but requires authoritative app sync
before immediate identity publication; no revision is guessed.

## Failure ownership and compensation

No OS call is made if cache commit, metadata validation or a pre-publication proof check fails.
After an attempted OS add, a late invalidation or uncertain adapter error triggers targeted
removal of that same descriptor. Existing unrelated identities are never removed or replaced.
Compensation intentionally does not require the revoked proof: its purpose is removal, not
fulfilment. Cleanup failure is a distinct `identityCleanupFailed` projection error. The writer
turns either projection failure into a repair receipt without retrying the HTTP write; the
durable marker survives and app sync exposes/retries recovery. Runtime revocation still denies
registration output rather than returning a successful OS completion.

Even successful incremental publication does not clear the journal. Only full authoritative
app sync with exact unique credential evidence and successful cache/full-OS publication may do
that. The incremental operation cannot prove full-vault identity health or relying-party/OS
completion. Unobserved ambiguous writes remain blocked, with no TTL or automatic retry.

## Executed checks

Seventeen new methods: seven projection actor, three real-cache receipt, two SDK metadata mapper,
three platform capability/strict mapping and two asynchronous writer methods. Parameterized
continuation fixtures verify cache-before-identity order, exact selection, foreign/missing/
duplicate metadata, proof/UUID/revision/encrypted-record changes, lock during metadata and OS
awaits, targeted cleanup, explicit cleanup failure, unsupported incremental capability, legacy
cache repair, parallel calls and UI cancellation during async projection. Existing assertions
remain. OS calls, crypto and network are faked in these new tests.

Complete AppModules targets: 662 Swift-Testing methods in 84 suites plus two XCTest tests,
664 total, passed. XcodeGen regenerated both extension targets with the PlatformServices product;
unsigned macOS-arm64 and generic iOS-Simulator app/extension builds passed. Official SDK/subrepos
are unchanged. Commands and limits: [verification](../Verification.md).

## Remaining limits

The grant/file authorization lock is not held across asynchronous OS calls. A separate FD-owned
shared identity batch now orders app replacement/clear against extension add/recheck/compensation;
see [ADR 019](019-shared-credential-identity-mutation-ordering.md). Targeted compensation finishes
before a queued newer app publication of that identity. Current-cache/unlock guards reject stale
batches, including an old session's clear over a successor. Real signed processes, old uncoordinated
binaries and daemon-side completion after process death remain unverified; no global-linearizability
or atomic cache/OS transaction claim is made. Full sync remains the repair path.
There remains a gap between the final proof check and OS completion, and process death can skip
compensation. The signed concurrent-process/termination matrix must verify and characterize
these cases before X-604/V-403 or any release gate closes.

Explicit reviewed abandonment of new lineage-bound journal markers without observable credential
evidence is implemented by [ADR 017](017-passkey-registration-reviewed-abandonment.md); it is not
rollback or proof that retrying is safe. SDK-shaped FIDO/serverwriter ports are now separated by
[ADR 018](018-autofill-sdk-callback-and-registration-ports.md). Legacy-origin recovery, signed
workflow verification and the controller/OS-context harness remain open.
No real server/SDK crypto, signed device/entitlements, actual process kill, power-loss durability,
UI launch or Release build was verified here. No new compatibility feature was introduced.
