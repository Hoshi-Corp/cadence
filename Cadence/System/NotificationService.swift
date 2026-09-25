import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject {
    enum Action {
        case remindersDone([Reminder.ID])
        case snooze([Reminder.ID])
        case logOutcome(String)
        case startFocus
    }

    var onAction: ((Action) -> Void)?

    private let center = UNUserNotificationCenter.current()

    private enum Category {
        static let reminder = "reminder"
        static let focusEnded = "focusEnded"
        static let focusEndedWithReminders = "focusEndedWithReminders"
        static let breakEnded = "breakEnded"
    }

    private enum ActionID {
        static let done = "done"
        static let snooze = "snooze"
        static let logOutcome = "logOutcome"
        static let startFocus = "startFocus"
    }

    private nonisolated static let reminderIDsKey = "reminderIDs"
    static let snoozeMinutes = 10

    func configure() {
        center.delegate = self

        let done = UNNotificationAction(identifier: ActionID.done, title: "Done")
        let doneAll = UNNotificationAction(identifier: ActionID.done, title: "Mark reminders done")
        let snooze = UNNotificationAction(identifier: ActionID.snooze, title: "Snooze \(Self.snoozeMinutes) min")
        let logOutcome = UNTextInputNotificationAction(
            identifier: ActionID.logOutcome,
            title: "Log what you did",
            textInputButtonTitle: "Log",
            textInputPlaceholder: "What did you get done?"
        )
        let startFocus = UNNotificationAction(identifier: ActionID.startFocus, title: "Start focus")

        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.reminder, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.focusEnded, actions: [logOutcome], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.focusEndedWithReminders, actions: [logOutcome, doneAll], intentIdentifiers: []
            ),
            UNNotificationCategory(identifier: Category.breakEnded, actions: [startFocus], intentIdentifiers: []),
        ])

        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    func postReminder(_ reminder: Reminder) {
        post(
            id: "reminder-\(reminder.id.uuidString)",
            title: reminder.label,
            body: reminder.message,
            category: Category.reminder,
            reminderIDs: [reminder.id]
        )
    }

    /// One notification for the end of focus, carrying any reminders held during it.
    func postFocusEnded(session: FocusSession?, nextBreak: PomodoroEngine.Phase, breakMinutes: Int, held: [Reminder]) {
        guard session != nil || !held.isEmpty else { return }
        let breakName = nextBreak == .longBreak ? "long break" : "break"
        let title = session != nil
            ? "🍅 Focus complete — time for a \(breakMinutes)-min \(breakName)"
            : "Break time"
        var lines: [String] = []
        if let session, !session.task.isEmpty { lines.append(session.task) }
        if !held.isEmpty { lines.append(held.map(\.label).joined(separator: " · ")) }

        post(
            id: "focus-ended",
            title: title,
            body: lines.joined(separator: "\n"),
            category: held.isEmpty ? Category.focusEnded : Category.focusEndedWithReminders,
            reminderIDs: held.map(\.id)
        )
    }

    func postBreakEnded() {
        post(id: "break-ended", title: "Break over", body: "Ready for the next focus session?",
             category: Category.breakEnded, reminderIDs: [])
    }

    private func post(id: String, title: String, body: String, category: String, reminderIDs: [Reminder.ID]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = [Self.reminderIDsKey: reminderIDs.map(\.uuidString)]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func handle(actionID: String, reminderIDs: [Reminder.ID], text: String?) {
        switch actionID {
        case ActionID.done: onAction?(.remindersDone(reminderIDs))
        case ActionID.snooze: onAction?(.snooze(reminderIDs))
        case ActionID.logOutcome: if let text { onAction?(.logOutcome(text)) }
        case ActionID.startFocus: onAction?(.startFocus)
        default: break
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    // Menu bar apps count as "active", so banners must be allowed explicitly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let ids = (response.notification.request.content.userInfo[Self.reminderIDsKey] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run { handle(actionID: actionID, reminderIDs: ids, text: text) }
    }
}
