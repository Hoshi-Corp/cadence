import Foundation
import Testing
@testable import Cadence

private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!

/// A span `minutes` long starting `at` minutes after 09:00.
private func span(_ app: String, at start: Double, minutes: Double, title: String? = nil, url: String? = nil)
    -> AppSpan {
    AppSpan(appName: app, bundleID: "com.example.\(app.lowercased())", windowTitle: title, url: url,
            start: day + start * 60, end: day + (start + minutes) * 60)
}

private func segmented(_ spans: [AppSpan], rules: [ActivityRule] = [], minimum: Double = 5) -> [ActivitySegment] {
    spans.reduce([]) { ActivitySegmenter.append($1, to: $0, rules: rules, minimum: minimum * 60) }
}

struct ActivitySegmenterTests {
    @Test func foldsShortSwitchesIntoTheSurroundingActivity() {
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Slack", at: 20, minutes: 2),
                                  span("Xcode", at: 22, minutes: 15)])
        #expect(segments.count == 1)
        #expect(segments[0].title(rules: []) == "Xcode")
        #expect(segments[0].usage.map(\.name) == ["Xcode", "Slack"])
        #expect(segments[0].duration == 37 * 60)
    }

    @Test func startsANewSegmentForALongerSwitch() {
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Safari", at: 20, minutes: 10)])
        #expect(segments.map { $0.title(rules: []) } == ["Xcode", "Safari"])
    }

    @Test func takesAlongTheStartOfANewActivityThatWasFoldedIn() {
        // Safari arrives in two parts, the first short enough to be folded into Xcode.
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Safari", at: 20, minutes: 3),
                                  span("Safari", at: 23, minutes: 10)])
        #expect(segments.count == 2)
        #expect(segments[0].end == day + 20 * 60)
        #expect(segments[1].start == day + 20 * 60)
        #expect(segments[1].spans.count == 1)
    }

    @Test func aShortFirstSegmentJoinsTheNextActivity() {
        let segments = segmented([span("Mail", at: 0, minutes: 1), span("Xcode", at: 1, minutes: 30)])
        #expect(segments.count == 1)
        #expect(segments[0].title(rules: []) == "Xcode")
        #expect(segments[0].start == day)
    }

    @Test func aGapStartsANewSegment() {
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Xcode", at: 40, minutes: 20)])
        #expect(segments.count == 2)
    }

    @Test func rulesNameAndJoinActivity() {
        let rules = [ActivityRule(field: .app, pattern: "xcode", task: "Cadence"),
                     ActivityRule(field: .app, pattern: "Terminal", task: "Cadence")]
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Terminal", at: 20, minutes: 15)], rules: rules)
        #expect(segments.count == 1)
        #expect(segments[0].title(rules: rules) == "Cadence")
        #expect(ActivityLog.line(for: segments[0], rules: rules) == "- **09:00–09:35** Cadence · Xcode 20m, Terminal 15m")
    }

    @Test func windowTitleRulesNeedATitle() {
        let rule = ActivityRule(field: .windowTitle, pattern: "PR #412", task: "Review")
        #expect(!rule.matches(span("Safari", at: 0, minutes: 5)))
        #expect(rule.matches(span("Safari", at: 0, minutes: 5, title: "Fix login · PR #412")))
        #expect(!ActivityRule(field: .app, pattern: "Safari", task: " ").matches(span("Safari", at: 0, minutes: 5)))
    }

    @Test func mergesNeighboursOnly() throws {
        let segments = segmented([span("Xcode", at: 0, minutes: 20), span("Safari", at: 20, minutes: 10),
                                  span("Mail", at: 30, minutes: 10)])
        #expect(ActivitySegmenter.merging([segments[0].id, segments[2].id], in: segments) == nil)
        #expect(ActivitySegmenter.merging([segments[0].id], in: segments) == nil)

        var renamed = ActivitySegmenter.renaming(segments[1].id, to: "Research", in: segments)
        renamed = try #require(ActivitySegmenter.merging([segments[0].id, segments[1].id], in: renamed))
        #expect(renamed.count == 2)
        #expect(renamed[0].id == segments[0].id)
        #expect(renamed[0].title(rules: []) == "Research")
        #expect(renamed[0].isEdited)
        #expect(renamed[0].end == day + 30 * 60)
    }

    @Test func splitsInsideASpan() throws {
        let segments = segmented([span("Xcode", at: 0, minutes: 60)])
        #expect(ActivitySegmenter.splitting(segments[0].id, at: day, in: segments) == nil)

        let split = try #require(ActivitySegmenter.splitting(segments[0].id, at: day + 25 * 60, in: segments))
        #expect(split.map(\.duration) == [25 * 60, 35 * 60])
        #expect(split[0].id == segments[0].id)
        #expect(split.allSatisfy { $0.isEdited })
    }

    @Test func editedSegmentsKeepTheirShape() {
        // A short segment the user renamed isn't swallowed by what comes next.
        var segments = segmented([span("Mail", at: 0, minutes: 2)])
        segments = ActivitySegmenter.renaming(segments[0].id, to: "Inbox zero", in: segments)
        segments = ActivitySegmenter.append(span("Xcode", at: 2, minutes: 30), to: segments, rules: [], minimum: 5 * 60)
        #expect(segments.map { $0.title(rules: []) } == ["Inbox zero", "Xcode"])
    }

    @Test func excludedSegmentsStayOutOfTheLog() {
        var segments = segmented([span("Xcode", at: 0, minutes: 20), span("Safari", at: 20, minutes: 10)])
        segments = ActivitySegmenter.settingExcluded(true, for: [segments[1].id], in: segments)
        #expect(ActivityLog.markdown(for: segments, rules: []) == "## Activity\n\n- **09:00–09:20** Xcode")
        let none = ActivitySegmenter.settingExcluded(true, for: [segments[0].id], in: segments)
        #expect(ActivityLog.markdown(for: none, rules: []) == "## Activity\n\nNothing recorded.")
    }

    @Test func privateSegmentsShowTheirTimesOnly() throws {
        var segments = segmented([span("Xcode", at: 0, minutes: 20), span("Safari", at: 20, minutes: 10)])
        segments = ActivitySegmenter.settingPrivate(true, for: [segments[1].id], in: segments)
        #expect(ActivityLog.markdown(for: segments, rules: [])
            == "## Activity\n\n- **09:00–09:20** Xcode\n- **09:20–09:30** 🔒 Private")

        // Merging never reveals a private part.
        let merged = try #require(ActivitySegmenter.merging([segments[0].id, segments[1].id], in: segments))
        #expect(merged[0].isPrivate)
    }

    @Test func urlRulesAndTheIgnoreList() {
        let tab = span("Safari", at: 0, minutes: 5, title: "Pull requests", url: "https://www.github.com/acme/app/pulls")
        #expect(tab.host == "github.com")
        #expect(ActivityRule(field: .url, pattern: "github.com/acme", task: "Acme").matches(tab))
        #expect(!ActivityRule(field: .url, pattern: "github.com/acme", task: "Acme")
            .matches(span("Safari", at: 0, minutes: 5, title: "Pull requests")))

        var config = ActivityConfig()
        config.ignored = [ActivityIgnore(field: .app, pattern: " "), ActivityIgnore(field: .windowTitle, pattern: "bank")]
        #expect(!config.ignores(tab))
        #expect(config.ignores(span("Safari", at: 0, minutes: 5, title: "My Bank — Accounts")))
    }

    @Test func windowTitlesAreListedPerSegment() {
        let segments = segmented([
            span("Safari", at: 0, minutes: 10, title: "Docs", url: "https://developer.apple.com/documentation"),
            span("Safari", at: 10, minutes: 2, title: "Inbox"),
            span("Safari", at: 12, minutes: 5, title: "Docs", url: "https://developer.apple.com/documentation"),
        ])
        #expect(segments.count == 1)
        #expect(segments[0].spans.count == 3)
        #expect(segments[0].windowTitles.map(\.name) == ["Docs — developer.apple.com", "Inbox"])
        #expect(segments[0].usage.map(\.name) == ["Safari"])
    }

    @Test func readsActivitySavedByVersion03() throws {
        let json = """
            {"segments":[{"id":"6F1C1D2E-0000-4000-8000-000000000001","isExcluded":false,"isEdited":false,
            "spans":[{"appName":"Xcode","bundleID":"com.apple.dt.Xcode","start":781340400,"end":781341600}]}]}
            """
        let day = try JSONDecoder().decode(ActivityDay.self, from: Data(json.utf8))
        #expect(day.segments.count == 1)
        #expect(!day.segments[0].isPrivate)
        #expect(day.segments[0].spans[0].url == nil)

        let config = try JSONDecoder().decode(ActivityConfig.self, from: Data(#"{"isEnabled":true,"minimumSegmentMinutes":7,"rules":[]}"#.utf8))
        #expect(config.isEnabled && config.minimumSegmentMinutes == 7)
        #expect(!config.recordsWindowTitles && !config.recordsBrowserTabs && config.ignored.isEmpty)
    }

    @Test func splitsSpansAtMidnight() {
        let late = Calendar.current.date(bySettingHour: 23, minute: 50, second: 0, of: day)!
        let parts = AppSpan(appName: "Xcode", start: late, end: late + 30 * 60).splitAtMidnight()
        #expect(parts.map(\.duration) == [10 * 60, 20 * 60])
    }
}

@MainActor
struct ActivityTrackerTests {
    let clock = TestClock()
    let front = FrontAppBox()
    let away = AwayBox()
    let window = WindowBox()
    let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "ActivityTrackerTests-\(UUID())")!)
    let store = ActivityStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("CadenceActivityTests-\(UUID())"))

    init() {
        clock.now = day
        preferences.value.activity.isEnabled = true
    }

    func makeTracker() -> ActivityTracker {
        let clock = clock, front = front, away = away, window = window
        return ActivityTracker(
            preferences: preferences, store: store, frontmostApp: { front.app },
            details: { app, config in
                var app = app
                if config.recordsWindowTitles { app.windowTitle = window.title }
                if config.recordsBrowserTabs { app.url = window.url }
                return app
            },
            awaySince: { away.since }, clock: { clock.now }
        )
    }

    @Test func recordsWindowTitleChangesWithinOneSegment() throws {
        preferences.value.activity.recordsWindowTitles = true
        window.title = "AppState.swift"
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 10)
        window.title = "ActivityTracker.swift"
        tracker.poll()
        clock.advance(minutes: 10)
        tracker.stop()

        let segments = store.load(for: day).segments
        #expect(segments.count == 1)
        #expect(segments[0].spans.map(\.windowTitle) == ["AppState.swift", "ActivityTracker.swift"])
        #expect(segments[0].duration == 20 * 60)
    }

    @Test func pollingDoesNothingWithoutWindowTitles() {
        window.title = "AppState.swift"
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 10)
        front.app = FrontApp(name: "Safari", bundleID: "com.apple.Safari")
        tracker.poll()
        #expect(tracker.current?.appName == "Xcode")
        #expect(tracker.current?.windowTitle == nil)
    }

    @Test func ignoredAppsAreLeftOut() throws {
        preferences.value.activity.ignored = [ActivityIgnore(field: .app, pattern: "1Password")]
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 20)
        tracker.appDidActivate(FrontApp(name: "1Password", bundleID: "com.1password.1password"))
        #expect(tracker.current == nil)
        clock.advance(minutes: 5)
        tracker.appDidActivate(FrontApp(name: "Safari", bundleID: "com.apple.Safari"))
        clock.advance(minutes: 10)
        tracker.stop()

        let segments = store.load(for: day).segments
        #expect(segments.map { $0.title(rules: []) } == ["Xcode", "Safari"])
        #expect(segments[0].end == day + 20 * 60)
        #expect(segments[1].start == day + 25 * 60)
    }

    @Test func addingToTheIgnoreListStopsRecordingAtOnce() throws {
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 10)
        preferences.value.activity.ignored = [ActivityIgnore(field: .app, pattern: "Xcode")]
        tracker.sync()
        #expect(tracker.current == nil)
        let segments = store.load(for: day).segments
        #expect(segments.count == 1)
        #expect(try #require(segments.first).duration == 10 * 60)
    }

    @Test func recordsAppSwitches() {
        let tracker = makeTracker()
        tracker.start()
        #expect(tracker.current?.appName == "Xcode")

        clock.advance(minutes: 30)
        tracker.appDidActivate(FrontApp(name: "Safari", bundleID: "com.apple.Safari"))
        clock.advance(minutes: 10)
        tracker.appDidActivate(FrontApp(name: "Safari", bundleID: "com.apple.Safari"))

        #expect(store.load(for: day).segments.map { $0.title(rules: []) } == ["Xcode"])
        // The live segment shows what's being recorded right now.
        let live = tracker.segments(for: day)
        #expect(live.map { $0.title(rules: []) } == ["Xcode", "Safari"])
        #expect(live[1].duration == 10 * 60)
    }

    @Test func doesNothingWhileDisabled() {
        preferences.value.activity.isEnabled = false
        let tracker = makeTracker()
        tracker.start()
        tracker.appDidActivate(FrontApp(name: "Safari", bundleID: "com.apple.Safari"))
        #expect(tracker.current == nil)
        #expect(store.load(for: day).segments.isEmpty)
    }

    @Test func stopsWhileAwayFromWhenTheUserLeft() throws {
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 30)
        away.since = clock.now
        clock.advance(minutes: 6)
        tracker.tick()
        #expect(tracker.current == nil)
        let segment = try #require(store.load(for: day).segments.first)
        #expect(segment.duration == 30 * 60)

        away.since = nil
        tracker.sync(at: clock.now)
        #expect(tracker.current?.start == clock.now)
    }

    @Test func pausesWhileAsleep() {
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 10)
        tracker.suspend(.asleep)
        #expect(tracker.current == nil)
        clock.advance(minutes: 60)
        tracker.resume(.asleep)
        #expect(tracker.current?.start == clock.now)
    }

    @Test func recoversTheSpanInProgressAfterACrash() throws {
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 10)
        tracker.tick()
        let checkpoint = try #require(store.load(for: day).inProgress)
        #expect(checkpoint.duration == 10 * 60)

        // Relaunch without stop().
        clock.advance(minutes: 30)
        let relaunched = makeTracker()
        relaunched.start()
        let saved = store.load(for: day)
        #expect(saved.inProgress == nil)
        #expect(try #require(saved.segments.first).duration == 10 * 60)
    }

    @Test func editsApplyToTheLiveSegmentToo() throws {
        let tracker = makeTracker()
        tracker.start()
        clock.advance(minutes: 20)
        let live = try #require(tracker.segments(for: day).first)
        #expect(tracker.edit(on: day) { ActivitySegmenter.renaming(live.id, to: "Planning", in: $0) })
        #expect(store.load(for: day).segments.map(\.task) == ["Planning"])
    }

    @Test func ignoresCadenceItself() {
        let tracker = makeTracker()
        tracker.start()
        tracker.appDidActivate(FrontApp(name: "Cadence", bundleID: ActivityTracker.ownBundleID))
        #expect(tracker.current?.appName == "Xcode")
    }
}

@MainActor final class FrontAppBox {
    var app: FrontApp? = FrontApp(name: "Xcode", bundleID: "com.apple.dt.Xcode")
}

@MainActor final class WindowBox {
    var title: String?
    var url: String?
}

@MainActor final class AwayBox {
    var since: Date?
}
