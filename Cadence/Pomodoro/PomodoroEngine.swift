import Foundation
import Observation

struct FocusSession: Equatable {
    var task: String
    var start: Date
    var end: Date
}

enum PomodoroEvent: Equatable {
    /// `session` is nil when the focus session was skipped.
    case focusEnded(session: FocusSession?, nextBreak: PomodoroEngine.Phase)
    case breakEnded(skipped: Bool)
}

/// Pomodoro state machine. Time is derived from a stored end date rather than
/// counted down, so it stays correct across app stalls and sleep.
@MainActor @Observable
final class PomodoroEngine {
    enum Phase: Equatable {
        case focus, shortBreak, longBreak

        var isBreak: Bool { self != .focus }
    }

    enum RunState: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    private(set) var phase: Phase = .focus
    private(set) var runState: RunState = .idle
    /// Focus sessions completed since the last long break.
    private(set) var completedInCycle = 0
    private(set) var now: Date
    var task = ""

    @ObservationIgnored var onEvent: ((PomodoroEvent) -> Void)?

    @ObservationIgnored private let config: () -> PomodoroConfig
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let usesTicker: Bool
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var focusStartedAt: Date?

    init(config: @escaping () -> PomodoroConfig, clock: @escaping () -> Date = Date.init, usesTicker: Bool = true) {
        self.config = config
        self.clock = clock
        self.usesTicker = usesTicker
        self.now = clock()
    }

    var isRunning: Bool {
        if case .running = runState { true } else { false }
    }

    var isFocusing: Bool { phase == .focus && isRunning }

    var remaining: TimeInterval {
        switch runState {
        case .idle: duration(of: phase)
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    func duration(of phase: Phase) -> TimeInterval {
        let config = config()
        let minutes = switch phase {
        case .focus: config.focusMinutes
        case .shortBreak: config.shortBreakMinutes
        case .longBreak: config.longBreakMinutes
        }
        return TimeInterval(minutes * 60)
    }

    // MARK: Controls

    func toggle() {
        switch runState {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        guard runState == .idle else { return }
        begin(phase)
    }

    func pause() {
        guard case .running(let endDate) = runState else { return }
        now = clock()
        runState = .paused(remaining: max(0, endDate.timeIntervalSince(now)))
        stopTicker()
    }

    func resume() {
        guard case .paused(let remaining) = runState else { return }
        now = clock()
        runState = .running(endDate: now + remaining)
        startTicker()
    }

    func extend(by seconds: TimeInterval) {
        switch runState {
        case .idle: break
        case .running(let endDate): runState = .running(endDate: endDate + seconds)
        case .paused(let remaining): runState = .paused(remaining: remaining + seconds)
        }
    }

    func skip() {
        advance(completed: false)
    }

    func reset() {
        stopTicker()
        runState = .idle
        phase = .focus
        completedInCycle = 0
        focusStartedAt = nil
    }

    func tick() {
        now = clock()
        if case .running(let endDate) = runState, now >= endDate {
            advance(completed: true)
        }
    }

    // MARK: Transitions

    private func begin(_ next: Phase) {
        phase = next
        now = clock()
        runState = .running(endDate: now + duration(of: next))
        if next == .focus { focusStartedAt = now }
        startTicker()
    }

    private func idle(at next: Phase) {
        stopTicker()
        phase = next
        runState = .idle
    }

    private func advance(completed: Bool) {
        let config = config()
        now = clock()

        switch phase {
        case .focus:
            var session: FocusSession?
            if completed {
                completedInCycle += 1
                if let start = focusStartedAt {
                    let task = self.task.trimmingCharacters(in: .whitespacesAndNewlines)
                    session = FocusSession(task: task, start: start, end: now)
                }
            }
            focusStartedAt = nil
            let next: Phase = completed && completedInCycle >= config.sessionsBeforeLongBreak
                ? .longBreak : .shortBreak
            onEvent?(.focusEnded(session: session, nextBreak: next))
            config.autoStartBreaks ? begin(next) : idle(at: next)

        case .shortBreak, .longBreak:
            if phase == .longBreak { completedInCycle = 0 }
            onEvent?(.breakEnded(skipped: !completed))
            config.autoStartFocus ? begin(.focus) : idle(at: .focus)
        }
    }

    // MARK: Ticker

    private func startTicker() {
        guard usesTicker else { return }
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps the countdown moving while menus are open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
