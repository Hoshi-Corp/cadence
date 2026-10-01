import Foundation
import Observation

/// Tracks when each reminder is next due. Reminders that come due during a
/// focus session are held and handed over when the break starts.
///
/// Interval reminders only fire during active hours and not while the user is
/// away. Fixed-time and one-off reminders were set for a specific moment, so
/// they always fire; a one-off turns itself off once it has.
@MainActor @Observable
final class ReminderScheduler {
    private(set) var nextFire: [Reminder.ID: Date] = [:]
    private(set) var held: [Reminder.ID] = []

    /// Called for each reminder that should be shown right now.
    @ObservationIgnored var onDue: ((Reminder) -> Void)?

    @ObservationIgnored private var scheduled: [Reminder.ID: Reminder.Schedule] = [:]
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let isFocusing: () -> Bool
    @ObservationIgnored private let isAway: () -> Bool
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(
        preferences: PreferencesStore,
        isFocusing: @escaping () -> Bool,
        isAway: @escaping () -> Bool = { false },
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.preferences = preferences
        self.isFocusing = isFocusing
        self.isAway = isAway
        self.clock = clock
        self.calendar = calendar
    }

    private var shouldHold: Bool {
        preferences.value.holdRemindersDuringFocus && isFocusing()
    }

    func tick() {
        let now = clock()
        let prefs = preferences.value
        let enabled = prefs.reminders.filter(\.isEnabled)
        let enabledIDs = Set(enabled.map(\.id))

        nextFire = nextFire.filter { enabledIDs.contains($0.key) }
        scheduled = scheduled.filter { enabledIDs.contains($0.key) }
        // A one-off turns itself off when it fires, but stays held until delivered.
        held.removeAll { id in
            !prefs.reminders.contains { $0.id == id && ($0.isEnabled || $0.schedule.isOnce) }
        }

        // Focus ended without a break (reset or paused): deliver what we held.
        if !held.isEmpty && !shouldHold && !isAway() {
            takeHeld().forEach { onDue?($0) }
        }

        for reminder in enabled {
            guard scheduled[reminder.id] == reminder.schedule, let due = nextFire[reminder.id] else {
                scheduled[reminder.id] = reminder.schedule
                nextFire[reminder.id] = reminder.schedule.nextOccurrence(after: now, calendar: calendar)
                continue
            }
            guard now >= due else { continue }

            switch reminder.schedule {
            case .interval:
                nextFire[reminder.id] = reminder.schedule.nextOccurrence(after: now, calendar: calendar)
                guard prefs.activeHours.contains(now, calendar: calendar), !isAway() else { continue }
            case .daily:
                nextFire[reminder.id] = reminder.schedule.nextOccurrence(after: now, calendar: calendar)
                // Missed while the Mac slept: still worth showing today, not tomorrow.
                guard calendar.isDate(due, inSameDayAs: now) else { continue }
            case .once:
                nextFire[reminder.id] = nil
                scheduled[reminder.id] = nil
                setEnabled(false, for: reminder.id)
            }

            if shouldHold {
                if !held.contains(reminder.id) { held.append(reminder.id) }
            } else {
                onDue?(reminder)
            }
        }
    }

    /// Returns and clears the reminders held during focus.
    func takeHeld() -> [Reminder] {
        let reminders = preferences.value.reminders
        let result = held.compactMap { id in reminders.first { $0.id == id } }
        held = []
        return result
    }

    func snooze(_ id: Reminder.ID, minutes: Int) {
        let date = clock() + TimeInterval(minutes * 60)
        // A one-off has already turned itself off, so move it and turn it back on.
        if let index = preferences.value.reminders.firstIndex(where: { $0.id == id }),
           preferences.value.reminders[index].schedule.isOnce {
            preferences.value.reminders[index].schedule = .once(date)
            preferences.value.reminders[index].isEnabled = true
            scheduled[id] = .once(date)
        }
        nextFire[id] = date
    }

    /// Starts every interval reminder over, e.g. after the Mac wakes from sleep
    /// or the user comes back. Fixed-time and one-off reminders keep their time.
    func restartIntervals() {
        for reminder in preferences.value.reminders {
            if case .interval = reminder.schedule {
                nextFire[reminder.id] = nil
                scheduled[reminder.id] = nil
            }
        }
        tick()
    }

    var upcoming: [(reminder: Reminder, date: Date)] {
        preferences.value.reminders
            .compactMap { reminder in nextFire[reminder.id].map { (reminder, $0) } }
            .sorted { $0.date < $1.date }
    }

    private func setEnabled(_ enabled: Bool, for id: Reminder.ID) {
        guard let index = preferences.value.reminders.firstIndex(where: { $0.id == id }) else { return }
        preferences.value.reminders[index].isEnabled = enabled
    }
}
