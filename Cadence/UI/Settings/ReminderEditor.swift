import SwiftUI

struct ReminderDraft: Identifiable {
    var reminder: Reminder
    var isNew: Bool
    var id: Reminder.ID { reminder.id }
}

extension Reminder.Schedule {
    var summary: String {
        switch self {
        case .interval(let minutes):
            return "Every \(minutes) min"
        case let .daily(minuteOfDay, weekdays):
            let time = String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
            return "\(Self.describe(weekdays)) at \(time)"
        case .once(let date):
            return "Once, \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private static func describe(_ weekdays: Set<Int>) -> String {
        switch weekdays {
        case Set(1...7): return "Every day"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        case []: return "Never"
        default:
            let calendar = Calendar.current
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter(weekdays.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }
}

struct ReminderEditor: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case interval = "Repeat every few minutes"
        case daily = "At a set time"
        case once = "Once"
        var id: Self { self }
    }

    let isNew: Bool
    let onSave: (Reminder) -> Void
    let onDelete: (Reminder) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var reminder: Reminder
    @State private var kind: Kind
    // Each kind keeps its own values, so switching back and forth loses nothing.
    @State private var intervalMinutes = 30
    @State private var dailyTime: Date
    @State private var dailyWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var onceDate = Date().addingTimeInterval(60 * 60)
    @State private var confirmDelete = false

    init(draft: ReminderDraft, onSave: @escaping (Reminder) -> Void, onDelete: @escaping (Reminder) -> Void) {
        isNew = draft.isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _reminder = State(initialValue: draft.reminder)
        let calendar = Calendar.current
        var dailyTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        switch draft.reminder.schedule {
        case .interval(let minutes):
            _kind = State(initialValue: .interval)
            _intervalMinutes = State(initialValue: minutes)
        case let .daily(minuteOfDay, weekdays):
            _kind = State(initialValue: .daily)
            dailyTime = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: Date())
                ?? dailyTime
            _dailyWeekdays = State(initialValue: weekdays)
        case .once(let date):
            _kind = State(initialValue: .once)
            _onceDate = State(initialValue: date)
        }
        _dailyTime = State(initialValue: dailyTime)
    }

    private var schedule: Reminder.Schedule {
        switch kind {
        case .interval:
            return .interval(minutes: intervalMinutes)
        case .daily:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            return .daily(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), weekdays: dailyWeekdays)
        case .once:
            return .once(onceDate)
        }
    }

    private var problem: String? {
        if reminder.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the reminder a name." }
        if kind == .daily && dailyWeekdays.isEmpty { return "Choose at least one day." }
        if kind == .once && onceDate <= Date() && onceDate != originalOnceDate { return "Choose a time in the future." }
        return nil
    }

    /// A one-off that already fired keeps its past date until it's changed.
    private var originalOnceDate: Date? {
        if case .once(let date) = reminder.schedule { date } else { nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $reminder.title, prompt: Text("Required"))
                    TextField("Emoji", text: $reminder.emoji, prompt: Text("Optional"))
                    TextField("Message", text: $reminder.message, prompt: Text("Shown in the notification"))
                }
                Section {
                    Picker("When", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    switch kind {
                    case .interval:
                        Stepper("Every \(intervalMinutes) min", value: $intervalMinutes, in: 5...480, step: 5)
                    case .daily:
                        DatePicker("Time", selection: $dailyTime, displayedComponents: .hourAndMinute)
                        WeekdayPicker(selection: $dailyWeekdays)
                    case .once:
                        DatePicker("Date", selection: $onceDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Toggle("Log to work log when done", isOn: $reminder.logWhenDone)
                    if !isNew {
                        Toggle("Enabled", isOn: $reminder.isEnabled)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew && !reminder.isBuiltIn {
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
                if let problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .confirmationDialog("Delete “\(reminder.label)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                onDelete(reminder)
                dismiss()
            }
        }
    }

    private func save() {
        var result = reminder
        result.title = result.title.trimmingCharacters(in: .whitespaces)
        result.emoji = result.emoji.trimmingCharacters(in: .whitespaces)
        result.schedule = schedule
        // Rescheduling a one-off that already fired turns it back on.
        if case .once(let date) = result.schedule, date > Date(), result.schedule != reminder.schedule {
            result.isEnabled = true
        }
        onSave(result)
        dismiss()
    }
}

/// Click, then press the new shortcut. Esc cancels.
struct HotKeyRecorder: View {
    @Environment(AppState.self) private var app
    @Binding var hotKey: HotKey
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press a shortcut…" : hotKey.displayString) {
            isRecording ? stop() : start()
        }
        .monospaced(!isRecording)
        .help(isRecording ? "Press Esc to cancel" : "Click to record a new shortcut")
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        app.setRecordingHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let recorded = HotKey(event: event) {
                hotKey = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        app.setRecordingHotKey(false)
    }
}
