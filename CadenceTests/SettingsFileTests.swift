import Foundation
import Testing
@testable import Cadence

struct SettingsFileTests {
    func sample() -> Preferences {
        var prefs = Preferences()
        prefs.pomodoro.focusMinutes = 50
        prefs.logFolderPath = "/Users/someone/Vault/Daily"
        prefs.quickLogHotKey = HotKey(keyCode: 49, modifiers: 2304, key: "Space")
        prefs.reminders.append(Reminder(
            id: UUID(), emoji: "💊", title: "Vitamins", message: "",
            schedule: .once(Date(timeIntervalSince1970: 1_790_000_000))
        ))
        return prefs
    }

    @Test func roundTrips() throws {
        let prefs = sample()
        let contents = try SettingsFile.decode(try SettingsFile.encode(prefs, appVersion: "0.2.0"))
        #expect(contents.preferences == prefs)
        #expect(contents.appVersion == "0.2.0")
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: SettingsFile.ReadError.self) {
            try SettingsFile.decode(Data(#"{"pomodoro":{}}"#.utf8))
        }
    }

    @Test func rejectsNewerVersions() throws {
        var json = String(decoding: try SettingsFile.encode(sample(), appVersion: "9"), as: UTF8.self)
        json = json.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 2"#)
        #expect(throws: SettingsFile.ReadError.self) { try SettingsFile.decode(Data(json.utf8)) }
    }

    @Test func keepsThisMacsLogFolderUnlessAsked() {
        var current = Preferences()
        current.logFolderPath = "/Users/me/Documents/Cadence"
        let imported = sample()

        #expect(SettingsFile.applying(imported, to: current, includingLogFolder: false).logFolderPath == current.logFolderPath)
        #expect(SettingsFile.applying(imported, to: current, includingLogFolder: true).logFolderPath == imported.logFolderPath)
        #expect(SettingsFile.applying(imported, to: current, includingLogFolder: false).pomodoro.focusMinutes == 50)
    }

    @Test func clampsValuesThatWouldBreakTimers() throws {
        var prefs = sample()
        prefs.pomodoro.focusMinutes = 0
        prefs.reminders[0].schedule = .interval(minutes: 0)
        let contents = try SettingsFile.decode(try SettingsFile.encode(prefs, appVersion: "0.2.0"))
        #expect(contents.preferences.pomodoro.focusMinutes == 1)
        #expect(contents.preferences.reminders[0].schedule == .interval(minutes: 1))
    }

    @Test func loadsVersion1Preferences() throws {
        let json = """
        {"pomodoro":{"focusMinutes":30,"shortBreakMinutes":5,"longBreakMinutes":15,"sessionsBeforeLongBreak":4,
        "autoStartBreaks":true,"autoStartFocus":false},"holdRemindersDuringFocus":false,
        "reminders":[{"id":"5E0F4C2A-0002-4000-8000-000000000002","emoji":"💧","title":"Drink water",
        "message":"Have a glass of water.","intervalMinutes":40,"isEnabled":true,"logWhenDone":true}],
        "logFolderPath":"/tmp/log"}
        """
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(prefs.pomodoro.focusMinutes == 30)
        #expect(prefs.reminders.map(\.schedule) == [.interval(minutes: 40)])
        #expect(prefs.idle == IdleConfig())
        #expect(prefs.quickLogHotKey == .defaultQuickLog)
    }

    @Test func hotKeyDisplay() {
        #expect(HotKey.defaultQuickLog.displayString == "⌃⌥⌘L")
    }
}
