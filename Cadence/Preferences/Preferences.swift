import Foundation

struct PomodoroConfig: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var sessionsBeforeLongBreak = 4
    var autoStartBreaks = true
    var autoStartFocus = false
}

/// The window in which reminders are allowed to fire.
struct ActiveHours: Codable, Equatable {
    /// Minutes since midnight.
    var startMinute = 9 * 60
    var endMinute = 18 * 60
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, weekdays.contains(weekday) else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute <= endMinute {
            return minute >= startMinute && minute < endMinute
        }
        // Window crosses midnight, e.g. 22:00–02:00.
        return minute >= startMinute || minute < endMinute
    }
}

/// Detects time away from the Mac from the absence of keyboard and mouse input.
struct IdleConfig: Codable, Equatable {
    var isEnabled = true
    var thresholdMinutes = 5
    /// Adds a "💤 Away" line to the work log when the user comes back.
    var logAwayTime = false
}

struct Preferences: Codable, Equatable {
    var pomodoro = PomodoroConfig()
    var activeHours = ActiveHours()
    var holdRemindersDuringFocus = true
    /// Shows a window in the middle of the screen when a focus session or break ends.
    var showTimerAlert = true
    var reminders = Reminder.builtIns
    var logFolderPath = Preferences.defaultLogFolderPath
    var idle = IdleConfig()
    var quickLogHotKeyEnabled = true
    var quickLogHotKey = HotKey.defaultQuickLog
    var activity = ActivityConfig()

    static var defaultLogFolderPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Cadence", isDirectory: true).path
    }

    init() {}

    // Decoded field by field so preferences saved by older versions keep
    // loading when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        pomodoro = try c.decodeIfPresent(PomodoroConfig.self, forKey: .pomodoro) ?? defaults.pomodoro
        activeHours = try c.decodeIfPresent(ActiveHours.self, forKey: .activeHours) ?? defaults.activeHours
        holdRemindersDuringFocus = try c.decodeIfPresent(Bool.self, forKey: .holdRemindersDuringFocus)
            ?? defaults.holdRemindersDuringFocus
        showTimerAlert = try c.decodeIfPresent(Bool.self, forKey: .showTimerAlert) ?? defaults.showTimerAlert
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? defaults.reminders
        logFolderPath = try c.decodeIfPresent(String.self, forKey: .logFolderPath) ?? defaults.logFolderPath
        idle = try c.decodeIfPresent(IdleConfig.self, forKey: .idle) ?? defaults.idle
        quickLogHotKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickLogHotKeyEnabled)
            ?? defaults.quickLogHotKeyEnabled
        quickLogHotKey = try c.decodeIfPresent(HotKey.self, forKey: .quickLogHotKey) ?? defaults.quickLogHotKey
        activity = try c.decodeIfPresent(ActivityConfig.self, forKey: .activity) ?? defaults.activity
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoro, activeHours, holdRemindersDuringFocus, reminders, logFolderPath
        case idle, quickLogHotKeyEnabled, quickLogHotKey, showTimerAlert, activity
    }

    /// Clamps values that would make timers misbehave, for settings that come
    /// from outside the app (an imported file).
    func sanitized() -> Preferences {
        var result = self
        result.pomodoro.focusMinutes = max(1, pomodoro.focusMinutes)
        result.pomodoro.shortBreakMinutes = max(1, pomodoro.shortBreakMinutes)
        result.pomodoro.longBreakMinutes = max(1, pomodoro.longBreakMinutes)
        result.pomodoro.sessionsBeforeLongBreak = max(1, pomodoro.sessionsBeforeLongBreak)
        result.activeHours.startMinute = min(max(0, activeHours.startMinute), 24 * 60)
        result.activeHours.endMinute = min(max(0, activeHours.endMinute), 24 * 60)
        result.idle.thresholdMinutes = max(1, idle.thresholdMinutes)
        result.activity.minimumSegmentMinutes = min(max(1, activity.minimumSegmentMinutes), 60)
        for index in result.reminders.indices {
            switch result.reminders[index].schedule {
            case .interval(let minutes):
                result.reminders[index].schedule = .interval(minutes: max(1, minutes))
            case let .daily(minuteOfDay, weekdays):
                result.reminders[index].schedule = .daily(
                    minuteOfDay: min(max(0, minuteOfDay), 24 * 60 - 1), weekdays: weekdays
                )
            case .once:
                break
            }
        }
        return result
    }
}
