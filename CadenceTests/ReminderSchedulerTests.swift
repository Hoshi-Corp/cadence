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

    func makeScheduler(
        focusing: @escaping () -> Bool = { false },
        away: @escaping () -> Bool = { false }
    ) -> (ReminderScheduler, DueLog) {
        let clock = self.clock
        let scheduler = ReminderScheduler(preferences: preferences, isFocusing: focusing, isAway: away,
                                          clock: { clock.now })
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

extension ReminderSchedulerTests {
    func at(day: Int = 24, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func custom(_ title: String, _ schedule: Reminder.Schedule) -> Reminder {
        Reminder(id: UUID(), emoji: "🔔", title: title, message: "", schedule: schedule)
    }

    @Test func dailyFiresAtItsTimeOutsideActiveHours() {
        // Active hours end at 10:30, but a set-time reminder isn't bound by them.
        preferences.value.activeHours = ActiveHours(startMinute: 9 * 60, endMinute: 10 * 60 + 30, weekdays: Set(1...7))
        preferences.value.reminders = [custom("Lunch", .daily(minuteOfDay: 12 * 60 + 30, weekdays: Set(1...7)))]
        let (scheduler, log) = makeScheduler()
        scheduler.tick()
        #expect(scheduler.nextFire.values.first == at(hour: 12, minute: 30))

        clock.now = at(hour: 12, minute: 29); scheduler.tick()
        #expect(log.titles.isEmpty)
        clock.now = at(hour: 12, minute: 30); scheduler.tick()
        #expect(log.titles == ["Lunch"])
        #expect(scheduler.nextFire.values.first == at(day: 25, hour: 12, minute: 30))
    }

    @Test func dailySkipsDaysNotChosen() {
        // 2026-09-24 is a Thursday (weekday 5); only Mondays (2) are chosen.
        let next = Reminder.Schedule.daily(minuteOfDay: 9 * 60, weekdays: [2]).nextOccurrence(after: at(hour: 10))
        #expect(next == at(day: 28, hour: 9))
    }

    @Test func dailyMissedOnAnEarlierDayIsSkipped() {
        preferences.value.reminders = [custom("Standup", .daily(minuteOfDay: 9 * 60 + 30, weekdays: Set(1...7)))]
        let (scheduler, log) = makeScheduler()
        scheduler.tick()                       // 10:00, next is tomorrow 09:30
        clock.now = at(day: 26, hour: 8)       // asleep through the 25th
        scheduler.tick()
        #expect(log.titles.isEmpty)
        #expect(scheduler.nextFire.values.first == at(day: 26, hour: 9, minute: 30))
    }

    @Test func onceFiresOnceAndTurnsOff() {
        preferences.value.reminders = [custom("Call dentist", .once(at(hour: 15)))]
        let (scheduler, log) = makeScheduler()
        scheduler.tick()
        clock.now = at(hour: 15); scheduler.tick()
        clock.now = at(hour: 16); scheduler.tick()

        #expect(log.titles == ["Call dentist"])
        #expect(preferences.value.reminders[0].isEnabled == false)
        #expect(scheduler.upcoming.isEmpty)
    }

    @Test func snoozingAOneOffTurnsItBackOn() {
        preferences.value.reminders = [custom("Call dentist", .once(at(hour: 15)))]
        let (scheduler, log) = makeScheduler()
        scheduler.tick()
        clock.now = at(hour: 15); scheduler.tick()
        scheduler.snooze(preferences.value.reminders[0].id, minutes: 10)

        #expect(preferences.value.reminders[0].isEnabled)
        #expect(preferences.value.reminders[0].schedule == .once(at(hour: 15, minute: 10)))
        clock.now = at(hour: 15, minute: 10); scheduler.tick()
        #expect(log.titles == ["Call dentist", "Call dentist"])
    }

    @Test func heldOneOffIsDeliveredAfterItTurnsOff() {
        let state = FocusFlag()
        preferences.value.reminders = [custom("Call dentist", .once(at(hour: 10, minute: 30)))]
        let (scheduler, log) = makeScheduler(focusing: { state.value })
        scheduler.tick()
        state.value = true
        clock.now = at(hour: 10, minute: 30); scheduler.tick()
        clock.now = at(hour: 10, minute: 31); scheduler.tick()

        #expect(log.titles.isEmpty)
        #expect(scheduler.takeHeld().map(\.title) == ["Call dentist"])
    }

    @Test func intervalRemindersWaitWhileAway() {
        let away = FocusFlag()
        let (scheduler, log) = makeScheduler(away: { away.value })
        scheduler.tick()
        away.value = true
        clock.advance(minutes: 60); scheduler.tick()
        #expect(log.titles.isEmpty)

        away.value = false
        scheduler.restartIntervals()
        #expect(scheduler.nextFire.values.first == clock.now + 60 * 60)
    }

    @Test func restartKeepsSetTimeReminders() {
        let daily = custom("Lunch", .daily(minuteOfDay: 12 * 60 + 30, weekdays: Set(1...7)))
        preferences.value.reminders = [Reminder.builtIns[1], daily]
        let (scheduler, _) = makeScheduler()
        scheduler.tick()
        clock.advance(minutes: 30)
        scheduler.restartIntervals()

        #expect(scheduler.nextFire[daily.id] == at(hour: 12, minute: 30))
        #expect(scheduler.nextFire[Reminder.builtIns[1].id] == clock.now + 60 * 60)
    }

    @Test func changingTheScheduleReschedules() {
        let (scheduler, _) = makeScheduler()
        scheduler.tick()
        preferences.value.reminders[0].schedule = .interval(minutes: 15)
        clock.advance(minutes: 5); scheduler.tick()
        #expect(scheduler.nextFire.values.first == clock.now + 15 * 60)
    }

    @Test func decodesVersion1Reminders() throws {
        let json = #"{"id":"5E0F4C2A-0001-4000-8000-000000000001","emoji":"🧍","title":"Stand up","message":"Move","intervalMinutes":50,"isEnabled":false,"logWhenDone":true}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.schedule == .interval(minutes: 50))
        #expect(reminder.isEnabled == false)
        #expect(reminder.isBuiltIn)
    }
}

@MainActor final class DueLog { var titles: [String] = [] }
@MainActor final class FocusFlag { var value = false }
