import Foundation
import Testing
@testable import Cadence

@MainActor
struct TimerAlertTests {
    let clock = TestClock()
    let app: AppState

    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CadenceTests-\(UUID())")
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "TimerAlertTests-\(UUID())")!)
        preferences.value.logFolderPath = folder.appendingPathComponent("log").path
        let clock = self.clock
        app = AppState(preferences: preferences, stats: StatsStore(directory: folder.appendingPathComponent("stats")),
                       clock: { clock.now })
    }

    @Test func completedFocusShowsAlert() {
        app.pomodoro.task = "Write tests"
        app.pomodoro.start()
        clock.advance(minutes: 25)
        app.pomodoro.tick()

        #expect(app.timerAlert == .focusEnded(task: "Write tests", nextBreak: .shortBreak, breakMinutes: 5, held: []))
        app.dismissTimerAlert()
        #expect(app.timerAlert == nil)
    }

    @Test func skippedFocusShowsNoAlert() {
        app.pomodoro.start()
        app.pomodoro.skip()
        #expect(app.timerAlert == nil)
    }

    @Test func breakEndShowsAlert() {
        app.pomodoro.start()
        clock.advance(minutes: 25); app.pomodoro.tick()
        clock.advance(minutes: 5); app.pomodoro.tick()
        #expect(app.timerAlert == .breakEnded)
    }

    @Test func turnedOffFallsBackToNotifications() {
        app.preferences.value.showTimerAlert = false
        app.pomodoro.start()
        clock.advance(minutes: 25); app.pomodoro.tick()
        #expect(app.timerAlert == nil)
    }
}
