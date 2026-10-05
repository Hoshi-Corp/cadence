import Foundation

/// Reads and writes one JSON file of recorded activity per day.
struct ActivityStore {
    let directory: URL

    init(directory: URL = ActivityStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/activity", isDirectory: true)
    }

    func load(for date: Date) -> ActivityDay {
        // Dates use the default encoding, which round-trips exactly; spans
        // are joined by comparing their ends and starts.
        guard let data = try? Data(contentsOf: url(for: date)),
              let day = try? JSONDecoder().decode(ActivityDay.self, from: data)
        else { return ActivityDay() }
        return day
    }

    @discardableResult
    func update(for date: Date, _ change: (inout ActivityDay) -> Void) throws -> ActivityDay {
        var day = load(for: date)
        change(&day)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(day).write(to: url(for: date), options: .atomic)
        return day
    }

    private func url(for date: Date) -> URL {
        let name = WorkLogDocument.fileName(for: date).replacingOccurrences(of: ".md", with: ".json")
        return directory.appendingPathComponent(name)
    }
}

/// The Activity section of the daily Markdown file.
enum ActivityLog {
    static func markdown(for segments: [ActivitySegment], rules: [ActivityRule]) -> String {
        let lines = segments.filter { !$0.isExcluded }.map { line(for: $0, rules: rules) }
        return ([WorkLogDocument.Block.activity.heading, ""] + (lines.isEmpty ? ["Nothing recorded."] : lines))
            .joined(separator: "\n")
    }

    /// e.g. `- **09:05–09:40** Cadence · Xcode 30m, Safari 5m`
    static func line(for segment: ActivitySegment, rules: [ActivityRule]) -> String {
        let title = LogEntry.singleLine(segment.title(rules: rules))
        let time = "\(LogEntry.time(segment.start))–\(LogEntry.time(segment.end))"
        let usage = segment.usage
        // The breakdown adds nothing when the title already names the only app.
        guard !(usage.count == 1 && usage[0].name == title) else { return "- **\(time)** \(title)" }
        let apps = usage.filter { $0.seconds >= 30 }.prefix(3)
            .map { "\($0.name) \(DayStats.duration($0.seconds))" }
        return apps.isEmpty ? "- **\(time)** \(title)" : "- **\(time)** \(title) · \(apps.joined(separator: ", "))"
    }
}
