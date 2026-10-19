import Foundation

/// A stretch of time with one app in front.
struct AppSpan: Codable, Equatable {
    var appName: String
    var bundleID: String?
    /// The front window's title, or the browser tab's. Recorded from activity tracking level 2.
    var windowTitle: String?
    /// The browser tab's address. Recorded at activity tracking level 3.
    var url: String?
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func isSameApp(as other: AppSpan) -> Bool {
        appName == other.appName && bundleID == other.bundleID && windowTitle == other.windowTitle
            && url == other.url
    }

    /// The app and window it records, without a time.
    var frontApp: FrontApp {
        FrontApp(name: appName, bundleID: bundleID, windowTitle: windowTitle, url: url)
    }

    /// The site of a browser tab, e.g. `github.com`.
    var host: String? {
        url.flatMap { URL(string: $0)?.host() }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    /// The span cut at each midnight it crosses, so every part belongs to one day.
    func splitAtMidnight(calendar: Calendar = .current) -> [AppSpan] {
        var parts: [AppSpan] = []
        var part = self
        while let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: part.start)),
              midnight < part.end {
            var head = part
            head.end = midnight
            parts.append(head)
            part.start = midnight
        }
        parts.append(part)
        return parts
    }
}

// In an extension so Swift still generates the memberwise init.
extension AppSpan {
    init(_ app: FrontApp, at date: Date) {
        self.init(appName: app.name, bundleID: app.bundleID, windowTitle: app.windowTitle, url: app.url,
                  start: date, end: date)
    }
}

/// Activity merged into one block for the Activity Review window and the log.
struct ActivitySegment: Codable, Equatable, Identifiable {
    var id = UUID()
    /// In time order. Short switches to other apps are folded in.
    var spans: [AppSpan]
    /// A name the user gave it. Without one, a rule or the main app names it.
    var task: String?
    /// Left out of the work log.
    var isExcluded = false
    /// Written to the work log as "Private", with its times only.
    var isPrivate = false
    /// Set once the user has renamed, merged, split, excluded or made it private.
    var isEdited = false

    init(id: UUID = UUID(), spans: [AppSpan]) {
        self.id = id
        self.spans = []
        add(spans)
    }

    // Decoded field by field so activity saved by older versions keeps loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        spans = try c.decode([AppSpan].self, forKey: .spans)
        task = try c.decodeIfPresent(String.self, forKey: .task)
        isExcluded = try c.decodeIfPresent(Bool.self, forKey: .isExcluded) ?? false
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
    }

    var start: Date { spans.first?.start ?? .distantPast }
    var end: Date { spans.last?.end ?? start }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Time per app, longest first.
    var usage: [(name: String, seconds: TimeInterval)] {
        var seconds: [String: TimeInterval] = [:]
        var order: [String] = []
        for span in spans {
            if seconds[span.appName] == nil { order.append(span.appName) }
            seconds[span.appName, default: 0] += span.duration
        }
        return order.map { ($0, seconds[$0]!) }.sorted { $0.seconds > $1.seconds }
    }

    /// Time per window title (with the site, for browser tabs), longest first.
    var windowTitles: [(name: String, seconds: TimeInterval)] {
        var seconds: [String: TimeInterval] = [:]
        var order: [String] = []
        for span in spans {
            guard let title = span.windowTitle else { continue }
            let name = span.host.map { "\(title) — \($0)" } ?? title
            if seconds[name] == nil { order.append(name) }
            seconds[name, default: 0] += span.duration
        }
        return order.map { ($0, seconds[$0]!) }.sorted { $0.seconds > $1.seconds }
    }

    /// The segmentation key with the most time: a rule's task, or the app.
    func mainKey(rules: [ActivityRule]) -> String? {
        var seconds: [String: TimeInterval] = [:]
        for span in spans { seconds[ActivitySegmenter.key(for: span, rules: rules), default: 0] += span.duration }
        return seconds.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
    }

    /// The user's name for it, else the task of a matching rule, else the main app.
    func title(rules: [ActivityRule]) -> String {
        if let task, !task.isEmpty { return task }
        guard let key = mainKey(rules: rules),
              let span = spans.first(where: { ActivitySegmenter.key(for: $0, rules: rules) == key })
        else { return "Unknown" }
        return rules.task(for: span) ?? span.appName
    }

    /// Appends spans, joining one that carries straight on from the same app.
    mutating func add(_ newSpans: [AppSpan]) {
        for span in newSpans {
            if var last = spans.last, last.isSameApp(as: span), last.end == span.start {
                last.end = span.end
                spans[spans.count - 1] = last
            } else {
                spans.append(span)
            }
        }
    }
}

