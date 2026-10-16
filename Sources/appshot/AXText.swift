import AppKit
import ApplicationServices

/// Reads window text through the macOS Accessibility (AX) API. No OCR involved.
enum AXText {
    struct Result {
        var windowTitle: String?
        var text: String
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

    static func extract(pid: pid_t, maxNodes: Int = 8000, maxChars: Int = 200_000, deadline: TimeInterval = 2.5) -> Result {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)  // global per-call timeout
        // Ask Chromium/Electron apps to expose their web accessibility tree.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = element(app, "AXFocusedWindow") ?? element(app, "AXMainWindow") else {
            return Result(windowTitle: nil, text: "")
        }
        var lines: [String] = []
        var chars = 0
        var nodes = 0
        let stopAt = Date().addingTimeInterval(deadline)

        func add(_ s: String?) {
            guard let s else { return }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != lines.last else { return }
            lines.append(t)
            chars += t.count
        }

        func walk(_ el: AXUIElement, depth: Int) {
            guard depth < 60, nodes < maxNodes, chars < maxChars, Date() < stopAt else { return }
            nodes += 1
            let role = string(el, "AXRole") ?? ""
            if valueRoles.contains(role) {
                add(string(el, "AXValue") ?? string(el, "AXTitle") ?? string(el, "AXDescription"))
            } else if titleRoles.contains(role) {
                add(string(el, "AXTitle") ?? string(el, "AXDescription"))
            } else if role != "AXImage", role != "AXScrollBar", let v = string(el, "AXValue") {
                add(v)
            }
            for child in children(el) { walk(child, depth: depth + 1) }
        }
        walk(window, depth: 0)
        return Result(windowTitle: string(window, "AXTitle"), text: lines.joined(separator: "\n"))
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

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (copy(el, "AXChildren") as? [AXUIElement]) ?? []
    }
}
