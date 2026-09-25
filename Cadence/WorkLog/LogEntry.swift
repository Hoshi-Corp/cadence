import Foundation

struct LogEntry: Equatable {
    enum Kind: Equatable {
        case note
        case pomodoro(end: Date)
        case reminder(emoji: String)
    }

    var date: Date
    var kind: Kind
    var text: String
    var outcome: String?

    var markdown: String {
        let time = Self.time(date)
        let text = Self.singleLine(text)
        switch kind {
        case .note:
            return "- **\(time)** \(text)"
        case .reminder(let emoji):
            return "- **\(time)** \(emoji) \(text)"
        case .pomodoro(let end):
            let task = text.isEmpty ? "Focus session" : text
            let outcome = outcome.map(Self.singleLine).flatMap { $0.isEmpty ? nil : " — *\($0)*" } ?? ""
            return "- **\(time)–\(Self.time(end))** 🍅 \(task)\(outcome)"
        }
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Keeps each entry on one Markdown list line.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
