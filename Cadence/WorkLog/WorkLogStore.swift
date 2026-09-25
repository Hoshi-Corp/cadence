import Foundation
import Observation

/// Writes entries into the daily Markdown file in the user's chosen folder.
@MainActor @Observable
final class WorkLogStore {
    private(set) var lastError: String?

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let stats: StatsStore

    init(preferences: PreferencesStore, stats: StatsStore = StatsStore()) {
        self.preferences = preferences
        self.stats = stats
    }

    var folderURL: URL {
        let path = (preferences.value.logFolderPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func fileURL(for date: Date) -> URL {
        folderURL.appendingPathComponent(WorkLogDocument.fileName(for: date))
    }

    func addNote(_ text: String, at date: Date = Date()) {
        let text = LogEntry.singleLine(text)
        guard !text.isEmpty else { return }
        let entry = LogEntry(date: date, kind: .note, text: text)
        write(for: date) { WorkLogDocument.appendingTimelineLine(entry.markdown, to: $0) }
    }

    /// Records a finished focus session and returns its entry so an outcome can be added later.
    @discardableResult
    func addFocusSession(_ session: FocusSession) -> LogEntry {
        let entry = LogEntry(date: session.start, kind: .pomodoro(end: session.end), text: session.task)
        write(for: session.start, updatingStats: {
            $0.pomodoros += 1
            $0.focusSeconds += session.end.timeIntervalSince(session.start)
        }) { WorkLogDocument.appendingTimelineLine(entry.markdown, to: $0) }
        return entry
    }

    /// Adds the outcome to a logged focus session. If the user already edited
    /// that line, the outcome is appended as a follow-up line instead.
    func addOutcome(_ outcome: String, to entry: LogEntry, at date: Date = Date()) {
        let outcome = LogEntry.singleLine(outcome)
        guard !outcome.isEmpty else { return }
        var amended = entry
        amended.outcome = outcome
        let fallback = LogEntry(date: date, kind: .note, text: "↳ \(outcome)")
        write(for: entry.date) { text in
            WorkLogDocument.replacingTimelineLine(entry.markdown, with: amended.markdown, in: text)
                ?? WorkLogDocument.appendingTimelineLine(fallback.markdown, to: text)
        }
    }

    func markReminderDone(_ reminder: Reminder, at date: Date = Date()) {
        let entry = LogEntry(date: date, kind: .reminder(emoji: reminder.emoji), text: reminder.title)
        write(for: date, updatingStats: {
            $0.reminderCounts[reminder.id.uuidString, default: 0] += 1
        }) { text in
            reminder.logWhenDone ? WorkLogDocument.appendingTimelineLine(entry.markdown, to: text) : text
        }
    }

    private func write(
        for date: Date,
        updatingStats change: (inout DayStats) -> Void = { _ in },
        _ transform: (String) -> String
    ) {
        do {
            let dayStats = try stats.update(for: date, change)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let url = fileURL(for: date)
            // Always re-read: the file may have been edited elsewhere (e.g. Obsidian).
            let existing = FileManager.default.fileExists(atPath: url.path)
                ? try String(contentsOf: url, encoding: .utf8)
                : WorkLogDocument.newDocument(for: date)

            var text = transform(existing)
            let summary = dayStats.summaryMarkdown(reminders: preferences.value.reminders)
            text = WorkLogDocument.replacingBlock(.summary, content: summary, in: text)

            try text.write(to: url, atomically: true, encoding: .utf8)
            lastError = nil
        } catch {
            lastError = "Couldn't write work log: \(error.localizedDescription)"
        }
    }
}
