# Common token refresh coordination

Status: live common core, incomplete storage/repository migration; 2026-09-26.
Verification update 2026-09-27: local fixtures and unsigned app builds pass. Not a security audit;
signed-device and cross-process checks remain open. See [results](../Verification.md).

## Decision and ownership

`Data.TokenCoordinator` owns cached lookup, expiry leeway, local single-flight refresh,
generation-bound Retry-After and permanent revocation. It receives one immutable `TokenScope`,
the existing derived identity URL, a `TokenPersistence` port and a `TokenRefreshing` port.
Neither port exposes SDK types. A coordinator never rebinds to a later login or unlock.

The AuthFeature SDK/bootstrap bridge creates a coordinator only after committing its own login,
or with an explicitly restored sign-in scope. `Data.SharedTokenProvider` delegates to the
same core through `Data.ExtensionTokenPersistence` with a fixed shared unlock proof. Copied
provider values share the same actor. `Data.AppTokenPersistence` owns private/shared merge/commit
and `SecurityStorage.CrossProcessFileLock` owns locking. Data owns shared envelope/grant
encoding behind `SharedTokenTransacting`; `Composition/SharedAppGroup.swift` supplies app/extension configuration.
The Auth bootstrap bridges are transitional, not the final `DefaultAuthRepository`. See [persistence ports](003-token-persistence-ports.md).

The synchronous persistence adapter must verify exact authority, compare and write under the
existing process lock, and adopt only strictly newer eligible winners. No network, SDK operation
or suspension occurs under that lock. A classified ownership change permanently revokes the
coordinator; a throwing storage outage denies the lookup without inventing a new sign-in state.

## Refresh rules

- Valid cached tokens require no request. Overflow is denied before consuming a server rotation.
- Concurrent requests for one generation share one task. UUID job ownership prevents an old
  waiter from erasing a newer job after actor reentrancy.
- Revocation cancels and detaches the task. Late/noncooperative responses cannot persist or yield
  tokens through that coordinator. Cancelling one waiter does not cancel the other waiters;
  output is denied, but prompt return while awaiting noncooperative work is not guaranteed.
- Before commit, reread scope and generation. A newer eligible winner is adopted rather than
  overwritten, including when the obsolete response was a rejection. Commit and final lookup
  must produce a generation strictly newer than the original request's generation.
- Explicit same-generation rejection closes the coordinator immediately and invokes the app
  expiry handler at most once. The extension has no app expiry callback; this does not prove
  global grant/key/cache cleanup or complete the OS error mapping.
- Finite positive Retry-After is an in-memory deadline for that generation. There is no sleep,
  automatic retry, durable deadline or cross-process backoff agreement.

`DefaultTokenRefreshService` owns the existing connector form and endpoint request, rejects
redirects and returns only typed rotation data/classification. HTTP 429/5xx take precedence over
the body. Only explicit OAuth `invalid_grant` on 400/401 without a challenge is definitive.
Non-JSON errors, other statuses, unexpected challenges and invalid successful payloads are
retryable. Transport errors are classified without retaining raw diagnostics. Successful payloads
require nonempty access tokens, positive integral expiry, nonempty refresh token when supplied,
and bearer token type when supplied. Omitted refresh/type preserves existing extension tolerance;
an omitted refresh token retains the current pair's refresh token. No new compatibility flow is added.

Login remains in the legacy service, but 429/5xx also precede challenge/error parsing there.
Raw server error descriptions no longer become login UI text. `Networking.HTTPRetryAfter` shares
the case-insensitive seconds/HTTP-date parser and rejects NaN, infinity and negative delays.
Legacy decoder/form helpers are aliases to their Networking/Data implementations, not duplicates.

## Verification and remaining work

New source fixtures cover single-flight, cancellation, noncooperative late refresh, revocation,
lineage change, newer winners, stale rejection, expiry-once, Retry-After, job replacement,
overflow, omitted rotation, storage/transport failure, status/body precedence, malformed payloads,
redacted descriptions and stable login errors. They have been built and **pass** locally.
Unsigned app builds cannot verify real shared Keychain entitlements, FFI/device/OS behavior or races.

Single-flight is **per actor**, not across processes. The storage lock does not serialize server
refresh-token consumption. Competing rotating app/extension refreshes, process death after server
success, dual-store failure, revocation failure and durable refresh/cleanup recovery remain open.
See [storage ownership](001-auth-token-ownership.md) and the
[unexecuted signed matrix](../AutoFillLifecycleChecks.md).

The initial `Data.DefaultAuthRepository` state machine is now connected to startup restoration,
returning-user unlock attempts, accepted handoff, expiry and lock/logout. Credential entry and 2FA
still run through AuthFeature/SDK bridges; presentation still receives the transition session and
optional token callback. PIN/settings ownership and full repository migration remain open.
S-302/S-303 remain partial; no release gate is closed and no secret-memory zeroization is promised.
