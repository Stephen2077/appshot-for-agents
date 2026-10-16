import AppKit

/// hotkey -> window image + AX text (Vision OCR fallback) -> clipboard + ~/.appshot -> transition animation.
final class Pipeline {
    var options: Options
    private var busy = false
    private let animator = CaptureAnimator()
    private let toast = Toast()
    private var lastNonSelf: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init(options: Options) {
        self.options = options
    }

    func startTracking() {
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.remember(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private func usable(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return nil }
        return app
    }

    private func remember(_ app: NSRunningApplication?) {
        if let app = usable(app) { lastNonSelf = app }
    }

    func trigger() {
        Task { await capture() }
    }

    @MainActor
    func capture() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        guard let app = usable(NSWorkspace.shared.frontmostApplication) ?? lastNonSelf else {
            log("No frontmost application to capture.")
            return
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"

        // AX text first (no OCR), off the main thread.
        let ax = await Task.detached { AXText.extract(pid: pid) }.value

        let shot: (image: CGImage, title: String?, frame: CGRect)
        do {
            shot = try await WindowCapture.capture(pid: pid, appName: name)
        } catch {
            log("Capture failed: \(error)")
            return
        }

        var text = ax.text
        var source = text.isEmpty ? "none" : "accessibility"
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            let image = shot.image
            let ocr = await Task.detached { OCR.recognize(image) }.value
            if !ocr.isEmpty {
                text = ocr
                source = "ocr"
            }
        }

        let record = Record(
            app: name,
            bundle_id: app.bundleIdentifier ?? "",
            window_title: ax.windowTitle ?? shot.title ?? "",
            text: text,
            text_source: source,
            char_count: text.count,
            timestamp: Store.timestamp(),
            image_path: Store.imageURL.path,
            json_path: Store.jsonURL.path
        )
        do {
            try Store.save(image: shot.image, record: record)
        } catch {
            log("Saving failed: \(error)")
            return
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        log("Captured \(name) (\(record.char_count) chars via \(source)) -> \(Store.directory.path)/latest.{png,json}; image copied to clipboard.")

        // Animation plays only after the screenshot has been taken and saved, so it never appears in the capture.
        // The overlay is a non-activating, click-through window: focus stays in the user's original input.
        var animation: Task<Void, Never>?
        if options.animation {
            let image = shot.image, frame = shot.frame
            animation = Task { @MainActor in await self.animator.play(image: image, windowFrame: frame) }
        }

        var message = "Copied to clipboard"
        if options.autoPaste {
            let result = await Paster.paste(
                targetPID: pid, image: shot.image,
                text: options.pasteText ? text : nil
            )
            message = result.message(appName: name)
            log(message)
        } else {
            log("Auto-paste off; image is on the clipboard.")
        }
        toast.show(message, windowFrame: shot.frame)
        await animation?.value
    }
}
