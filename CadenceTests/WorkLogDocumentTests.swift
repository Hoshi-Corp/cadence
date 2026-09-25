import Foundation
import Testing
@testable import Cadence

struct WorkLogDocumentTests {
    let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 5))!

    @Test func fileNameIsISODate() {
        #expect(WorkLogDocument.fileName(for: date) == "2026-09-25.md")
    }

    @Test func appendsEntriesAsContiguousList() {
        var text = WorkLogDocument.newDocument(for: date)
        text = WorkLogDocument.appendingTimelineLine("- **09:05** First", to: text)
        text = WorkLogDocument.appendingTimelineLine("- **09:10** Second", to: text)

        #expect(text.contains("## Timeline\n\n- **09:05** First\n- **09:10** Second\n\n<!-- cadence:timeline:end -->"))
    }

    @Test func preservesUserContentOutsideMarkers() {
        var text = WorkLogDocument.newDocument(for: date) + "\n## My notes\nKeep me.\n"
        text = WorkLogDocument.appendingTimelineLine("- **09:05** Entry", to: text)
        text = WorkLogDocument.replacingBlock(.summary, content: "## Summary\n\nstuff", in: text)

        #expect(text.contains("## My notes\nKeep me."))
        #expect(text.contains("- **09:05** Entry"))
        #expect(text.hasSuffix("<!-- cadence:summary:start -->\n## Summary\n\nstuff\n<!-- cadence:summary:end -->\n"))
    }

    @Test func createsTimelineInExistingDailyNote() {
        let note = "# Thursday\n\nWritten in Obsidian.\n"
        let text = WorkLogDocument.appendingTimelineLine("- **09:05** Entry", to: note)

        #expect(text == """
        # Thursday

        Written in Obsidian.

        <!-- cadence:timeline:start -->
        ## Timeline

        - **09:05** Entry
        <!-- cadence:timeline:end -->

        """)
    }

    @Test func replacesSummaryInPlace() {
        var text = WorkLogDocument.replacingBlock(.summary, content: "one", in: "# Log\n")
        text = WorkLogDocument.replacingBlock(.summary, content: "two", in: text)

        #expect(!text.contains("one"))
        #expect(text.components(separatedBy: "cadence:summary:start").count == 2)
    }

    @Test func replacesExactTimelineLine() {
        var text = WorkLogDocument.newDocument(for: date)
        text = WorkLogDocument.appendingTimelineLine("- **09:05** Task", to: text)
        text = WorkLogDocument.appendingTimelineLine("- **09:05** Task extra", to: text)

        let result = WorkLogDocument.replacingTimelineLine("- **09:05** Task", with: "- **09:05** Task — *done*", in: text)

        #expect(result?.contains("- **09:05** Task — *done*\n- **09:05** Task extra") == true)
    }

    @Test func replaceReturnsNilWhenLineWasEdited() {
        let text = WorkLogDocument.appendingTimelineLine("- **09:05** Edited by user", to: WorkLogDocument.newDocument(for: date))
        #expect(WorkLogDocument.replacingTimelineLine("- **09:05** Original", with: "x", in: text) == nil)
    }

    @Test func pomodoroEntryMarkdown() {
        let end = date.addingTimeInterval(25 * 60)
        var entry = LogEntry(date: date, kind: .pomodoro(end: end), text: "Refactor\nauth")
        #expect(entry.markdown == "- **09:05–09:30** 🍅 Refactor auth")
        entry.outcome = "extracted token service"
        #expect(entry.markdown == "- **09:05–09:30** 🍅 Refactor auth — *extracted token service*")
    }

    @Test func summaryListsOnlyCompletedReminders() {
        var stats = DayStats(focusSeconds: 150 * 60, pomodoros: 6)
        stats.reminderCounts[Reminder.builtIns[1].id.uuidString] = 5
        let markdown = stats.summaryMarkdown(reminders: Reminder.builtIns)

        #expect(markdown.contains("| Focus time | 2h 30m |"))
        #expect(markdown.contains("| 💧 Drink water | 5 |"))
        #expect(!markdown.contains("Stand up"))
    }
}
