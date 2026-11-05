import AppKit
import ApplicationServices

enum ChromeKeySender {
    struct Target {
        let pid: pid_t?
        let reason: String
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        guard !hasAccessibility else { return }
        // Open one setup surface. The system's AX prompt is a separate alert
        // that does not dismiss when the grant changes in Settings.
        // AppModel silently observes the grant and removes our inline setup.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func target() -> Target {
        guard hasAccessibility else { return Target(pid: nil, reason: "Allow Accessibility to send the arrow key") }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.google.Chrome" else {
            return Target(pid: nil, reason: "Bring YouTube in Chrome to the front")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let window = element(application, attribute: kAXFocusedWindowAttribute),
              let title = string(window, attribute: kAXTitleAttribute),
              title.localizedCaseInsensitiveContains("YouTube") else {
            return Target(pid: nil, reason: "Open a YouTube video in the active Chrome window")
        }
        guard let focus = element(application, attribute: kAXFocusedUIElementAttribute),
              let role = string(focus, attribute: kAXRoleAttribute) else {
            return Target(pid: nil, reason: "Click the YouTube player to give it keyboard focus")
        }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) {
            return Target(pid: nil, reason: "Click the player; a text field is focused")
        }
        return Target(pid: app.processIdentifier, reason: "YouTube is ready")
    }

    @discardableResult
    static func pressRightArrow(pid: pid_t) -> Bool {
        // Recheck immediately before posting. Never activate Chrome or post globally.
        guard hasAccessibility,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: false) else { return false }
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func element(_ value: AXUIElement, attribute: String) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(value, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func string(_ value: AXUIElement, attribute: String) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(value, attribute as CFString, &result) == .success else { return nil }
        return result as? String
    }
}
