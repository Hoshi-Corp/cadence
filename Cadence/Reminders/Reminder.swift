import Foundation

struct Reminder: Codable, Equatable, Identifiable {
    enum Schedule: Codable, Equatable {
        /// Repeats every few minutes during active hours.
        case interval(minutes: Int)
        /// Fires at a time of day on the chosen weekdays, regardless of active hours.
        case daily(minuteOfDay: Int, weekdays: Set<Int>)
        /// Fires once, then the reminder turns itself off.
        case once(Date)

        var isOnce: Bool {
            if case .once = self { true } else { false }
        }

        /// When the schedule next fires after `date`. One-off reminders return their
        /// date even if it has passed, so a reminder missed while Cadence wasn't
        /// running still shows up.
        func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
            switch self {
            case .interval(let minutes):
                return date + TimeInterval(max(minutes, 1) * 60)
            case let .daily(minuteOfDay, weekdays):
                guard !weekdays.isEmpty else { return nil }
                let startOfDay = calendar.startOfDay(for: date)
                for offset in 0...7 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay),
                          weekdays.contains(calendar.component(.weekday, from: day)),
                          let candidate = calendar.date(
                              bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day
                          ),
                          candidate > date
                    else { continue }
                    return candidate
                }
                return nil
            case .once(let date):
                return date
            }
        }
    }

    var id: UUID
    var emoji: String
    var title: String
    var message: String
    var schedule: Schedule
    var isEnabled = true
    /// Append a line to the work log when marked done.
    var logWhenDone = true

    var label: String { emoji.isEmpty ? title : "\(emoji) \(title)" }

    var isBuiltIn: Bool { Self.builtIns.contains { $0.id == id } }

    /// A one-off whose time has passed and that turned itself off.
    func hasFired(before date: Date) -> Bool {
        if case .once(let at) = schedule { !isEnabled && at <= date } else { false }
    }

    static func custom() -> Reminder {
        Reminder(id: UUID(), emoji: "🔔", title: "", message: "", schedule: .interval(minutes: 30))
    }

    // Fixed IDs keep the built-ins recognisable across machines and exports.
    static let builtIns: [Reminder] = [
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0001-4000-8000-000000000001")!,
            emoji: "🧍", title: "Stand up",
            message: "Time to get up and move for a minute.",
            schedule: .interval(minutes: 45)
        ),
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0002-4000-8000-000000000002")!,
            emoji: "💧", title: "Drink water",
            message: "Have a glass of water.",
            schedule: .interval(minutes: 60)
        ),
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0003-4000-8000-000000000003")!,
            emoji: "🤸", title: "Stretch",
            message: "Stretch your neck, shoulders and back.",
            schedule: .interval(minutes: 90)
        ),
    ]
}

// Declared in an extension so the memberwise initializer stays available.
extension Reminder {
    // v0.1 stored `intervalMinutes` instead of `schedule`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        title = try c.decode(String.self, forKey: .title)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        logWhenDone = try c.decodeIfPresent(Bool.self, forKey: .logWhenDone) ?? true
        if let schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) {
            self.schedule = schedule
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            schedule = .interval(minutes: try legacy.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 60)
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case intervalMinutes
    }
}
