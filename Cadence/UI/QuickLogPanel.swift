import AppKit
import SwiftUI

/// A Spotlight-style floating text area for the quick log, opened by the global
/// shortcut. It doesn't activate Cadence, so the app you were in stays in front.
@MainActor
final class QuickLogPanelController {
    private let onSave: (String) -> Void
    private var panel: QuickLogPanel?

    init(onSave: @escaping (String) -> Void) {
        self.onSave = onSave
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.close()
        } else {
            show()
        }
    }

    private func show() {
        let panel = QuickLogPanel()
        let view = QuickLogPanelView(
            onSave: { [weak self, weak panel] text in
                self?.onSave(text)
                panel?.close()
            },
            onCancel: { [weak panel] in panel?.close() }
        )
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.position()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private final class QuickLogPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 60),
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    // Clicking elsewhere dismisses the panel, as Spotlight does.
    override func resignKey() {
        super.resignKey()
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// Centred horizontally, a third of the way down the screen with the pointer.
    func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return center() }
        setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.maxY - visible.height / 3 - frame.height / 2
        ))
    }
}

struct QuickLogPanelView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                LogTextEditor(
                    text: $text,
                    placeholder: "Log something…",
                    fontSize: 17,
                    lines: 4,
                    bordered: false,
                    focusOnAppear: true,
                    onSubmit: save,
                    onCancel: onCancel
                )
            }
            Text("\(LogTextEditor.hint) · esc close")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 460)
    }

    private func save() {
        guard !LogEntry.multiline(text).isEmpty else { return onCancel() }
        onSave(text)
    }
}
