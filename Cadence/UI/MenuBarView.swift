import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PomodoroSection(pomodoro: app.pomodoro, sessionsBeforeLongBreak: app.preferences.value.pomodoro.sessionsBeforeLongBreak)

            if let pending = app.pendingOutcome {
                OutcomeSection(pending: pending)
            }

            Divider()
            RemindersSection()
            Divider()
            QuickLogSection()

            if let error = app.workLog.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button {
                    app.showToday()
                } label: {
                    Label("Today", systemImage: "list.bullet.rectangle")
                }
                .help("Review and edit today's entries")
                Button {
                    app.showActivity()
                } label: {
                    Label("Activity", systemImage: "chart.bar.xaxis")
                }
                .help("Review recorded app activity")
                Button {
                    app.openTodaysLog()
                } label: {
                    Image(systemName: "doc.text")
                }
                .help("Open today's Markdown file")
                Spacer()
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Cadence \(AppState.versionDescription)")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct PomodoroSection: View {
    @Bindable var pomodoro: PomodoroEngine
    let sessionsBeforeLongBreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(statusTitle, systemImage: pomodoro.phase.symbolName)
                    .font(.headline)
                Spacer()
                Text(formatCountdown(pomodoro.remaining))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            TextField("What are you working on?", text: $pomodoro.task)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(primaryTitle) { pomodoro.toggle() }
                    .keyboardShortcut(.defaultAction)
                Button("Skip") { pomodoro.skip() }
                Button("+5") { pomodoro.extend(by: 5 * 60) }
                    .disabled(pomodoro.runState == .idle)
                Spacer()
                Button {
                    pomodoro.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset cycle")
            }

            HStack(spacing: 4) {
                ForEach(0..<max(sessionsBeforeLongBreak, 1), id: \.self) { index in
                    Circle()
                        .fill(index < pomodoro.completedInCycle ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
                Text("\(pomodoro.completedInCycle) of \(sessionsBeforeLongBreak) before long break")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        if case .paused = pomodoro.runState { return "\(pomodoro.phase.title) (paused)" }
        return pomodoro.phase.title
    }

    private var primaryTitle: String {
        switch pomodoro.runState {
        case .idle: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        }
    }
}

private struct OutcomeSection: View {
    @Environment(AppState.self) private var app
    let pending: PendingOutcome
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pending.task.isEmpty ? "What did you get done?" : "What did you get done on “\(pending.task)”?")
                .font(.subheadline)
            HStack {
                TextField("Outcome", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                Button("Skip") { app.dismissOutcome() }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        app.submitOutcome(text)
        text = ""
    }
}

private struct RemindersSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next reminders")
                .font(.caption)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                let upcoming = Array(app.reminders.upcoming.prefix(5))
                if upcoming.isEmpty {
                    Text("No reminders enabled").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(upcoming, id: \.reminder.id) { item in
                            HStack {
                                Text(item.reminder.label)
                                Spacer()
                                Text(status(of: item.reminder, due: item.date, now: context.date))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !app.preferences.value.activeHours.contains(context.date) {
                        Text("Outside active hours — reminders are paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func status(of reminder: Reminder, due: Date, now: Date) -> String {
        if app.reminders.held.contains(reminder.id) { return "held until break" }
        let minutes = max(0, Int((due.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes == 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let calendar = Calendar.current
        if calendar.isDate(due, inSameDayAs: now) { return "at \(LogEntry.time(due))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return "tomorrow \(LogEntry.time(due))"
        }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

private struct QuickLogSection: View {
    @Environment(AppState.self) private var app
    @State private var text = ""
    @State private var justSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LogTextEditor(text: $text, placeholder: "Quick log…", onSubmit: save)
            HStack {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if justSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        }
    }

    private var hint: String {
        let prefs = app.preferences.value
        return prefs.quickLogHotKeyEnabled
            ? "\(LogTextEditor.hint) · \(prefs.quickLogHotKey.displayString) anywhere"
            : LogTextEditor.hint
    }

    private func save() {
        guard !LogEntry.multiline(text).isEmpty else { return }
        app.quickLog(text)
        text = ""
        withAnimation { justSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { justSaved = false }
        }
    }
}
