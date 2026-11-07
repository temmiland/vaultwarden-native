# AutoFill TOTP timing and terminal expiry fence

Status: locally implemented, 2026-09-28. X-602 period-boundary unit coverage is present;
signed Apple context/OS acceptance and real SDK cryptographic vectors remain separate gates.

The code-only AutoFill SDK adapter discarded the SDK's period and used an unspecified SDK clock.
Domain.TimeBasedOneTimeCode now carries a transient, redacted code, period and exact generation
date. CredentialQuery injects a clock and passes that exact date through the source to the SDK.
Validity is the same epoch-aligned time bucket, not generation date plus a whole period. Empty
codes, zero periods, invalid/negative dates and foreign generation timestamps fail closed. A
backward clock jump also rejects output; there is no promise of a monotonic wall clock.

The query rechecks the selected cipher's authorization after generation. One local regeneration
is allowed if generation/access checking crossed a boundary; repeated expiry stops after two
attempts. Permission/metadata errors never trigger regeneration, HTTP or a wait for a new period.
The seed is not retained in picker or actor state. AutoFillRequestCompletion checks expiry using
its injected clock after final access checking and before claiming or dispatching. A code that
expired after the query is cancelled with userInteractionRequired, not filled and not regenerated
using a retained picker seed. The OS adapter unwraps only the checked code string.

Seven new methods cover 30/45/60-second epoch boundaries, backward clock movement, malformed
metadata, one regeneration, bounded repeated rollover, zero-period no-retry, query-to-context
expiry and rollover inside the final access check. Existing query/completion assertions remain.
756 Swift-Testing methods in 98 suites plus two XCTest tests = **758 passed**; both unsigned
macOS/iOS app/extension builds passed. The new tests use fake crypto and an explicit clock, not
timers/sleeps or real FFI. Existing non-timing fixtures use a long synthetic period to avoid
wall-clock-boundary flakiness. Official SDK/subrepos and stored schemas remain unchanged.

This fences local dispatch, not later OS acceptance or relying-party validation. Time can change
after validation, and an already issued credential cannot be recalled. X-602/X-603 and all signed
device/process/OS/Release gates remain partial. The main-app TOTP display uses its existing
separate VaultOneTimeCode contract; this decision changes the AutoFill completion path only.
