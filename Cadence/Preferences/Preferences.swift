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

struct Preferences: Codable, Equatable {
    var pomodoro = PomodoroConfig()
    var activeHours = ActiveHours()
    var holdRemindersDuringFocus = true
    var reminders = Reminder.builtIns
    var logFolderPath = Preferences.defaultLogFolderPath

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
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? defaults.reminders
        logFolderPath = try c.decodeIfPresent(String.self, forKey: .logFolderPath) ?? defaults.logFolderPath
    }

    private enum CodingKeys: String, CodingKey {
        case pomodoro, activeHours, holdRemindersDuringFocus, reminders, logFolderPath
    }
}
