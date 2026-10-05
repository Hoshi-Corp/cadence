import AppKit
import SwiftUI

/// Hosts the Activity Review in a regular window, like the Today window.
@MainActor
final class ActivityWindowController {
    private let window: NSWindow

    init(app: AppState) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.contentViewController = NSHostingController(rootView: ActivityReviewView().environment(app))
        window.setContentSize(NSSize(width: 600, height: 560))
        if !window.setFrameUsingName("Activity") { window.center() }
        window.setFrameAutosaveName("Activity")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Lists a day's recorded activity so it can be renamed, merged, split or
/// left out before it's written to the work log.
struct ActivityReviewView: View {
    @Environment(AppState.self) private var app
    @State private var date = Date()
    @State private var segments: [ActivitySegment] = []
    @State private var writtenAt: Date?
    @State private var selection = Set<ActivitySegment.ID>()
    @State private var renaming: ActivitySegment?
    @State private var splitting: ActivitySegment?
    @State private var newRule: ActivityRule?
    @State private var message: String?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var rules: [ActivityRule] { app.preferences.value.activity.rules }
    private var isEnabled: Bool { app.preferences.value.activity.isEnabled }

    private var selected: [ActivitySegment] { segments.filter { selection.contains($0.id) } }
    private var single: ActivitySegment? { selected.count == 1 ? selected[0] : nil }
    private var canMerge: Bool { ActivitySegmenter.merging(selection, in: segments) != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let message = message ?? app.activity.lastError ?? app.workLog.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            Divider()
            actions
        }
        .onAppear(perform: reload)
        .onChange(of: date) { reload() }
        .onChange(of: app.activity.revision) { reload() }
        .onChange(of: app.preferences.value.activity) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .sheet(item: $renaming) { segment in
            RenameSheet(segment: segment, title: segment.title(rules: rules)) { task in
                edit { ActivitySegmenter.renaming(segment.id, to: task, in: $0) }
            }
        }
        .sheet(item: $splitting) { segment in
            SplitSheet(segment: segment, title: segment.title(rules: rules)) { time in
                edit { ActivitySegmenter.splitting(segment.id, at: time, in: $0) }
            }
        }
        .sheet(item: $newRule) { rule in
            RuleSheet(rule: rule) { app.preferences.value.activity.rules.append($0) }
        }
    }

