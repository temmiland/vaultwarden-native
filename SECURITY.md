# Security policy

This is an unaudited learning project, not a production password manager. There is no supported
stable security release or guarantee of timely fixes. Use disposable accounts and synthetic
credentials. Prefer an audited client for irreplaceable credentials.

## Reporting

Do not post passwords, access/refresh tokens, decrypted keys, credential IDs, user handles,
client-data hashes, real vault exports or unredacted logs in public issues or pull requests.
Send a sanitized report privately to [welcome@temmi.land](mailto:welcome@temmi.land), the
owner-provided security contact. Do not include real credential material in the initial message;
agree on a suitable private exchange if additional sensitive evidence is required. Plain email
is not end-to-end encrypted by default. The owner confirmed this mailbox is reachable on
2026-11-02; this work sent no test email. No guaranteed response time or separate private GitHub
reporting service is promised.

Include the source commit, OS/Xcode version, a minimal synthetic reproduction, expected/observed
behavior and whether the issue crosses app/extension or lock/account boundaries. Do not attach
real credential material. If exposure may have happened, stop using the test account and rotate
affected credentials through a trusted client.

## Scope and known boundaries

See [threat model](Docs/ThreatModel.md), [feature status](Docs/FeatureStatus.md),
[executed verification](Docs/Verification.md) and
[release checklist](Docs/RemainingReleaseWork.md). Green unit tests/unsigned builds are not a security
audit, signed-entitlement validation, server compatibility guarantee or permission to publish a
combined SDK binary. Existing crypto uses the SDK; this project does not implement replacement
vault cryptography or add telemetry as part of the polish.
