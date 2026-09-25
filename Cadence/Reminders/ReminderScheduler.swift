import Foundation
import Observation

/// Tracks when each interval reminder is next due. Reminders that come due
/// during a focus session are held and handed over when the break starts.
@MainActor @Observable
final class ReminderScheduler {
    private(set) var nextFire: [Reminder.ID: Date] = [:]
    private(set) var held: [Reminder.ID] = []

    /// Called for each reminder that should be shown right now.
    @ObservationIgnored var onDue: ((Reminder) -> Void)?

    @ObservationIgnored private var scheduledInterval: [Reminder.ID: Int] = [:]
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let isFocusing: () -> Bool
    @ObservationIgnored private let clock: () -> Date

    init(preferences: PreferencesStore, isFocusing: @escaping () -> Bool, clock: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.isFocusing = isFocusing
        self.clock = clock
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
        held.removeAll { !enabledIDs.contains($0) }

        // Focus ended without a break (reset or paused): deliver what we held.
        if !held.isEmpty && !shouldHold {
            takeHeld().forEach { onDue?($0) }
        }

        for reminder in enabled {
            let interval = TimeInterval(reminder.intervalMinutes * 60)
            guard scheduledInterval[reminder.id] == reminder.intervalMinutes,
                  let due = nextFire[reminder.id] else {
                scheduledInterval[reminder.id] = reminder.intervalMinutes
                nextFire[reminder.id] = now + interval
                continue
            }
            guard now >= due else { continue }

            nextFire[reminder.id] = now + interval
            guard prefs.activeHours.contains(now) else { continue }

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
        nextFire[id] = clock() + TimeInterval(minutes * 60)
    }

    /// Starts every interval over, e.g. after the Mac wakes from sleep.
    func restartAll() {
        nextFire = [:]
        scheduledInterval = [:]
        tick()
    }

    var upcoming: [(reminder: Reminder, date: Date)] {
        preferences.value.reminders
            .compactMap { reminder in nextFire[reminder.id].map { (reminder, $0) } }
            .sorted { $0.date < $1.date }
    }
}
