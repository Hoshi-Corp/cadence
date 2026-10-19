import AppKit
import Observation

/// An app in front, as the system reports it, with its window and browser
/// tab when those are recorded.
struct FrontApp: Equatable {
    var name: String
    var bundleID: String?
    var pid: pid_t?
    var windowTitle: String?
    var url: String?
}

// In an extension so Swift still generates the memberwise init.
extension FrontApp {
    init(_ app: NSRunningApplication) {
        self.init(name: app.localizedName ?? app.bundleIdentifier ?? "Unknown", bundleID: app.bundleIdentifier,
                  pid: app.processIdentifier)
    }
}

/// Records which app is in front (activity tracking level 1, no permission
/// needed), and optionally its window title (level 2) and browser tab
/// (level 3). Recording stops while the user is away, the Mac sleeps or
/// another user's session is in front, and while something on the ignore
/// list is in front.
@MainActor @Observable
final class ActivityTracker {
    enum Suspension: Hashable { case asleep, sessionInactive }

    /// The app being recorded right now, from when it came to the front.
    private(set) var current: AppSpan?
    /// Goes up whenever recorded activity changes, so views know to reload.
    private(set) var revision = 0
    private(set) var lastError: String?

    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let store: ActivityStore
    @ObservationIgnored private let frontmostApp: @MainActor () -> FrontApp?
    /// Adds the window title and browser tab the settings ask for.
    @ObservationIgnored private let details: @MainActor (FrontApp, ActivityConfig) -> FrontApp
    /// When the user went away, or nil while they're here.
    @ObservationIgnored private let awaySince: () -> Date?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var suspensions: Set<Suspension> = []
    /// The ID a new segment for `current` gets, so it keeps its identity once saved.
    @ObservationIgnored private var currentID = UUID()
    @ObservationIgnored private var lastCheckpoint = Date.distantPast

    static let checkpointInterval: TimeInterval = 60
    /// How often the window title is checked: titles change without the app switching.
    static let pollInterval: TimeInterval = 5
    nonisolated static let ownBundleID = Bundle.main.bundleIdentifier

    init(
        preferences: PreferencesStore,
        store: ActivityStore = ActivityStore(),
        frontmostApp: @escaping @MainActor () -> FrontApp? = ActivityTracker.systemFrontmostApp,
        details: @escaping @MainActor (FrontApp, ActivityConfig) -> FrontApp = {
            FrontWindowReader.shared.details(for: $0, config: $1)
        },
        awaySince: @escaping () -> Date? = { nil },
        clock: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.store = store
        self.frontmostApp = frontmostApp
        self.details = details
        self.awaySince = awaySince
        self.clock = clock
    }

    private var config: ActivityConfig { preferences.value.activity }

    private var canRecord: Bool {
        config.isEnabled && suspensions.isEmpty && awaySince() == nil
    }

    // MARK: Recording

    /// Saves a span left over from a crash, then starts recording if enabled.
    func start() {
        let now = clock()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        for date in [yesterday, now] {
            guard let span = store.load(for: date).inProgress else { continue }
            record(span, id: UUID())
        }
        sync()
    }

    /// Stops recording and saves what was recorded, e.g. when quitting.
    func stop() {
        close(at: clock())
    }

    func appDidActivate(_ app: FrontApp) {
        guard canRecord, app.bundleID != Self.ownBundleID else { return }
        show(details(app, config), at: clock())
    }

    func suspend(_ reason: Suspension) {
        suspensions.insert(reason)
        sync()
    }

    func resume(_ reason: Suspension) {
        suspensions.remove(reason)
        sync()
    }

    /// Starts or stops recording to match the settings, being away and sleep,
    /// and picks up a new window title. `date` is when that changed, if it's
    /// known more precisely than now.
    func sync(at date: Date? = nil) {
        if canRecord {
            // Switching to Cadence itself isn't recorded: the app before carries on.
            guard let app = frontmostApp(), app.bundleID != Self.ownBundleID else { return }
            show(details(app, config), at: date ?? clock())
        } else {
            close(at: awaySince() ?? date ?? clock())
        }
    }

