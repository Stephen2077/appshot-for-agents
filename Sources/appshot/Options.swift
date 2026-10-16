import Foundation

struct Options {
    var hotKey: HotKey = .default
    var animation = true
    var autoPaste = true
    var pasteText = false
    var hint = true
    var once = false
    var check = false
    var help = false

    static let usage = """
    appshot - hotkey -> frontmost window screenshot + Accessibility text, for any AI agent.

    Usage: appshot [options]
      --hotkey <name>   option (default: left+right Option), command, shift, control,
                        or double-command / double-option / double-shift / double-control
      --no-animation    disable the capture transition animation
      --no-paste        don't auto-paste into the focused app (only clipboard + ~/.appshot files)
      --paste-text      after the image, also paste the window text into the focused input
      --no-hint         don't paste the one-line "[appshot] ... saved at <path>" hint after the image
      --once            capture the frontmost window once (after 3s) and exit
      --check           print permission / config status and exit
      --help            show this help

    Environment: APPSHOT_HOTKEY, APPSHOT_ANIMATION=0, APPSHOT_PASTE=0, APPSHOT_PASTE_TEXT=1, APPSHOT_HINT=0
    Output: ~/.appshot/latest.png, ~/.appshot/latest.json (+ image on the clipboard)
    """

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        let env = ProcessInfo.processInfo.environment
        if let h = env["APPSHOT_HOTKEY"], let k = HotKey(h) { o.hotKey = k }
        if ["0", "false", "no", "off"].contains((env["APPSHOT_HINT"] ?? "").lowercased()) { o.hint = false }
        if ["0", "false", "no", "off"].contains((env["APPSHOT_PASTE"] ?? "").lowercased()) { o.autoPaste = false }
        if ["1", "true", "yes", "on"].contains((env["APPSHOT_PASTE_TEXT"] ?? "").lowercased()) { o.pasteText = true }
        if ["0", "false", "no", "off"].contains((env["APPSHOT_ANIMATION"] ?? "").lowercased()) { o.animation = false }

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--hotkey":
                i += 1
                if i < args.count, let k = HotKey(args[i]) { o.hotKey = k } else { log("Unknown hotkey; using default.") }
            case "--no-animation": o.animation = false
            case "--no-paste": o.autoPaste = false
            case "--paste-text": o.pasteText = true
            case "--no-hint": o.hint = false
            case "--once": o.once = true
            case "--check": o.check = true
            case "--help", "-h": o.help = true
            default: log("Ignoring unknown argument: \(args[i])")
            }
            i += 1
        }
        return o
    }
}
