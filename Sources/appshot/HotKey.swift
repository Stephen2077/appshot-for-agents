// Hotkey handling. The "press both left+right modifier keys" detection is adapted from
// EYHN/appshots (MIT, https://github.com/EYHN/appshots); double-tap support is new.
import AppKit

enum Modifier: String, CaseIterable {
    case command, option, shift, control

    // Device-specific modifier masks from IOLLEvent.h.
    var masks: (left: UInt, right: UInt) {
        switch self {
        case .command: return (0x08, 0x10)
        case .option: return (0x20, 0x40)
        case .shift: return (0x02, 0x04)
        case .control: return (0x01, 0x2000)
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .control: return "⌃"
        }
    }

    static let allDeviceMask: UInt = 0x01 | 0x2000 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40
}

enum HotKey: Equatable {
    case pair(Modifier)       // hold left + right of the same modifier
    case doubleTap(Modifier)  // tap the modifier twice quickly

    static let `default` = HotKey.pair(.option)

    /// Accepts "option", "command", "shift", "control" (left+right) or "double-command" etc.
    init?(_ string: String) {
        let s = string.lowercased().trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("double") {
            let name = String(s.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
            guard let m = Modifier(rawValue: name) else { return nil }
            self = .doubleTap(m)
        } else if let m = Modifier(rawValue: s) {
            self = .pair(m)
        } else {
            return nil
        }
    }

    var label: String {
        switch self {
        case .pair(let m): return "\(m.symbol) + \(m.symbol) (left + right \(m.rawValue))"
        case .doubleTap(let m): return "double-tap \(m.symbol) (\(m.rawValue))"
        }
    }
}

final class HotKeyMonitor {
    private let hotKey: HotKey
    private let onTrigger: () -> Void
    private var monitors: [Any] = []

    private var pairHeld = false
    private var singleDown = false
    private var lastTap: TimeInterval = 0
    private let doubleTapWindow: TimeInterval = 0.4

    init(hotKey: HotKey, onTrigger: @escaping () -> Void) {
        self.hotKey = hotKey
        self.onTrigger = onTrigger
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handleFlags: (NSEvent) -> Void = { [weak self] event in self?.flagsChanged(event) }
        let handleKey: (NSEvent) -> Void = { [weak self] _ in self?.resetTap() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handleFlags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handleKey) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.flagsChanged(e)
            return e
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func resetTap() {
        lastTap = 0
        singleDown = false
    }

    private func flagsChanged(_ event: NSEvent) {
        let pressed = event.modifierFlags.rawValue & Modifier.allDeviceMask
        switch hotKey {
        case .pair(let m):
            let expected = m.masks.left | m.masks.right
            if pressed == expected {
                if !pairHeld {
                    pairHeld = true
                    onTrigger()
                }
            } else {
                pairHeld = false
            }
        case .doubleTap(let m):
            if pressed == m.masks.left || pressed == m.masks.right {
                singleDown = true
            } else if pressed == 0 {
                if singleDown {
                    let now = event.timestamp
                    if lastTap > 0, now - lastTap < doubleTapWindow {
                        lastTap = 0
                        onTrigger()
                    } else {
                        lastTap = now
                    }
                }
                singleDown = false
            } else {
                resetTap()  // another modifier combination: not a clean tap
            }
        }
    }
}