    /// Called every few seconds. Window titles change without an app switch,
    /// so they're checked here.
    func poll() {
        guard config.recordsWindowTitles else { return }
        sync()
    }

    /// Called every 20 seconds.
    func tick() {
        sync()
        guard let current else { return }
        let now = clock()
        let calendar = Calendar.current
        if !calendar.isDate(current.start, inSameDayAs: now) {
            // Each day's activity goes in that day's file.
            let midnight = calendar.startOfDay(for: now)
            close(at: midnight)
            open(current.frontApp, at: midnight)
        } else if now.timeIntervalSince(lastCheckpoint) >= Self.checkpointInterval {
            var span = current
            span.end = now
            update(day: span.start) { $0.inProgress = span }
            lastCheckpoint = now
        }
    }

    /// Saves the current span so far and carries on recording, so edits apply to everything up to now.
    func flush() {
        guard let current else { return }
        let now = clock()
        close(at: now)
        open(current.frontApp, at: now)
    }

    /// Records `app` from `date` on, unless it's what's being recorded already
    /// or it's on the ignore list.
    private func show(_ app: FrontApp, at date: Date) {
        let span = AppSpan(app, at: date)
        let ignored = config.ignores(span)
        if !ignored, let current, current.isSameApp(as: span) { return }
        close(at: date)
        if !ignored { open(app, at: date) }
    }

    private func open(_ app: FrontApp, at date: Date) {
        current = AppSpan(app, at: date)
        currentID = UUID()
        lastCheckpoint = date
    }

    private func close(at date: Date) {
        guard var span = current else { return }
        current = nil
        span.end = max(span.start, date)
        record(span, id: currentID)
    }

    // shortcut: rewrites the whole day file for every span, so a window title that changes every
    // poll costs a full write every 5 s; only start a span once a title lasts ~30 s if that shows up.
    private func record(_ span: AppSpan, id: UUID) {
        let config = config
        for part in span.splitAtMidnight() {
            update(day: part.start) { day in
                day.inProgress = nil
                day.segments = ActivitySegmenter.append(
                    part, to: day.segments, rules: config.rules,
                    minimum: TimeInterval(config.minimumSegmentMinutes * 60), newID: id
                )
            }
        }
    }

    // MARK: Reviewing a day

    /// The day's segments, including what's being recorded right now.
    func segments(for date: Date) -> [ActivitySegment] {
        let saved = store.load(for: date).segments
        guard var live = current, Calendar.current.isDate(live.start, inSameDayAs: date) else { return saved }
        live.end = max(live.start, clock())
        return ActivitySegmenter.append(
            live, to: saved, rules: config.rules,
            minimum: TimeInterval(config.minimumSegmentMinutes * 60), newID: currentID
        )
    }

    func writtenAt(for date: Date) -> Date? {
        store.load(for: date).writtenAt
    }

    /// Changes a day's saved segments, e.g. to rename, merge or split them.
    func edit(on date: Date, _ change: ([ActivitySegment]) -> [ActivitySegment]?) -> Bool {
        if Calendar.current.isDate(date, inSameDayAs: clock()) { flush() }
        var changed = false
        update(day: date) { day in
            guard let segments = change(day.segments) else { return }
            day.segments = segments
            changed = true
        }
        return changed && lastError == nil
    }

    func markWritten(on date: Date) {
        let now = clock()
        update(day: date) { $0.writtenAt = now }
    }

    private func update(day date: Date, _ change: (inout ActivityDay) -> Void) {
        do {
            try store.update(for: date, change)
            lastError = nil
        } catch {
            lastError = "Couldn't save activity: \(error.localizedDescription)"
        }
        revision += 1
    }

    static func systemFrontmostApp() -> FrontApp? {
        NSWorkspace.shared.frontmostApplication.map(FrontApp.init)
    }
}
