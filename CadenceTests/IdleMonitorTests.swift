import Foundation
import Testing
@testable import Cadence

@MainActor
struct IdleMonitorTests {
    let clock = TestClock()
    let input = IdleInput()
    let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "IdleMonitorTests-\(UUID())")!)

    func makeMonitor() -> (IdleMonitor, ReturnLog) {
        let clock = self.clock, input = self.input
        let monitor = IdleMonitor(preferences: preferences, idleSeconds: { input.seconds }, clock: { clock.now })
        let log = ReturnLog()
        monitor.onReturn = { log.returns.append(($0, $1)) }
        return (monitor, log)
    }

    @Test func awayAfterThreshold() {
        let (monitor, _) = makeMonitor()
        input.seconds = 4 * 60
        monitor.tick()
        #expect(!monitor.isAway)

        input.seconds = 5 * 60
        monitor.tick()
        #expect(monitor.isAway)
        #expect(monitor.awaySince == clock.now - 5 * 60)
    }

    @Test func reportsWhenTheAbsenceStartedAndEnded() throws {
        let (monitor, log) = makeMonitor()
        let lastInput = clock.now
        clock.advance(minutes: 6); input.seconds = 6 * 60
        monitor.tick()

        // Input resumed 15 s before this tick.
        clock.advance(minutes: 20); input.seconds = 15
        monitor.tick()

        #expect(!monitor.isAway)
        let away = try #require(log.returns.first)
        #expect(away.from == lastInput)
        #expect(away.to == clock.now - 15)
    }

    @Test func disabledNeverReportsAway() {
        preferences.value.idle.isEnabled = false
        let (monitor, log) = makeMonitor()
        input.seconds = 60 * 60
        monitor.tick()
        #expect(!monitor.isAway)
        input.seconds = 0
        monitor.tick()
        #expect(log.returns.isEmpty)
    }
}

@MainActor final class IdleInput { var seconds: TimeInterval = 0 }
@MainActor final class ReturnLog { var returns: [(from: Date, to: Date)] = [] }
