import Foundation

/// A stretch of time with one app in front.
struct AppSpan: Codable, Equatable {
    var appName: String
    var bundleID: String?
    /// The front window's title. Recorded from activity tracking level 2 (v0.4); nil until then.
    var windowTitle: String?
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func isSameApp(as other: AppSpan) -> Bool {
        appName == other.appName && bundleID == other.bundleID && windowTitle == other.windowTitle
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

/// Activity merged into one block for the Activity Review window and the log.
struct ActivitySegment: Codable, Equatable, Identifiable {
    var id = UUID()
    /// In time order. Short switches to other apps are folded in.
    var spans: [AppSpan]
    /// A name the user gave it. Without one, a rule or the main app names it.
    var task: String?
    /// Left out of the work log.
    var isExcluded = false
    /// Set once the user has renamed, merged, split or excluded it.
    var isEdited = false

    init(id: UUID = UUID(), spans: [AppSpan]) {
        self.id = id
        self.spans = []
        add(spans)
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

/// Maps an app or window title to a task name.
struct ActivityRule: Codable, Equatable, Identifiable {
    enum Field: String, Codable, CaseIterable {
        case app, windowTitle

        var title: String {
            switch self {
            case .app: "App"
            case .windowTitle: "Window title"
            }
        }
    }

    var id = UUID()
    var field = Field.app
    /// Matched anywhere in the app name (or bundle ID) or title, ignoring case.
    var pattern = ""
    var task = ""

    func matches(_ span: AppSpan) -> Bool {
        let pattern = pattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !task.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch field {
        case .app:
            return span.appName.localizedCaseInsensitiveContains(pattern)
                || span.bundleID?.localizedCaseInsensitiveContains(pattern) == true
        case .windowTitle:
            return span.windowTitle?.localizedCaseInsensitiveContains(pattern) == true
        }
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
    /// Switches shorter than this are folded into the activity around them.
    var minimumSegmentMinutes = 5
    var rules: [ActivityRule] = []
}

/// A day's recorded activity, stored per machine in Application Support.
struct ActivityDay: Codable, Equatable {
    var segments: [ActivitySegment] = []
    /// The span being recorded, saved every minute so a crash loses little.
    var inProgress: AppSpan?
    /// When the day's activity was last written to the work log.
    var writtenAt: Date?
}
