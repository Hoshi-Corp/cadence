import AppKit
import SwiftUI

/// A window in the middle of the screen when a focus session or break ends,
/// since a notification banner is easy to miss. It stays until acted on.
///
/// It comes to the front without taking keyboard focus, so a keystroke meant
/// for the app you're typing in can't press one of its buttons. Click it to type.
@MainActor
final class TimerAlertController {
    private let panel: TimerAlertWindow

    init(app: AppState) {
        panel = TimerAlertWindow()
        let host = NSHostingController(rootView: TimerAlertView().environment(app))
        // Let the window follow the view's size as sections come and go.
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
    }

    func update(showing: Bool) {
        guard showing else {
            panel.orderOut(nil)
            return
        }
        let wasVisible = panel.isVisible
        panel.layoutIfNeeded()
        if !wasVisible {
            panel.positionOnActiveScreen()
            NSSound(named: "Glass")?.play()
        }
        panel.orderFrontRegardless()
    }
}

private final class TimerAlertWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        // Shows on whichever Space is current, including over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return center() }
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + visible.height / 8))
    }
}

struct TimerAlertView: View {
    @Environment(AppState.self) private var app
    @State private var outcome = ""

    var body: some View {
        VStack(spacing: 16) {
            if let alert = app.timerAlert {
                content(for: alert)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onExitCommand { app.dismissTimerAlert() }
    }

    @ViewBuilder
    private func content(for alert: TimerAlert) -> some View {
        switch alert {
        case let .focusEnded(task, nextBreak, breakMinutes, held):
            header(
                emoji: "🍅",
                title: "Focus complete",
                subtitle: "Time for a \(breakMinutes)-min \(nextBreak == .longBreak ? "long break" : "break")."
            )
            if !task.isEmpty {
                Text("“\(task)”").font(.title3).multilineTextAlignment(.center)
            }
            breakCountdown
            if !held.isEmpty {
                heldReminders(held)
            }
            if app.pendingOutcome != nil {
                TextField("What did you get done?", text: $outcome)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(primaryFocusEndedAction)
            }
            focusEndedButtons

        case .breakEnded:
            header(
                emoji: "☕️",
                title: "Break over",
                subtitle: app.pomodoro.isFocusing ? "The next focus session has started." : "Ready for the next focus session?"
            )
            breakEndedButtons
        }
    }

    private func header(emoji: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 52))
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var breakCountdown: some View {
        let pomodoro = app.pomodoro
        if pomodoro.phase.isBreak && pomodoro.runState != .idle {
            Text("Break ends in \(formatCountdown(pomodoro.remaining))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func heldReminders(_ held: [Reminder]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(held) { Text($0.label) }
            }
            Spacer()
            Button("Mark done") { app.markHeldRemindersDone() }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Start the break if it's waiting; otherwise just close.
    @ViewBuilder
    private var focusEndedButtons: some View {
        let pomodoro = app.pomodoro
        HStack {
            if pomodoro.phase.isBreak {
                Button("Skip break") { finish { pomodoro.skip() } }
                    .controlSize(.large)
            }
            Spacer()
            Button(pomodoro.phase.isBreak && pomodoro.runState == .idle ? "Start break" : "OK",
                   action: primaryFocusEndedAction)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var breakEndedButtons: some View {
        let pomodoro = app.pomodoro
        HStack {
            Spacer()
            if pomodoro.phase == .focus && pomodoro.runState == .idle {
                Button("Not now") { finish {} }
                    .controlSize(.large)
                Button("Start focus") { finish { pomodoro.start() } }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("OK") { finish {} }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func primaryFocusEndedAction() {
        let pomodoro = app.pomodoro
        finish { if pomodoro.phase.isBreak && pomodoro.runState == .idle { pomodoro.start() } }
    }

    /// Saves any outcome typed in, runs the action and closes the alert.
    private func finish(_ action: () -> Void) {
        if !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            app.submitOutcome(outcome)
        }
        outcome = ""
        action()
        app.dismissTimerAlert()
    }
}
