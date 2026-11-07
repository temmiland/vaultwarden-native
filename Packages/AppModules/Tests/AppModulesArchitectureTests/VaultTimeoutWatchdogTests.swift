import AppFeature
import Domain
import Foundation
import Testing

@MainActor
@Suite
struct VaultTimeoutWatchdogTests {
    private final class TestClock {
        var now = ContinuousClock.Instant.now
        func advance(_ seconds: Int64) { now += .seconds(seconds) }
    }

    private func makeWatchdog(_ preference: VaultTimeoutPreference, clock: TestClock) -> VaultTimeoutWatchdog {
        VaultTimeoutWatchdog(preference: { preference }, now: { clock.now })
    }

    @Test
    func nothingIsDueWhileTheAppIsStillFrontmost() throws {
        let clock = TestClock()
        #expect(try makeWatchdog(VaultTimeoutPreference(duration: .immediately), clock: clock).pendingAction() == nil)
    }

    @Test
    func lockIsDueOnceTheThresholdElapses() throws {
        let clock = TestClock()
        let watchdog = makeWatchdog(VaultTimeoutPreference(duration: .fifteenMinutes), clock: clock)
        watchdog.noteBecameInactive()
        clock.advance(15 * 60)
        #expect(try watchdog.pendingAction() == .lock)
    }

    @Test
    func logOutIsDueWhenConfigured() throws {
        let clock = TestClock()
        let watchdog = makeWatchdog(VaultTimeoutPreference(duration: .oneMinute, action: .logOut), clock: clock)
        watchdog.noteBecameInactive()
        clock.advance(61)
        #expect(try watchdog.pendingAction() == .logOut)
    }

    @Test
    func immediatelyAndNeverRespectTheirBoundaries() throws {
        let immediateClock = TestClock()
        let immediate = makeWatchdog(VaultTimeoutPreference(duration: .immediately), clock: immediateClock)
        immediate.noteBecameInactive()
        #expect(try immediate.pendingAction() == .lock)

        let neverClock = TestClock()
        let never = makeWatchdog(VaultTimeoutPreference(duration: .never), clock: neverClock)
        never.noteBecameInactive()
        neverClock.advance(60 * 60 * 24 * 30)
        #expect(try never.pendingAction() == nil)
    }

    @Test
    func repeatedInactiveNotificationsDoNotResetClockAndActivationDoes() throws {
        let clock = TestClock()
        let watchdog = makeWatchdog(VaultTimeoutPreference(duration: .oneMinute), clock: clock)
        watchdog.noteBecameInactive()
        clock.advance(40)
        watchdog.noteBecameInactive()
        clock.advance(25)
        #expect(try watchdog.pendingAction() == .lock)

        watchdog.noteBecameActive()
        watchdog.noteBecameInactive()
        clock.advance(30)
        #expect(try watchdog.pendingAction() == nil)
    }

    @Test
    func preferenceReadFailuresAreNotConvertedIntoAnUnrelatedDefault() throws {
        let clock = TestClock()
        let watchdog = VaultTimeoutWatchdog(preference: { throw PreferenceFailure.read }, now: { clock.now })
        watchdog.noteBecameInactive()

        #expect(throws: PreferenceFailure.self) { try watchdog.pendingAction() }
    }
}

private enum PreferenceFailure: Error { case read }
