// appshot-for-agents: an open-source "Appshots" for any AI agent.
// Based on EYHN/appshots (MIT) - https://github.com/EYHN/appshots
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let pipeline: Pipeline
    private var monitor: HotKeyMonitor?
    private var statusItem: NSStatusItem?
    private var speakItem: NSMenuItem?

    init(options: Options) {
        pipeline = Pipeline(options: options)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let o = pipeline.options
        _ = AXText.isTrusted(prompt: true)
        if !WindowCapture.hasScreenPermission { _ = CGRequestScreenCaptureAccess() }
        pipeline.startTracking()

        if o.once {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Task { @MainActor in
                    await self.pipeline.capture()
                    exit(0)
                }
            }
            log("Capturing the frontmost window in 3 seconds...")
            return
        }

        monitor = HotKeyMonitor(hotKey: o.hotKey) { [weak self] in self?.pipeline.trigger() }
        monitor?.start()
        setUpMenu()
        log("Ready. Hotkey: \(o.hotKey.label). Output: \(Store.directory.path)/latest.{png,json}")
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "📸"
        let menu = NSMenu()
        menu.addItem(withTitle: "Hotkey: \(pipeline.options.hotKey.label)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let capture = NSMenuItem(title: "Capture frontmost window now", action: #selector(captureNow), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let speak = NSMenuItem(title: "Speak result (ElevenLabs / say)", action: #selector(toggleSpeak), keyEquivalent: "")
        speak.target = self
        speak.state = pipeline.options.speak ? .on : .off
        speakItem = speak
        menu.addItem(speak)
        let open = NSMenuItem(title: "Open ~/.appshot", action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit appshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func captureNow() {
        // Let the menu close and the previous app become frontmost again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.pipeline.trigger() }
    }

    @objc private func toggleSpeak() {
        pipeline.options.speak.toggle()
        speakItem?.state = pipeline.options.speak ? .on : .off
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Store.directory)
    }
}

let options = Options.parse(CommandLine.arguments)

if options.help {
    print(Options.usage)
    exit(0)
}
if options.check {
    print("hotkey:            \(options.hotKey.label)")
    print("accessibility:     \(AXText.isTrusted(prompt: false) ? "granted" : "NOT granted")")
    print("screen recording:  \(WindowCapture.hasScreenPermission ? "granted" : "NOT granted")")
    print("ElevenLabs key:    \(Voice.hasElevenLabsKey ? "set (ELEVENLABS_API_KEY)" : "not set (will use `say`)")")
    print("speak:             \(options.speak ? "on" : "off")")
    print("output:            \(Store.directory.path)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
