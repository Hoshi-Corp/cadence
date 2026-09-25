import Foundation

struct Reminder: Codable, Equatable, Identifiable {
    var id: UUID
    var emoji: String
    var title: String
    var message: String
    var intervalMinutes: Int
    var isEnabled = true
    /// Append a line to the work log when marked done.
    var logWhenDone = true

    var label: String { "\(emoji) \(title)" }

    // Fixed IDs keep the built-ins recognisable across machines and exports.
    static let builtIns: [Reminder] = [
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0001-4000-8000-000000000001")!,
            emoji: "🧍", title: "Stand up",
            message: "Time to get up and move for a minute.",
            intervalMinutes: 45
        ),
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0002-4000-8000-000000000002")!,
            emoji: "💧", title: "Drink water",
            message: "Have a glass of water.",
            intervalMinutes: 60
        ),
        Reminder(
            id: UUID(uuidString: "5E0F4C2A-0003-4000-8000-000000000003")!,
            emoji: "🤸", title: "Stretch",
            message: "Stretch your neck, shoulders and back.",
            intervalMinutes: 90
        ),
    ]
}
