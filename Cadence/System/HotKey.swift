import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut that works system-wide.
struct HotKey: Codable, Equatable {
    /// Virtual key code (`kVK_…`).
    var keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: UInt32
    /// How the key is shown, captured when the shortcut is recorded since the
    /// character depends on the keyboard layout.
    var key: String

    static let defaultQuickLog = HotKey(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        key: "L"
    )

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }

    /// Builds a shortcut from a key press. Returns nil unless ⌘, ⌥ or ⌃ is held,
    /// so a plain key (or ⇧ + key) can't take over typing everywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        let keyCode = Int(event.keyCode)
        let key = Self.specialKeys[keyCode]
            ?? event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Registers one system-wide hotkey through Carbon, which needs no permission
/// (unlike a global event monitor, which needs Accessibility).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4344_4E43 // "CDNC"

    private init() {}

    /// Replaces the registered hotkey. Pass nil to remove it.
    /// Throws if macOS refuses it, usually because another app already uses it.
    func register(_ hotKey: HotKey?) throws {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let hotKey else { return }
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw HotKeyError(shortcut: hotKey.displayString)
        }
        hotKeyRef = ref
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }
}

struct HotKeyError: LocalizedError {
    let shortcut: String
    var errorDescription: String? { "\(shortcut) is already in use by another app. Choose a different shortcut." }
}
