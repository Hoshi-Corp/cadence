import Foundation

/// Per-day counters behind the Summary section. Stored per machine in
/// Application Support, since the Markdown file is meant for humans.
struct DayStats: Codable, Equatable {
    var focusSeconds: TimeInterval = 0
    var pomodoros = 0
    /// Keyed by reminder UUID string.
    var reminderCounts: [String: Int] = [:]

    func summaryMarkdown(reminders: [Reminder]) -> String {
        var rows = [
            ("Focus time", Self.duration(focusSeconds)),
            ("Pomodoros", "\(pomodoros)"),
        ]
        for reminder in reminders {
            if let count = reminderCounts[reminder.id.uuidString], count > 0 {
                rows.append((reminder.label, "\(count)"))
            }
        }
        let table = rows.map { "| \($0.0) | \($0.1) |" }.joined(separator: "\n")
        return """
        \(WorkLogDocument.Block.summary.heading)

        | Metric | Value |
        |---|---|
        \(table)
        """
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }
}

struct StatsStore {
    let directory: URL

    init(directory: URL = StatsStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/stats", isDirectory: true)
    }

    func load(for date: Date) -> DayStats {
        guard let data = try? Data(contentsOf: url(for: date)),
              let stats = try? JSONDecoder().decode(DayStats.self, from: data)
        else { return DayStats() }
        return stats
    }

    func update(for date: Date, _ change: (inout DayStats) -> Void) throws -> DayStats {
        var stats = load(for: date)
        change(&stats)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(stats).write(to: url(for: date), options: .atomic)
        return stats
    }

    private func url(for date: Date) -> URL {
        let name = WorkLogDocument.fileName(for: date).replacingOccurrences(of: ".md", with: ".json")
        return directory.appendingPathComponent(name)
    }
}
