import Foundation

struct LogEntry: Equatable {
    enum Kind: Equatable {
        case note
        case pomodoro(end: Date)
        case reminder(emoji: String)
        case away(end: Date)
    }

    var date: Date
    var kind: Kind
    var text: String
    var outcome: String?

    var markdown: String {
        let time = Self.time(date)
        // Notes may span several lines; everything else stays on one.
        let text = kind == .note ? Self.multiline(text) : Self.singleLine(text)
        switch kind {
        case .note:
            return "- **\(time)** \(text)"
        case .reminder(let emoji):
            return "- **\(time)** \(emoji) \(text)"
        case .pomodoro(let end):
            let task = text.isEmpty ? "Focus session" : text
            let outcome = outcome.map(Self.singleLine).flatMap { $0.isEmpty ? nil : " — *\($0)*" } ?? ""
            return "- **\(time)–\(Self.time(end))** 🍅 \(task)\(outcome)"
        case .away(let end):
            return "- **\(time)–\(Self.time(end))** 💤 \(text.isEmpty ? "Away" : text)"
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

    /// Keeps line breaks, indenting the lines after the first so they stay
    /// part of the same list item. Blank lines are dropped for the same reason.
    static func multiline(_ text: String) -> String {
        var lines = text.split(whereSeparator: \.isNewline).map { line in
            var line = String(line)
            while let last = line.last, last.isWhitespace { line.removeLast() }
            return line
        }
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return "" }
        let rest = lines.dropFirst().map { "  \($0)" }
        return ([first.trimmingCharacters(in: .whitespaces)] + rest).joined(separator: "\n")
    }
}
