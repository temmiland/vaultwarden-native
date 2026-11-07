# Token persistence ports and lock ownership

Status: live Data merge/shared stores and SecurityStorage lock; incomplete auth/recovery migration,
2026-09-27. Local regression tests pass. Not a security audit;
signed-device and cross-process checks remain open. See [results](../Verification.md).

## Decision

The refresh core must not reach back into AuthFeature for persistence policy. The app now injects
`Data.AppTokenPersistence` directly into its coordinator; the AuthFeature `AuthTokenPersistence`
bridge is removed. The extension injects `Data.ExtensionTokenPersistence` with its fixed proof.

| Responsibility | Current owner |
| --- | --- |
| Cache lookup, local refresh single-flight and expiry | Data.TokenCoordinator |
| Exact-scope private/shared merge, adoption, app commit and lock reconciliation | Data.AppTokenPersistence |
| Fixed-proof extension lookup, winner adoption and successor commit | Data.ExtensionTokenPersistence |
| Synchronous scoped lease contract | Data.SharedTokenTransacting / SharedTokenTransactionPort |
| Process mutex, file open/permissions/flock/release | SecurityStorage.CrossProcessFileLock |
| Existing shared JSON/token/grant operations and revocable transaction lease | Data.SharedTokenStore / SharedTokenTransaction / SharedAutoFillUnlockStore |
| SDK-free shared account metadata and existing Keychain wire names | AutoFillContract.SharedAccountInfo / AutoFillStorageKeys |
| KDF/SDK integer conversion and environment mapping | BitwardenSDKAdapter.SDKAutoFillAccountMapper |
| App Group/entitlement configuration and factory injection | Composition/SharedAppGroup.swift shared by all four targets; app-owned AuthServices injection |
| Public storage configuration validation | SecurityStorage.AppStorageConfiguration; Bundle/container lookup remains in composition |

There is no new package edge or SDK type in these ports. Only TokenPair/TokenScope and the
nonsecret AutoFillContract proof cross them. A port adapter must check ownership and distinguish
absence from read failure. The concrete transaction is non-Sendable and invalidated on callback
exit, including when the operation throws; returning the lease does not extend its authority.
No await/network/SDK/biometric call or nested lock belongs inside a transaction callback.

The process mutex and file-lock implementation moved unchanged in their serialization semantics
to SecurityStorage. Composition supplies the entitled container and Keychain to the Data stores.
Data retains the exact `.vaultwarden-token-store.lock` filename, so old/new processes lock the
same file. Live missing
containers fail closed; process-only mode is explicit fixture injection, never a fallback.
Shared composition has no fallback Team ID, group or service. It validates expanded xcconfig
values and resolves the configured container before making shared stores. Private/shared service
names retain their existing defaults; changing contributor identifiers selects a different local
storage namespace, not a credential migration. See [build configuration](008-build-configuration.md).
Filename validation rejects empty/traversing/NUL-containing names before opening anything.
The lock remains synchronous and non-reentrant across instances. It is not a server-token or
Keychain/OS-completion transaction.

## Merge and failure behavior

Within one transaction, load the private atomic session first and check the requested sign-in
scope before looking at shared tokens. Only a strictly newer, exact-scope/current-grant shared
pair is adopted. Equal generations retain the private record. Lock uses this same reconciliation
before independent shared capability removal, even if reconciliation fails.

App commit accepts only the next generation of the exact baseline. A newer eligible winner is
returned untouched; a lower stored generation is not a winner. Candidate validation happens
**before** shared publication, not after a potentially invalid shared write. The extension also
validates its candidate and does compare/replace/readback inside one proof-bound transaction.

- Shared write succeeds / private fails: the matching shared rotation remains recoverable.
- Shared write fails / private succeeds: retain the issued pair privately, independently revoke
  the obsolete capability, and fail this lookup. Cleanup failure propagates.
- Both writes fail: still attempt revocation, then report
  `TokenCommitRecoveryError.rotationNotDurable(capabilityRevocationFailed:)`. It contains no tokens
  or raw diagnostic objects. The server-issued rotation can be lost; this classification is not
  a recovery journal, a forced re-login flow or proof of successful cleanup.
- Scope mismatch, malformed payload and illegal generation cannot overwrite the current pair.

Live coordinator callers currently receive nil on persistence failure. Propagating typed recovery
to presentation and recording durable refresh/cleanup intent remain unfinished.

## Verification and next work

AppModules source fixtures cover strictly-newer/equal/lower merge, scope denial before shared
reads, grant/no-grant commits, malformed/non-successor candidates, both one-sided failures,
dual-write/revocation failures, lock read outages and old unlock proofs. AuthFeature/Data
fixtures additionally exercise the real shared adapter with in-memory Keychain values,
lease expiry and dual-failure classification. Lock source fixtures cover missing-container,
explicit process-only and invalid filenames without touching the filesystem.
The local fixtures have been built and **pass**; they cannot validate entitlements or real process races.

Still open: full login/TOTP implementation inside the repository, broader settings migration,
remaining App Group/Auth composition migration, typed UI/OS error propagation, durable recovery and
the [signed cross-process matrix](../AutoFillLifecycleChecks.md). Actor-local single-flight does
not stop simultaneous app/extension network refreshes. No new Vaultwarden compatibility feature,
storage schema migration or security-audit/zeroization claim is introduced. S-302/S-303 stay partial.
