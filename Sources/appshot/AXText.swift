import AppKit
import ApplicationServices

/// Reads window text through the macOS Accessibility (AX) API. No OCR involved.
///
/// Walks the *whole* AX tree of the focused window (not just the visible part): every element's
/// children via `AXChildren`, plus `AXRows` / `AXContents` where a container exposes them. Scroll areas,
/// lists and web areas are therefore read in full as far as the app exposes them. Chromium/Electron apps
/// only build their web accessibility tree on request, so we switch it on first (see `enableWebAccessibility`).
enum AXText {
    struct Result {
        var windowTitle: String?
        var text: String
        var nodesVisited: Int
        var truncated: Bool   // a limit (nodes / chars / depth / time) cut the walk short
    }

    struct Limits {
        var maxNodes = 50_000
        var maxChars = 200_000
        var maxDepth = 60
        var deadline: TimeInterval = 3.0
    }

    static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    private static let valueRoles: Set<String> = [
        "AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXHeading",
    ]
    private static let titleRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXCheckBox", "AXRadioButton",
        "AXTab", "AXPopUpButton", "AXDisclosureTriangle",
    ]
    /// Attributes that can list child elements. Order matters (document order); duplicates are skipped.
    private static let childAttributes = ["AXChildren", "AXRows", "AXContents"]

    private static var enabledPIDs = Set<pid_t>()

    /// Chromium/Electron build their web AX tree lazily. AXManualAccessibility is the modern opt-in,
    /// AXEnhancedUserInterface the legacy one; set both, and give a freshly-enabled tree a moment to build.
    private static func enableWebAccessibility(_ app: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        if enabledPIDs.insert(pid).inserted {
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    static func extract(pid: pid_t, limits: Limits = Limits()) -> Result {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)  // global per-call timeout
        enableWebAccessibility(app, pid: pid)

        guard let window = element(app, "AXFocusedWindow") ?? element(app, "AXMainWindow") else {
            return Result(windowTitle: nil, text: "", nodesVisited: 0, truncated: false)
        }

        var lines: [String] = []
        var seenLines = Set<String>()   // drop repeats (e.g. a link title that repeats its inner static text)
        var visited = Set<AXUIElement>()
        var chars = 0
        var truncated = false
        let stopAt = Date().addingTimeInterval(limits.deadline)

        func add(_ s: String?) {
            guard let s else { return }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != lines.last else { return }
            // Keep repeats of long text out; short strings (e.g. "OK") may legitimately repeat.
            if t.count > 24, !seenLines.insert(t).inserted { return }
            lines.append(t)
            chars += t.count
        }

        func walk(_ el: AXUIElement, depth: Int) {
            if truncated { return }
            if depth > limits.maxDepth || visited.count >= limits.maxNodes || chars >= limits.maxChars || Date() >= stopAt {
                truncated = true
                return
            }
            guard visited.insert(el).inserted else { return }

            let role = string(el, "AXRole") ?? ""
            let kids = children(el)
            if valueRoles.contains(role) {
                add(string(el, "AXValue") ?? string(el, "AXTitle") ?? string(el, "AXDescription"))
            } else if titleRoles.contains(role) {
                add(string(el, "AXTitle") ?? string(el, "AXDescription"))
            } else if role != "AXImage", role != "AXScrollBar", let v = string(el, "AXValue") {
                add(v)
            } else if kids.isEmpty, role != "AXImage", role != "AXScrollBar", let d = string(el, "AXDescription") {
                add(d)   // text-less leaf that still carries a label (common in Chromium)
            }
            for child in kids { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return Result(
            windowTitle: string(window, "AXTitle"),
            text: lines.joined(separator: "\n"),
            nodesVisited: visited.count,
            truncated: truncated
        )
    }

    private static func copy(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = copy(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(v, to: AXUIElement.self)
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        copy(el, name) as? String
    }

    /// All children from AXChildren (and AXRows / AXContents), in order, without duplicates.
    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var seen = Set<AXUIElement>()
        for attr in childAttributes {
            guard let list = copy(el, attr) as? [AXUIElement] else { continue }
            for child in list where seen.insert(child).inserted { result.append(child) }
        }
        return result
    }
}
