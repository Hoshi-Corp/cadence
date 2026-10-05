import Foundation

/// One list line in a day's timeline, as found in the file. Lines may have
/// been written by Cadence or by hand, so the time prefix is optional.
struct TimelineItem: Equatable, Identifiable {
    /// Position among the timeline's list items, counting from 0.
    let index: Int
    /// The whole item as it appears in the file, e.g. `- **09:05** Standup`.
    /// A multi-line note continues on indented lines.
    let line: String
    /// `09:05` or `09:05–09:30`, nil when the line has no bold time prefix.
    let time: String?
    /// The text without the time. Continuation lines are included, unindented.
    let text: String

    var id: Int { index }

    init(index: Int, line: String) {
        self.index = index
        self.line = line
        let lines = line.split(separator: "\n", omittingEmptySubsequences: false)
        let continuation = lines.dropFirst().map(Self.unindented)
        let first = lines.first ?? ""
        let body = first.hasPrefix("- ") ? first.dropFirst(2) : first
        var time: String?
        var head = body.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("**") {
            let afterOpen = body.dropFirst(2)
            if let close = afterOpen.range(of: "**"),
               Self.isValidTime(afterOpen[..<close.lowerBound]) {
                time = String(afterOpen[..<close.lowerBound])
                head = afterOpen[close.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        self.time = time
        text = ([head] + continuation).joined(separator: "\n")
    }

    /// Removes the indent that keeps a continuation line inside its list item.
    private static func unindented(_ line: Substring) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return String(line.dropFirst(min(2, line.prefix { $0 == " " }.count)))
    }

    /// The Markdown for this item with a new time and text.
    static func line(time: String?, text: String) -> String {
        let text = LogEntry.multiline(text)
        guard let time = time?.trimmingCharacters(in: .whitespaces), !time.isEmpty else { return "- \(text)" }
        return "- **\(time)** \(text)"
    }

    /// Start and end as minutes since midnight. `end` is nil for a single time.
    var minutes: (start: Int, end: Int?)? {
        guard let time else { return nil }
        return Self.parse(time)
    }

    /// Length of a `09:05–09:30` range, allowing it to cross midnight.
    var duration: TimeInterval? {
        guard let minutes, let end = minutes.end else { return nil }
        return TimeInterval(((end - minutes.start) % (24 * 60) + 24 * 60) % (24 * 60) * 60)
    }

    /// `HH:MM`, or a range `HH:MM–HH:MM` joined by an en dash or a hyphen.
    static func isValidTime<S: StringProtocol>(_ time: S) -> Bool {
        parse(time) != nil
    }

    private static func parse<S: StringProtocol>(_ time: S) -> (start: Int, end: Int?)? {
        let parts = time.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "–" || $0 == "-" })
        guard (1...2).contains(parts.count) else { return nil }
        let values = parts.map { clockMinutes($0.trimmingCharacters(in: .whitespaces)) }
        guard let start = values[0] else { return nil }
        if values.count == 1 { return (start, nil) }
        guard let end = values[1] else { return nil }
        return (start, end)
    }

    private static func clockMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
