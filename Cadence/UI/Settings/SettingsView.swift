import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PomodoroSettingsView()
                .tabItem { Label("Pomodoro", systemImage: "timer") }
            RemindersSettingsView()
                .tabItem { Label("Reminders", systemImage: "bell") }
            WorkLogSettingsView()
                .tabItem { Label("Work Log", systemImage: "doc.text") }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Active hours") {
                DatePicker("From", selection: minuteOfDay($preferences.value.activeHours.startMinute),
                           displayedComponents: .hourAndMinute)
                DatePicker("To", selection: minuteOfDay($preferences.value.activeHours.endMinute),
                           displayedComponents: .hourAndMinute)
                WeekdayPicker(selection: $preferences.value.activeHours.weekdays)
            }

            Section {
                Toggle("Hold reminders until the next break", isOn: $preferences.value.holdRemindersDuringFocus)
            } footer: {
                Text("Reminders that come due during a focus session are delivered together when it ends.")
            }
        }
    }

    private func minuteOfDay(_ minutes: Binding<Int>) -> Binding<Date> {
        let calendar = Calendar.current
        return Binding {
            calendar.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                          second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        // Order days starting from the user's first weekday.
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }

        LabeledContent("Days") {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    Toggle(symbols[day - 1], isOn: Binding {
                        selection.contains(day)
                    } set: { isOn in
                        if isOn { selection.insert(day) } else { selection.remove(day) }
                    })
                    .toggleStyle(.button)
                }
            }
        }
    }
}

struct PomodoroSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            Section("Durations") {
                Stepper("Focus: \(preferences.value.pomodoro.focusMinutes) min",
                        value: $preferences.value.pomodoro.focusMinutes, in: 5...120, step: 5)
                Stepper("Short break: \(preferences.value.pomodoro.shortBreakMinutes) min",
                        value: $preferences.value.pomodoro.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(preferences.value.pomodoro.longBreakMinutes) min",
                        value: $preferences.value.pomodoro.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Long break after \(preferences.value.pomodoro.sessionsBeforeLongBreak) sessions",
                        value: $preferences.value.pomodoro.sessionsBeforeLongBreak, in: 2...8)
            }
            Section("Automation") {
                Toggle("Start breaks automatically", isOn: $preferences.value.pomodoro.autoStartBreaks)
                Toggle("Start focus automatically after a break", isOn: $preferences.value.pomodoro.autoStartFocus)
            }
        }
    }
}

struct RemindersSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            ForEach($preferences.value.reminders) { $reminder in
                Section {
                    Toggle(reminder.label, isOn: $reminder.isEnabled)
                        .font(.headline)
                    Stepper("Every \(reminder.intervalMinutes) min",
                            value: $reminder.intervalMinutes, in: 5...240, step: 5)
                        .disabled(!reminder.isEnabled)
                    Toggle("Log to work log when done", isOn: $reminder.logWhenDone)
                        .disabled(!reminder.isEnabled)
                }
            }
        }
    }
}

struct WorkLogSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            Section {
                LabeledContent("Folder") {
                    Text(abbreviated(preferences.value.logFolderPath))
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { revealFolder() }
                    Button("Choose…") { chooseFolder() }
                }
            } footer: {
                Text("One Markdown file per day, named like 2026-09-25.md. That matches Obsidian's Daily Notes, so you can point this at a folder in your vault. Cadence only edits its own sections; your notes elsewhere in the file are left alone.")
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.directoryURL = app.workLog.folderURL
        if panel.runModal() == .OK, let url = panel.url {
            app.preferences.value.logFolderPath = url.path
        }
    }

    private func revealFolder() {
        let url = app.workLog.folderURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
