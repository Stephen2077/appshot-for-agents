import AppKit

/// Small HUD pill ("Pasted into Safari") near the bottom-right, where the capture thumbnail lands.
/// Non-activating and click-through, so it never steals focus from the input box.
final class Toast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    @MainActor
    func show(_ message: String, windowFrame: CGRect) {
        hide()
        guard let primary = NSScreen.screens.first else { return }
        let appKitRect = CGRect(x: windowFrame.minX, y: primary.frame.height - windowFrame.maxY,
                                width: windowFrame.width, height: windowFrame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(appKitRect) } ?? primary

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let size = label.fittingSize
        let padding = CGSize(width: 28, height: 16)
        let frame = CGRect(x: 0, y: 0, width: size.width + padding.width, height: size.height + padding.height)

        let background = NSVisualEffectView(frame: frame)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = frame.height / 2
        background.layer?.masksToBounds = true
        label.frame = CGRect(x: padding.width / 2, y: padding.height / 2, width: size.width, height: size.height)
        background.addSubview(label)

        let vis = screen.visibleFrame
        let origin = CGPoint(x: vis.maxX - 24 - frame.width, y: vis.minY + 24 + 130)
        let panel = NSPanel(contentRect: CGRect(origin: origin, size: frame.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = background
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                 completionHandler: { self.hide() })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    private func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
