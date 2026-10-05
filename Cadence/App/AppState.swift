import AppKit
import Observation

/// A finished focus session waiting for the user to describe what got done.
struct PendingOutcome: Equatable {
    var entry: LogEntry
    var task: String
}

/// What the timer alert window is showing.
enum TimerAlert: Equatable {
    case focusEnded(task: String, nextBreak: PomodoroEngine.Phase, breakMinutes: Int, held: [Reminder])
    case breakEnded
}

/// Wires the timer, reminders, notifications and work log together.
@MainActor @Observable
final class AppState {
    let preferences: PreferencesStore
    let pomodoro: PomodoroEngine
    let reminders: ReminderScheduler
    let workLog: WorkLogStore
    let idle: IdleMonitor
    let activity: ActivityTracker
    @ObservationIgnored let notifications = NotificationService()

    private(set) var pendingOutcome: PendingOutcome?
    /// Set while the timer alert window is up.
    private(set) var timerAlert: TimerAlert?
    /// Why the quick log shortcut couldn't be registered, if it couldn't.
    private(set) var hotKeyError: String?

    @ObservationIgnored private var reminderTimer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isRecordingHotKey = false
    @ObservationIgnored private var quickLogPanel: QuickLogPanelController?
    @ObservationIgnored private var todayWindow: TodayWindowController?
    @ObservationIgnored private var activityWindow: ActivityWindowController?
    @ObservationIgnored private var timerAlertWindow: TimerAlertController?

    init(
        preferences: PreferencesStore = PreferencesStore(),
        stats: StatsStore = StatsStore(),
        activityStore: ActivityStore = ActivityStore(),
        frontmostApp: @escaping @MainActor () -> FrontApp? = ActivityTracker.systemFrontmostApp,
        idleSeconds: @escaping () -> TimeInterval = IdleMonitor.systemIdleSeconds,
        clock: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        let pomodoro = PomodoroEngine(config: { preferences.value.pomodoro }, clock: clock)
        self.pomodoro = pomodoro
        let idle = IdleMonitor(preferences: preferences, idleSeconds: idleSeconds, clock: clock)
        self.idle = idle
        self.reminders = ReminderScheduler(
            preferences: preferences, isFocusing: { pomodoro.isFocusing }, isAway: { idle.isAway }, clock: clock
        )
        self.workLog = WorkLogStore(preferences: preferences, stats: stats)
        self.activity = ActivityTracker(
            preferences: preferences, store: activityStore, frontmostApp: frontmostApp,
            awaySince: { idle.awaySince }, clock: clock
        )

        pomodoro.onEvent = { [weak self] in self?.handle($0) }
        reminders.onDue = { [weak self] in self?.notifications.postReminder($0) }
        notifications.onAction = { [weak self] in self?.handle($0) }
        idle.onReturn = { [weak self] in self?.userReturned(from: $0, to: $1) }
    }

