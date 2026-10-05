import SwiftUI
import UniformTypeIdentifiers

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
            ActivitySettingsView()
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
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
    @State private var transferMessage: String?

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

            Section {
                Toggle("Notice when I step away", isOn: $preferences.value.idle.isEnabled)
                Stepper("Away after \(preferences.value.idle.thresholdMinutes) min without keyboard or mouse input",
                        value: $preferences.value.idle.thresholdMinutes, in: 1...60)
                    .disabled(!preferences.value.idle.isEnabled)
                Toggle("Log time away to the work log", isOn: $preferences.value.idle.logAwayTime)
                    .disabled(!preferences.value.idle.isEnabled)
            } header: {
                Text("Away")
            } footer: {
                Text("While you're away, interval reminders don't fire. When you come back, they start over.")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Export…", action: exportSettings)
                    Button("Import…", action: importSettings)
                }
                if let transferMessage {
                    Text(transferMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Settings file")
            } footer: {
                Text("Copy your Pomodoro, reminder, activity and shortcut settings to another Mac. Launch at login isn't included.")
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(AppState.versionDescription).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("About Cadence…") {
                        NSApp.activate()
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                }
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SettingsFile.defaultFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.exportSettings().write(to: url, options: .atomic)
            transferMessage = "Exported to \(url.lastPathComponent)."
        } catch {
            transferMessage = "Couldn't export settings: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let contents: SettingsFile.Contents
        do {
            contents = try SettingsFile.decode(try Data(contentsOf: url))
        } catch {
            transferMessage = "Couldn't import settings: \(error.localizedDescription)"
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace your settings with the ones in “\(url.lastPathComponent)”?"
        alert.informativeText = "This replaces your Pomodoro, reminder, active hours, away, activity and shortcut settings. "
            + "Exported \(contents.exportedAt.formatted(date: .abbreviated, time: .shortened)) by Cadence \(contents.appVersion)."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        let otherFolder = contents.preferences.logFolderPath != app.preferences.value.logFolderPath
        if otherFolder {
            alert.showsSuppressionButton = true
            let path = (contents.preferences.logFolderPath as NSString).abbreviatingWithTildeInPath
            alert.suppressionButton?.title = "Also use its work log folder (\(path))"
            alert.suppressionButton?.state = .off
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let includeFolder = otherFolder && alert.suppressionButton?.state == .on
        app.importSettings(contents, includingLogFolder: includeFolder)
        transferMessage = "Imported settings from \(url.lastPathComponent)."
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

struct WeekdayPicker: View {
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
            Section {
                Toggle("Show an alert window when a timer ends", isOn: $preferences.value.showTimerAlert)
            } footer: {
                Text("A window in the middle of the screen, with a sound, that stays until you respond. When this is off, Cadence uses a notification banner.")
            }
        }
    }
}

struct RemindersSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var editing: ReminderDraft?

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            Section {
                ForEach($preferences.value.reminders) { $reminder in
                    let fired = reminder.hasFired(before: Date())
                    HStack {
                        Toggle(isOn: $reminder.isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.label)
                                Text(fired ? "\(reminder.schedule.summary) · done" : reminder.schedule.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Turning it back on would fire it again at once; pick a new time instead.
                        .disabled(fired)
                        Button("Edit…") { editing = ReminderDraft(reminder: reminder, isNew: false) }
                    }
                }
            } footer: {
                Text("Repeating reminders fire during active hours. Reminders at a set time fire on their own days, and one-off reminders turn off once they've fired.")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Add Reminder…") { editing = ReminderDraft(reminder: .custom(), isNew: true) }
                }
            }
        }
        .sheet(item: $editing) { draft in
            ReminderEditor(draft: draft, onSave: save, onDelete: delete)
        }
    }

    private func save(_ reminder: Reminder) {
        if let index = app.preferences.value.reminders.firstIndex(where: { $0.id == reminder.id }) {
            app.preferences.value.reminders[index] = reminder
        } else {
            app.preferences.value.reminders.append(reminder)
        }
        app.reminders.tick()
    }

    private func delete(_ reminder: Reminder) {
        app.preferences.value.reminders.removeAll { $0.id == reminder.id }
        app.reminders.tick()
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

            Section {
                Toggle("Open quick log from anywhere", isOn: $preferences.value.quickLogHotKeyEnabled)
                LabeledContent("Shortcut") {
                    HotKeyRecorder(hotKey: $preferences.value.quickLogHotKey)
                }
                .disabled(!preferences.value.quickLogHotKeyEnabled)
                if let error = app.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Quick log shortcut")
            } footer: {
                Text("Opens a small text area over any app. Type, press ⏎, and it's in today's log. ⇧⏎ starts a new line.")
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

struct ActivitySettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var preferences = app.preferences

        Form {
            Section {
                Toggle("Record which app is in front", isOn: $preferences.value.activity.isEnabled)
                Stepper("Fold app switches shorter than \(preferences.value.activity.minimumSegmentMinutes) min into the activity around them",
                        value: $preferences.value.activity.minimumSegmentMinutes, in: 1...30)
                    .disabled(!preferences.value.activity.isEnabled)
                HStack {
                    Spacer()
                    Button("Review Activity…") { app.showActivity() }
                }
            } header: {
                Text("Activity tracking")
            } footer: {
                Text("Cadence notes the app in front and for how long. This needs no permission, pauses while you're away, and stays on this Mac until you write it to the log from the Activity window.")
            }

            Section {
                ForEach($preferences.value.activity.rules) { $rule in
                    HStack {
                        ActivityRuleFields(rule: $rule)
                        Button {
                            preferences.value.activity.rules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete rule")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Rule") { preferences.value.activity.rules.append(ActivityRule()) }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Name activity after a task, e.g. App contains “Xcode” → Cadence. The first rule that matches wins, and activity with the same task joins into one segment. Window titles are recorded from activity tracking level 2, so title rules don't match anything yet.")
            }
        }
    }
}
