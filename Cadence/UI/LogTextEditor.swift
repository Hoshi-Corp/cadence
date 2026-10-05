import AppKit
import SwiftUI

/// A text area for log entries. ⏎ saves, ⇧⏎ or ⌥⏎ starts a new line and
/// esc cancels, so a one-line entry is as quick as in a text field.
struct LogTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var fontSize = NSFont.systemFontSize
    /// How many lines tall the area is. Longer text scrolls.
    var lines = 3
    var bordered = true
    var focusOnAppear = false
    var onSubmit: () -> Void
    var onCancel: (() -> Void)?

    static let hint = "⏎ save · ⇧⏎ new line"

    private var font: NSFont { .systemFont(ofSize: fontSize) }

    private var height: CGFloat {
        NSLayoutManager().defaultLineHeight(for: font) * CGFloat(lines) + 2 * Self.inset.height
    }

    fileprivate static let inset = NSSize(width: 4, height: 4)

    var body: some View {
        LogTextView(text: $text, font: font, focusOnAppear: focusOnAppear, onSubmit: onSubmit, onCancel: onCancel)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: fontSize))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Self.inset.width)
                        .padding(.vertical, Self.inset.height)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if bordered {
                    RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor))
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor))
                }
            }
    }
}

private struct LogTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let focusOnAppear: Bool
    let onSubmit: () -> Void
    let onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        // Keep Markdown as typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = LogTextEditor.inset
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = font
        textView.string = text
        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LogTextView

        init(_ parent: LogTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let onCancel = parent.onCancel else { return false }
                onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                // ⌥⏎ arrives as insertNewlineIgnoringFieldEditor and inserts a line break.
                return false
            }
        }
    }
}