    @ViewBuilder private var content: some View {
        if segments.isEmpty {
            if isEnabled || !isToday {
                ContentUnavailableView(
                    "No activity",
                    systemImage: "chart.bar.xaxis",
                    description: Text(isToday
                        ? "Cadence is recording which app is in front. It shows up here as you work."
                        : "Nothing was recorded on this day.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Activity tracking is off", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Cadence can record which app is in front and for how long. It needs no permission, and everything stays on this Mac until you write it to the log.")
                } actions: {
                    Button("Turn On") { app.preferences.value.activity.isEnabled = true }
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            List(selection: $selection) {
                ForEach(segments) { segment in
                    ActivitySegmentRow(
                        segment: segment,
                        title: segment.title(rules: rules),
                        isLive: isToday && app.activity.current != nil && segment.id == segments.last?.id
                    )
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: ActivitySegment.ID.self) { ids in
                menu(for: ids)
            } primaryAction: { ids in
                if ids.count == 1, let segment = segments.first(where: { ids.contains($0.id) }) { renaming = segment }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day")
            Button { shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next day")
                .disabled(isToday)
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isToday {
                Button("Today") { date = Date() }
            }
            if isToday && isEnabled {
                Label(app.activity.current == nil ? "Paused" : "Recording",
                      systemImage: app.activity.current == nil ? "pause.circle" : "record.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(app.activity.current == nil
                          ? "Not recording while you're away or the Mac is asleep"
                          : "Recording the app in front")
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private var summary: String {
        let included = segments.filter { !$0.isExcluded }
        let tracked = included.reduce(0) { $0 + $1.duration }
        var parts = [date.formatted(date: .long, time: .omitted), "\(DayStats.duration(tracked)) recorded"]
        if let writtenAt {
            parts.append("written to the log at \(LogEntry.time(writtenAt))")
        }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack {
            Button("Rename…") { renaming = single }
                .disabled(single == nil)
            Button("Merge") { merge(selection) }
                .disabled(!canMerge)
                .help("Join neighbouring segments into one")
            Button("Split…") { splitting = single }
                .disabled(!canSplit(single))
            Button(excludeTitle(for: selection)) { toggleExcluded(selection) }
                .disabled(selection.isEmpty)
                .help("Leave segments out of the work log")
            Spacer()
            Button("Write to Log") { writeToLog() }
                .disabled(segments.isEmpty)
                .help("Replace the Activity section of this day's Markdown file")
        }
        .padding(12)
    }

    @ViewBuilder private func menu(for ids: Set<ActivitySegment.ID>) -> some View {
        let picked = segments.filter { ids.contains($0.id) }
        if picked.count == 1 {
            Button("Rename…") { renaming = picked[0] }
            Button("Split…") { splitting = picked[0] }
                .disabled(!canSplit(picked[0]))
        }
        if picked.count > 1 {
            Button("Merge") { merge(ids) }
                .disabled(ActivitySegmenter.merging(ids, in: segments) == nil)
        }
        if !picked.isEmpty {
            Button(excludeTitle(for: ids)) { toggleExcluded(ids) }
        }
        if picked.count == 1, let app = picked[0].usage.first?.name {
            Divider()
            Button("Add Rule for \(app)…") {
                let title = picked[0].title(rules: rules)
                newRule = ActivityRule(field: .app, pattern: app, task: title == app ? "" : title)
            }
        }
    }

    private func canSplit(_ segment: ActivitySegment?) -> Bool {
        guard let segment else { return false }
        return segment.duration >= 2 * 60
    }

    private func excludeTitle(for ids: Set<ActivitySegment.ID>) -> String {
        let picked = segments.filter { ids.contains($0.id) }
        return !picked.isEmpty && picked.allSatisfy(\.isExcluded) ? "Include" : "Exclude"
    }

    private func merge(_ ids: Set<ActivitySegment.ID>) {
        edit { ActivitySegmenter.merging(ids, in: $0) }
    }

    private func toggleExcluded(_ ids: Set<ActivitySegment.ID>) {
        let exclude = excludeTitle(for: ids) == "Exclude"
        edit { ActivitySegmenter.settingExcluded(exclude, for: ids, in: $0) }
    }

    private func edit(_ change: @escaping ([ActivitySegment]) -> [ActivitySegment]?) {
        if app.activity.edit(on: date, change) {
            message = nil
        } else if app.activity.lastError == nil {
            message = "That change no longer fits the recorded activity, so nothing was changed."
        }
        reload()
    }

    private func writeToLog() {
        if app.writeActivityToLog(for: date) {
            message = "Written to the Activity section of \(WorkLogDocument.fileName(for: date))."
        }
        reload()
    }

    private func reload() {
        segments = app.activity.segments(for: date)
        writtenAt = app.activity.writtenAt(for: date)
        selection.formIntersection(segments.map(\.id))
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        date = min(next, Date())
        selection = []
        message = nil
    }
}

private struct ActivitySegmentRow: View {
    let segment: ActivitySegment
    let title: String
    let isLive: Bool

    private var apps: String {
        segment.usage.prefix(4).map { "\($0.name) \(DayStats.duration($0.seconds))" }.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(LogEntry.time(segment.start))–\(isLive ? "now" : LogEntry.time(segment.end))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .strikethrough(segment.isExcluded)
                    if segment.isExcluded {
                        Text("excluded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(apps)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(DayStats.duration(segment.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .opacity(segment.isExcluded ? 0.55 : 1)
    }
}

private struct RenameSheet: View {
    let segment: ActivitySegment
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var task: String

    init(segment: ActivitySegment, title: String, onSave: @escaping (String) -> Void) {
        self.segment = segment
        self.onSave = onSave
        _task = State(initialValue: segment.task ?? title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(LogEntry.time(segment.start))–\(LogEntry.time(segment.end))")
                .font(.headline)
            TextField("Task", text: $task)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("Leave it empty to name it after a rule or the main app again.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        onSave(task)
        dismiss()
    }
}

private struct SplitSheet: View {
    let segment: ActivitySegment
    let title: String
    let onSplit: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(segment: ActivitySegment, title: String, onSplit: @escaping (Date) -> Void) {
        self.segment = segment
        self.title = title
        self.onSplit = onSplit
        let middle = segment.start + segment.duration / 2
        _time = State(initialValue: Date(timeIntervalSinceReferenceDate:
            (middle.timeIntervalSinceReferenceDate / 60).rounded() * 60))
    }

    private var range: ClosedRange<Date> {
        let start = segment.start + 60
        return start...max(start, segment.end - 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split “\(title)”")
                .font(.headline)
            Text("\(LogEntry.time(segment.start))–\(LogEntry.time(segment.end)) becomes two segments.")
                .foregroundStyle(.secondary)
            DatePicker("Split at", selection: $time, in: range, displayedComponents: .hourAndMinute)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Split") {
                    onSplit(time)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// Adds a rule, starting from a segment's main app.
private struct RuleSheet: View {
    let onSave: (ActivityRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ActivityRule

    init(rule: ActivityRule, onSave: @escaping (ActivityRule) -> Void) {
        self.onSave = onSave
        _rule = State(initialValue: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Rule")
                .font(.headline)
            ActivityRuleFields(rule: $rule)
            Text("Activity matching the rule is named after the task, and joins into one segment.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty
                          || rule.task.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// "App contains … → task" fields, shared by the rule sheet and Settings.
struct ActivityRuleFields: View {
    @Binding var rule: ActivityRule

    var body: some View {
        HStack {
            Picker("Match", selection: $rule.field) {
                ForEach(ActivityRule.Field.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("contains", text: $rule.pattern, prompt: Text(rule.field == .app ? "Xcode" : "Pull request"))
                .labelsHidden()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            TextField("Task", text: $rule.task, prompt: Text("Task"))
                .labelsHidden()
        }
        .textFieldStyle(.roundedBorder)
    }
}
