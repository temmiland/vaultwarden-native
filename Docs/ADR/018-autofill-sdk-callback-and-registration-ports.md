# AutoFill SDK callbacks and typed registration ports

Status: implemented locally, 2026-09-28. This completes the SDK-shaped callback/server-writer
split left by ADR 014–017, not the signed OS-context, server or cross-process release gates.

## Ownership

`BitwardenSDKAdapter` now owns `Fido2CredentialStore`/`Fido2UserInterface` implementations,
SDK WebAuthn encoding, raw cipher backing, credential-delta validation and crypto result mapping.
The extension receives opaque `SDKAutoFillCredentialView`/`SDKAutoFillEncryptedCipher` values
and typed assertion/registration bytes. `legacyView` is internal and raw crypto entry points
are private. Neither the extension nor AutoFillData imports BitwardenSdk; the Xcode app/extension
graph no longer declares a direct SDK product dependency. AppModules' adapter still depends on
the unchanged local SDK package. No official SDK/subrepo sources were changed.

`Domain.PasskeyUserVerifying` expresses device-owner verification, including passcode. Its
`PlatformServices.SystemPasskeyUserVerifier` creates a fresh LAContext per evaluation, preserves
false/OS rejection, and rejects a late evaluation after caller cancellation. This is not a
vault-unlock biometric enrollment or a new re-prompt grant. The SDK adapter also rechecks the
invocation's original cache/proof after verification. Required/preferred false is returned
explicitly; the existing SDK engine decides whether the request can proceed.

`AutoFillData.PasskeyRegistrationPersistence` composes a typed crypto/HTTP source with the
existing mutation actor, journal and asynchronous projection port. It rechecks original cache
access after decrypt and before HTTP, requires the same editable login target, preserves the
old credential-ID set and accepts exactly one new, nonempty SDK-decoded credential for the
requested RP. Existing-target metadata must belong to that exact cipher; a new target has no
server ID yet and does not guess one. The post-write identity mapper still checks the returned
server cipher and exact credential metadata. Reservation binds the originating unlock before
HTTP. This is a guard, not a new lossless whole-cipher or server-idempotency contract.

`AutoFillData.PasskeyRegistrationCoordinator` owns whole-registration single-flight before
crypto/verification, recovers the writer's typed terminal state when FFI wraps a callback error,
and requires its confirmed receipt to match the SDK result ID plus nonempty attestation. Crypto
output without a receipt cannot complete. Caller cancellation denies completion, without
cancelling the submitted write's operation-owned Task or skipping its confirmed projection.
Runtime revocation remains effective. The SDK save callback's post-write check is proof-only:
it must not invalidate a successful registration by rereading the old cache UUID it just advanced.

The extension retains only Apple request/result mapping and invocation-scoped composition of
HTTP/token/cache/journal/platform services. `AutoFillFido2Bridge` is a 24-line composition adapter;
registration is reduced from about 300 to 109 lines. Its obsolete Base64URL extension was removed
(recoverable from Git); encoding belongs to the SDK adapter. Endpoint/payload conventions,
algorithms/defaults, client-data hash handling and the existing product scope are unchanged.

## Defects addressed

- Credential lookup previously ignored the passed userHandle. It now matches exact SDK-decoded
  bytes alongside RP and requested credential IDs, with duplicate/foreign/empty matching metadata
  rejected. Existing nil/empty ID-list behavior is preserved; no global credential listing added.
- Authentication previously picked the first available cipher. It now requires exactly one
  candidate bound to the selected current eligible cipher; ambiguous alternatives fail closed.
- Thrown passkey metadata errors previously became a silent empty fallback. They now propagate.
- Registration and creation now bind exact RP, target and decoded delta at the typed boundaries,
  and overlapping attempts are rejected before crypto rather than only at HTTP.

## Executed checks and limits

26 new test methods: eight SDK callback, three request/delta contract, four platform-verifier,
five typed persistence and six coordinator methods. Parametrized cases cover exact ID/RP/handle,
ambiguity and policy, late verification, unchanged/duplicate/dropped/foreign credential deltas,
reserve-before-HTTP, stale cache/decrypt, independent post-submit projection, output receipt
binding, busy exclusion and wrapped terminal errors. Explicit gates, no sleeps or OS prompts.
The callback tests call Swift protocol implementations directly with synthetic SDK structs;
they do not execute real SDK FIDO crypto or its FFI callback invocation.

Complete AppModules targets: 710 Swift-Testing methods in 90 suites plus two XCTest tests
(712 total), all passed. Both regenerated macOS-arm64 and iOS-Simulator app/extension builds
passed unsigned. See [verification](../Verification.md).

Still open: controller/OS-context completion and error mapping, real user-verification/userHandle
and create/update response-preservation matrices, silent SDK field degradation, collection policy
missing from legacy caches, Release/signing/entitlement/device checks, server/FFI round-trips,
process death/power-loss and signed app/extension OS publication ordering. A shared mutation
lock and current-cache/unlock guards are implemented locally by
[ADR 019](019-shared-credential-identity-mutation-ordering.md). Journal/Keychain/cache/
HTTP/OS completion are not one transaction; issued server requests cannot be recalled.
ADR 015–017 recovery limitations remain unchanged. No new compatibility functionality added.
