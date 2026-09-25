import AppKit
import Observation

/// A finished focus session waiting for the user to describe what got done.
struct PendingOutcome: Equatable {
    var entry: LogEntry
    var task: String
}

/// Wires the timer, reminders, notifications and work log together.
@MainActor @Observable
final class AppState {
    let preferences: PreferencesStore
    let pomodoro: PomodoroEngine
    let reminders: ReminderScheduler
    let workLog: WorkLogStore
    @ObservationIgnored let notifications = NotificationService()

    private(set) var pendingOutcome: PendingOutcome?

    @ObservationIgnored private var reminderTimer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init(preferences: PreferencesStore = PreferencesStore(), clock: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        let pomodoro = PomodoroEngine(config: { preferences.value.pomodoro }, clock: clock)
        self.pomodoro = pomodoro
        self.reminders = ReminderScheduler(preferences: preferences, isFocusing: { pomodoro.isFocusing }, clock: clock)
        self.workLog = WorkLogStore(preferences: preferences)

        pomodoro.onEvent = { [weak self] in self?.handle($0) }
        reminders.onDue = { [weak self] in self?.notifications.postReminder($0) }
        notifications.onAction = { [weak self] in self?.handle($0) }
    }

    func start() {
        notifications.configure()
        reminders.tick()

        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reminders.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reminders.restartAll() }
            },
        ]
    }

    // MARK: User actions

    func quickLog(_ text: String) {
        workLog.addNote(text)
    }

    func submitOutcome(_ text: String) {
        guard let pending = pendingOutcome else { return }
        workLog.addOutcome(text, to: pending.entry)
        pendingOutcome = nil
    }

    func dismissOutcome() {
        pendingOutcome = nil
    }

    func openTodaysLog() {
        let url = workLog.fileURL(for: Date())
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            try? FileManager.default.createDirectory(at: workLog.folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(workLog.folderURL)
        }
    }

    // MARK: Events

    private func handle(_ event: PomodoroEvent) {
        switch event {
        case let .focusEnded(session, nextBreak):
            let held = reminders.takeHeld()
            if let session {
                let entry = workLog.addFocusSession(session)
                pendingOutcome = PendingOutcome(entry: entry, task: session.task)
            }
            let breakMinutes = Int(pomodoro.duration(of: nextBreak) / 60)
            notifications.postFocusEnded(session: session, nextBreak: nextBreak, breakMinutes: breakMinutes, held: held)

        case .breakEnded(let skipped):
            if !skipped { notifications.postBreakEnded() }
        }
    }

    private func handle(_ action: NotificationService.Action) {
        switch action {
        case .remindersDone(let ids):
            for reminder in preferences.value.reminders where ids.contains(reminder.id) {
                workLog.markReminderDone(reminder)
            }
        case .snooze(let ids):
            ids.forEach { reminders.snooze($0, minutes: NotificationService.snoozeMinutes) }
        case .logOutcome(let text):
            submitOutcome(text)
        case .startFocus:
            if pomodoro.phase == .focus { pomodoro.start() }
        }
    }

    private func systemWillSleep() {
        if pomodoro.isFocusing { pomodoro.pause() }
    }
}