    func start() {
        timerAlertWindow = TimerAlertController(app: self)
        notifications.configure()
        reminders.tick()
        activity.start()

        HotKeyCenter.shared.onPress = { [weak self] in self?.showQuickLogPanel() }
        applyHotKey()
        preferences.onChange = { [weak self] old, new in
            if old.quickLogHotKey != new.quickLogHotKey || old.quickLogHotKeyEnabled != new.quickLogHotKeyEnabled {
                self?.applyHotKey()
            }
            if old.activity.isEnabled != new.activity.isEnabled {
                self?.activity.sync()
            }
        }

        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.idle.tick()
                self?.reminders.tick()
                self?.activity.tick()
            }
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
                MainActor.assumeIsolated {
                    self?.activity.resume(.asleep)
                    self?.reminders.restartIntervals()
                }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let front = app.map { FrontApp(name: $0.localizedName ?? $0.bundleIdentifier ?? "Unknown", bundleID: $0.bundleIdentifier) }
                MainActor.assumeIsolated {
                    if let front { self?.activity.appDidActivate(front) }
                }
            },
            // Fast user switching: another user's session is in front.
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.activity.suspend(.sessionInactive) }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.activity.resume(.sessionInactive) }
            },
        ]
    }

    /// Saves what's being recorded before the app quits.
    func stop() {
        activity.stop()
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

    func dismissTimerAlert() {
        setTimerAlert(nil)
    }

    /// Marks the reminders held during focus as done, from the timer alert.
    func markHeldRemindersDone() {
        guard case let .focusEnded(task, nextBreak, breakMinutes, held) = timerAlert else { return }
        held.forEach { workLog.markReminderDone($0) }
        setTimerAlert(.focusEnded(task: task, nextBreak: nextBreak, breakMinutes: breakMinutes, held: []))
    }

    private func setTimerAlert(_ alert: TimerAlert?) {
        timerAlert = alert
        timerAlertWindow?.update(showing: alert != nil)
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

    func showQuickLogPanel() {
        if quickLogPanel == nil {
            quickLogPanel = QuickLogPanelController { [weak self] in self?.quickLog($0) }
        }
        quickLogPanel?.toggle()
    }

    func showToday() {
        if todayWindow == nil { todayWindow = TodayWindowController(app: self) }
        todayWindow?.show()
    }

    func showActivity() {
        if activityWindow == nil { activityWindow = ActivityWindowController(app: self) }
        activityWindow?.show()
    }

    /// Replaces the day's Activity section in the work log with its reviewed segments.
    @discardableResult
    func writeActivityToLog(for date: Date) -> Bool {
        if Calendar.current.isDateInToday(date) { activity.flush() }
        let markdown = ActivityLog.markdown(
            for: activity.segments(for: date), rules: preferences.value.activity.rules
        )
        guard workLog.writeActivity(markdown, for: date) else { return false }
        activity.markWritten(on: date)
        return true
    }

    // MARK: Settings

    /// Turns the global shortcut off while a new one is being recorded, so
    /// pressing the current shortcut records it instead of opening the panel.
    func setRecordingHotKey(_ recording: Bool) {
        isRecordingHotKey = recording
        applyHotKey()
    }

    private func applyHotKey() {
        let prefs = preferences.value
        let hotKey = prefs.quickLogHotKeyEnabled && !isRecordingHotKey ? prefs.quickLogHotKey : nil
        do {
            try HotKeyCenter.shared.register(hotKey)
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// e.g. "0.2.0 (42)", with the build number from the release workflow.
    static var versionDescription: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(appVersion) (\(build))"
    }

    func exportSettings() throws -> Data {
        try SettingsFile.encode(preferences.value, appVersion: Self.appVersion)
    }

    func importSettings(_ contents: SettingsFile.Contents, includingLogFolder: Bool) {
        preferences.value = SettingsFile.applying(
            contents.preferences, to: preferences.value, includingLogFolder: includingLogFolder
        )
        reminders.tick()
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
            // A skipped session means the user is right here, so a notification is enough.
            if let session, preferences.value.showTimerAlert {
                setTimerAlert(.focusEnded(task: session.task, nextBreak: nextBreak, breakMinutes: breakMinutes, held: held))
            } else {
                notifications.postFocusEnded(session: session, nextBreak: nextBreak, breakMinutes: breakMinutes, held: held)
            }

        case .breakEnded(let skipped):
            guard !skipped else { return }
            if preferences.value.showTimerAlert {
                setTimerAlert(.breakEnded)
            } else {
                notifications.postBreakEnded()
            }
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
        activity.suspend(.asleep)
    }

    /// Being away counts as a break from the desk, so interval reminders start over.
    private func userReturned(from start: Date, to end: Date) {
        reminders.restartIntervals()
        activity.sync(at: end)
        if preferences.value.idle.logAwayTime {
            workLog.addAway(from: start, to: end)
        }
    }
}
