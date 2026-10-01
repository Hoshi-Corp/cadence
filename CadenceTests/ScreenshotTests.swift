import AppKit
import SwiftUI
import Testing
@testable import Cadence

/// Renders the README screenshots from the real views with demo data.
/// Skipped unless CADENCE_SCREENSHOTS points at an output folder; run `make screenshots`.
private let screenshotDirectory = ProcessInfo.processInfo.environment["CADENCE_SCREENSHOTS"]

@MainActor
struct ScreenshotTests {
    @Test(.enabled(if: screenshotDirectory != nil))
    func generateScreenshots() throws {
        let output = URL(fileURLWithPath: screenshotDirectory!, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = makeDemoApp()
        // Settings show the out-of-the-box preferences plus one custom reminder.
        let settingsApp = AppState(preferences: PreferencesStore(defaults: ephemeralDefaults()))
        settingsApp.preferences.value.logFolderPath = "~/Documents/Cadence"
        settingsApp.preferences.value.reminders.append(Reminder(
            id: UUID(), emoji: "🥗", title: "Lunch", message: "Step away from the desk.",
            schedule: .daily(minuteOfDay: 12 * 60 + 30, weekdays: [2, 3, 4, 5, 6])
        ))

        try snapshot(
            MenuBarView().environment(app).background(.background),
            to: output.appendingPathComponent("menu-bar.png")
        )

        let tabs: [(String, AnyView)] = [
            ("settings-general", AnyView(GeneralSettingsView())),
            ("settings-pomodoro", AnyView(PomodoroSettingsView())),
            ("settings-reminders", AnyView(RemindersSettingsView())),
            ("settings-work-log", AnyView(WorkLogSettingsView())),
        ]
        try snapshot(
            TodayView().environment(try makeTodayApp()).frame(width: 520, height: 420),
            to: output.appendingPathComponent("today.png")
        )
        try snapshot(
            TimerAlertView().environment(try makeAlertApp()).background(.background),
            to: output.appendingPathComponent("timer-alert.png")
        )
        try snapshot(
            QuickLogPanelView(onSave: { _ in }, onCancel: {}).background(.background),
            to: output.appendingPathComponent("quick-log.png")
        )
        try snapshot(
            ReminderEditor(
                draft: ReminderDraft(reminder: settingsApp.preferences.value.reminders.last!, isNew: false),
                onSave: { _ in }, onDelete: { _ in }
            ).environment(settingsApp).background(.background),
            to: output.appendingPathComponent("reminder-editor.png")
        )

        for (name, view) in tabs {
            try snapshot(
                view.formStyle(.grouped)
                    .frame(width: 500)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(settingsApp),
                to: output.appendingPathComponent("\(name).png")
            )
        }
    }

    /// A focus session 6m18s in, with reminders coming up in 12, 27 and 57 minutes.
    private func makeDemoApp() -> AppState {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        // Active all day so the demo never shows "outside active hours".
        preferences.value.activeHours = ActiveHours(startMinute: 0, endMinute: 24 * 60, weekdays: Set(1...7))
        preferences.value.logFolderPath = "~/Documents/Cadence"

        let base = Date()
        let offset = Offset()
        let app = AppState(preferences: preferences, clock: { base + offset.seconds })

        offset.seconds = -33 * 60
        app.reminders.tick()

        offset.seconds = 0
        app.pomodoro.task = "Refactor auth module"
        app.pomodoro.start()
        offset.seconds = 6 * 60 + 18
        app.pomodoro.tick()
        return app
    }

    /// A focus session that just ended, with two reminders held during it.
    private func makeAlertApp() throws -> AppState {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceScreenshots-\(UUID())")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.value.logFolderPath = folder.appendingPathComponent("log").path
        preferences.value.activeHours = ActiveHours(startMinute: 0, endMinute: 24 * 60, weekdays: Set(1...7))
        preferences.value.reminders = [Reminder.builtIns[0], Reminder.builtIns[1]]
            .map { var r = $0; r.schedule = .interval(minutes: 20); return r }
        let base = Date()
        let offset = Offset()
        let app = AppState(preferences: preferences, stats: StatsStore(directory: folder.appendingPathComponent("stats")),
                           clock: { base + offset.seconds })
        app.reminders.tick()
        app.pomodoro.task = "Refactor auth module"
        app.pomodoro.start()
        offset.seconds = 21 * 60
        app.reminders.tick()
        offset.seconds = 25 * 60
        app.pomodoro.tick()
        offset.seconds = 25 * 60 + 12
        app.pomodoro.tick()
        return app
    }

    /// A day with a few entries, written into a temporary log folder.
    private func makeTodayApp() throws -> AppState {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceScreenshots-\(UUID())")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.value.logFolderPath = folder.appendingPathComponent("log").path
        let app = AppState(preferences: preferences, stats: StatsStore(directory: folder.appendingPathComponent("stats")))

        let day = Calendar.current.startOfDay(for: Date())
        let at = { (hour: Int, minute: Int) in day + TimeInterval(hour * 3600 + minute * 60) }
        let auth = app.workLog.addFocusSession(FocusSession(task: "Refactor auth module", start: at(9, 5), end: at(9, 30)))
        app.workLog.addOutcome("extracted token service", to: auth)
        app.workLog.markReminderDone(Reminder.builtIns[1], at: at(9, 32))
        app.workLog.addNote("Standup with team #meeting", at: at(10, 15))
        app.workLog.addFocusSession(FocusSession(task: "Review PR #412", start: at(11, 0), end: at(11, 25)))
        app.workLog.addAway(from: at(12, 30), to: at(13, 10))
        app.workLog.addNote("Decided to ship v0.2 on Friday #decision", at: at(14, 2))
        return app
    }

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CadenceScreenshots-\(UUID())")!
    }

    private func snapshot<V: View>(_ view: V, to url: URL) throws {
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key))
        host.appearance = NSAppearance(named: .aqua)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        // Controls draw in grey unless their window is key, so pretend it is.
        let window = KeyWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first render pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor private final class Offset {
    var seconds: TimeInterval = 0
}
