import Foundation
import Testing
@testable import Cadence

struct TimelineItemTests {
    @Test func parsesTimeRangeAndText() {
        let item = TimelineItem(index: 0, line: "- **09:05–09:30** 🍅 Refactor auth — *done*")
        #expect(item.time == "09:05–09:30")
        #expect(item.text == "🍅 Refactor auth — *done*")
        #expect(item.duration == TimeInterval(25 * 60))
    }

    @Test func lineWithoutTime() {
        let item = TimelineItem(index: 0, line: "- **Important** call back")
        #expect(item.time == nil)
        #expect(item.text == "**Important** call back")
    }

    @Test func rangeAcrossMidnight() {
        #expect(TimelineItem(index: 0, line: "- **23:50–00:15** 🍅 Late").duration == TimeInterval(25 * 60))
    }

    @Test func validatesTimes() {
        #expect(TimelineItem.isValidTime("09:05"))
        #expect(TimelineItem.isValidTime("09:05-10:00"))
        #expect(!TimelineItem.isValidTime("9:05"))
        #expect(!TimelineItem.isValidTime("24:00"))
        #expect(!TimelineItem.isValidTime("09:05–"))
    }

    @Test func buildsLines() {
        #expect(TimelineItem.line(time: "10:15", text: "Standup\nwith team") == "- **10:15** Standup\n  with team")
        #expect(TimelineItem.line(time: " ", text: "No time") == "- No time")
    }

    @Test func parsesContinuationLines() {
        let item = TimelineItem(index: 0, line: "- **10:15** Standup\n  - auth is done\n    - nested")
        #expect(item.time == "10:15")
        #expect(item.text == "Standup\n- auth is done\n  - nested")
        #expect(TimelineItem.line(time: item.time, text: item.text) == item.line)
    }
}

struct MultilineEntryTests {
    @Test func indentsContinuationLinesAndDropsBlankOnes() {
        #expect(LogEntry.multiline("  Decided:  \n\n- ship Friday\n   \n- tell QA\n") == "Decided:\n  - ship Friday\n  - tell QA")
        #expect(LogEntry.multiline(" \n \n") == "")
    }

    @Test func notesKeepLineBreaksOtherEntriesDont() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 15))!
        #expect(LogEntry(date: date, kind: .note, text: "Standup\nAll good").markdown == "- **10:15** Standup\n  All good")
        #expect(LogEntry(date: date, kind: .reminder(emoji: "💧"), text: "Drink\nwater").markdown == "- **10:15** 💧 Drink water")
    }

    let text = """
    <!-- cadence:timeline:start -->
    ## Timeline

    - **09:05** First
      second line
    - **09:10** Second
    <!-- cadence:timeline:end -->
    """

    @Test func itemsIncludeTheirContinuationLines() {
        let items = WorkLogDocument.timelineItems(in: text)
        #expect(items.map(\.line) == ["- **09:05** First\n  second line", "- **09:10** Second"])
        #expect(items[0].text == "First\nsecond line")
    }

    @Test func deletingAMultilineItemRemovesAllItsLines() throws {
        let result = try #require(WorkLogDocument.replacingTimelineItem(
            at: 0, expected: "- **09:05** First\n  second line", with: nil, in: text
        ))
        #expect(result.contains("## Timeline\n\n- **09:10** Second\n"))
    }

    @Test func appendsAfterAMultilineItemWithoutABlankLine() {
        let result = WorkLogDocument.appendingTimelineLine("- **09:20** Third", to: text)
        #expect(result.contains("- **09:10** Second\n- **09:20** Third\n"))
        let afterMultiline = WorkLogDocument.appendingTimelineLine(
            "- **09:30** Fourth", to: WorkLogDocument.appendingTimelineLine("- **09:20** A\n  b", to: text)
        )
        #expect(afterMultiline.contains("- **09:20** A\n  b\n- **09:30** Fourth"))
    }
}

struct TimelineDocumentTests {
    let text = """
    # Log

    <!-- cadence:timeline:start -->
    ## Timeline

    - **09:05** First
    - **09:10** Second
    Some prose the user wrote.
    - **09:20** Third
    <!-- cadence:timeline:end -->

    - Not in the timeline
    """

    @Test func listsOnlyTimelineListItems() {
        #expect(WorkLogDocument.timelineItems(in: text).map(\.text) == ["First", "Second", "Third"])
    }

