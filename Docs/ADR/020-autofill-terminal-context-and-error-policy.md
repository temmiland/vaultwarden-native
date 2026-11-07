# AutoFill terminal context and typed error policy

Status: implemented locally, 2026-09-28; X-602/X-603 remain partial. This is a live controller
boundary with an injected context harness, not an executed AuthenticationServices UI test.

## Defects and decision

The controller duplicated its final access check, lifecycle claim, teardown and Apple completion
calls. Passkey/TOTP paths claimed completion and then used an async platform wrapper; teardown
also happened before dispatch. That made the claimed request harder to reason about across
suspension or synchronous teardown reentry. Generic registration failures warned that the write
might have succeeded but still enabled the same Save action. Explicit biometric user cancellation
was indistinguishable from ordinary verification=false and could permit a preferred-verification
fallback.

`AutoFillData.AutoFillRequestCompletion` now owns the terminal sequence used by every controller
password, TOTP, assertion, registration and cancellation path. It retains only lifecycle metadata,
not the context or credential payload. `AutoFillExtensionContext` is a synchronous MainActor port;
`SystemAutoFillExtensionContext` is the sole Apple terminal adapter. The extension keeps Apple
input mapping and UI composition; error classification and terminal orchestration are SDK/OS-free
in AutoFillData. This port is extension-specific, not a general Domain service.

## Completion contract

1. Reject replaced or already completed invocation IDs without checking the successor's lease.
2. Check task cancellation and the invocation's current authorization. Password/TOTP/assertion
   recheck the original cache; confirmed registration checks its proof without rejecting its own
   successful cache revision change.
3. Reject unavailable output capabilities and malformed empty mandatory fields before claiming.
   An intentionally empty password username and an SDK-decoded empty user handle remain valid;
   this validation does not prove hashes, signatures or attestation cryptographically valid.
4. Claim once, then synchronously start the Apple callback API with no await or UI teardown in
   between. The optional background completion handler is not a new authorization acknowledgment.
5. Retire the old session/task/picker only if the invocation is still current after dispatch. A
   synchronously reentrant context that starts a successor must not have that successor retired.

Cancellation uses the same claim and retirement rule. Old callbacks cannot cancel the newer
context or release its busy-action gate. The output enum redacts both diagnostic descriptions;
production completion retains no payload. Test fixtures retain only synthetic outputs.

Apple callback API signatures were checked against the installed SDK header, and both production
targets compiled. This avoids relying on the async convenience API's scheduling. It does not
guarantee OS acceptance or recall credentials after dispatch, and the shared-grant check plus OS
call are not one atomic transaction.

## Failure and retry contract

`AutoFillRequestErrorPolicy` maps known access/output/verification errors to typed cancellation
reasons. Unknown errors use the request route; identified failures never widen to a whole-vault
picker. Unknown credential types are not interpreted as passwords or assertions. UI messages
never render generic error descriptions or server bodies.

Only known pre-write or definite-rejection registration failures enable local retry. Unknown,
confirmed/uncertain-write, output-validation and invalid-request errors disable the same Save
action and require cancellation/sync or a new request. The registration writer/journal, not this
UI policy, remains the authority preventing duplicate mutations.

`PlatformServices.SystemPasskeyUserVerifier` converts only LocalAuthentication's explicit
userCancel in its own error domain to `Domain.PasskeyUserVerificationError.userCanceled`.
Task cancellation still wins over late platform results; unavailable/system/auth-failure cases
retain the existing false result, and required/preferred handling remains the SDK engine's job.
The SDK callback records explicit user cancellation in a lock-protected, invocation-local sticky
error. It cannot subsequently fall back to discouraged verification or reprompt. The adapter
restores this typed error if an FFI layer wraps it or returns output. A confirmed/uncertain writer
outcome takes priority over this callback error: never report "no write started" after a commit.

## Executed checks and limits

21 new test methods: ten terminal boundary, four query/context compositions, four error policy,
two SDK callback cancellation and one platform error mapping. An existing post-commit test also
adds explicit verification cancellation after confirmation. Full AppModules execution passed
749 Swift-Testing methods in 97 suites plus two XCTest tests, **751 total**. Both regenerated
unsigned macOS-arm64 and iOS-Simulator app/extension builds passed. No official SDK/subrepo edits,
new compatibility functionality, credential/journal schema or storage-name changes.

Explicit gates verify replacement during decryption, cancellation before dispatch, lease failure,
reentrant dispatch, all four completion kinds, typed cancel exactly once, malformed output and
unsupported TOTP capability. Composition tests execute the real CredentialQuery and completion
components against fake ports; they do not instantiate ASCredentialProviderViewController or
execute AuthenticationServices completion. The LAContext/SDK callback fixtures do not execute
real biometric prompts or FIDO cryptography/FFI callbacks.

TOTP is generated after selection using a fresh selected seed; this is **not** an expiry-boundary
proof. SDK period/expiry is still discarded by the code-only adapter. A separate bounded step
must preserve that timing metadata, fence generation/dispatch across a period boundary and test
it with an injected clock without retaining picker seeds/codes. Signed OS context/UI, Release,
server, concurrent processes, termination/power loss and entitlements remain open. ADR 015–019
recovery/order limits and operation-owned auth commit/durable recovery are unchanged.
