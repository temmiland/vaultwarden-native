# Shared app/extension credential-identity mutation ordering

Status: implemented locally, 2026-09-28; partial V-403/X-604. This orders participating OS-index
mutation batches, not cache/Keychain/HTTP/OS completion as one atomic transaction.

## Defect and decision

The app publisher previously serialized only its own replace/clear operations. An extension
could add a passkey, discover an obsolete cache after the OS await, then remove that descriptor
after a newer app sync had published the same identity. Both actors were locally correct but
their compensation/publication order was wrong.

`Domain.CredentialIdentityMutationCoordinating` now expresses an exclusive async mutation batch.
Both live composition roots inject a SecurityStorage-backed coordinator using the same stable
App Group leaf file, `.autofill-identities.lock`. No raw OS store call in app/extension composition
is made outside the corresponding publisher/projection batch. Future consumers must use that
same boundary, not instantiate the platform store for uncoordinated writes.

`SecurityStorage.AsyncCrossProcessFileLock` owns an open-file descriptor and exclusive flock
across awaits. It does not hold NSLock or block a Swift executor waiting for a contended lock.
Acquisition uses LOCK_NB with cancellable 25 ms async waits and a 10-second default waiting limit.
That limit never expires an acquired lease while an OS call might still mutate state. FD close/
unlock is deferred on every exit; caller cancellation alone does not skip batch confirmation or
compensation. A process-only coordinator exists solely as an explicit test fixture.

The lock requires a live file container, a nonempty leaf filename and a regular file. O_NOFOLLOW,
O_CLOEXEC/O_NONBLOCK and 0600 permissions reject symlinks/special files and avoid FIFO-open hangs.
Missing containers, storage errors, timeout or cancelled acquisition do not run an uncoordinated
fallback. Never unlink/rotate the live lock file: different inodes would split the exclusion.

## Batch boundaries

- Extension: confirmed encrypted cache commit and SDK public-metadata decoding remain before
  acquisition. After acquiring, recheck the exact proof/UUID/revision/encrypted-cipher receipt,
  add only the new passkey, recheck after the OS await, and perform any targeted removal before
  releasing. A queued app replacement cannot publish that same descriptor before removal finishes.
- App publish: commit cache first, acquire, check live runtime plus current authorized cache
  owner/monotonic revision, replace, and check those again after the OS await. Obsolete or uncertain
  replacement is compensated by a conditional clear in the same batch; errors remain stale/
  unavailable and never trigger another server mutation.
- App clear/lock: acquire and check the current shared grant under the token lock. The captured
  same unlock, or no remaining grant, permits clear; a different current unlock denies an old
  session's removal. Cleanup deliberately does not require its revoked runtime to be live.
  This publisher's queued lock still drains its own in-flight replacement before final clear.

`AutoFillData.AutoFillIdentityMutationPolicy` supplies the pure current-cache and captured/current
proof checks. App `SessionVaultProjection` assembles the publisher with its fixed proof and
authorized file reader. `CredentialIdentityPublisher` and `PasskeyRegistrationProjection` now
require an explicit coordinator; the publisher also requires explicit publication/clear guards.
No implicit live default bypasses coordination. Missing app container leaves projection unavailable
and may leave old suggestions until repair; it cannot safely clear them without shared ordering.
Missing/revoked grants continue to deny credential fulfilment independently of those suggestions.

Lock ordering is identity batch -> short grant/token transaction, never the reverse. Neither HTTP
nor SDK crypto runs while the identity batch is held. The existing synchronous grant lock is NOT
held over OS awaits, so lock/logout can revoke authorization while an OS callback is outstanding.
Cache writes can occur during a batch; post-await guards reject those changes. A conflict may
temporarily clear suggestions and require another authoritative full sync. No automatic merge,
server retry, new compatibility behavior, cache schema or journal schema change was added.

## Executed checks

18 new methods: seven async file-lock, two pure policy, five publisher guard and four combined
app/extension ordering methods. Real temporary files and independently opened descriptors verify
exclusion across awaits, throwing release, cancelled wait without waiting for the owner, timeout
without lease expiry, acquired consumer cancellation, 0600 permissions and unsafe file denial.
Combined tests use separate coordinator instances and the real file lock with gated fake OS
callbacks: late add/compensation before newer full replacement, lock clear after extension drain,
old app replacement after incremental cache commit, and stale incremental waiter before any OS
call. No sleep-based correctness assertions; the acquisition adapter itself uses async polling.

Complete AppModules targets: 728 Swift-Testing methods in 94 suites plus two XCTest tests,
730 total, passed. Both regenerated macOS-arm64 and generic iOS-Simulator app/extension builds
passed unsigned. Existing assertions preserved, official SDK/subrepos untouched. See
[verification](../Verification.md).

## Remaining limits

The tests exercise two independent descriptors in one process, not signed concurrent app/extension
processes or real ASCredentialIdentityStore callbacks. An old running binary or external writer
that does not take this lock is not ordered by it. A hung/noncooperative OS operation holds its
lease until it exits or the process dies; waiters report repair instead of forcibly releasing it.
Process death releases the FD but cannot recall a request already submitted to the OS daemon;
that request could complete after a newer process's batch. No persisted OS-operation/fencing
ledger or OS idempotency contract exists. Signed upgrade/termination/disabled-store/failure cases
must characterize this, and full sync remains the repair path.

The final proof check and OS completion are still separate, issued credentials/HTTP cannot be
recalled, and cache/repository/journal health is not a durable cross-process transaction. A later
cache change may invalidate an already returned publication health; recovery/review freshness
and crash gaps still need the full signed/process matrix. ADR 015–018 limits, legacy-origin
recovery, controller-context, server/FFI, Release/entitlements and power-loss gates remain open.
This block does not finish X-604/V-403 or the overall implementation plan.
