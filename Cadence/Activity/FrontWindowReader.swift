import AppKit
import ApplicationServices

/// Reads the front window's title (activity tracking level 2, through the
/// Accessibility API) and the browser tab's title and URL (level 3, through
/// AppleScript).
@MainActor
final class FrontWindowReader {
    static let shared = FrontWindowReader()

    /// Browsers whose tab Cadence can read, by bundle ID.
    static let browsers: [String: Browser] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.brave.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "org.chromium.Chromium": .chromium,
        "company.thebrowser.Browser": .arc,
    ]

    enum Browser {
        case safari, chromium, arc
    }

    /// Browsers the user has already been asked about this session, so macOS
    /// isn't asked again while they decide.
    private var askedBrowsers: Set<String> = []
    private var scripts: [String: NSAppleScript] = [:]

    /// The app with its window title and, for a browser, its tab, as far as
    /// the settings and permissions allow.
    func details(for app: FrontApp, config: ActivityConfig) -> FrontApp {
        var app = app
        guard config.recordsWindowTitles, let pid = app.pid else { return app }
        app.windowTitle = Self.hasWindowTitleAccess ? Self.windowTitle(pid: pid) : nil
        if config.recordsBrowserTabs, let bundleID = app.bundleID, let tab = browserTab(bundleID: bundleID) {
            // A private window keeps neither its title nor its address.
            app.windowTitle = tab.url == nil ? nil : tab.title ?? app.windowTitle
            app.url = tab.url
        }
        return app
    }

    // MARK: Window titles

    static var hasWindowTitleAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Accessibility in System Settings.
    static func requestWindowTitleAccess() {
        // kAXTrustedCheckOptionPrompt, which Swift 6 won't read from a global var.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func windowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // An app that's hung shouldn't hold up Cadence.
        AXUIElementSetMessagingTimeout(app, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return cleaned(title as? String)
    }

    // MARK: Browser tabs

    /// The active tab of the browser's front window, with a nil URL when the
    /// window is private. Nil when it isn't a supported browser or permission
    /// isn't granted.
    func browserTab(bundleID: String) -> (title: String?, url: String?)? {
        guard let browser = Self.browsers[bundleID], hasAutomationAccess(to: bundleID),
              let script = script(for: bundleID, browser: browser)
        else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        if result.atIndex(1)?.stringValue == Self.privateWindow { return (nil, nil) }
        guard result.numberOfItems >= 2,
              let url = Self.cleaned(result.atIndex(2)?.stringValue)
        else { return nil }
        return (Self.cleaned(result.atIndex(1)?.stringValue), url)
    }

    /// Whether Cadence may send Apple events to the browser. The first time,
    /// it asks macOS to prompt the user in the background and answers false
    /// until they've agreed.
    private func hasAutomationAccess(to bundleID: String) -> Bool {
        switch Self.automationPermission(for: bundleID, askingIfNeeded: false) {
        case noErr:
            return true
        case OSStatus(errAEEventWouldRequireUserConsent):
            guard askedBrowsers.insert(bundleID).inserted else { return false }
            // Asking waits for the user's answer, so it can't happen on the main thread.
            Task.detached(priority: .utility) {
                _ = Self.automationPermission(for: bundleID, askingIfNeeded: true)
            }
            return false
        default:
            return false
        }
    }

    private nonisolated static func automationPermission(for bundleID: String, askingIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, askingIfNeeded)
    }

    private func script(for bundleID: String, browser: Browser) -> NSAppleScript? {
        if let script = scripts[bundleID] { return script }
        // Each script returns {title, URL}, or {privateWindow} for an incognito window.
        // The timeout keeps a busy browser from holding up Cadence for long.
        let body = switch browser {
        case .safari:
            """
            set t to current tab of front window
            return {name of t, URL of t}
            """
        case .chromium:
            """
            set w to front window
            if mode of w is "incognito" then return {"\(Self.privateWindow)"}
            set t to active tab of w
            return {title of t, URL of t}
            """
        case .arc:
            """
            set w to front window
            try
                if incognito of w then return {"\(Self.privateWindow)"}
            end try
            set t to active tab of w
            return {title of t, URL of t}
            """
        }
        let source = """
            with timeout of 1 second
                tell application id "\(bundleID)"
                    if (count of windows) is 0 then return {}
            \(body)
                end tell
            end timeout
            """
        guard let script = NSAppleScript(source: source) else { return nil }
        scripts[bundleID] = script
        return script
    }

    private static let privateWindow = "cadence:private"

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return LogEntry.singleLine(text)
    }
}
