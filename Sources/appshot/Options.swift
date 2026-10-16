import Foundation

struct Options {
    var hotKey: HotKey = .default
    var speak = false
    var speakText = false
    var lang = "en"
    var once = false
    var check = false
    var help = false

    static let usage = """
    appshot - hotkey -> frontmost window screenshot + Accessibility text, for any AI agent.

    Usage: appshot [options]
      --hotkey <name>   option (default: left+right Option), command, shift, control,
                        or double-command / double-option / double-shift / double-control
      --speak           announce each capture (ElevenLabs if ELEVENLABS_API_KEY is set, else macOS `say`)
      --speak-text      also read a short summary of the captured text
      --lang <en|zh>    language of the spoken announcement (default: en)
      --once            capture the frontmost window once (after 3s) and exit
      --check           print permission / config status and exit
      --help            show this help

    Environment: APPSHOT_HOTKEY, APPSHOT_SPEAK=1, APPSHOT_SPEAK_TEXT=1, APPSHOT_LANG,
                 ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID, ELEVENLABS_MODEL_ID
    Output: ~/.appshot/latest.png, ~/.appshot/latest.json (+ image on the clipboard)
    """

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        let env = ProcessInfo.processInfo.environment
        func truthy(_ v: String?) -> Bool { ["1", "true", "yes", "on"].contains((v ?? "").lowercased()) }
        if let h = env["APPSHOT_HOTKEY"], let k = HotKey(h) { o.hotKey = k }
        o.speak = truthy(env["APPSHOT_SPEAK"])
        o.speakText = truthy(env["APPSHOT_SPEAK_TEXT"])
        if let l = env["APPSHOT_LANG"], !l.isEmpty { o.lang = l }

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--hotkey":
                i += 1
                if i < args.count, let k = HotKey(args[i]) { o.hotKey = k } else { log("Unknown hotkey; using default.") }
            case "--lang":
                i += 1
                if i < args.count { o.lang = args[i] }
            case "--speak": o.speak = true
            case "--speak-text": o.speak = true; o.speakText = true
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
