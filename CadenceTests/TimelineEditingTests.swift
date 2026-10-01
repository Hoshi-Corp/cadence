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
        #expect(TimelineItem.line(time: "10:15", text: "Standup\nwith team") == "- **10:15** Standup with team")
        #expect(TimelineItem.line(time: " ", text: "No time") == "- No time")
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

    @Test func logsTimeAway() throws {
        store.addAway(from: start, to: start + 20 * 60)
        #expect(try fileText().contains("- **09:05–09:25** 💤 Away"))
    }
}
