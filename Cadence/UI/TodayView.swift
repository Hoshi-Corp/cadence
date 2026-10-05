import AppKit
import SwiftUI

/// Hosts the Today view in a regular window. Managed through AppKit rather than
/// a SwiftUI `Window` scene, which macOS 14 would open at launch.
@MainActor
final class TodayWindowController {
    private let window: NSWindow

    init(app: AppState) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Today"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.contentViewController = NSHostingController(rootView: TodayView().environment(app))
        window.setContentSize(NSSize(width: 520, height: 560))
        if !window.setFrameUsingName("Today") { window.center() }
        window.setFrameAutosaveName("Today")
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Lists a day's timeline so entries can be fixed or removed without opening
/// the Markdown file.
struct TodayView: View {
    @Environment(AppState.self) private var app
    @State private var date = Date()
    @State private var items: [TimelineItem] = []
    @State private var stats = DayStats()
    @State private var editing: TimelineItem?
    @State private var pendingDelete: TimelineItem?
    @State private var message: String?
    @State private var newEntry = ""

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing logged",
                    systemImage: "doc.text",
                    description: Text(isToday ? "Entries you log today show up here." : "There are no entries for this day.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        if editing?.id == item.id {
                            TimelineItemEditor(item: item, onSave: { save(item, as: $0) }, onCancel: { editing = nil })
                        } else {
                            TimelineItemRow(item: item, onEdit: { editing = item }, onDelete: { pendingDelete = item })
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            if let message = message ?? app.workLog.lastError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            if isToday {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    LogTextEditor(text: $newEntry, placeholder: "Add an entry…", lines: 2, onSubmit: addEntry)
                    Text(LogTextEditor.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: date) { reload() }
        .onChange(of: app.workLog.revision) { reload() }
        // Picks up edits made in other apps when the window comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { save(item, as: nil) }
        } message: { item in
            Text(item.text)
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
                Text("\(date.formatted(date: .long, time: .omitted)) · \(DayStats.duration(stats.focusSeconds)) focus · \(stats.pomodoros) 🍅")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isToday {
                Button("Today") { date = Date() }
            }
            Button {
                NSWorkspace.shared.open(app.workLog.fileURL(for: date))
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Open in your Markdown editor")
            .disabled(items.isEmpty)
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private func reload() {
        items = app.workLog.timeline(for: date)
        stats = app.workLog.dayStats(for: date)
        if let editing, items.first(where: { $0.id == editing.id })?.line != editing.line {
            self.editing = nil
        }
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        date = min(next, Date())
        editing = nil
        message = nil
    }

    private func save(_ item: TimelineItem, as newLine: String?) {
        editing = nil
        if app.workLog.replace(item, with: newLine, on: date) {
            message = nil
        } else if app.workLog.lastError == nil {
            message = "That entry changed in another app, so nothing was saved. The list has been reloaded."
        }
        reload()
    }

    private func addEntry() {
        guard !LogEntry.multiline(newEntry).isEmpty else { return }
        app.quickLog(newEntry)
        newEntry = ""
    }
}

private struct TimelineItemRow: View {
    let item: TimelineItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    /// Shows inline Markdown (*italic*, **bold**, links) the way an editor would.
    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: item.text, options: options)) ?? AttributedString(item.text)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.time ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(rendered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .help("Edit")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .help("Delete")
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

private struct TimelineItemEditor: View {
    let item: TimelineItem
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var time: String
    @State private var text: String

    init(item: TimelineItem, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        _time = State(initialValue: item.time ?? "")
        _text = State(initialValue: item.text)
    }

    private var timeIsValid: Bool {
        let time = time.trimmingCharacters(in: .whitespaces)
        return time.isEmpty || TimelineItem.isValidTime(time)
    }

    private var canSave: Bool {
        timeIsValid && !LogEntry.multiline(text).isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("09:00", text: $time)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 92)
                .foregroundStyle(timeIsValid ? Color.primary : Color.red)
                .help("HH:MM, or a range like 09:00–09:25")
                .onSubmit(save)
            LogTextEditor(
                text: $text,
                placeholder: "Entry",
                lines: max(2, min(6, text.split(separator: "\n").count)),
                focusOnAppear: true,
                onSubmit: save,
                onCancel: onCancel
            )
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
    }

    private func save() {
        if canSave { onSave(TimelineItem.line(time: time, text: text)) }
    }
}
