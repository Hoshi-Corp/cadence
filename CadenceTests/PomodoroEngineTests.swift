import Foundation
import Testing
@testable import Cadence

@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(minutes: Double) { now += minutes * 60 }
}

@MainActor
struct PomodoroEngineTests {
    let clock = TestClock()

    func makeEngine(_ config: PomodoroConfig = PomodoroConfig()) -> (PomodoroEngine, EventLog) {
        let clock = self.clock
        let engine = PomodoroEngine(config: { config }, clock: { clock.now }, usesTicker: false)
        let log = EventLog()
        engine.onEvent = { log.events.append($0) }
        return (engine, log)
    }

    @Test func completedFocusReportsSessionAndStartsBreak() {
        let (engine, log) = makeEngine()
        engine.task = "  Write tests "
        let start = clock.now
        engine.start()

        clock.advance(minutes: 25)
        engine.tick()

        let session = FocusSession(task: "Write tests", start: start, end: clock.now)
        #expect(log.events == [.focusEnded(session: session, nextBreak: .shortBreak)])
        #expect(engine.phase == .shortBreak)
        #expect(engine.isRunning)
        #expect(engine.completedInCycle == 1)
    }

    @Test func longBreakAfterConfiguredSessions() {
        var config = PomodoroConfig()
        config.sessionsBeforeLongBreak = 2
        config.autoStartFocus = true
        let (engine, log) = makeEngine(config)
        engine.start()

        for _ in 0..<2 {
            clock.advance(minutes: 25); engine.tick()   // focus ends
            if engine.phase == .shortBreak { clock.advance(minutes: 5); engine.tick() }
        }

        #expect(engine.phase == .longBreak)
        #expect(log.events.last == .focusEnded(session: FocusSession(task: "", start: clock.now - 25 * 60, end: clock.now), nextBreak: .longBreak))

        clock.advance(minutes: 15); engine.tick()
        #expect(engine.completedInCycle == 0)
        #expect(engine.phase == .focus)
    }

    @Test func skippedFocusHasNoSession() {
        let (engine, log) = makeEngine()
        engine.start()
        clock.advance(minutes: 10)
        engine.skip()

        #expect(log.events == [.focusEnded(session: nil, nextBreak: .shortBreak)])
        #expect(engine.completedInCycle == 0)
    }

    @Test func pauseFreezesRemainingTime() {
        let (engine, _) = makeEngine()
        engine.start()
        clock.advance(minutes: 10)
        engine.pause()
        clock.advance(minutes: 30)
        engine.tick()

        #expect(engine.remaining == 15 * 60)
        engine.resume()
        clock.advance(minutes: 5)
        engine.tick()
        #expect(engine.remaining == 10 * 60)
    }

    @Test func breakWaitsWhenAutoStartIsOff() {
        var config = PomodoroConfig()
        config.autoStartBreaks = false
        let (engine, _) = makeEngine(config)
        engine.start()
        clock.advance(minutes: 25)
        engine.tick()

        #expect(engine.phase == .shortBreak)
        #expect(engine.runState == .idle)
    }

    @Test func extendAddsTime() {
        let (engine, _) = makeEngine()
        engine.start()
        engine.extend(by: 300)
        #expect(engine.remaining == 30 * 60)
    }
}

@MainActor
final class EventLog {
    var events: [PomodoroEvent] = []
}