    @Test func replacesItemAtIndex() throws {
        let result = try #require(
            WorkLogDocument.replacingTimelineItem(at: 1, expected: "- **09:10** Second", with: "- **09:11** Edited", in: text)
        )
        #expect(result.contains("- **09:05** First\n- **09:11** Edited\nSome prose"))
    }

    @Test func deletesItemWithItsLineBreak() throws {
        let result = try #require(
            WorkLogDocument.replacingTimelineItem(at: 0, expected: "- **09:05** First", with: nil, in: text)
        )
        #expect(result.contains("## Timeline\n\n- **09:10** Second\n"))
        #expect(!result.contains("First"))
    }

    @Test func refusesWhenTheLineChanged() {
        #expect(WorkLogDocument.replacingTimelineItem(at: 0, expected: "- **09:05** Old", with: nil, in: text) == nil)
        #expect(WorkLogDocument.replacingTimelineItem(at: 9, expected: "- **09:05** First", with: nil, in: text) == nil)
    }
}

@MainActor
struct WorkLogStoreTests {
    let folder: URL
    let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "WorkLogStoreTests-\(UUID())")!)
    let store: WorkLogStore
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 5))!

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceTests-\(UUID())")
        preferences.value.logFolderPath = folder.appendingPathComponent("log").path
        store = WorkLogStore(preferences: preferences, stats: StatsStore(directory: folder.appendingPathComponent("stats")))
    }

    func fileText() throws -> String {
        try String(contentsOf: store.fileURL(for: start), encoding: .utf8)
    }

    @Test func deletingAPomodoroUpdatesTheSummary() throws {
        store.addFocusSession(FocusSession(task: "Write tests", start: start, end: start + 25 * 60))
        store.addFocusSession(FocusSession(task: "Review", start: start + 30 * 60, end: start + 55 * 60))
        #expect(store.dayStats(for: start).pomodoros == 2)

        let first = try #require(store.timeline(for: start).first)
        #expect(store.replace(first, with: nil, on: start))

        let stats = store.dayStats(for: start)
        #expect(stats.pomodoros == 1)
        #expect(stats.focusSeconds == 25 * 60)
        #expect(try fileText().contains("| Pomodoros | 1 |"))
        #expect(store.timeline(for: start).map(\.text) == ["🍅 Review"])
    }

    @Test func editingAPomodoroRangeAdjustsFocusTime() throws {
        store.addFocusSession(FocusSession(task: "Write tests", start: start, end: start + 25 * 60))
        let item = try #require(store.timeline(for: start).first)
        #expect(store.replace(item, with: "- **09:05–09:50** 🍅 Write tests", on: start))

        #expect(store.dayStats(for: start).focusSeconds == 45 * 60)
        #expect(store.dayStats(for: start).pomodoros == 1)
    }

    @Test func deletingAReminderLineUncountsIt() throws {
        let water = Reminder.builtIns[1]
        store.markReminderDone(water, at: start)
        let item = try #require(store.timeline(for: start).first)
        store.replace(item, with: nil, on: start)

        #expect(store.dayStats(for: start).reminderCounts[water.id.uuidString] == nil)
        #expect(try !fileText().contains("💧 Drink water |"))
    }

    @Test func refusesToOverwriteAnEditMadeElsewhere() throws {
        store.addNote("Standup", at: start)
        let item = try #require(store.timeline(for: start).first)
        let edited = try fileText().replacingOccurrences(of: "Standup", with: "Standup with team")
        try edited.write(to: store.fileURL(for: start), atomically: true, encoding: .utf8)

        #expect(!store.replace(item, with: nil, on: start))
        #expect(try fileText().contains("Standup with team"))
        #expect(store.lastError == nil)
    }

    @Test func keepsLineBreaksInNotes() throws {
        store.addNote("Standup\n- auth done\n- PR #412 blocked", at: start)
        #expect(try fileText().contains("- **09:05** Standup\n  - auth done\n  - PR #412 blocked\n"))
        #expect(store.timeline(for: start).map(\.text) == ["Standup\n- auth done\n- PR #412 blocked"])
    }

    @Test func writesTheActivitySection() throws {
        store.addNote("Standup", at: start)
        #expect(store.writeActivity("## Activity\n\n- **09:00–10:00** Cadence", for: start))
        #expect(store.writeActivity("## Activity\n\n- **09:00–11:00** Cadence", for: start))
        let text = try fileText()
        #expect(text.contains("<!-- cadence:activity:start -->\n## Activity\n\n- **09:00–11:00** Cadence\n<!-- cadence:activity:end -->"))
        #expect(!text.contains("10:00** Cadence"))
        #expect(store.timeline(for: start).map(\.text) == ["Standup"])
    }

    @Test func logsTimeAway() throws {
        store.addAway(from: start, to: start + 20 * 60)
        #expect(try fileText().contains("- **09:05–09:25** 💤 Away"))
    }
}
