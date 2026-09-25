import Foundation
import Testing
@testable import Cadence

@MainActor
struct ReminderSchedulerTests {
    let clock = TestClock()
    let preferences: PreferencesStore

    init() {
        let defaults = UserDefaults(suiteName: "ReminderSchedulerTests-\(UUID())")!
        preferences = PreferencesStore(defaults: defaults)
        // Always inside active hours; only the water reminder, every 60 min.
        preferences.value.activeHours = ActiveHours(startMinute: 0, endMinute: 24 * 60, weekdays: Set(1...7))
        preferences.value.reminders = [Reminder.builtIns[1]]
        clock.now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10))!
    }

    func makeScheduler(focusing: @escaping () -> Bool = { false }) -> (ReminderScheduler, DueLog) {
        let clock = self.clock
        let scheduler = ReminderScheduler(preferences: preferences, isFocusing: focusing, clock: { clock.now })
        let log = DueLog()
        scheduler.onDue = { log.titles.append($0.title) }
        return (scheduler, log)
    }

    @Test func firesAfterInterval() {
        let (scheduler, log) = makeScheduler()
        scheduler.tick()
        clock.advance(minutes: 59); scheduler.tick()
        #expect(log.titles.isEmpty)
        clock.advance(minutes: 1); scheduler.tick()
        #expect(log.titles == ["Drink water"])
    }

    @Test func holdsDuringFocusUntilTaken() {
        let state = FocusFlag()
        let (scheduler, log) = makeScheduler(focusing: { state.value })
        scheduler.tick()
        state.value = true
        clock.advance(minutes: 60); scheduler.tick()

        #expect(log.titles.isEmpty)
        #expect(scheduler.held == [Reminder.builtIns[1].id])
        #expect(scheduler.takeHeld().map(\.title) == ["Drink water"])
        #expect(scheduler.held.isEmpty)
    }

    @Test func deliversHeldWhenFocusStopsWithoutBreak() {
        let state = FocusFlag()
        let (scheduler, log) = makeScheduler(focusing: { state.value })
        scheduler.tick()
        state.value = true
        clock.advance(minutes: 60); scheduler.tick()
        state.value = false
        scheduler.tick()

        #expect(log.titles == ["Drink water"])
    }

    @Test func skipsOutsideActiveHours() {
        preferences.value.activeHours = ActiveHours(startMinute: 9 * 60, endMinute: 10 * 60 + 30, weekdays: Set(1...7))
        let (scheduler, log) = makeScheduler()
        scheduler.tick()
        clock.advance(minutes: 60); scheduler.tick()   // 11:00
        #expect(log.titles.isEmpty)
    }

    @Test func activeHoursAcrossMidnight() {
        let hours = ActiveHours(startMinute: 22 * 60, endMinute: 2 * 60, weekdays: Set(1...7))
        let calendar = Calendar.current
        let at = { (h: Int) in calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: h))! }
        #expect(hours.contains(at(23)))
        #expect(hours.contains(at(1)))
        #expect(!hours.contains(at(12)))
    }
}

@MainActor final class DueLog { var titles: [String] = [] }
@MainActor final class FocusFlag { var value = false }
