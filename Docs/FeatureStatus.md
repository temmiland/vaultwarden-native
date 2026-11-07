# Feature status

This is an unaudited learning project. “Implemented” means a code path exists, not a release or
device acceptance. First publication is source-only; project-owned source, documentation and assets use
GPL-3.0-only. Third-party materials retain their individual licenses (see THIRD_PARTY_NOTICES.md).

The single current review, product acceptance matrix, task status and release checklist is
[RemainingReleaseWork.md](RemainingReleaseWork.md). Historical test counts
belong to [Verification.md](Verification.md); they are not current acceptance claims.

The frozen scope includes custom HTTPS servers, password/TOTP login, password/PIN/biometric
unlock, refresh/lock/logout, vault sync/search/filter/details, the existing login/card/identity/
secure-note/SSH editors, generator/clipboard/TOTP, attachments, text/file Sends, device revocation,
password/TOTP AutoFill, existing passkey flows, and native macOS menu/quick-access/login-item flows.
iPhone, iPad and macOS share the universal app modules. Re-prompt items without an established
master-password grant and unsupported/unknown payloads keep their existing access/write fences.

Password and TOTP QuickType suggestions are restricted to Base Domain URI rules and revalidated
against the current cache and unlock proof before fulfilment. Host, exact, prefix, regex and never
rules are not published as domain suggestions; the scoped interactive picker preserves those rules.
Native password saving and explicit existing-login updates are implemented for iOS/iPadOS 26.2+;
the macOS credential-provider API does not offer password saving, so use the app editor there.
Signed-device acceptance of both features remains pending. Passkey suggestions are separate. Vaultwarden 1.37.5 was tested locally and
does not implement the app's individual-device DELETE endpoint: the app reports the failure and
retains the device. Do not rely on individual-device revocation on that server version.

Additional 2FA methods, new cipher editors, multi-account, a main-app offline vault, background
sync, extension unlock and new administration endpoints remain out of scope.
See the [frozen specification](Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md),
[architecture](Architecture.md) and [third-party notices](../THIRD_PARTY_NOTICES.md).
