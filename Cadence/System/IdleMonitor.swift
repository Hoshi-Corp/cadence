import CoreGraphics
import Foundation
import Observation

/// Notices when the user has stepped away, from how long there has been no
/// keyboard or mouse input. Reading the idle time needs no permission.
@MainActor @Observable
final class IdleMonitor {
    private(set) var isAway = false
    /// When the last input happened before the user went away.
    private(set) var awaySince: Date?

    /// Called when input resumes after an absence, with when it started and ended.
    @ObservationIgnored var onReturn: ((_ from: Date, _ to: Date) -> Void)?

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let idleSeconds: () -> TimeInterval
    @ObservationIgnored private let clock: () -> Date

    init(
        preferences: PreferencesStore,
        idleSeconds: @escaping () -> TimeInterval = IdleMonitor.systemIdleSeconds,
        clock: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.idleSeconds = idleSeconds
        self.clock = clock
    }

    func tick() {
        let config = preferences.value.idle
        guard config.isEnabled else {
            isAway = false
            awaySince = nil
            return
        }
        let idle = idleSeconds()
        let now = clock()
        let threshold = TimeInterval(config.thresholdMinutes * 60)

        if !isAway, idle >= threshold {
            isAway = true
            awaySince = now - idle
        } else if isAway, idle < threshold {
            let since = awaySince ?? now
            isAway = false
            awaySince = nil
            // Input resumed `idle` seconds ago, not at this (up to 20 s late) tick.
            onReturn?(since, max(since, now - idle))
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    nonisolated static func systemIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType: any input event.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
