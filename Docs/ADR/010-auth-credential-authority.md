# Data-owned credential authority and PIN settings

Status: partial S-302/S-303/U-504 migration, 2026-09-28. Affected tests and both unsigned
app/extension builds pass. Credential command orchestration and release verification remain open.

Current follow-up: [AuthPresentation and Domain handoff](013-auth-presentation-and-handoff.md)
completes restore/root UI migration and removes the AuthFeature package and AuthServices.
The boundaries and counts below record this ADR's introducing block; operation/recovery and
real-server/device/process gates remain open.

## Decision

Data.AuthCredentialStore owns the former AuthKeychainStore implementation: device ID, atomic
private session, scoped biometric/PIN persistence, shared grant/token publication and lifecycle
cleanup. Existing key names, schema, protection classes, file-lock policy and exact persisted
server identity stay unchanged. No credential migration or new compatibility feature.

AppComposition creates one store after configuration/container validation, injects it into
AuthServices and passes it directly as AuthSessionLifecycleStore to DefaultAuthRepository.
AuthServices creates no storage, repository or PIN-settings implementation. The former
AuthLifecyclePersistence, PinEnrollment and SessionPinUnlockSettingsAdapter are removed.
StoredAccount-to-Domain mapping and classified optional Keychain reads also move into Data.

AppAuthTokenProvider owns bootstrap/commit proof, scope/epoch validation, refresh coordination,
expiry handler and permanent revocation. Its initializer and commit proof stay Data-internal;
the production factory validates server/account/scope/epoch before creating a returning provider
or capturing fresh-login authority. A fresh provider cannot borrow old credentials. Data imports
no SDK module. SDKManagedTokenAdapter only forwards a Sendable token capability to the SDK,
checking cancellation before and after a potentially noncooperative callback.

Data.SessionPinUnlockSettings implements Domain.PinUnlockSettings against one authenticated
runtime and the same store. It validates before derivation and after suspension. Enrollment and
removal compare the captured publication epoch inside the locked persistence operation, not just
the sign-in scope that survives lock. A late derivation after runtime revocation, lock or a new
sign-in cannot write. Separate PIN key/counter/account writes are still not an atomic transaction.

## Defect corrected in the real publication path

The preceding KDF mapper migration normalized legacy Argon2 metadata, but the actual shared
write still compared against raw PBKDF2/Nil defaults. It could refuse valid normalized metadata.
The write now computes the same canonical expected account inside its storage transaction and
compares every shared identity/KDF/wrapped-private-key field. It accepts existing omitted defaults
without rewriting the private record; altered/foreign values and pre-lock epochs remain denied.
Producer/mapper tests alone were not evidence of successful grant/token publication.

## Verification and limits

54 existing test methods from four persistence/token suites move to AppModules with synchronized,
in-memory stores/refresh fixtures. They are ported, not counted as new coverage. 18 new methods
cover actual shared publication, metadata denial, PIN success/crypto/write failure, controlled
noncooperative derivation/revocation, cancelled token callbacks and bootstrap authority. Full
private-record comparisons include schema, account, scope and all token fields.

The final runs pass 477 AppModules Swift-Testing tests plus two XCTest tests and 63 AuthFeature
tests (542 total); macOS-arm64 and generic iOS Simulator apps/extensions build unsigned.
See [executed commands and results](../Verification.md).

Follow-up: [password/TOTP command capabilities](011-auth-command-capabilities.md) move fresh
sequencing and private challenge/pending resources into Data. Login/TOTP/enrollment models now
consume Domain-only ports, with no raw credential/SDK route contexts. A further
[returning-unlock migration](012-returning-unlock-commands.md) moves UnlockModel behind Domain ports
and Data-owned scoped operations too; restore/root handoff remain Data-shaped. AuthPresentation
retains Domain/SharedUI-only dependencies. Three packages remain until the remaining consumers move.
Durable recovery, ambiguous/confirmed-write ownership across UI cancellation, real server/device/
process tests, full KDF cost limits and release gates remain open. No SDK FFI/real crypto smoke,
signed entitlement/device proof, UI launch, zeroization or rollback guarantee in this block.
