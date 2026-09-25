import SwiftUI

struct MenuBarLabel: View {
    let pomodoro: PomodoroEngine

    var body: some View {
        if pomodoro.runState == .idle {
            Image(systemName: "timer")
        } else {
            Text("\(Image(systemName: pomodoro.phase.symbolName)) \(formatCountdown(pomodoro.remaining))")
                .monospacedDigit()
        }
    }
}

extension PomodoroEngine.Phase {
    var symbolName: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak, .longBreak: "cup.and.saucer"
        }
    }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

func formatCountdown(_ interval: TimeInterval) -> String {
    let seconds = Int(interval.rounded(.up))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
