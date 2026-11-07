# Domain-only Auth presentation and session handoff

Status: live module migration, 2026-09-28. Local package targets and unsigned macOS/iOS-Simulator
app/extension builds pass. S-303/U-504 and release gates remain partial for the limits below.

## Decision

The complete Auth UI now belongs to AppModules.AuthPresentation, not a separate AuthFeature
package. Its only application dependencies are Domain and SharedUI. This includes the typed
Observation controller and public AuthRootView, not merely the five screen models. None imports
Data, Networking, SecurityStorage, AutoFillContract, the SDK adapter or BitwardenSdk.

Domain.AuthFlowCommands supplies the password command, typed restore result and single-use
handoff. Domain.AuthenticatedSessionCapability supplies account/runtime identity, synchronous
access checks, persistent authorization and revocation. These APIs expose no credential stores,
wrapped keys, TokenScope, raw clients, token callbacks or repository constructors.
AppFeature.AppSessionResource is now an alias of that same Domain capability, avoiding a second
runtime contract. The existing app-owned LegacySessionAdapter conforms to it.

Data.DefaultAuthFlowService owns restore/persistence mapping and command construction. The app
injects exactly one credential store and repository, HTTP and platform clients plus its version;
the service creates neither a store nor a repository. AuthServices is deleted. AuthDependencies
exists only in the migrated test target as an integration-fixture assembly, not in production.
The app passes Domain commands and its biometric client into AuthRootView.

The prepared Data.AuthenticatedSession implements the Domain capability. The UI validates it
after handoff preparation and again checks the route/runtime before calling the app owner.
Only AppComposition converts that capability to the concrete Data assembly and constructs the
session-bound Vault/Send/Settings adapter. There is no session registry, second SDK resource,
token closure or unrevocable handoff ticket. AppModel remains the authority that accepts and
publishes the runtime after temporary-file preparation and repository authorization.

Data installs expiry before the capability escapes: revoke the same runtime, mark the injected
repository expiring for that runtime ID, then notify the app on MainActor. Obsolete/failed UI
handoff revokes both the prepared runtime and pending candidate. Accepted UI teardown does not
revoke the transferred session. The pre-existing single-use guard remains in PendingAuthSession;
a duplicate prepare cannot replace an accepted session's expiry handler or revoke it.

## Restore corrections

Restore captures the persistent revocation epoch before repository suspension. Cancellation,
changed epoch, replacement account/scope or disagreement with the repository deny a returning
route. The controller additionally retires any late returning command from a noncooperative
Domain implementation when its route changed. A Keychain/decode failure goes to recovery, not
first-run setup. These checks do not claim that several Keychain reads form one atomic snapshot.

Displaying the returning screen no longer calls beginUnlock. Only a submitted ReturningUnlock
command starts that transition; cancelled restore cannot leave a spurious unlocking state.
Atomic records authorize returning commands. Split legacy metadata requires a fresh password
sign-in and migration notice; its unrelated tokens are not imported. Unsafe legacy HTTP records
remain stored for explicit recovery/logout but are never offered for authentication. Exact
persisted server spelling and the existing Keychain service identifiers remain unchanged,
including the historical `.AuthFeature` private-service suffix.

## Package and verification

All 65 existing Auth tests are ported, with their assertions, to AppModules.AuthPresentationTests.
That test target explicitly depends on Data/SDK/storage fixtures; production AuthPresentation
does not. It stays separate from AppModulesArchitectureTests to avoid helper-name collisions.
Four new Domain-only controller methods exercise obsolete restore, recovery, stale prepared
runtime and accepted teardown. Ten new Data methods exercise typed restore, unchanged storage
identity, migration, unsafe servers, read/decode errors, account mismatch, cancellation at both
repository hops, lock/logout/replacement fences, single-use handoff and expiry ordering.

The final complete run passes 589 Swift-Testing methods in 75 suites plus two XCTest tests:
591 total. Migrated methods are not counted as new coverage. Both unsigned app/extension builds
pass after XcodeGen regeneration. project.yml and Scripts/test-packages.sh reference only
AppModules and VaultwardenSDK. All former feature-package manifests are gone; ignored build
caches are retained. The official SDK/subrepos are unchanged.
See [executed commands and limits](../Verification.md).

## Remaining limits

This removes the Data-shaped UI boundary, not every auth operation/recovery problem. A confirmed
private credential commit is not rolled back merely because its UI consumer disappears.
Full repository/operation-owned commit and cancellation semantics and durable cleanup recovery
remain open. Separate biometric/PIN Keychain writes are not an atomic multi-item transaction.
The app-shell concrete adapter and existing handoff notification remain explicit transitional
composition; the plan's final repository-observation-only auth workflow is not claimed complete.

Concurrent settings/key replacement, real multi-scene behavior, rotating cross-process refresh,
signed entitlements/biometry, server interoperability, Release product builds and device/UI smoke
tests remain separate gates. No secure-zeroization claim, external security audit, new login
provider or Vaultwarden compatibility feature is introduced by this migration.
