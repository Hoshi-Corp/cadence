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
        // Settings show the out-of-the-box preferences.
        let settingsApp = AppState(preferences: PreferencesStore(defaults: ephemeralDefaults()))
        settingsApp.preferences.value.logFolderPath = "~/Documents/Cadence"

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
