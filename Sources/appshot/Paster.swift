import AppKit
import ApplicationServices

/// Simulates Cmd+V in the frontmost app so the capture lands in the input box the user is typing in.
/// Needs the Accessibility permission (already required for reading window text).
enum Paster {
    enum Result {
        case pasted(image: Bool, text: Bool)
        case noAccessibility
        case focusChanged

        func message(appName: String) -> String {
            switch self {
            case .pasted(_, let text): return text ? "Pasted image + text into \(appName)" : "Pasted into \(appName)"
            case .noAccessibility: return "Copied to clipboard. Grant Accessibility to enable auto-paste"
            case .focusChanged: return "Copied to clipboard (focus changed, not pasted)"
            }
        }
    }

    /// Order: image -> (0.3 s) -> hint line -> (0.45 s) -> window text. Never presses Return.
    static func paste(targetPID: pid_t, image: CGImage, hint: String?, text: String?) async -> Result {
        guard AXText.isTrusted(prompt: false) else { return .noAccessibility }
        // The hotkey is still physically held: wait for it to be released, otherwise we would send Cmd+Option+V.
        await waitForModifiersReleased()
        guard isStillFrontmost(targetPID) else { return .focusChanged }

        pressCommandV()   // the screenshot is already on the clipboard
        var pastedText = false

        if let hint, !hint.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if isStillFrontmost(targetPID) { await pasteString(hint); pastedText = true }
        }
        if let text, !text.isEmpty {
            // Small delay so the target app finishes ingesting the previous paste first.
            try? await Task.sleep(nanoseconds: 450_000_000)
            if isStillFrontmost(targetPID) { await pasteString(String(text.prefix(50_000))); pastedText = true }
        }
        if pastedText {
            try? await Task.sleep(nanoseconds: 300_000_000)
            Store.copyToClipboard(image: image)   // leave the screenshot on the clipboard
        }
        return .pasted(image: true, text: text?.isEmpty == false)
    }

    private static func isStillFrontmost(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private static func pasteString(_ s: String) async {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        try? await Task.sleep(nanoseconds: 60_000_000)
        pressCommandV()
    }

    private static func waitForModifiersReleased(timeout: TimeInterval = 2.0) async {
        let mask: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift, .maskControl]
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { break }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