/// Maps an app, window title or URL to a task name.
struct ActivityRule: Codable, Equatable, Identifiable {
    enum Field: String, Codable, CaseIterable {
        case app, windowTitle, url

        var title: String {
            switch self {
            case .app: "App"
            case .windowTitle: "Window title"
            case .url: "URL"
            }
        }

        var example: String {
            switch self {
            case .app: "Xcode"
            case .windowTitle: "Pull request"
            case .url: "github.com"
            }
        }

        /// Whether `pattern` appears anywhere in the field, ignoring case. The
        /// app field also matches the bundle ID.
        func matches(_ pattern: String, in span: AppSpan) -> Bool {
            let pattern = pattern.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { return false }
            switch self {
            case .app:
                return span.appName.localizedCaseInsensitiveContains(pattern)
                    || span.bundleID?.localizedCaseInsensitiveContains(pattern) == true
            case .windowTitle:
                return span.windowTitle?.localizedCaseInsensitiveContains(pattern) == true
            case .url:
                return span.url?.localizedCaseInsensitiveContains(pattern) == true
            }
        }
    }

    var id = UUID()
    var field = Field.app
    /// Matched anywhere in the app name (or bundle ID) or title, ignoring case.
    var pattern = ""
    var task = ""

    func matches(_ span: AppSpan) -> Bool {
        !task.trimmingCharacters(in: .whitespaces).isEmpty && field.matches(pattern, in: span)
    }
}

/// An app, window or page that's never recorded.
struct ActivityIgnore: Codable, Equatable, Identifiable {
    var id = UUID()
    var field = ActivityRule.Field.app
    var pattern = ""

    func matches(_ span: AppSpan) -> Bool {
        field.matches(pattern, in: span)
    }
}

extension [ActivityRule] {
    /// The task of the first rule that matches.
    func task(for span: AppSpan) -> String? {
        first { $0.matches(span) }?.task.trimmingCharacters(in: .whitespaces)
    }
}

struct ActivityConfig: Codable, Equatable {
    /// Level 1: record the frontmost app. Off until the user turns it on.
    var isEnabled = false
    /// Level 2: also record the front window's title. Needs Accessibility.
    var recordsWindowTitles = false
    /// Level 3: also record the browser tab's title and URL. Needs Automation, per browser.
    var recordsBrowserTabs = false
    /// Switches shorter than this are folded into the activity around them.
    var minimumSegmentMinutes = 5
    var rules: [ActivityRule] = []
    /// Nothing is recorded while a matching app, window or page is in front.
    var ignored: [ActivityIgnore] = []

    init() {}

    // Decoded field by field so preferences saved by older versions keep
    // loading when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ActivityConfig()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        recordsWindowTitles = try c.decodeIfPresent(Bool.self, forKey: .recordsWindowTitles)
            ?? defaults.recordsWindowTitles
        recordsBrowserTabs = try c.decodeIfPresent(Bool.self, forKey: .recordsBrowserTabs)
            ?? defaults.recordsBrowserTabs
        minimumSegmentMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumSegmentMinutes)
            ?? defaults.minimumSegmentMinutes
        rules = try c.decodeIfPresent([ActivityRule].self, forKey: .rules) ?? defaults.rules
        ignored = try c.decodeIfPresent([ActivityIgnore].self, forKey: .ignored) ?? defaults.ignored
    }

    func ignores(_ span: AppSpan) -> Bool {
        ignored.contains { $0.matches(span) }
    }
}

/// A day's recorded activity, stored per machine in Application Support.
struct ActivityDay: Codable, Equatable {
    var segments: [ActivitySegment] = []
    /// The span being recorded, saved every minute so a crash loses little.
    var inProgress: AppSpan?
    /// When the day's activity was last written to the work log.
    var writtenAt: Date?
}
